# rex-kit

我的 [Rex](https://www.superlogical.com/rex) 工具包：收集可复用脚本、个人配置和扩展，
以后也会容纳插件。可以整套使用，也可以只挑需要的功能。

完整参数、快捷键表和限制见 [English README](README.md)。MIT 开源。

## 已有功能

- **会话导航器**：在 Rex 原生命令面板中列出所有 session、tab、pane，显示 Agent 状态，可搜索、可按状态筛选。
- **Git worktree 管理**：创建、打开、删除 worktree，问题都在命令面板中询问，每个分支在当前 Session 下开一个 Tab。
- **弹窗**：lazygit 和临时 shell，默认使用分屏。
- **快捷键配置**：Ctrl+A 前缀、窗口切换、分屏导航和调整尺寸模式。

目前使用 Rex 的 Lua 和 CLI API，还没有原生 Block Plugin。
`prefix+d` 项目选择器、`prefix+a` quick-actions 尚未移植。

## 安装

需要 macOS、Rex 2061 及以上（API revision 17+）、Bash、Git；lazygit 弹窗另需安装 lazygit。
导航器和 worktree 通过 [`rex.ui`](https://www.superlogical.com/rex/docs/customize/custom-ui)
在命令面板中提问，服务器和 Rex App 都需要支持；App 版本过旧时会给出明确的报错。

```sh
git clone https://github.com/mackt/rex-kit.git ~/.config/rex/rex-kit
```

在已有的 `~/.config/rex/init.lua` 中加入：

```lua
require("rex-kit").setup{
  prefix = "ctrl+a",
  keymap = true,
  popup_style = "split",
}
```

```sh
rex config check
rex config reload
```

如果使用自定义 Rex 配置目录，将仓库放在该目录下的 `rex-kit` 即可。
仓库也可以放在其他目录，再用符号链接接入。安装过程不覆盖已有配置；
默认会绑定 README 列出的前缀快捷键，有冲突时更换 prefix 或设置 `keymap = false`。

## 常用快捷键

先按 Ctrl+A，松开，再按：

| 按键 | 功能 |
| --- | --- |
| `g` | 会话导航器 |
| `Shift+G` | 创建 worktree |
| `Alt+O` | 打开 worktree |
| `Alt+D` | 删除 worktree（有确认） |
| `Alt+G` | lazygit |
| `t` | 临时 shell |
| `h/j/k/l` | 在分屏间移动 |
| `v` / `-` | 向右 / 向下分屏 |
| `r` | 调整尺寸模式，Esc 退出 |

导航器在命令面板中打开，按侧栏顺序列出所有会话：输入即筛选，Enter 跳转，Esc 关闭。
右侧一列显示状态（`●` blocked、`◉` unread、`✔` done、`◐` working、`○` idle），
`◆` 标记打开导航器时所在的 pane。想只看某种状态，可以绑定带参数的快捷键：
`rex.bind("ctrl+a>u", "rex_kit_goto", { state = "unread" })`。

worktree 操作需从 Git 仓库内启动；在非 Git 目录中触发时，命令面板会给出提示。默认路径是
`~/.rex/worktrees/<repo>/<branch-slug>`，可用 setup 的 `worktree_dir` 修改。
新建时在命令面板里输入分支名（预填一个生成的名字），Enter 按输入的名称创建并打开，
名称不合法会重新询问。打开/删除会列出该仓库的 worktree，已开成 Tab 的会标出来。
创建或打开后默认在当前 Session 下开 Tab，再次打开会复用该 Tab。
在 Rex 之外运行，或设置 `worktree_target = "session"`，仍可创建独立 Session。
删除前需要确认（默认选项是“保留”），保留分支；丢弃未提交修改需要再次确认。共享 Session 中的 Tab 保留，由用户自行关闭；
旧版创建的独立会话仍会关闭，但不会关闭正在执行删除的当前 Session。

## 更新和卸载

更新仓库后重新执行 `rex config check`、`rex config reload`。
卸载时删除配置中的 setup 调用及自定义 kit 快捷键，重新加载，再移除仓库或符号链接。
卸载不会删除已创建的 worktree。
