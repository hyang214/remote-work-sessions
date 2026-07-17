# Remote Work Sessions

[English](README.md) | 中文

通过 SSH 管理可持久化的远程工作会话。

Remote Work Sessions (`rws`) 是一个小型命令行工具，用来创建、重连、检查和清理远程 shell 会话。它把连接层保持得足够简单：SSH 负责登录机器，`shpool` 负责让远程 shell 会话持续存在。

## 为什么需要

远程工作站很有用，但日常命令流经常变得繁琐：

- SSH 命令越来越长，也不容易记住。
- 笔记本休眠、网络切换或连接中断后，原本有用的 shell 状态容易丢失。
- `tmux` 和 `zellij` 很强大，但很多工作流只需要一个可持久化的 shell 会话。
- 状态检查分散在 SSH、会话管理器和项目命令之间。

`rws` 把常用路径缩短为：

```bash
rws new review --pick-cwd
rws attach review
rws f
rws s
rws --cwd '~/repo' run -- git status --short
```

## 依赖要求

本机：

- 通过 npm 安装时需要 Node.js 22.14+
- Bash 3.2+
- OpenSSH client

远端机器：

- OpenSSH server
- 一个 SSH 账号，可以使用已有 key，或允许首次密码登录
- [`shpool`](https://github.com/shell-pool/shpool) 在 `PATH` 上可用，或者远端有受支持的包管理器，使 `rws setup` 能安装已固定版本

如果远端依赖安装需要 sudo，交互式 setup 支持正常的远端 sudo 密码提示。非交互式 setup 需要 root、免密 sudo，或提前安装好 Cargo/shpool。

当本机缺少 `ssh` 或 `ssh-keygen` 时，`rws` 会明确提示缺少的命令，并引导重新执行 `rws setup`。当 SSH 可用但远端缺少 `shpool` 时，检查和会话命令会提示 `remote dependency missing: shpool`。

## 安装

从公共 npm registry 安装：

```bash
npm install -g remote-work-sessions
rws setup
```

安装后的命令是 `rws`。

已经安装过时，直接更新：

```bash
npm install -g remote-work-sessions@latest
rws --version
```

从源码安装：

```bash
git clone https://github.com/hyang214/remote-work-sessions.git
cd remote-work-sessions
ln -sfn "$PWD/bin/rws" "$HOME/.local/bin/rws"
```

确认 `~/.local/bin` 已加入 `PATH`。

## 快速开始

运行 setup 向导：

```bash
rws setup
```

向导会处理：

- 检查本机 OpenSSH client，并在可能时安装；
- 在 `~/.config/rws/` 下创建设备配置；
- 如果设备已存在，让用户选择继续使用已保存值、重置替换或退出；
- 建立首次远端连接并验证密码或 host key；
- 创建或复用 SSH key，并通过交互选择是否启用 key 方式重连；
- 通过已建立的 SSH 连接或 bootstrap key 安装首次公钥；
- 检查或安装固定版本的远端 `shpool`；
- 可选安装远端持久会话的紧凑提示符；
- setup 结束前用保存后的设备验证 SSH 和 `shpool`；
- 设备验证完成后，询问是否创建初始 session；如果创建，会通过远端 cwd picker 选择目录、后台创建 session，并打印 attach 命令，不会自动连接进去。

检查 setup 结果：

```bash
rws doctor
```

创建并进入一个持久会话：

```bash
rws new review --pick-cwd
rws attach review
```

把远程 coding CLI 与可恢复会话绑定，只需在首次创建时声明一次 agent：

```bash
rws new coding --pick-cwd --agent codex
# 远端重启或断电后
rws attach coding
```

支持 `codex`、`claude` 和 `kiro`。只要声明 `--agent`，默认就会启用全权限并
随该 session 持久化。`rws` 会进入选中的 cwd，创建或连接前台 shpool Session，
然后在其中自动启动 agent：Codex 使用官方
`codex --dangerously-bypass-approvals-and-sandbox`，Claude 使用 bypass permission
模式，Kiro 信任全部工具。需要普通权限时显式传 `--no-full-access`。shpool
session 仍在时 `attach` 连接原进程；重启后则以相同权限模式在原 cwd 恢复
最新对话。provider 首次初始化、新 workspace 信任，以及 Kiro 首次启用
trust-all 的风险确认仍可能需要确认一次；此后不会再逐个确认工具调用。

在同一个远端设备上启动另一个会话，不需要重新输入 host：

```bash
rws new review
```

笔记本休眠、网络切换或旧客户端残留后重新连接：

```bash
rws f
```

查看远端、会话和 git 状态：

```bash
rws s
```

在已配置的远端目录里执行一次性命令：

```bash
rws --cwd '~/repo' run -- git status --short
```

## 文档地图

- [`docs/SCENARIOS.zh-CN.md`](docs/SCENARIOS.zh-CN.md)：面向任务的使用流程，包括首次 setup、日常使用、重连、多设备、自动化和故障排查。
- [`docs/COMMAND_REFERENCE.zh-CN.md`](docs/COMMAND_REFERENCE.zh-CN.md)：完整命令面、选项、副作用、输出契约和退出行为。
- [`docs/SETUP.zh-CN.md`](docs/SETUP.zh-CN.md)：setup 流程、依赖安装、紧凑提示符、重复 setup 和实体管理。
- [`docs/CONFIGURATION.zh-CN.md`](docs/CONFIGURATION.zh-CN.md)：配置文件格式、设备/会话模型和 CRUD 风格实体命令。
- [`docs/DEPENDENCIES.zh-CN.md`](docs/DEPENDENCIES.zh-CN.md)：本机/远端依赖策略和受支持安装范围。
- [`docs/DESIGN.zh-CN.md`](docs/DESIGN.zh-CN.md)：架构模型、实体边界和职责范围。
- [`docs/TESTING.zh-CN.md`](docs/TESTING.zh-CN.md)：smoke 和容器 E2E 两层测试。
- [`docs/QUALITY_GATES.zh-CN.md`](docs/QUALITY_GATES.zh-CN.md)：验证门禁，包括中英文文档覆盖规则。
- [`docs/RELEASING.zh-CN.md`](docs/RELEASING.zh-CN.md)：clean public export、GitHub 配置和 npm trusted publishing。
- [`docs/USER_STORIES.zh-CN.md`](docs/USER_STORIES.zh-CN.md)：产品场景、状态、验收标准和验证证据。

## 配置

用户配置位于：

```text
~/.config/rws/
  default.conf
  devices/
    default.conf
  sessions/
    default/
      coding.conf
```

仓库里也提供了 `config/` 示例默认配置，供源码 checkout 使用。

`default.conf` 选择默认设备：

```conf
device=default
```

设备配置定义 SSH 目标和远端运行时信息。默认情况下，setup 不会给设备写入默认工作目录，因为不同 session 通常有不同目录：

```conf
host=workstation
identity_file=~/.ssh/rws_default_ed25519
prompt_mode=compact
prompt_label=workstation
ssh_option=ServerAliveInterval=30
```

设备和会话是两个不同实体：

- 设备：可复用的 SSH 连接配置，例如 `workstation` 或 `lab`。
- 会话：该设备上的一个 shpool 会话，例如 `project`、`review` 或 `build`。

使用不同设备：

```bash
rws --device lab
```

临时覆盖设备配置：

```bash
rws --host other-host --cwd '~/work/other-project' --session other
```

## 命令

每个公共命令都有主题帮助，例如 `rws help new` 或 `rws help attach`。如果 `rws`
发现参数错误，stderr 会在错误消息后自动附上该命令的用法、参数/选项和典型场景。

| 命令 | 使用场景 |
| --- | --- |
| `rws` | 进入或创建默认持久会话。 |
| `rws help [topic]` | 显示通用帮助或主题帮助，不要求已有初始化配置。 |
| `rws help scenarios` | 显示按场景组织的常见使用建议。 |
| `rws help commands` | 显示完整命令和选项参考。 |
| `rws a` | `rws attach` 的短别名。 |
| `rws attach [session]` | 进入默认会话或指定的已有会话。普通命名会话不存在时失败；带 agent 元数据的 Session 会自动恢复。 |
| `rws new <session> [--cwd <dir>] [--agent codex\|claude\|kiro] [--no-full-access]` | 在当前设备上进入或创建另一个会话；`--agent` 默认启动并持久化全权限 agent，`--no-full-access` 改用 provider 普通权限。 |
| `rws new <session> --pick-cwd` | 创建会话前浏览远端文件系统，选择不同 cwd。 |
| `rws f` | 当另一个客户端仍 attached 或状态残留时，强制重新连接。 |
| `rws force [session]` | `rws f` 的长形式。 |
| `rws s` | 显示远端健康状态、shpool 会话和 git 状态。 |
| `rws status` | `rws s` 的长形式。 |
| `rws c` | 检查 SSH、远端目录和 shpool 是否可用。 |
| `rws check` | `rws c` 的长形式。 |
| `rws sh` | 在已配置目录中打开普通 SSH shell。 |
| `rws shell` | `rws sh` 的长形式。 |
| `rws sessions` | 列出当前设备上的 shpool 会话。 |
| `rws ls` | `rws sessions` 的别名。 |
| `rws list` | `rws sessions` 的别名。 |
| `rws session create <session> [--cwd <dir>]` | 在当前设备上创建后台 shpool 会话。目录不存在时会创建。 |
| `rws session get <session>` | 读取当前设备上的指定 shpool 会话对象。 |
| `rws session list` | `rws sessions` 的实体命令形式。 |
| `rws session update <session> --detach` | 将会话改为 detached 状态。 |
| `rws session delete <session...>` | 杀掉一个或多个指定 shpool 会话。 |
| `rws session attach [session]` | `rws attach` 的实体命令形式。 |
| `rws bg` | 在后台创建默认会话。 |
| `rws background [session]` | `rws bg` 的长形式。 |
| `rws run -- <command>` | 在已配置远端目录执行一次性命令，并保留 stdout、stderr 和远端退出码。 |
| `rws d` | detach 已配置会话。已经 disconnected 时重复执行也是安全的。 |
| `rws detach [session...]` | `rws d` 的长形式；接受一个或多个会话。 |
| `rws k` | kill 已配置会话。 |
| `rws kill [session...]` | `rws k` 的长形式。 |
| `rws setup` | 添加设备、准备远端依赖，并可选创建初始 session。可安全重复执行。 |
| `rws doctor` | 验证本地配置、SSH、远端目录和 shpool。 |
| `rws key create` | 创建本地 SSH identity 文件；传 `--force` 时替换已有文件。 |
| `rws key get` | 显示本地 SSH identity 文件状态和 fingerprint。 |
| `rws key list` | 列出已配置设备引用的 identity 文件。 |
| `rws key update` | 通过 `--force` 重新生成本地 identity 文件。 |
| `rws key remove` | 通过 `--force` 删除本地 identity 文件。 |
| `rws devices` | 列出已配置设备。 |
| `rws device create <device>` | 通过 setup 创建设备。 |
| `rws device get [device]` | 显示设备配置。 |
| `rws device update <device>` | 修改本地设备配置字段。 |
| `rws device list` | `rws devices` 的别名。 |
| `rws remove <device>` | 删除已配置设备。 |
| `rws rm <device>` | `rws remove` 的别名。 |
| `rws device remove <device>` | `rws remove` 的别名。 |
| `rws init ...` | 底层配置写入器。优先使用 `rws setup`。 |

## SSH Key Setup

`rws setup` 支持三种 key 模式：

| 模式 | 使用场景 |
| --- | --- |
| `--key-mode create` | 为该设备创建专用 ed25519 key。 |
| `--key-mode existing` | 复用用户选择的已有 key。 |
| `--key-mode skip` | 只写配置，SSH 设置由用户自己管理。 |

创建专用 key：

```bash
rws setup --host workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519'
```

复用已有 key：

```bash
rws setup --host workstation \
  --key-mode existing \
  --identity-file '~/.ssh/id_ed25519'
```

通过远端用户的普通 SSH 密码，在远端安装新建的 public key：

```bash
rws setup --host user@workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key
```

这个过程使用 SSH 自己的交互式密码和 host-key 提示。`rws` 不读取也不保存密码。

非交互式 setup 可以通过一个已经授权的 bootstrap key 安装 public key：

```bash
rws setup --host workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key \
  --bootstrap-identity '~/.ssh/id_ed25519'
```

`rws setup` 是幂等的。除非提供 `--force-key`，已有 key 会被复用；已有 public key 不会在 `authorized_keys` 中重复追加；session 创建时远端目录通过 `mkdir -p` 创建。

## 紧凑提示符

交互式 `rws setup` 会询问是否为远端会话安装紧凑提示符。启用后，zsh 远端 shell 中的会话提示符会缩短为：

```text
project %                                      [workstation:project]
```

左侧保留简短当前目录。右侧显示设备 label 和 shpool session。对于 bash 远端，回退为紧凑左提示符：

```text
[workstation:project] project $
```

非交互式 setup 可以显式启用或跳过：

```bash
rws setup --prompt-mode compact --prompt-label workstation
rws setup --prompt-mode skip
```

Setup 会把 `prompt_mode` 和 `prompt_label` 写入设备配置，在远端用户的 shell rc 文件里安装一段受管理的 block，并设置远端 shpool `prompt_prefix = ""`。已有 shpool daemon 可能会继续保留旧 prompt prefix，直到被重启；setup 不会中断活跃会话。

## 实体管理

核心实体都有显式管理命令：

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

`rws key remove` 只删除本地 key 文件。远端 `authorized_keys` 的变更由 setup 的 key-install 路径处理，不会自动移除。

删除设备：

```bash
rws remove lab
```

在一个记不清完整路径的远端目录里创建另一个会话：

```bash
rws new review --pick-cwd
```

在 `rws cwd>` 提示符下，可以使用 `ls`、`ls <path>`、`cd <path>`、`mkdir <path>`、`mkdir -p <path>` 或 `pwd`；按 Enter 会在当前显示目录中创建会话。远端有 bash 时，Tab 可以补全文件和路径。这个操作不会改写设备保存的默认 cwd。

## 测试

产品用户场景记录在 [`docs/USER_STORIES.zh-CN.md`](docs/USER_STORIES.zh-CN.md)。质量门禁单独记录在 [`docs/QUALITY_GATES.zh-CN.md`](docs/QUALITY_GATES.zh-CN.md)，其中 QG-001 覆盖用户故事覆盖度和执行正确性。

快速检查：

```bash
scripts/smoke-test.sh
```

使用 client container 和 server container 的容器端到端检查：

```bash
tests/e2e/podman-e2e.sh
```

E2E 会验证干净的 client/server 初始化、本机 OpenSSH 安装、错误密码处理、host-key 确认、SSH key 创建、通过 bootstrap key 或密码登录安装 SSH key、真实 SSH config 下的 `--key-mode skip`、`--remote-install check`、真实固定版本 shpool 安装、紧凑提示符 setup、设备加载、诊断、JSON 会话契约、一次性命令、显式默认 attach、coding CLI 的首次启动和最近对话恢复、可选 setup session 创建且不自动 attach、在已有设备上创建另一个会话、交互式选择 cwd 创建新会话、中断 attach、后台会话创建、强制重连、detach、kill、设备覆盖/删除、默认设备改写、最后一个设备删除，以及最终 setup 验证。

## 目标

- 让日常远程会话路径保持简短。
- 在连接中断后保留远端 shell 状态。
- 支持多个远端设备，以及每个设备上的多个会话。
- 保持与普通 SSH 和已有 shell 工具兼容。

## 非目标

- 远程桌面。
- 文件同步。
- 替代 VS Code Remote。
- 替代终端复用器。
- 公网暴露、隧道或堡垒机管理。
- 密钥、密码或 secret 管理。

## License

MIT
