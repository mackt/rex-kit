-- rex do --all seen-watcher.lua state=FILE
-- Records when each pane was last in view, for the navigator's unread state:
-- a pane whose agent reported "done" after it was last seen is unread.
-- "In view" means focused in its session's active tab. Rex doesn't say which
-- session the app is showing, so a focused pane in a background session also
-- counts as seen.
--
-- FILE holds "block_id<TAB>epoch" lines. One watcher runs per server: a
-- second copy exits when FILE.pid names a live process.
local state = assert(rex.args.state, "state=FILE is required")
local pidfile = state .. ".pid"

local function sh(script, ...)
  local r = rex.exec({ "sh", "-c", script, "sh", ... })
  return r and r.ok and r.stdout or nil
end

local f = io.open(pidfile)
local other = f and f:read("*l")
if f then f:close() end
if other and other ~= "" and sh('kill -0 "$1" 2>/dev/null', other) then rex.stop(0) end
local pid = assert(sh("echo $PPID")):match("%d+")
f = assert(io.open(pidfile, "w")); f:write(pid, "\n"); f:close()

local seen = {}
f = io.open(state)
if f then
  for line in f:lines() do
    local bid, t = line:match("^(%S+)\t(%d+)$")
    if bid then seen[bid] = tonumber(t) end
  end
  f:close()
end

local function save()
  local tmp = state .. ".tmp"
  local out = assert(io.open(tmp, "w"))
  for bid, t in pairs(seen) do out:write(bid, "\t", t, "\n") end
  out:close()
  os.rename(tmp, state)
end

local focused = {}   -- session_id -> block focused in its active tab

local function refresh(sid)
  local v = rex.session.view{ session_id = sid }
  if not v then focused[sid] = nil; return end
  local now, new = os.time(), nil
  for _, w in ipairs(v.windows or {}) do
    if w.window_id == v.active_window_id then new = w.focused_block_id end
  end
  -- Both the pane losing focus and the one gaining it were in view until now.
  if focused[sid] then seen[focused[sid]] = now end
  if new then seen[new] = now end
  focused[sid] = new
  save()
end

for _, s in ipairs((rex.call("session.list") or {}).sessions or {}) do
  rex.session.attach{ session_id = s.session_id }
  refresh(s.session_id)
end

rex.on("session_view_changed", function(ctx, ev) refresh(ev.session_id) end)
rex.on("session_destroyed", function(ctx, ev) focused[ev.session_id] = nil end)
rex.on("block_closed", function(ctx, ev) seen[ev.block_id] = nil; save() end)
-- A reply that finishes while its pane is in view is read straight away.
rex.on("terminal.program_status_changed", function(ctx, ev)
  if focused[ev.session_id] == ev.block_id then seen[ev.block_id] = os.time(); save() end
end)
