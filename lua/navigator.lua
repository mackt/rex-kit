-- Session navigator: every session, tab and pane on the server in Rex's
-- command palette, in sidebar order. Picking one jumps there.
-- Loaded by init.lua with dofile(path)(common, opts).
--
-- collect() reads the server; items() is pure, so tests can run it with a
-- plain Lua interpreter (see tests/test_navigator.py).
local common, opts = ...
local tilde = common and common.tilde or function(p) return p end
local M = {}

-- OSC 7501 states, most urgent first. "unread" is ours: a pane whose agent
-- reported done after the pane was last in view (see seen-watcher.lua).
M.STATES = {
  blocked = { rank = 1, label = "● blocked" },
  unread  = { rank = 2, label = "◉ unread" },
  error   = { rank = 3, label = "✖ error" },
  done    = { rank = 4, label = "✔ done" },
  working = { rank = 5, label = "◐ working" },
  idle    = { rank = 6, label = "○ idle" },
}

-- Epoch seconds of an RFC 3339 time such as 2026-10-28T14:55:55.12+08:00.
function M.epoch(s)
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

-- The most urgent state among a pane's status records.
function M.pane_state(records, seen_at, in_view)
  local best
  for _, r in pairs(records or {}) do
    if type(r) == "table" then
      local state = r.state
      if state == "done" and not in_view then
        local t = M.epoch(r.updated_at)
        if t and t > (seen_at or 0) then state = "unread" end
      end
      if M.STATES[state] and (not best or M.STATES[state].rank < M.STATES[best.state].rank) then
        best = { state = state, msg = r.msg, app = r.app or r.title }
      end
    end
  end
  return best
end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- Counts of each state, most urgent first: "● 1  ◐ 2".
local function summary(counts)
  local order = {}
  for state in pairs(counts) do order[#order + 1] = state end
  table.sort(order, function(a, b) return M.STATES[a].rank < M.STATES[b].rank end)
  local parts = {}
  for _, state in ipairs(order) do
    parts[#parts + 1] = M.STATES[state].label:match("^(%S+)") .. " " .. counts[state]
  end
  return #parts > 0 and table.concat(parts, "  ") or nil
end

-- Palette items for SESSIONS (see collect for the shape). HERE is the pane
-- the navigator was opened from. With ONLY set to a state, list just the
-- panes in that state (and "all" or nil for everything).
-- An item's id is "kind|session_id|window_id|block_id".
function M.items(sessions, here, only)
  if only == "all" then only = nil end
  local items = {}
  for _, s in ipairs(sessions) do
    local session_items, counts, panes = {}, {}, 0
    for wi, w in ipairs(s.windows) do
      local tab = (w.label or ""):gsub("^Window %x+$", "tab " .. wi)
      if tab == "" then tab = "tab " .. wi end
      local tab_counts = {}
      local pane_items = {}
      for _, p in ipairs(w.panes) do
        panes = panes + 1
        local st = p.state and M.STATES[p.state.state] and p.state
        if st then
          counts[st.state] = (counts[st.state] or 0) + 1
          tab_counts[st.state] = (tab_counts[st.state] or 0) + 1
        end
        if not only or (st and st.state == only) then
          local name = (st and st.app) or p.name or p.label or "shell"
          local where = s.label .. " › " .. tab
          local about = (st and st.msg) or p.title
          local subtitle = where .. (p.cwd and ("  " .. tilde(p.cwd)) or "") .. (about and ("  " .. about) or "")
          local detail = st and M.STATES[st.state].label or nil
          if p.block_id == here then detail = detail and (detail .. "  ◆") or "◆ here" end
          -- Panes are labelled "shell" unless someone renamed them.
          local custom = p.label and p.label ~= "shell" and p.label ~= name and p.label
          pane_items[#pane_items + 1] = {
            id = table.concat({ "pane", s.session_id, w.window_id, p.block_id }, "|"),
            title = custom and (custom .. " · " .. name) or name,
            subtitle = subtitle, icon = "terminal", detail = detail,
          }
        end
      end
      if not only then
        session_items[#session_items + 1] = {
          id = table.concat({ "window", s.session_id, w.window_id, "" }, "|"),
          title = tab, subtitle = s.label .. " · " .. plural(#w.panes, "pane"),
          icon = "document", detail = summary(tab_counts),
        }
      end
      for _, item in ipairs(pane_items) do session_items[#session_items + 1] = item end
    end
    if not only then
      items[#items + 1] = {
        id = table.concat({ "session", s.session_id, s.active_window_id or "", "" }, "|"),
        title = s.label, subtitle = plural(#s.windows, "tab") .. " · " .. plural(panes, "pane"),
        icon = "folder", detail = summary(counts),
      }
    end
    for _, item in ipairs(session_items) do items[#items + 1] = item end
  end
  return items
end

-- Seen times written by seen-watcher.lua: block_id -> epoch.
local function read_seen(file)
  local seen = {}
  local f = file and io.open(file)
  if not f then return seen end
  for line in f:lines() do
    local bid, t = line:match("^(%S+)\t(%d+)$")
    if bid then seen[bid] = tonumber(t) end
  end
  f:close()
  return seen
end

-- Every session, tab and tiled pane on the server, with each pane's
-- program state. Floating layers are skipped.
function M.collect(here, seen_file)
  local T = common.TERMINAL
  local seen = read_seen(seen_file)
  local sessions = {}
  for _, s in ipairs((rex.call("session.list") or {}).sessions or {}) do
    local v = rex.session.view{ session_id = s.session_id }
    local session = { session_id = s.session_id, label = s.label or "?",
                      active_window_id = v and v.active_window_id, windows = {} }
    for _, w in ipairs((v and v.windows) or {}) do
      local win = { window_id = w.window_id, label = w.label, panes = {} }
      for _, l in ipairs(w.layers or {}) do
        if l.kind == "tiled" then
          for _, b in ipairs(l.blocks or {}) do
            local where = { session_id = s.session_id, block_id = b.block_id }
            -- The pane the navigator was opened from, and each session's
            -- focused pane in its active tab, are in view now.
            local in_view = b.block_id == here
              or (w.window_id == session.active_window_id and b.block_id == w.focused_block_id)
            local status = rex.block.call(T, "program_status", where)
            local proc = rex.block.call(T, "process", where)
            local title = rex.block.call(T, "title", where)
            local fg = proc and proc.foreground
            win.panes[#win.panes + 1] = {
              block_id = b.block_id, label = b.label,
              state = M.pane_state(status and status.records, seen[b.block_id], in_view),
              name = fg and fg.name, cwd = fg and fg.cwd,
              -- A shell's default "user@host:path" title repeats the cwd.
              title = title and title.title and not title.title:find("^[^@]+@[^:]+:")
                and title.title ~= "" and title.title or nil,
            }
          end
        end
      end
      session.windows[#session.windows + 1] = win
    end
    sessions[#sessions + 1] = session
  end
  return sessions
end

-- Focus the target ID names and show it in the app.
function M.jump(ctx, id)
  local kind, sid, wid, bid = id:match("^(%w+)|([^|]*)|([^|]*)|([^|]*)$")
  if not kind then error("navigator: bad target " .. tostring(id), 0) end
  if kind == "pane" then
    rex.session.focus_block{ session_id = sid, block_id = bid }
  elseif kind == "window" then
    rex.session.focus_window{ session_id = sid, window_id = wid }
  end
  if not common.show(ctx, sid, wid ~= "" and wid or nil) then
    rex.log("warn", "navigator: no Rex app to show " .. sid .. " in")
  end
  return { kind = kind, session_id = sid, window_id = wid ~= "" and wid or nil,
           block_id = bid ~= "" and bid or nil }
end

-- The action: args.state limits the list to panes in that state;
-- args.target (an item id) jumps without asking.
function M.run(ctx, args)
  if args.target then return M.jump(ctx, args.target) end
  local only = args.state
  if only and only ~= "all" and not M.STATES[only] then
    error("navigator: unknown state " .. only, 0)
  end
  local items = M.items(M.collect(ctx.block_id, opts.seen_file), ctx.block_id, only)
  if #items == 0 then
    error(only and ("No panes are " .. only) or "No sessions", 0)
  end
  local id = common.pick{
    title = only and ("Go to a " .. only .. " pane") or "Go to session, tab or pane",
    placeholder = "Filter",
    items = items,
    confirm = "Go",
  }
  if id == nil then return nil end
  return M.jump(ctx, id)
end

return M
