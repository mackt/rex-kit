-- rex-kit: personal Rex tools, configuration and reusable extensions.
-- Load with require("rex-kit").setup{ prefix = "ctrl+a" }.
local source = debug.getinfo(1, "S").source
local kit_dir = assert(source:gsub("^@", ""):match("^(.+)/[^/]+$"), "rex-kit must be loaded from a file")
local M = {}

function M.setup(opts)
  opts = opts or {}
  local prefix = opts.prefix or "ctrl+a"
  local scripts_dir = kit_dir .. "/scripts"
  local state_dir = os.getenv("REX_KIT_STATE_DIR")
    or (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/rex-kit"
  rex.exec{ "mkdir", "-p", state_dir }

  local function bind(key, action, args)
    if opts.keymap ~= false then rex.bind(prefix .. ">" .. key, action, args) end
  end

  -- Press the prefix twice to send the literal prefix key to the terminal
  -- (readline / emacs beginning-of-line, nested tmux, etc.).
  bind(prefix, "pane.send_key", { key = prefix })

  -- ── General ──────────────────────────────────────────────────────────────
  bind("shift+/", "client.palette.toggle")   -- help      (herdr prefix+?)
  bind("s",       "client.settings")         -- settings  (herdr prefix+s)
  bind("shift+r", "client.config.reload")    -- reload    (herdr prefix+shift+r)
  bind("b",       "client.sidebar.toggle")   -- sidebar   (herdr prefix+b)

  -- ── Sessions (herdr workspaces) ──────────────────────────────────────────
  bind("w",       "session.switch")          -- workspace picker (prefix+w)
  bind("shift+c", "session.new")             -- new workspace    (prefix+shift+c)
  bind("shift+w", "session.rename")          -- rename workspace (prefix+shift+w)
  bind("shift+d", "session.close")           -- close workspace  (prefix+shift+d)
  -- herdr leaves previous/next_workspace unset; uncomment to enable in Rex.
  -- bind("shift+p", "session.previous")
  -- bind("shift+n", "session.next")

  -- ── Tabs ─────────────────────────────────────────────────────────────────
  bind("c",           "client.tab.new")            -- new tab        (prefix+c)
  bind("shift+t",     "client.tab.rename")         -- rename tab     (prefix+shift+t)
  bind("p",           "client.tab.previous")       -- previous tab   (prefix+p)
  bind("n",           "client.tab.next")           -- next tab       (prefix+n)
  bind("shift+left",  "client.tab.move.backward")  -- move tab left  (prefix+shift+left)
  bind("shift+right", "client.tab.move.forward")   -- move tab right (prefix+shift+right)
  bind("shift+x",     "client.tab.close")          -- close tab      (prefix+shift+x)
  for i = 1, 9 do                                  -- switch tab     (prefix+1..9)
    bind(tostring(i), "client.tab.goto", { index = i })
  end

  -- ── Panes ────────────────────────────────────────────────────────────────
  bind("h", "pane.focus.left")    -- (prefix+h)
  bind("j", "pane.focus.down")    -- (prefix+j)
  bind("k", "pane.focus.up")      -- (prefix+k)
  bind("l", "pane.focus.right")   -- (prefix+l)
  bind("tab",       "pane.focus_next")       -- cycle pane next     (prefix+tab)
  bind("shift+tab", "pane.focus_previous")   -- cycle pane previous (prefix+shift+tab)
  bind("v", "pane.split", { direction = "right" })  -- split_vertical   (prefix+v)
  bind("-", "pane.split", { direction = "down" })   -- split_horizontal (prefix+minus)
  bind("x", "pane.close")   -- close pane (prefix+x)
  bind("z", "pane.zoom")    -- zoom       (prefix+z)
  bind("r", "client.mode.enter", { name = "rex_kit_resize" })  -- resize mode (prefix+r)

  -- ── Resize mode ──────────────────────────────────────────────────────────
  -- Entered with prefix+r. h/j/k/l or arrows resize, shift for bigger steps,
  -- "=" balances, Enter/Esc/q leave the mode.
  if opts.keymap ~= false then
  rex.mode("rex_kit_resize", { exclusive = true })
  local dirs = { h = "left", j = "down", k = "up", l = "right",
                 left = "left", down = "down", up = "up", right = "right" }
  for key, direction in pairs(dirs) do
    rex.bind("rex_kit_resize/" .. key, "pane.resize", { direction = direction })
    rex.bind("rex_kit_resize/shift+" .. key, "pane.resize", { direction = direction, amount = 15 })
  end
  rex.bind("rex_kit_resize/=",     "pane.balance")
  rex.bind("rex_kit_resize/enter", "client.mode.exit")
  rex.bind("rex_kit_resize/q",     "client.mode.exit")
  rex.bind("rex_kit_resize/escape", "client.mode.exit")
  end

  local common = dofile(kit_dir .. "/lua/common.lua")
  local cwd_of = common.cwd_of

  -- ── Popups (herdr [[keys.command]] type = "popup") ───────────────────────
  -- Opens COMMAND beside, over or instead of the current pane, in the focused
  -- pane's working directory. The popup closes when the command exits.

  -- Theme applied to "layer" popups: floating layers draw the terminal
  -- background translucent, so give them explicit colors (Merino themes,
  -- surfaceSubtle as the background). Not enough on its own in the current beta.
  local popup_theme = {
    dark = {
      background = "#131519", foreground = "#e6edf3", cursor = "#2f81f7",
      palette = { "#484f58", "#ff7b72", "#3fb950", "#d29922", "#58a6ff", "#bc8cff", "#39c5cf", "#b1bac4",
                  "#6e7681", "#ffa198", "#56d364", "#e3b341", "#79c0ff", "#d2a8ff", "#56d4dd", "#ffffff" },
    },
    light = {
      background = "#eceef2", foreground = "#1f2328", cursor = "#0969da",
      palette = { "#24292f", "#cf222e", "#116329", "#9d5c00", "#0969da", "#8250df", "#1b7c83", "#6e7781",
                  "#57606a", "#a40e26", "#1a7f37", "#c47a00", "#218bff", "#a475f9", "#3192aa", "#8c959f" },
    },
  }

  local function read_default(domain, key)
    local r = rex.exec{ "defaults", "read", domain, key }
    if not r or not r.ok then return nil end
    return r.stdout:match("([^\r\n]+)")
  end

  -- Rex's own appearance setting first, then the system appearance.
  local function current_appearance()
    if opts.appearance == "light" or opts.appearance == "dark" then return opts.appearance end
    local pref = read_default("com.superlogical.rex", "Workspace.appearance")
    if pref == "light" or pref == "dark" then return pref end
    return read_default("-g", "AppleInterfaceStyle") == "Dark" and "dark" or "light"
  end

  -- How a popup is shown:
  --   "split": a pane beside the focused one. The default.
  --   "tab":   a new tab.
  --   "layer": a floating layer over the window. The app draws the terminal's
  --            default background see-through there, so it gets the theme
  --            above; full-screen programs may still show through.
  local default_popup_style = opts.popup_style or "split"
  assert(default_popup_style == "split" or default_popup_style == "tab" or default_popup_style == "layer",
    "popup_style must be split, tab or layer")

  -- open_popup(ctx, command, size): SIZE is the share of the window (or
  -- split) the popup gets.
  local function open_popup(ctx, command, size)
    size = size or 0.8
    local layout = rex.layout.block{
      flavor  = "com.superlogical.terminal.shell",
      options = { command = command, cwd = cwd_of(ctx.block_id) },
    }
    local r, err
    if default_popup_style == "tab" then
      r, err = rex.session.new_window{ window_label = "popup", focus = true, layout = layout }
    elseif default_popup_style == "layer" then
      -- Rex reads bounds w and h as the right and bottom edges.
      local edge = (1 - size) / 2
      local placed = ctx.block_id and rex.session.describe_block{ block_id = ctx.block_id }
      r, err = rex.session.new_layer{
        window_id = placed and placed.block.window_id or nil,
        bounds = { x = edge, y = edge, w = edge + size, h = edge + size },
        focus  = true,
        layout = layout,
      }
    else
      r, err = rex.session.new_split{
        anchor_id = ctx.block_id,
        -- ratio is the anchor's share, so the popup gets at most 60% of the width
        direction = "horizontal", side = "after", ratio = 1 - math.min(size, 0.6),
        focus = true, layout = layout,
      }
    end
    if err ~= nil then error(err, 0) end
    local block_id = r.block_ids and r.block_ids[1]
    if default_popup_style == "layer" and block_id then
      local theme = popup_theme[current_appearance()]
      local palette = {}   -- set_theme wants "index=color" entries
      for i, color in ipairs(theme.palette) do palette[i] = (i - 1) .. "=" .. color end
      local _, terr = rex.block.call(common.TERMINAL, "set_theme", {
        block_id = block_id, background = theme.background, foreground = theme.foreground,
        cursor = theme.cursor, palette = palette,
      })
      if terr ~= nil then rex.log("warn", "popup set_theme: " .. tostring(terr)) end
    end
  end

  local function popup(name, title, command)
    rex.action{
      name  = name,
      title = title,
      category = "Popups",
      run   = function(ctx, args) open_popup(ctx, command) end,
    }
  end

  popup("rex_kit_popup_lazygit", "Popup: lazygit",       { "lazygit" })
  popup("rex_kit_popup_shell",   "Popup: scratch shell", { opts.shell or "zsh" })

  bind("alt+g", "rex_kit_popup_lazygit")   -- (herdr prefix+alt+g)
  bind("t",     "rex_kit_popup_shell")     -- (herdr prefix+t)

  -- ── Worktrees (herdr new/open/remove_worktree) ───────────────────────────
  -- Questions are asked in Rex's command palette (rex.ui); the Git work is
  -- done by scripts/worktree.sh. A worktree lives under
  -- ~/.rex/worktrees/<repo>/<branch> and opens as a tab named "<repo>/<branch>"
  -- in the current session.
  local worktree = assert(loadfile(kit_dir .. "/lua/worktree.lua"))(common, {
    scripts_dir = scripts_dir, worktree_target = opts.worktree_target,
    worktree_dir = opts.worktree_dir,
  })
  rex.action{
    name = "rex_kit_worktree_new", title = "Worktree: New…", category = "Worktrees",
    keywords = "git branch create checkout",
    args = { branch = "string?" },
    run = function(ctx, args) return worktree.new(ctx, args) end,
  }
  rex.action{
    name = "rex_kit_worktree_open", title = "Worktree: Open…", category = "Worktrees",
    keywords = "git branch switch checkout",
    args = { path = "string?" },
    run = function(ctx, args) return worktree.open(ctx, args) end,
  }
  rex.action{
    name = "rex_kit_worktree_remove", title = "Worktree: Remove…", category = "Worktrees",
    keywords = "git branch delete",
    args = { path = "string?", yes = "boolean?" },
    run = function(ctx, args) return worktree.remove(ctx, args) end,
  }

  -- ── Session navigator (herdr goto) ──────────────────────────────────────
  -- seen-watcher.lua records when each pane was last in view, so the
  -- navigator can mark agents that finished since as unread. One copy runs
  -- per server; starting another (on reload) exits at once.
  if opts.unread ~= false then
    -- The server's PATH may lack rex; it sits beside the server binary.
    local _, err = rex.exec.start({ "sh", "-c",
      'PATH="$PATH:$(dirname "$(ps -o comm= -p $PPID)")"'
        .. ':"$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"'
        .. '; exec rex do --all "$1" "state=$2" >>"$2.log" 2>&1',
      "sh", scripts_dir .. "/seen-watcher.lua", state_dir .. "/seen.tsv" }, { detach = true })
    if err ~= nil then rex.log("warn", "seen-watcher: " .. tostring(err)) end
  end
  local navigator = assert(loadfile(kit_dir .. "/lua/navigator.lua"))(common, {
    seen_file = opts.unread ~= false and (state_dir .. "/seen.tsv") or nil,
  })
  rex.action{
    name = "rex_kit_goto", title = "Go to Session, Tab or Pane…", category = "Navigation",
    keywords = "navigator jump switch agent blocked unread",
    args = { state = "string?", target = "string?" },
    run = function(ctx, args) return navigator.run(ctx, args) end,
  }
  bind("g", "rex_kit_goto")                    -- (herdr prefix+g)

  bind("shift+g", "rex_kit_worktree_new")      -- (herdr prefix+shift+g)
  bind("alt+o",   "rex_kit_worktree_open")     -- (herdr prefix+alt+o)
  bind("alt+d",   "rex_kit_worktree_remove")   -- (herdr prefix+alt+d)

end

return M
