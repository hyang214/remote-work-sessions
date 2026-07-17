# Setup

[English](SETUP.md) | 中文

这是新用户路径。

## 安装

从公共 npm registry 安装：

```bash
npm install -g remote-work-sessions
rws setup
```

已经安装过时，直接更新：

```bash
npm install -g remote-work-sessions@latest
rws --version
```

`rws setup` 会把用户配置写到 `~/.config/rws/`，然后验证远端主机。Setup 会打印 `[1/12]`、`[9/12]` 这类带编号的阶段标志，让首次长时间安装时也能看出当前处在整体流程的哪一步。远端依赖初始化期间，如果远端命令长时间没有输出，本地也会周期性打印 `still preparing remote dependencies` 提醒。

Setup 有意拆成设备阶段和可选初始 session 阶段：

1. 准备本地 SSH 工具；
2. 收集设备名和远端 SSH 目标；
3. 验证首次 SSH 连接；
4. 收集紧凑提示符设置；
5. 收集 SSH key 设置；
6. 创建或更新本地设备配置；
7. 可选：通过该连接安装选中的 SSH 公钥；
8. 安装或验证远端依赖；
9. 可选：安装紧凑提示符远端运行时配置；
10. 使用保存后的设备重连并验证 SSH 与 `shpool`；
11. 询问是否创建初始 session；如果创建，选择或使用一次性 cwd，并在后台创建 session；
12. 打印 attach 命令，不自动连接进 session。

交互式 setup 在写远端状态前会打印简短的远端变更摘要。摘要会说明 setup 是否可能追加公钥到 `~/.ssh/authorized_keys`、安装或检查 `shpool`、更新受管理的紧凑提示符 shell block，以及设备验证后是否会创建初始 session。

交互式 setup 使用默认 `--remote-install auto` 时，会在安装缺失远端依赖前询问。选择 `n` 会把本次运行切换为只检查模式；setup 会报告缺失的 `shpool` 或 Cargo，而不是直接开始耗时安装。

## 交互式 Setup

向导会询问：

- 设备名；
- 如果设备已存在，选择继续使用已保存值、重置替换或退出；
- 远端 host 或 IP；
- 如果 host 不是 `user@host`，询问 SSH 用户名；
- 需要时通过 SSH 输入远端密码或确认 host key；
- 是否为远端会话使用紧凑提示符；
- 紧凑提示符展示的设备标签；
- 是否启用 SSH key 认证来稳定重连；
- 启用 key 认证时的 SSH key 模式；
- 设备验证后是否创建初始 session；
- 创建初始 session 时的 session 名和远端工作目录。

任一本地 setup 提示都可以输入 `q`、`quit` 或 `exit` 取消。如果上次
setup 已经写入部分设备配置，下次对同一设备运行交互式 `rws setup`
会询问是继续使用已保存值，还是重置该设备。

远端只有用户名和密码时，选择创建 key，并允许 setup 安装公钥：

```bash
rws setup --host user@workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key
```

密码提示由 SSH 处理。`rws` 不读取、不保存密码。

首次 SSH 连接失败时，setup 会在任何 session 目录选择前停止，并提示检查 host、用户名或密码。登录后如果公钥安装失败，setup 会报告远端 `~/.ssh/authorized_keys` 权限问题，不会静默继续。

## 非交互式 Setup

setup 必须在无终端环境执行时，使用 bootstrap key：

```bash
rws setup --host user@workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key \
  --bootstrap-identity '~/.ssh/id_ed25519' \
  --yes
```

非交互式 setup 默认只创建设备。需要 setup 同时创建初始 session 时，加 `--create-session --cwd DIR`。需要紧凑提示符时显式开启：

为了兼容旧脚本，非交互式 setup 如果提供了 `--cwd` 或 `--session`，但没有显式传 `--create-session` 或 `--no-create-session`，也会创建初始 session。设备-only setup 中如果只想忽略这些值，请显式传 `--no-create-session`。

```bash
rws setup --host user@workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key \
  --bootstrap-identity '~/.ssh/id_ed25519' \
  --prompt-mode compact \
  --prompt-label workstation \
  --yes
```

## 依赖 Setup

本地依赖：

- `ssh`
- `ssh-keygen`

任一缺失时，`rws setup` 会尝试用本地包管理器安装 OpenSSH client 工具。当前发布门禁在 Alpine/apk 上验证这一路径。

如果日常命令需要 SSH 但本地 `ssh` 缺失，会在任何远端连接前失败，并提示 `missing local dependency: ssh (run: rws setup)`。如果 key 命令需要 `ssh-keygen` 但缺失，会提示 `missing local dependency: ssh-keygen (run: rws setup)`。

远端依赖：

- SSH server；
- `shpool`；
- 当缺少 `shpool` 且需要安装时使用 `cargo`；
- 安装 `shpool` 所需的原生 build 依赖，例如 C compiler、`pkg-config`/`pkgconf` 和 OpenSSL development headers。

`rws setup` 在设备阶段检查 `shpool`。如果缺少 `shpool`，setup 用下面命令安装固定版本：

```bash
cargo install shpool --version 0.9.8 --locked
```

如果 SSH 可用但远端配置的 `shpool` 缺失，check 和 session 命令会提示 `remote dependency missing: shpool (<configured path>). Run: rws setup`。如果远端 SSH server 本身缺失或不可达，失败会被分类为 SSH 错误，例如 `connection_refused` 或 `connection_timeout`。

正式支持的自动远端安装路径是 Alpine/apk。其他安装分支可以 best-effort 使用，但在有真实 E2E 覆盖前不属于正式支持。

如果安装 Cargo 需要管理员权限，交互式 setup 会分配远端 TTY，让 `sudo` 可以询问远端用户的 sudo 密码。非交互式 setup 无法回答 sudo 密码提示；该模式下远端用户必须是 root、有免密 sudo，或已经安装 Cargo/shpool。

固定版本已存在于 `~/.cargo/bin/shpool` 时，setup 会复用它，并把设备更新到该路径，不重新安装。

## 紧凑提示符 Setup

紧凑提示符 setup 是远端运行时配置的一部分。compact 模式下，setup 会：

- 在设备配置中保存 `prompt_mode=compact` 和 `prompt_label=<label>`；
- 向远端用户的 `.zshrc` 或 `.bashrc` 写入受管理 block；
- 向远端 shpool config 写入 `prompt_prefix = ""`；
- 创建 shpool 会话时传入 `RWS_DEVICE_LABEL=<label>`。

预期 zsh 提示符：

```text
project %                                      [workstation:project]
```

bash 远端 fallback：

```text
[workstation:project] project $
```

Setup 不会中断已有 shpool 会话。如果 shpool daemon 已经用旧配置运行，旧的 `shpool:` prompt prefix 可能保留到 daemon 重启。

## Setup 之后

Setup 会自动验证保存后的设备：重新连接并检查 SSH 与 `shpool`。如果选择创建初始 session，setup 会在后台创建它并打印 `connect with: rws attach <session>`，不会自动 attach。之后常用命令：

```bash
rws new review --pick-cwd
rws attach review
rws f
rws s
rws --cwd '~/repo' run -- git status --short
```

`rws attach <session>` 会连接已存在的命名会话。普通命名 Session 不存在时，它会失败并打印 `Run: rws new <session>`，避免意外创建。若缺失 Session 有已保存的 coding-agent 元数据，则属于恢复例外：`attach` 会按保存的 cwd、恢复命令和权限模式重建。`rws new <session>` 是新建 Session 或 coding-agent 注册的明确入口。

完整检查：

```bash
rws doctor
```

完整项目文档：<https://github.com/hyang214/remote-work-sessions/blob/main/README.zh-CN.md>

## 在已有设备上创建新会话

Setup 创建设备。设备保存 SSH host、认证、提示符偏好和远端 `shpool` 路径，不要求默认工作目录。

会话是独立实体。要在默认设备上创建或连接另一个会话，只传会话名：

```bash
rws new review
rws new review --pick-cwd
rws session create review --cwd '~/work/review'
rws session get review
rws session update review --detach
rws session delete review
rws bg long-build
rws sessions
```

想先浏览远端文件系统时使用 `--pick-cwd`。选择器接受 `ls`、`ls <path>`、`cd <path>`、`mkdir <path>`、`mkdir -p <path>` 和 `pwd`；Enter 确认当前显示目录，不改写设备默认值。远端有 bash 时，Tab 可以补全文件和路径。

使用另一个已配置设备，不需要重新输入 host：

```bash
rws --device lab new review
```

## 删除设备

列出设备：

```bash
rws devices
```

删除设备：

```bash
rws remove lab
```

如果删除的是默认设备且还有其他设备，`rws` 会选择下一个可用设备作为默认。如果没有设备了，日常命令会要求重新运行 `rws setup`。

## 实体管理

需要直接管理而不是使用日常别名时，使用实体命令：

```bash
rws key create --identity-file '~/.ssh/rws_lab_ed25519'
rws key get --identity-file '~/.ssh/rws_lab_ed25519'
rws key update --identity-file '~/.ssh/rws_lab_ed25519' --force
rws key remove --identity-file '~/.ssh/rws_lab_ed25519' --force

rws device create lab --host user@workstation
rws device get lab
rws device update lab --cwd '~/work/other' --session other --default
rws device remove lab

rws session create review --cwd '~/work/review'
rws session get review
rws session list --json
rws session update review --detach
rws session delete review
```

`rws key remove` 只删除本地 key 文件，不删除远端用户 `authorized_keys` 中的条目。

## 重复 Setup

`rws setup` 可以安全重复执行：

- 用相同格式重写所选设备；
- 复用已有 key，除非使用 `--force-key`；
- 不重复追加 authorized keys；
- 创建 session 时创建缺失的远端目录；
- 只有缺少 `shpool` 时才安装；
- 安装固定 `shpool` package 前，可能修复缺失的原生 build 依赖；
- compact 模式启用时刷新受管理的紧凑提示符 block；
- 除非为测试或预管理环境使用 `--no-verify`，否则重新执行最终 connect/shpool 验证。
