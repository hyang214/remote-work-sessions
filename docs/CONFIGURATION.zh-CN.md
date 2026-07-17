# 配置

[English](CONFIGURATION.md) | 中文

Remote Work Sessions 使用普通 key-value 配置文件。

## 用户配置

默认用户配置位置：

```text
~/.config/rws/
  default.conf
  devices/
    default.conf
  sessions/
    default/
      coding.conf
```

通过集成 setup 流程创建：

```bash
rws setup
```

## 设备和会话

`rws` 把设备和会话分开：

- 设备：可复用的 SSH 连接配置，包括 host、identity 文件、SSH 选项、提示符偏好和远端 `shpool` 路径。
- 会话：某个设备上的一个 shpool 会话。
- 远端运行环境：setup 管理的远端状态，例如 `shpool`、shpool config 和可选 shell prompt block。

设备完成 setup 后，在该设备上创建新会话不再需要 `--host`：

```bash
rws new review
rws new review --pick-cwd
rws --device lab new build
rws bg long-build
rws session create review --pick-cwd
rws session update review --detach
rws session delete review
rws sessions
```

只在 setup 或有意做一次性覆盖时使用 `--host`。

`rws new <session> --pick-cwd` 可以在创建新会话前查看并切换远端 cwd。选中的目录只对本次创建生效；设备文件不需要、也不会因此写入保存的 `cwd`。

设备名和会话名必须是普通标识符：字母、数字、点、下划线和连字符。不能为空，不能以 `.` 或 `-` 开头，不能包含 `/` 或 `..`。

## Session 可选恢复元数据

首次执行 `rws new SESSION --agent codex --cwd '~/repo'` 时，
`rws` 会写入 `sessions/<device>/SESSION.conf`：

```text
rws-coding-session-v2
codex
~/repo
full
```

这些字段只是给现有 Session 增加可选的 agent、远端 cwd 和权限模式属性，
并没有定义新实体。新建 agent Session 默认记录 `full`；显式传
`--no-full-access` 时记录 `default`，表示 provider 普通权限。文件权限受
`umask 077` 保护，不含 prompt、conversation 内容、token 或 secret。agent
原生历史仍保存在远端自己的数据目录中，`rws` 不复制或解析它。

Session 恢复元数据保存在发起连接的本机配置目录中。换一台客户端不会自动
同步；可在新客户端重新执行一次带 `--agent` 的 `rws new`。`rws kill`/
`session delete` 会删除对应元数据，删除设备会删除其全部 Session 元数据。

恢复要求远端磁盘上的 cwd、agent 可执行文件和 agent 原生历史仍然存在。恢复不会自动重建丢失 workspace，也不能恢复断电前尚未落盘的进程内状态。

历史 `rws-coding-session-v1` 文件仍可读取，并按 `default` 权限处理，避免升级
后静默扩大已有 Session 权限；已有 v2 文件也继续使用其保存的权限值。新写入
使用 v2。

## 默认设备

`default.conf` 选择 `rws` 默认使用的设备：

```conf
device=default
```

## 设备格式

每个设备保存为 `devices/<name>.conf`：

```conf
host=workstation
identity_file=~/.ssh/rws_default_ed25519
shpool_bin=shpool
prompt_mode=compact
prompt_label=workstation
setup_version=0.2.0
shpool_version=0.9.8
ssh_option=ServerAliveInterval=30
```

字段：

| Key | 含义 |
| --- | --- |
| `host` | SSH host 或别名。 |
| `cwd` | 可选远端工作目录。不同 session 使用不同目录时，优先用每次 session 创建的 `--cwd` 或 `--pick-cwd`。 |
| `default_session` | 可选默认 shpool 会话名。setup 只有在创建初始 session 时才写入。 |
| `identity_file` | 可选 SSH 私钥路径。 |
| `shpool_bin` | 远端 shpool 命令或路径，默认 `shpool`。 |
| `prompt_mode` | `compact` 或 `skip`，缺省为 `skip`。 |
| `prompt_label` | 紧凑提示符中的设备标签；`prompt_mode=compact` 时默认用设备名。 |
| `setup_version` | 上次写入该设备的 `rws` setup 版本。 |
| `shpool_version` | setup 需要远端安装时使用的固定 shpool 版本。 |
| `ssh_option` | 可选 SSH `-o` 选项，可出现多次。 |

只接受这些当前 key。未知 key 会直接失败，不作为历史兼容静默处理。

## SSH Key Setup

交互式 `rws setup` 会询问 key setup 选择。脚本中使用明确模式：

```bash
rws setup --host workstation --key-mode create --identity-file '~/.ssh/rws_workstation_ed25519'
rws setup --host workstation --key-mode existing --identity-file '~/.ssh/id_ed25519'
rws setup --host workstation --key-mode skip --no-install-key
```

用远端用户的普通 SSH 密码创建设备 key 并安装公钥：

```bash
rws setup --host user@workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key
```

SSH 负责交互式密码和 host-key 提示。`rws` 不读取、不保存密码。

交互式 setup 在首次登录成功后打开一个临时 SSH control connection。如果选择安装 SSH key，setup 会用同一连接追加公钥并继续远端初始化。setup 会在最终验证前关闭临时连接，再用保存后的设备重新连接。

非交互式 setup 需要通过已授权的 bootstrap key 安装公钥：

```bash
rws setup --host workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key \
  --bootstrap-identity '~/.ssh/id_ed25519'
```

两种路径都会把选中的公钥追加到远端用户的 `~/.ssh/authorized_keys`。密码存储不在范围内。

## Setup 幂等性

`rws setup` 可以重复执行：

- 已有设备文件会用所选值重写；
- 已有生成 key 会复用，除非传入 `--force-key`；
- 缺失的 `.pub` 会从私钥重新生成；
- 公钥只在 `authorized_keys` 缺失时追加；
- 创建 session 时，session 工作目录通过 `mkdir -p` 创建；
- 只有缺少 `shpool` 且 `--remote-install auto` 时才安装；
- 紧凑提示符 setup 只更新受管理的 shell rc block 和 shpool `prompt_prefix`；
- 最终验证会重新连接并检查 SSH 与 `shpool`。

## 紧凑提示符

交互式 setup 会询问是否为远端会话启用紧凑提示符。非交互式 setup 默认 `prompt_mode=skip`，除非显式设置：

```bash
rws setup --prompt-mode compact --prompt-label workstation
rws setup --prompt-mode skip
```

zsh 远端会把当前目录放在左侧，把设备/会话上下文放在右侧：

```text
project %                                      [workstation:project]
```

bash 远端没有原生右提示符，因此使用较短左提示符：

```text
[workstation:project] project $
```

设备标签通过 `RWS_DEVICE_LABEL` 注入每个新 shpool 会话。会话名来自 shpool 的 `SHPOOL_SESSION_NAME`。

使用 `--remote-install check` 可以只验证远端依赖而不安装。`--remote-install skip` 只用于测试或远端 setup 已由其他系统管理的环境。只有在保存设备还无法验证时，例如隔离配置生成测试，才使用 `--no-verify`。

## 多设备

创建另一个设备：

```text
~/.config/rws/devices/lab.conf
```

```conf
host=lab-box
```

使用它：

```bash
rws --device lab new review --pick-cwd
rws --device lab attach review
```

列出或删除设备：

```bash
rws devices
rws device get lab
rws device update lab --cwd '~/work/other' --session other --default
rws remove lab
```

一次性覆盖：

```bash
rws --host lab-box --cwd '~/work/other' --session other
```

## 实体命令

CRUD 风格实体命令：

| 实体 | Create | Read | Update | Delete |
| --- | --- | --- | --- | --- |
| SSH key | `rws key create` | `rws key get`, `rws key list` | `rws key update --force` | `rws key remove --force` |
| 设备 | `rws device create` | `rws device get`, `rws device list` | `rws device update` | `rws device remove` |
| 会话 | `rws session create` | `rws session get`, `rws session list` | `rws session update --detach` | `rws session delete` |

`rws device get` 可接收可选设备名；不传时读取默认设备。`rws device update` 修改本地设备配置字段，例如 `host`、`cwd`、`default_session`、`identity_file`、`shpool_bin`、prompt 设置和 SSH 选项。使用 `--clear-identity-file`、`--clear-prompt-label` 或 `--clear-ssh-options` 删除可选字段。需要远端验证连接字段时，运行 `rws doctor`。

`rws session create SESSION --cwd DIR` 会在一次性目录里创建该会话，不改写设备默认值。`rws session get SESSION` 返回匹配的会话对象。`rws session delete` 接受一个或多个会话名。

`rws key remove` 只删除本地 key 文件，不会编辑远端用户的 `authorized_keys`。
