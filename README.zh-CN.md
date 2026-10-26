# rex-kit

我的 [Rex](https://www.superlogical.com/rex) 工具包：收集可复用脚本、个人配置和扩展，
以后也会容纳插件。可以整套使用，也可以只挑需要的功能。

完整参数、快捷键表和限制见 [English README](README.md)。MIT 开源。

## 已有功能

- **会话导航器**：以树形展示 session、tab、pane，支持搜索和 Agent 状态筛选。
- **Git worktree 管理**：创建、打开、删除 worktree，并为分支创建 Rex 会话。
- **弹窗**：lazygit 和临时 shell，默认使用分屏。
- **快捷键配置**：Ctrl+A 前缀、窗口切换、分屏导航和调整尺寸模式。

目前使用 Rex 的 Lua 和 CLI API，还没有原生 Block Plugin。
`prefix+d` 项目选择器、`prefix+a` quick-actions 尚未移植。

## 安装

需要 macOS、Rex、Bash、Git、jq、fzf；lazygit 弹窗另需安装 lazygit。
已验证 Rex Beta 1408（API 7）和 fzf 0.74.5，其他版本可能需要适配。

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

在 Rex 设置中启用 **Remote Control**，脚本才能让客户端切换会话和标签页。
连接多个客户端时，用 `REX_CLIENT` 指定目标。

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

Go to 打开时默认选中当前 pane（`◆` 标记）。列表覆盖服务器上的所有会话，
但面板仍挂在打开它的标签页上：切换会话时隐藏，切回来仍存在。
当前 Rex 公开 API 未提供自定义的应用级全局浮层。

worktree 操作需从 Git 仓库内启动。默认路径是
`~/.rex/worktrees/<repo>/<branch-slug>`，可用 `REX_WORKTREE_DIR` 修改。
删除保留分支；丢弃未提交修改需要再次确认。关闭对应会话会结束其中运行的程序。

## 更新和卸载

更新仓库后重新执行 `rex config check`、`rex config reload`。
卸载时删除配置中的 setup 调用及自定义 kit 快捷键，重新加载，再移除仓库或符号链接。
卸载不会删除已创建的 worktree。
