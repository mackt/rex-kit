-- rex do goto-rows.lua [here=BLOCK_ID]
-- Prints one row per session, tab and pane across every session on this
-- server, for goto.sh's picker. Tab-separated: kind, session_id, window_id,
-- block_id, state, display text (ANSI colored, tree-shaped like herdr's
-- navigator), detail (shown under the list for the selected row).
-- Floating layers are skipped (the picker itself is one).
local T = "com.superlogical.terminal"
local ESC = string.char(27)
local function c(code, s) return ESC .. "[" .. code .. "m" .. s .. ESC .. "[39;22m" end
local DIM, BOLD, ACCENT, TREE = "90", "1", "34", "90"
local STATE = {  -- OSC 7501 states, most urgent first
  blocked = { rank = 1, icon = "●", color = "31" },
  error   = { rank = 2, icon = "✖", color = "35" },
  done    = { rank = 3, icon = "✔", color = "32" },
  working = { rank = 4, icon = "◐", color = "33" },
  idle    = { rank = 5, icon = "○", color = DIM },
}
local here = rex.args.here
local HOME = os.getenv("HOME") or "~"
local function tilde(p) return p and (p:gsub("^" .. HOME:gsub("%p", "%%%0"), "~")) or nil end

local function block_info(sid, bid)
  local info = {}
  local st = rex.block.call(T, "program_status", { session_id = sid, block_id = bid })
  for _, r in pairs((st and st.records) or {}) do
    if type(r) == "table" and STATE[r.state] and (not info.state or STATE[r.state].rank < STATE[info.state].rank) then
      info.state, info.msg, info.app = r.state, r.msg, r.app or r.title
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
      local i = block_info(s.session_id, b.block_id)
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
