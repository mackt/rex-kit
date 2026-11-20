-- Helpers shared by rex-kit's actions. Loaded by init.lua with dofile.
local M = {}

local TERMINAL = "com.superlogical.terminal"
M.TERMINAL = TERMINAL

local HOME = os.getenv("HOME") or ""

-- ~/… for paths under the home directory, for display.
function M.tilde(path)
  if not path or HOME == "" then return path end
  if path == HOME then return "~" end
  if path:sub(1, #HOME + 1) == HOME .. "/" then return "~" .. path:sub(#HOME + 1) end
  return path
end

-- Lines of TEXT, without empty ones.
function M.lines(text)
  local out = {}
  for line in (text or ""):gmatch("[^\r\n]+") do out[#out + 1] = line end
  return out
end

-- The working directory of the program in BLOCK_ID, or nil. SESSION_ID is
-- needed for a block outside the action's session.
function M.cwd_of(block_id, session_id)
  if not block_id then return nil end
  local proc = rex.block.call(TERMINAL, "process", { block_id = block_id, session_id = session_id })
  if proc and proc.foreground and proc.foreground.cwd then return proc.foreground.cwd end
  local r = rex.block.call(TERMINAL, "pwd", { block_id = block_id, session_id = session_id })
  if r and r.pwd and r.pwd ~= "" then
    if r.pwd:match("^file://") then
      return (r.pwd:gsub("^file://[^/]*", ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
      end))
    end
    return r.pwd
  end
  return proc and proc.child and proc.child.cwd or nil
end

-- The one connected Rex app, for actions run from the CLI.
local function only_app()
  local list = rex.call("client.list")
  local found
  for _, c in ipairs((list and list.clients) or {}) do
    if c.info and c.info.kind == "app" then
      if found then return nil end   -- several apps: don't guess
      found = c.client_id
    end
  end
  return found
end

-- Show SESSION_ID (and WINDOW_ID) in the Rex app. From a key or the palette
-- the app that asked does it once the action returns; from the CLI the one
-- connected app is asked, if there is exactly one.
function M.show(ctx, session_id, window_id)
  local args = { session_id = session_id, window_id = window_id }
  if ctx.origin == "key" or ctx.origin == "palette" then
    rex.client.queue("session.select", args)
    return true
  end
  local app = only_app()
  if not app then return false end
  local _, err = rex.call("client.perform", { client_id = app, action = "session.select", args = args })
  return err == nil
end

-- rex.ui.input / rex.ui.pick that return nil only when the person cancelled,
-- and fail the action with a readable message for every other reason.
local REASONS = {
  unsupported = "The connected Rex app can't show questions in the command palette yet; update Rex",
  no_client = "No Rex app is connected to ask",
  busy = "Rex is already asking another question",
  timeout = "Nobody answered in time",
}
local function asker(fn)
  return function(spec)
    local answer, why, detail = fn(spec)
    if answer ~= nil or why == "cancelled" then return answer end
    error(REASONS[why] or ("Couldn't ask: " .. tostring(detail or why)), 0)
  end
end
M.input = asker(function(spec) return rex.ui.input(spec) end)
M.pick = asker(function(spec) return rex.ui.pick(spec) end)

-- Ask a yes/no question in the palette. The safe answer is listed first, so
-- pressing Return straight away never does anything destructive. YES and NO
-- are { title, subtitle } tables.
function M.confirm(title, yes, no)
  local answer = M.pick{
    title = title,
    items = {
      { id = "no", title = no[1], subtitle = no[2] },
      { id = "yes", title = yes[1], subtitle = yes[2] },
    },
  }
  return answer == "yes"
end

return M
