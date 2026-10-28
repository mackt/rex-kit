# rex-kit

My growing toolkit for [Rex](https://www.superlogical.com/rex): reusable scripts,
personal configuration, and extensions. Pick the pieces you want, or use the
included `Ctrl+A` keymap.

[中文说明](README.zh-CN.md) · [MIT License](LICENSE)

## What's inside

- **Session navigator** — an fzf tree of sessions, tabs and panes, with search,
  program status filters, and a jump to the selected target.
- **Git worktrees** — create, open and remove worktrees, with a tab in the
  current Rex session for each branch. Removal requires confirmation; discarding changes requires a
  second confirmation. Branches are kept.
- **Popups** — lazygit and a scratch shell, shown as splits by default.
- **Keymap** — a `Ctrl+A` prefix, pane navigation, tabs and a resize mode,
  inspired by my Herdr setup.

This is an independent community project. It currently uses Rex's Lua and CLI
APIs. There is no native Block Plugin implementation here yet; future plugins
can live alongside the scripts and configuration.

## Requirements

- macOS with Rex. Tested against Rex Beta **1408**, CLI commit **623b2d**, API 7.
- Bash, Git, `jq`, and `fzf`. Tested with fzf **0.74.5**; the navigator uses recent
  features including `--footer` and `--ghost`.
- `zsh` for the default scratch shell; `lazygit` for its popup.
- Python 3 with `curses` for the new-worktree form.
- Enable **Remote Control** in Rex settings for scripts to select sessions/tabs
  in the app. With several apps connected, set `REX_CLIENT` to the intended client.

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
  ascii_input_source = true, -- macOS: switch to an ASCII layout after the prefix
  unread = true,         -- track unread agent replies for the navigator
  -- appearance = "dark", -- optional: light or dark; otherwise follow macOS/Rex
}
```

With `keymap = false`, bind only the actions you want:

```lua
rex.bind("ctrl+a>g", "rex_kit_goto")
rex.bind("ctrl+a>shift+g", "rex_kit_worktree_new")
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

On macOS, pressing the prefix switches to the current ASCII-capable keyboard
layout, as Herdr's `switch_ascii_input_source_in_prefix` does, so a CJK input
method doesn't swallow the next key. The previous input source is restored when
the command runs, on Esc, or when resize mode ends. The helper
(`scripts/input-source.c`) is compiled with `clang` on first use. Set
`ascii_input_source = false` to keep a plain `prefix>key` sequence instead.
Bare `prefix+d` and `prefix+a` are not bound: the Herdr project picker and
quick-actions have not been ported.

### Navigator controls

- Opens with the current pane selected (the `◆` marker).
- `j/k` or arrows: move; Enter: jump; `/`: search.
- `b/u/w/i/d/a`: blocked / unread / working / idle / done / all.
- `◉ unread`: the agent reported done after you last had that pane in view.
  `scripts/seen-watcher.lua` (started by `setup`, one per server) records when
  each pane was focused in its session's active tab, under
  `~/.local/state/rex-kit`. Rex doesn't report which session the app shows, so
  a focused pane in a background session counts as seen.
- Ctrl+D / Ctrl+U: half-page down / up in list mode.
- Esc: return from search to list mode, or close from list mode.

Program states depend on applications reporting OSC 7501. Unknown states are
shown without a state icon; the kit does not infer agent progress from output.

The list covers all sessions on the server, but its floating panel belongs to
the tab where it was opened. Switching sessions hides it; returning shows it
again. Rex's current public API does not expose a custom app-wide overlay.

### Worktrees

The new-worktree form has an editable branch name and a live checkout path.
It starts with a generated name selected: type to replace it, or use the arrow
keys to edit it. Enter creates/opens that exact branch; Esc cancels. There is
no branch search. Ctrl+U clears the name, and Ctrl+A/Ctrl+E move to its ends.

Creating or opening a worktree opens a named tab under the current session,
reusing that tab on later opens. It does not create a new Sidebar session group.
Outside a Rex session, it creates a standalone session; set
`REX_WORKTREE_TARGET=session` to explicitly choose that behavior inside Rex too.

Run from inside a Git checkout. New branches start at that checkout's HEAD.
Paths default to `~/.rex/worktrees/<repo>/<branch-slug>`; override the base with
`REX_WORKTREE_DIR`. Spaces, quotes and non-ASCII paths are supported. Tabs and
newlines in worktree paths are rejected. Bare repositories and separate Git
directories are not supported. Repositories with the same basename share the
default namespace; give them separate `REX_WORKTREE_DIR` values.

Shell entry points are usable independently:

```sh
./scripts/worktree.sh new /path/to/repo feature/example
./scripts/worktree.sh open /path/to/repo
./scripts/worktree.sh remove /path/to/repo
```

`remove` excludes the main checkout, asks before deleting, and keeps the Git
branch. Tabs in shared sessions stay open and can be closed separately. A
matching legacy standalone session is closed unless it is the session running
the picker; closing that session also ends the programs running in it.

## Update and uninstall

Update the checkout with `git pull --ff-only`, then `rex config check` and
`rex config reload`. To uninstall, remove the `require("rex-kit").setup(...)`
call and any custom bindings to kit actions, reload Rex, then remove the checkout
or symlink. Worktrees are independent and are not removed by uninstalling.

## Development

```sh
python3 -m unittest discover -s tests -v
```

Tests use disposable Git repositories and stub session creation; they never
delete user worktrees. Navigator selection tests run the real fzf in a
pseudo-terminal and skip when a version supporting `--ghost` is unavailable.
Live Rex smoke tests are separate from CI.

Floating pickers retain a workaround for Rex Beta's layer sizing and background
rendering. If a future build changes this behavior, the geometry and margin
compensation may need updating. Split popups avoid that issue for full-screen
tools such as lazygit.

## Credits

Built on [Rex's Lua/CLI APIs](https://www.superlogical.com/rex/docs),
[fzf](https://github.com/junegunn/fzf), and Git worktrees. The keymap and workflow
are inspired by [Herdr](https://github.com/ogulcancelik/herdr) and my personal dotfiles.
