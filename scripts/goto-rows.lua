-- rex do goto-rows.lua [here=BLOCK_ID] [seen=FILE]
-- Prints one row per session, tab and pane across every session on this
-- server, for goto.sh's picker. Tab-separated: kind, session_id, window_id,
-- block_id, state, display text (ANSI colored, tree-shaped like herdr's
-- navigator), detail (shown under the list for the selected row).
-- Floating layers are skipped (the picker itself is one).
-- A "done" pane is shown as "unread" when its agent finished after the pane
-- was last in view, per FILE (written by seen-watcher.lua).
local T = "com.superlogical.terminal"
local ESC = string.char(27)
local function c(code, s) return ESC .. "[" .. code .. "m" .. s .. ESC .. "[39;22m" end
local DIM, BOLD, ACCENT, TREE = "90", "1", "34", "90"
local STATE = {  -- OSC 7501 states, most urgent first
  blocked = { rank = 1, icon = "●", color = "31" },
  unread  = { rank = 2, icon = "◉", color = "36;1" },
  error   = { rank = 3, icon = "✖", color = "35" },
  done    = { rank = 4, icon = "✔", color = "32" },
  working = { rank = 5, icon = "◐", color = "33" },
  idle    = { rank = 6, icon = "○", color = DIM },
}
local here = rex.args.here

local seen = {}   -- block_id -> epoch it was last in view
local f = rex.args.seen and io.open(rex.args.seen)
if f then
  for line in f:lines() do
    local bid, t = line:match("^(%S+)\t(%d+)$")
    if bid then seen[bid] = tonumber(t) end
  end
  f:close()
end

-- Epoch seconds of an RFC 3339 time such as 2026-10-28T14:55:55.12+08:00.
local function epoch(s)
  local y, mo, d, h, mi, sec, rest = (s or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)[%.%d]*(.*)$")
  if not y then return nil end
  y, mo = tonumber(y), tonumber(mo)
  if mo <= 2 then y = y - 1 end   -- days from civil (Howard Hinnant)
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * ((mo + 9) % 12) + 2) / 5) + tonumber(d) - 1
  local days = era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
  local t = days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(sec)
  local sign, oh, om = rest:match("^([+-])(%d+):(%d+)$")
  if sign then t = t - (sign == "+" and 1 or -1) * (tonumber(oh) * 3600 + tonumber(om) * 60) end
  return t
end
local HOME = os.getenv("HOME") or "~"
local function tilde(p) return p and (p:gsub("^" .. HOME:gsub("%p", "%%%0"), "~")) or nil end

local function block_info(sid, bid, in_view)
  local info = {}
  local st = rex.block.call(T, "program_status", { session_id = sid, block_id = bid })
  for _, r in pairs((st and st.records) or {}) do
    local state = r.state
    if type(r) == "table" and state == "done" and not in_view then
      local t = epoch(r.updated_at)
      if t and t > (seen[bid] or 0) then state = "unread" end
    end
    if type(r) == "table" and STATE[state] and (not info.state or STATE[state].rank < STATE[info.state].rank) then
      info.state, info.msg, info.app = state, r.msg, r.app or r.title
    end
  end
  local p = rex.block.call(T, "process", { session_id = sid, block_id = bid })
  local fg = p and p.foreground
  if fg then info.name, info.cwd = fg.name, tilde(fg.cwd) end
  local t = rex.block.call(T, "title", { session_id = sid, block_id = bid })
  -- A shell's default "user@host:path" title repeats the cwd; skip it.
  if t and t.title and not t.title:find("^[^@]+@[^:]+:") then info.title = t.title end
  return info
end

local function emit(kind, sid, wid, bid, state, text, detail)
  print(table.concat({ kind, sid or "", wid or "", bid or "", state or "", text, detail or "" }, "\t"))
end

local list = rex.call("session.list") or {}
for _, s in ipairs(list.sessions or {}) do
  -- A control connection may only call into a session it is attached to;
  -- `rex do` attaches to one, so attach to each of the others as we go.
  rex.session.attach{ session_id = s.session_id }
  local v = rex.session.view{ session_id = s.session_id }
  local windows = (v and v.windows) or {}
  local label = s.label or "?"
  local pane_rows, states = {}, {}
  local total = 0
  for wi, w in ipairs(windows) do
    local last_w = wi == #windows
    local blocks = {}
    for _, l in ipairs(w.layers or {}) do
      if l.kind == "tiled" then for _, b in ipairs(l.blocks or {}) do blocks[#blocks + 1] = b end end
    end
    total = total + #blocks
    local wlabel = (w.label or ""):gsub("^Window %x+$", "tab " .. wi)
    local wrows = {}
    local wstates = {}
    for bi, b in ipairs(blocks) do
      -- The pane the picker was opened from, and each session's focused pane
      -- in its active tab, are in view now.
      local in_view = b.block_id == here
        or (w.window_id == (v and v.active_window_id) and b.block_id == w.focused_block_id)
      local i = block_info(s.session_id, b.block_id, in_view)
      local gutter = (b.block_id == here) and c("36", "◆ ") or "  "
      local branch = c(TREE, (last_w and "   " or "│  ") .. (bi == #blocks and "└─ " or "├─ "))
      local st = i.state and STATE[i.state]
      local icon = st and c(st.color, st.icon) or c(DIM, "·")
      local name = (i.state and i.app) or i.name or ""
      local text = gutter .. branch .. icon .. " " .. (b.label or "shell")
        .. c(DIM, "  " .. name .. (i.cwd and (" " .. i.cwd) or ""))
      if i.msg or i.title then text = text .. c(DIM, "  " .. (i.msg or i.title)) end
      local detail = label .. " · tab " .. wi .. " · " .. (b.label or "shell")
        .. (i.state and (" · " .. i.state .. (i.app and (" " .. i.app) or "")) or "")
        .. (i.cwd and (" · " .. i.cwd) or "")
      wrows[#wrows + 1] = { "pane", s.session_id, w.window_id, b.block_id, i.state or "", text, detail }
      if i.state then wstates[#wstates + 1] = i.state end
    end
    local wdetail = label .. " · tab " .. wi .. " · " .. #blocks .. " pane" .. (#blocks == 1 and "" or "s")
    emit("window", s.session_id, w.window_id, w.focused_block_id, table.concat(wstates, ","),
      "  " .. c(TREE, last_w and "└─ " or "├─ ") .. c(DIM, wi .. " ") .. wlabel, wdetail)
    for _, r in ipairs(wrows) do emit(unpack(r)) end
    for _, st in ipairs(wstates) do states[#states + 1] = st end
  end
  -- The session row is printed last so it can carry its panes' states, then
  -- goto.sh sorts rows back into tree order by the running line number.
  emit("session", s.session_id, v and v.active_window_id, nil, table.concat(states, ","),
    "  " .. c(ACCENT .. ";1", "▾ " .. label), label .. " · " .. total .. " pane" .. (total == 1 and "" or "s"))
end
