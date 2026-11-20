# rex-kit

My growing toolkit for [Rex](https://www.superlogical.com/rex): reusable scripts,
personal configuration, and extensions. Pick the pieces you want, or use the
included `Ctrl+A` keymap.

[中文说明](README.zh-CN.md) · [MIT License](LICENSE)

## What's inside

- **Session navigator** — every session, tab and pane in Rex's command
  palette, with agent states (blocked, unread, working…), search, and a jump
  to the selected target.
- **Git worktrees** — create, open and remove worktrees, with a tab in the
  current Rex session for each branch. Questions are asked in the command
  palette. Removal requires confirmation; discarding changes requires a
  second confirmation. Branches are kept.
- **Popups** — lazygit and a scratch shell, shown as splits by default.
- **Keymap** — a `Ctrl+A` prefix, pane navigation, tabs and a resize mode,
  inspired by my Herdr setup.

This is an independent community project. It currently uses Rex's Lua and CLI
APIs. There is no native Block Plugin implementation here yet; future plugins
can live alongside the scripts and configuration.

## Requirements

- macOS with Rex **2061** or later (API revision 17+): the navigator and
  worktree actions ask their questions with
  [`rex.ui`](https://www.superlogical.com/rex/docs/customize/custom-ui), so
  both the server and the Rex app must be new enough to show prompts. Older
  apps get an error saying so.
- Bash and Git.
- `zsh` for the default scratch shell; `lazygit` for its popup.

Rex is in beta and its API changes. Linux and Windows are not tested. The popup
appearance helper reads macOS preferences; these are not portable theme APIs.

## Install

Clone into Rex's configuration directory (use your actual config directory if
you set `XDG_CONFIG_HOME` or `REX_CONFIG`):

```sh
git clone https://github.com/mackt/rex-kit.git ~/.config/rex/rex-kit
```

Add this line to your existing `~/.config/rex/init.lua`:

```lua
require("rex-kit").setup{ prefix = "ctrl+a" }
```

Then validate and reload:

```sh
rex config check
rex config reload
```

No installer overwrites your configuration. The default keymap does bind the
listed prefix sequences; pick another prefix if they conflict. Avoid loading
both this kit and a copied version of its old standalone configuration.

If the checkout lives elsewhere, symlink that directory as `rex-kit` inside your
Rex configuration directory. The Lua module resolves scripts relative to itself.

## Configure

```lua
require("rex-kit").setup{
  prefix = "ctrl+a",
  keymap = true,         -- false: register actions only; keep your own keys
  popup_style = "split", -- split, tab or layer (lazygit / scratch shell)
  shell = "zsh",         -- executable name or path
  unread = true,         -- track unread agent replies for the navigator
  -- appearance = "dark", -- optional: light or dark; otherwise follow macOS/Rex
  -- worktree_dir = "~/src/worktrees", -- base for worktrees (default ~/.rex/worktrees)
  -- worktree_target = "session",      -- open worktrees as sessions, not tabs
}
```

With `keymap = false`, bind only the actions you want:

```lua
rex.bind("ctrl+a>g", "rex_kit_goto")
rex.bind("ctrl+a>shift+g", "rex_kit_worktree_new")
-- the navigator, listing only blocked (or unread, working, idle, done) panes
rex.bind("ctrl+a>u", "rex_kit_goto", { state = "unread" })
```

Call `setup` once. Actions are named `rex_kit_goto`, `rex_kit_worktree_new`,
`rex_kit_worktree_open`, `rex_kit_worktree_remove`, `rex_kit_popup_lazygit`, and
`rex_kit_popup_shell`. They also appear in the command palette.

## Keymap

Press `Ctrl+A`, release it, then press the key below. `Alt` is Option on macOS.

| Key after prefix | Action |
| --- | --- |
| `g` | Session/tab/pane navigator |
| `Shift+G` | New worktree |
| `Alt+O` / `Alt+D` | Open / remove worktree |
| `Alt+G` / `t` | lazygit / scratch shell |
| `w` / `Shift+C` | Session picker / new session |
| `Shift+W` / `Shift+D` | Rename / close session |
| `c` / `Shift+T` / `Shift+X` | New / rename / close tab |
| `p` / `n` / `1`–`9` | Previous / next / numbered tab |
| `Shift+Left` / `Shift+Right` | Move tab |
| `h j k l` | Focus left / down / up / right |
| `Tab` / `Shift+Tab` | Next / previous pane |
| `v` / `-` | Split right / down |
| `x` / `z` | Close / zoom pane |
| `r` | Resize mode: h/j/k/l or arrows; Shift for larger steps |
| `?` / `s` / `b` / `Shift+R` | Palette / settings / sidebar / reload |
| `Ctrl+A` | Send a literal Ctrl+A |

In resize mode, `=` balances panes; Enter, Esc or `q` exits.
Bare `prefix+d` and `prefix+a` are not bound: the Herdr project picker and
quick-actions have not been ported.

### Navigator

The navigator opens in Rex's command palette, so it works the same in every
session and on every connected Rex app. Sessions, tabs and panes are listed in
sidebar order; type to filter, Return to jump, Esc to close.

- Each pane shows its program (or agent), where it is and its working
  directory; the right-hand column shows its state, and `◆` marks the pane
  you opened the navigator from. Session and tab rows count their panes'
  states (`● 1  ◐ 2`).
- States: `●` blocked, `◉` unread, `✖` error, `✔` done, `◐` working, `○` idle.
  They depend on programs reporting OSC 7501; the kit does not infer agent
  progress from output.
- `◉ unread`: the agent reported done after you last had that pane in view.
  `scripts/seen-watcher.lua` (started by `setup`, one per server) records when
  each pane was focused in its session's active tab, under
  `~/.local/state/rex-kit`. Rex doesn't report which session the app shows, so
  a focused pane in a background session counts as seen.
- `state=STATE` lists only the panes in that state (see the binding above);
  `target=ID` jumps without asking, for scripts.

### Worktrees

**New** asks for a branch name in the palette, starting with a generated
one. Return creates (or opens) exactly the branch typed; an invalid name is
asked for again. **Open** and **Remove** list the repository's worktrees by
branch and path, marking those already open as tabs. Removing asks for
confirmation, with "Keep it" first so a reflexive Return is harmless, and a
checkout with uncommitted changes is only discarded after a second question.

Creating or opening a worktree opens a named tab under the current session,
reusing that tab on later opens. It does not create a new Sidebar session group.
Outside a Rex session, or with `worktree_target = "session"`, it uses a
standalone session instead.

For scripts, each action takes its answer as an argument and skips the
question: `rex do rex_kit_worktree_new branch=feature/x`,
`rex_kit_worktree_open path=…`, `rex_kit_worktree_remove path=… yes=true`
(a checkout with changes still asks before discarding them).

Run from inside a Git checkout. New branches start at that checkout's HEAD.
From a pane outside any repository, the palette just says so.
Paths default to `~/.rex/worktrees/<repo>/<branch-slug>`; override the base with
`worktree_dir` (or `REX_WORKTREE_DIR` for the script). Spaces, quotes and non-ASCII paths are supported. Tabs and
newlines in worktree paths are rejected. Bare repositories and separate Git
directories are not supported. Repositories with the same basename share the
default namespace; give them separate `REX_WORKTREE_DIR` values.

`scripts/worktree.sh` does the Git work and never prompts, so it is usable on
its own:

```sh
./scripts/worktree.sh list /path/to/repo
./scripts/worktree.sh new /path/to/repo feature/example   # prints the checkout path
./scripts/worktree.sh remove /path/to/repo /path/to/checkout [--force]
```

`remove` refuses the main checkout and keeps the Git branch. Tabs in shared
sessions stay open and can be closed separately. A matching standalone session
is closed unless it is the session the action was run from; closing that
session also ends the programs running in it.

## Update and uninstall

Update the checkout with `git pull --ff-only`, then `rex config check` and
`rex config reload`. To uninstall, remove the `require("rex-kit").setup(...)`
call and any custom bindings to kit actions, reload Rex, then remove the checkout
or symlink. Worktrees are independent and are not removed by uninstalling.

## Development

```sh
python3 -m unittest discover -s tests -v
```

Worktree tests use disposable Git repositories; they never touch user
worktrees. Navigator tests run `lua/navigator.lua`'s list building with a plain
Lua 5.1 (`luajit`) and skip without one. Live Rex smoke tests are separate from
CI.

The `layer` popup style keeps a workaround for Rex Beta's floating layer
sizing and see-through background. Split popups avoid that issue for
full-screen tools such as lazygit.

## Credits

Built on [Rex's Lua/CLI APIs](https://www.superlogical.com/rex/docs) and Git
worktrees. The keymap and workflow
are inspired by [Herdr](https://github.com/ogulcancelik/herdr) and my personal dotfiles.
