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
  local uname = rex.exec{ "uname" }
  local macos = uname ~= nil and uname.ok and uname.stdout:match("^Darwin") ~= nil

  -- ── ASCII input source in prefix mode (herdr switch_ascii_input_source_in_prefix)
  -- With a CJK input method active, pressing the prefix switches to the
  -- ASCII-capable keyboard layout so the next key reaches Rex as a letter;
  -- the previous input source comes back when the prefix command runs, or
  -- when a mode it started (resize) ends. The prefix then enters an
  -- exclusive one-shot mode instead of starting a key sequence, because Rex
  -- has no hook for "a sequence started". Esc cancels, as before.
  local ascii_prefix = opts.keymap ~= false and opts.ascii_input_source ~= false and macos
  local input_source_bin = state_dir .. "/input-source"
  local saved_source

  local function input_source(...)
    -- Build the helper on first use, and again when its source changes.
    local src = scripts_dir .. "/input-source.c"
    local built = rex.exec{ "sh", "-c", '[ -x "$1" ] && [ ! "$2" -nt "$1" ] || clang -O2 -framework Carbon -o "$1" "$2"',
                            "sh", input_source_bin, src }
    if not (built and built.ok) then
      rex.log("warn", "input-source build failed: " .. tostring(built and built.stderr))
      return nil
    end
    return rex.exec{ input_source_bin, ... }
  end

  local function restore_input_source()
    if saved_source then
      input_source("select", saved_source)
      saved_source = nil
    end
  end

  if ascii_prefix then
    rex.action{
      name  = "rex_kit_prefix",
      title = "Prefix (ASCII input source)",
      category = "Navigation",
      run   = function(ctx, args)
        local r = input_source("ascii")
        local previous = r and r.ok and r.stdout:match("([^\r\n]+)")
        if previous then saved_source = previous end
        rex.client.queue("client.mode.enter", { name = "rex_kit_prefix", once = true })
      end,
    }
    -- Runs ACTION with ARGS after restoring the input source. KEEP leaves
    -- the ASCII source on, for modes the action enters.
    rex.action{
      name  = "rex_kit_prefixed",
      title = "Prefix: run action",
      category = "Navigation",
      args  = { action = "string?", args = "object?", keep = "boolean?" },
      run   = function(ctx, args)
        if not args.keep then restore_input_source() end
        if not args.action then return end
        if args.action:match("^rex_kit_") then
          local _, err = rex.invoke(args.action, args.args)
          if err ~= nil then error(err, 0) end
        else
          rex.client.queue(args.action, args.args)
        end
      end,
    }
    rex.mode("rex_kit_prefix", { exclusive = true })
    rex.bind(prefix, "rex_kit_prefix")
    rex.bind("rex_kit_prefix/escape", "rex_kit_prefixed")
  end

  local function bind(key, action, args, keep)
    if opts.keymap == false then return end
    if ascii_prefix then
      rex.bind("rex_kit_prefix/" .. key, "rex_kit_prefixed", { action = action, args = args, keep = keep })
    else
      rex.bind(prefix .. ">" .. key, action, args)
    end
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
  bind("r", "client.mode.enter", { name = "rex_kit_resize" }, true)  -- resize mode (prefix+r)

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
  for _, key in ipairs{ "enter", "q", "escape" } do
    if ascii_prefix then
      rex.bind("rex_kit_resize/" .. key, "rex_kit_prefixed", { action = "client.mode.exit" })
    else
      rex.bind("rex_kit_resize/" .. key, "client.mode.exit")
    end
  end
  end

  -- ── Popups (herdr [[keys.command]] type = "popup") ───────────────────────
  -- Opens COMMAND in a floating layer over the current window, in the focused
  -- pane's working directory. The layer closes when the command exits.
  local function cwd_of(block_id)
    if not block_id then return nil end
    local proc = rex.block.call("com.superlogical.terminal", "process", { block_id = block_id })
    if proc and proc.foreground and proc.foreground.cwd then return proc.foreground.cwd end
    local r = rex.block.call("com.superlogical.terminal", "pwd", { block_id = block_id })
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
  --   "layer": a floating layer over the window. The app draws the terminal's
  --            default background see-through, so only programs that paint an
  --            explicit background on every cell (fzf with --color, see
  --            scripts/worktree.sh) look right there.
  --   "split": a pane beside the focused one, closed when the command exits.
  --            Opaque, so this is what lazygit and shells use.
  --   "tab":   a new tab, closed when the command exits.
  local default_popup_style = opts.popup_style or "split"
  assert(default_popup_style == "split" or default_popup_style == "tab" or default_popup_style == "layer",
    "popup_style must be split, tab or layer")

  -- open_popup(ctx, command, size, style): COMMAND is a list, or a
  -- function(cwd) returning one. SIZE is the share of the window (or split)
  -- the popup gets. STYLE overrides default_popup_style.
  local function open_popup(ctx, command, size, style)
    size = size or 0.8
    local popup_style = style or default_popup_style
    local cwd = cwd_of(ctx.block_id)
    if type(command) == "function" then command = command(cwd) end
    -- Floating layer geometry. Rex draws the layer from (x, y) to (w, h) as
    -- edges, but sizes the layer's terminal as if w and h were its width and
    -- height, so the terminal is wider and taller than what is visible. The
    -- script compensates with an fzf margin: right x/w, bottom y/h.
    local left, top = (1 - size) / 2, (1 - size) / 2
    local right, bottom = left + size, top + size
    if popup_style == "layer" then
      -- Only the default background is see-through in a floating layer; cells
      -- with an explicit background are opaque. Tell the script which colors
      -- to paint with (worktree.sh passes them to fzf).
      local theme = popup_theme[current_appearance()]
      local margin = string.format("0,%d%%,%d%%,0",
        math.ceil(left / right * 100), math.ceil(top / bottom * 100))
      command = { "env", "REX_POPUP_BG=" .. theme.background, "REX_POPUP_FG=" .. theme.foreground,
                  "REX_POPUP_MARGIN=" .. margin, unpack(command) }
    end
    local layout = rex.layout.block{
      flavor  = "com.superlogical.terminal.shell",
      options = { command = command, cwd = cwd },
    }
    local r, err
    if popup_style == "tab" then
      r, err = rex.session.new_window{ window_label = "popup", focus = true, layout = layout }
    elseif popup_style == "layer" then
      r, err = rex.session.new_layer{
        window_id = ctx.block_id and (function()
          local r, err = rex.session.describe_block{ block_id = ctx.block_id }
          if not r then error(err or "cannot locate popup window", 0) end
          return r.block.window_id
        end)() or nil,
        bounds = { x = left, y = top, w = right, h = bottom },
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
    if popup_style == "layer" and block_id then
      local theme = popup_theme[current_appearance()]
      local palette = {}   -- set_theme wants "index=color" entries
      for i, color in ipairs(theme.palette) do palette[i] = (i - 1) .. "=" .. color end
      local _, terr = rex.block.call("com.superlogical.terminal", "set_theme", {
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
  -- Backed by scripts/worktree.sh. Each opens a picker in a popup, creates or
  -- finds the worktree under ~/.rex/worktrees/<repo>/<branch>, and opens a
  -- tab named "<repo>/<branch>" in the current session. Auto-switching
  -- needs Remote Control enabled in Rex's settings.
  local worktree_sh = scripts_dir .. "/worktree.sh"

  -- Same precondition herdr checks before opening its worktree dialogs.
  local function inside_git_work_tree(dir)
    local r = rex.exec{ "git", "-C", dir, "rev-parse", "--is-inside-work-tree" }
    return r ~= nil and r.ok and r.stdout:match("([^\r\n]+)") == "true"
  end

  local function worktree_action(name, title, subcommand)
    rex.action{
      name  = name,
      title = title,
      category = "Worktrees",
      args  = { branch = "string?" },
      run   = function(ctx, args)
        local cwd = cwd_of(ctx.block_id) or os.getenv("HOME")
        if not inside_git_work_tree(cwd) then
          error("worktree actions require a directory inside a Git work tree (" .. cwd .. ")", 0)
        end
        open_popup(ctx, function(cwd)
          local command = { worktree_sh, subcommand, cwd or "" }
          if args.branch then command[#command + 1] = args.branch end
          return command
        end, 0.6, "layer")
      end,
    }
  end

  worktree_action("rex_kit_worktree_new",    "Worktree: new…",    "new")
  worktree_action("rex_kit_worktree_open",   "Worktree: open…",   "open")
  worktree_action("rex_kit_worktree_remove", "Worktree: remove…", "remove")

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
  rex.action{
    name  = "rex_kit_goto",
    title = "Go to Session, Tab or Pane…",
    category = "Navigation",
    run   = function(ctx, args)
      local goto_sh = scripts_dir .. "/goto.sh"
      open_popup(ctx, { goto_sh, ctx.block_id or "" }, 0.7, "layer")
    end,
  }
  bind("g", "rex_kit_goto")                    -- (herdr prefix+g)

  bind("shift+g", "rex_kit_worktree_new")      -- (herdr prefix+shift+g)
  bind("alt+o",   "rex_kit_worktree_open")     -- (herdr prefix+alt+o)
  bind("alt+d",   "rex_kit_worktree_remove")   -- (herdr prefix+alt+d)

end

return M
