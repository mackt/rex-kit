-- Worktree actions: questions in Rex's command palette, Git work in
-- scripts/worktree.sh. Loaded by init.lua with dofile(path)(common, opts).
local common, opts = ...
local tilde, lines = common.tilde, common.lines
local M = {}

local script = opts.scripts_dir .. "/worktree.sh"

-- Run worktree.sh; return its stdout, or nil, its stderr and exit code.
local function wt(...)
  local env = opts.worktree_dir and { REX_WORKTREE_DIR = opts.worktree_dir } or nil
  local r, err = rex.exec({ script, ... }, { env = env })
  if not r then return nil, err, -1 end
  if not r.ok then
    local msg = (r.stderr ~= "" and r.stderr or r.stdout):gsub("%s+$", "")
    return nil, msg, r.code
  end
  return r.stdout
end

local function must(...)
  local out, err = wt(...)
  if not out then error(err, 0) end
  return out
end

-- The repository DIR is in: { cwd, repo, root, base }, or nil.
local function repository_at(dir)
  local out = dir and wt("info", dir)
  if not out then return nil end
  local repo, root, base = out:match("^([^\t]*)\t([^\t]*)\t([^\r\n]*)")
  return repo and { cwd = dir, repo = repo, root = root, base = base }
end

-- The repositories that panes in every session are in, one per main
-- checkout, in sidebar order.
local function open_repositories()
  local found, seen_dirs, seen_roots = {}, {}, {}
  for _, s in ipairs((rex.call("session.list") or {}).sessions or {}) do
    local v = rex.session.view{ session_id = s.session_id }
    for _, w in ipairs((v and v.windows) or {}) do
      for _, l in ipairs(w.layers or {}) do
        for _, b in ipairs((l.kind == "tiled" and l.blocks) or {}) do
          local dir = common.cwd_of(b.block_id, s.session_id)
          if dir and not seen_dirs[dir] then
            seen_dirs[dir] = true
            local r = repository_at(dir)
            if r and not seen_roots[r.root] then
              seen_roots[r.root] = true
              found[#found + 1] = r
            end
          end
        end
      end
    end
  end
  return found
end

-- The repository the focused pane is in. Outside one, say so in the palette
-- and offer the repositories other panes are in; nil if none is chosen.
local function repository(ctx, doing)
  local cwd = common.cwd_of(ctx.block_id) or os.getenv("HOME")
  local here = repository_at(cwd)
  if here then return here end

  local repos = open_repositories()
  local items = {}
  for _, r in ipairs(repos) do
    items[#items + 1] = { id = r.root, title = r.repo, subtitle = tilde(r.root), icon = "folder" }
  end
  local placeholder = #repos > 0 and ("Pick a repository to " .. doing .. " in")
    or "cd into a Git repository first, then try again"
  if #repos == 0 then
    items[1] = { id = "ok", title = "Got it", subtitle = "Worktrees need a pane inside a Git repository" }
  end
  local root = common.pick{
    title = tilde(cwd) .. " isn't in a Git repository",
    placeholder = placeholder,
    items = items,
    confirm = #repos > 0 and "Use this repository" or nil,
  }
  for _, r in ipairs(repos) do
    if r.root == root then return r end
  end
  return nil
end

local function worktrees(r)
  local list = {}
  for _, line in ipairs(lines(must("list", r.cwd))) do
    local path, branch = line:match("^([^\t]*)\t(.*)$")
    if path then list[#list + 1] = { path = path, branch = branch } end
  end
  return list
end

-- Labels of the tabs open in the action's session.
local function open_tabs()
  local labels = {}
  local v = rex.session.view{}
  for _, w in ipairs((v and v.windows) or {}) do
    if w.label then labels[w.label] = w.window_id end
  end
  return labels
end

-- Open DIR in a tab labelled LABEL in the action's session, reusing that
-- tab if it is already open. Outside a session (or with
-- worktree_target = "session"), use a session of its own instead.
local function open(ctx, dir, label)
  local layout = rex.layout.block{
    flavor = "com.superlogical.terminal.shell",
    options = { cwd = dir },
  }
  if ctx.session_id and opts.worktree_target ~= "session" then
    local window_id = open_tabs()[label]
    if window_id then
      local _, err = rex.session.focus_window{ window_id = window_id }
      if err ~= nil then error(err, 0) end
    else
      local r, err = rex.session.new_window{ window_label = label, layout = layout, focus = true }
      if err ~= nil then error(err, 0) end
      window_id = r.window_id
    end
    common.show(ctx, ctx.session_id, window_id)
    return { session_id = ctx.session_id, window_id = window_id, path = dir }
  end
  local session_id
  for _, s in ipairs((rex.call("session.list") or {}).sessions or {}) do
    if s.label == label then session_id = s.session_id end
  end
  if not session_id then
    local r, err = rex.call("session.create", {
      label = label, initial_windows = { { window_label = label, layout = layout } },
    })
    if err ~= nil then error(err, 0) end
    session_id = r.session_id
  end
  common.show(ctx, session_id)
  return { session_id = session_id, path = dir }
end

-- Ask for a branch name until it is a valid one, or nil if cancelled.
local function ask_branch(r)
  local title = "New worktree in " .. r.repo
  local value = must("suggest"):gsub("%s+$", "")
  while true do
    local branch = common.input{
      title = title,
      placeholder = "Branch name",
      value = value,
      confirm = "Create worktree under " .. tilde(r.base),
    }
    if branch == nil then return nil end
    branch = branch:gsub("^%s+", ""):gsub("%s+$", "")
    if branch ~= "" then
      local ok = rex.exec{ "git", "check-ref-format", "--branch", branch }
      if ok and ok.ok and branch:sub(1, 1) ~= "-" then return branch end
    end
    title, value = "Not a valid branch name: " .. branch, branch
  end
end

function M.new(ctx, args)
  local r = repository(ctx, "create a worktree")
  if not r then return nil end
  local branch = args.branch or ask_branch(r)
  if not branch then return nil end
  local dir = must("new", r.cwd, branch):gsub("%s+$", "")
  return open(ctx, dir, r.repo .. "/" .. branch)
end

-- Pick one of the repository's worktrees; returns it, or nil if cancelled.
local function pick_worktree(r, title, confirm)
  local list = worktrees(r)
  if #list == 0 then error("No worktrees in " .. r.repo .. " besides its main checkout", 0) end
  local tabs = open_tabs()
  local items = {}
  for _, w in ipairs(list) do
    items[#items + 1] = {
      id = w.path, title = w.branch, subtitle = tilde(w.path), icon = "branch",
      detail = tabs[r.repo .. "/" .. w.branch] and "open" or nil,
    }
  end
  local path = common.pick{
    title = title .. " · " .. r.repo, placeholder = "Filter worktrees",
    items = items, confirm = confirm,
  }
  for _, w in ipairs(list) do
    if w.path == path then return w end
  end
end

-- args.path skips the question (for scripts).
local function chosen(r, args, title, confirm)
  if not args.path then return pick_worktree(r, title, confirm) end
  for _, w in ipairs(worktrees(r)) do
    if w.path == args.path then return w end
  end
  error("Not a worktree of " .. r.repo .. ": " .. args.path, 0)
end

function M.open(ctx, args)
  local r = repository(ctx, "open a worktree")
  if not r then return nil end
  local w = chosen(r, args, "Open worktree", "Open")
  if not w then return nil end
  return open(ctx, w.path, r.repo .. "/" .. w.branch)
end

-- Removing asks first; a checkout with changes is only forced after a second
-- question. The branch is always kept.
function M.remove(ctx, args)
  local r = repository(ctx, "remove a worktree")
  if not r then return nil end
  local w = chosen(r, args, "Remove worktree", "Remove…")
  if not w then return nil end
  if not args.yes and not common.confirm("Delete checkout of " .. w.branch .. "?",
      { "Delete checkout", tilde(w.path) .. " — branch " .. w.branch .. " is kept" },
      { "Keep it" }) then
    return nil
  end
  local _, err, code = wt("remove", r.cwd, w.path)
  if code == 3 then
    local why = lines(err)[1] or "Git refused to remove it"
    if not common.confirm(w.branch .. " has uncommitted changes",
        { "Discard changes and delete", why },
        { "Keep it" }) then
      return nil
    end
    must("remove", r.cwd, w.path, "--force")
  elseif err then
    error(err, 0)
  end
  -- A standalone session for this branch (worktree_target = "session") is
  -- closed, but never the session the action was run from.
  local label = r.repo .. "/" .. w.branch
  for _, s in ipairs((rex.call("session.list") or {}).sessions or {}) do
    if s.label == label and s.session_id ~= ctx.session_id then
      rex.call("session.destroy", { session_id = s.session_id })
    end
  end
  return { removed = w.path, branch = w.branch }
end

return M
