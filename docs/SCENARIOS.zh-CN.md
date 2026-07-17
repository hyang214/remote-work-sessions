# 场景

[English](SCENARIOS.md) | 中文

这份指南从用户任务出发，而不是按命令分类。完整命令参考见 [`COMMAND_REFERENCE.zh-CN.md`](COMMAND_REFERENCE.zh-CN.md)。

## 使用密码登录完成首次 Setup

适用于远端机器接受用户名和密码，且你希望 `rws` 创建稳定 SSH key 供后续重连使用的场景。

```bash
rws setup
```

按向导填写：

```text
Device name: devbox
Remote host or IP: devbox.example.net
Remote SSH user (default is local user): developer
Connecting to developer@devbox.example.net. Enter the remote SSH password if prompted.
Use compact prompt for remote sessions: Y
Use SSH key authentication for stable reconnects: Y
Choose: create a dedicated key
Create an initial session now: Y
Initial session name: coding
Remote cwd: /home/developer
rws cwd> cd ~/src/sample-project
rws cwd> <press Enter>
```

执行过程：

- SSH 会在任何 session cwd 选择前询问远端密码或 host-key 确认。
- `rws` 创建或复用所选本地 key。
- 远端 `authorized_keys` 缺少公钥时，`rws` 会追加。
- `rws` 准备固定版本 `shpool` 并验证保存后的设备。
- 如果选择创建初始 session，远端 cwd picker 支持用 `ls`、`cd`、`mkdir` 和 `pwd` 浏览后再确认；session 会在后台创建，setup 只打印 attach 命令，不会自动连接进去。

Setup 后：

```bash
rws attach coding
rws s
```

如果 setup 在写入设备配置后失败，重新运行 `rws setup`，输入同一个设备名，
再选择继续使用已保存值或重置该设备。

## 使用已有 SSH Key 完成 Setup

适用于 `ssh user@host` 已经能通过 key 登录的场景。

```bash
rws setup \
  --host user@workstation \
  --key-mode existing \
  --identity-file '~/.ssh/id_ed25519'
```

检查保存后的设备：

```bash
rws doctor
```

## 在预管理远端环境中 Setup

适用于远端 SSH 和 `shpool` 都由其他系统管理的环境。

只检查，不安装：

```bash
rws setup \
  --host user@workstation \
  --key-mode skip \
  --remote-install check \
  --shpool-bin /opt/homebrew/bin/shpool
```

只写配置、不做远端验证，仅用于隔离配置生成或测试环境：

```bash
rws setup \
  --host user@workstation \
  --key-mode skip \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes
```

## 日常使用一个会话

在选择的目录中创建会话，之后只 attach 已存在会话，避免意外创建：

```bash
rws new project --pick-cwd
rws attach project
```

使用 shpool detach 序列离开会话但不杀掉它：

```text
Ctrl-Space Ctrl-q
```

稍后检查状态：

```bash
rws s
rws sessions
```

只连接一个已存在的命名会话，避免意外创建：

```bash
rws attach review
```

如果 `review` 不存在，命令会失败并打印 `rws new review` 下一步动作。

不再需要该会话时杀掉它：

```bash
rws k project
```

## 创建独立 Review 会话

当你希望在同一远端设备上保留另一份 shell 状态时，创建独立会话。

```bash
rws new review --pick-cwd
```

列出会话：

```bash
rws sessions
rws sessions --json
```

完成后删除：

```bash
rws session delete review
```

## 选择记不住的远端目录

知道主机但记不清完整远端路径时，使用 `--pick-cwd`。

```bash
rws new review --pick-cwd
```

在提示符中：

```text
rws cwd> pwd
rws cwd> ls ..
rws cwd> cd ../review-work
rws cwd>
```

按 Enter 使用当前显示目录。会话会在该目录中创建，但不会修改设备保存的 cwd。

## 远端重启或断电后恢复 Coding Agent

创建 Session 时声明一次 agent。该命令会进入选中的 cwd，并默认以全权限启动
agent，因此只应在可信远端设备上使用：

```bash
rws new coding --pick-cwd --agent codex
# 或 --agent claude / --agent kiro
```

如果需要保留 provider 的逐工具授权提示，在首次创建 Session 时加
`--no-full-access`。

平时用 shpool detach 序列退出。只要远端未重启，`rws attach coding` 会连接仍在
运行的进程。若重启或断电导致 shpool session 消失，同一命令会在保存的 cwd
中以保存的权限模式自动调用：

```text
codex resume --last --dangerously-bypass-approvals-and-sandbox
claude --dangerously-skip-permissions --continue
kiro-cli chat --trust-all-tools --resume
```

Codex 全权限模式调用官方 `codex` 命令，并传入
`--dangerously-bypass-approvals-and-sandbox`；不依赖个人 alias 或 wrapper。传入
`--no-full-access` 时，三个 provider 都保持普通权限行为。
首次使用时，Codex 仍可能询问是否信任新 cwd，Kiro 也可能要求确认 trust-all
风险；如果希望 Kiro 自己记住该选择，应选择“不再询问”。这些是 provider
控制的一次性提示，不是逐工具授权，`rws` 不会代替用户自动回答。

这些命令都选择当前 cwd 最近一次原生对话，因此同一 rws session 中多次退出、重开 agent 后，恢复的是该目录最新一次，而不是第一次。不同 rws session 如果共用同一 agent 和 cwd，也会指向同一个“最近一次”；需要隔离时使用不同目录。

恢复成立的前提是远端系统盘、workspace、agent 可执行文件及其原生历史仍在。断电可能丢失尚未刷盘的最后一小段对话或未保存文件，`rws` 不能恢复纯内存状态；重要代码仍应提交到 Git，并对远端磁盘做备份。

明确结束并取消自动恢复：

```bash
rws kill coding
```

## 修正参数错误

命令出现未知选项、参数缺值或非法参数时，`rws` 会先打印错误，再自动输出当前命令
的语法、参数和典型场景：

```bash
rws new coding --agent unknown
```

输出会指出有效值是 `codex`、`claude` 和 `kiro`，说明默认启用全权限，展示
`--no-full-access`，并给出创建和恢复示例。setup、key、device、session、attach、
诊断、run 和清理命令遵循同一规则。没有初始化配置时，也可以直接查看：

```bash
rws help new
rws help attach
rws help scenarios
```

## 从笔记本休眠或网络切换中恢复

先看远端状态：

```bash
rws s
```

如果会话存在但另一客户端仍被标记为 attached，强制连接：

```bash
rws f
```

命名会话：

```bash
rws f review
```

如果你明确想创建一个新的命名会话：

```bash
rws new review
```

不要用 `rws attach review` 创建会话。普通命名 Session 不存在时，`attach` 会失败，并打印 `rws new review` 下一步动作；有已保存 coding-agent 元数据的 Session 是恢复例外，会从元数据重建。

## 自动化中执行一次远端命令

脚本需要远端执行但不想进入交互 shell 时，使用 `rws run -- ...`。

```bash
rws --cwd '~/repo' run -- git status --short
```

自动化契约：

- 保留 stdout；
- 保留 stderr；
- 退出码等于远端命令退出码。

示例：

```bash
if ! rws --cwd '~/repo' run -- test -f package.json; then
  echo "remote project is not initialized" >&2
  exit 1
fi
```

## 使用多个设备

创建第二个设备：

```bash
rws setup \
  --device lab \
  --host user@lab-box
```

使用它：

```bash
rws --device lab new review --pick-cwd
rws --device lab attach review
```

设为默认：

```bash
rws device update lab --default
```

删除：

```bash
rws remove lab
```

## 缩短拥挤的远端提示符

Setup 时启用紧凑提示符：

```bash
rws setup --prompt-mode compact --prompt-label devbox
```

或更新已有设备：

```bash
rws device update devbox --prompt-mode compact --prompt-label devbox
```

`device update` 只修改本地配置。要安装或刷新远端 shell rc block 和 shpool prompt config，需要带紧凑提示符选项重新运行 setup：

```bash
rws setup --device devbox --prompt-mode compact --prompt-label devbox
```

紧凑模式保留设备/会话上下文，同时给命令输入区更多空间。已运行的 shpool daemon 可能会继续使用旧 prompt prefix，直到 daemon 重启。

## 排查 Setup 或连接失败

先运行：

```bash
rws doctor
```

常见失败：

| 现象 | 含义 | 下一步 |
| --- | --- | --- |
| `Run: rws setup` | 还没有初始化设备。 | 运行 `rws setup`。 |
| `ssh_error=dns_failed` | host 无法解析。 | 检查 `host` 或 SSH alias。 |
| `ssh_error=connection_refused` | SSH 服务不接受连接。 | 检查远端 SSH server 和端口。 |
| `ssh_error=connection_timeout` | 网络、VPN、防火墙或路由问题。 | 检查网络路径和 SSH 选项。 |
| `ssh_error=authentication_failed` | SSH 认证失败。 | 检查用户名、key、密码或 ssh-agent。 |
| `ssh_error=host_key_changed` | 已知 host 身份发生变化。 | 先确认主机可信，再更新 `known_hosts`。 |
| `ssh_error=connection_reset` | SSH 服务或 Podman VM 可能还在启动。 | 等待后重试。 |
| `remote cwd missing` | 保存的 cwd 不存在。 | 重建目录或更新设备 cwd。 |
| `remote cwd not accessible` | 权限不足或目录不可访问。 | 修复权限或选择其他 cwd。 |
| `remote dependency missing: shpool` | 配置的 `shpool` 路径缺失或不可执行。 | 重新运行 setup、修复 `shpool_bin`，或用 `--shpool-bin` 指向可用二进制。 |
| `expected shpool ... but found ...` | 远端 shpool 版本不匹配。 | 重新运行 setup，或把 `--shpool-bin` 指向固定版本。 |
| `shpool daemon check failed` | `shpool list --json` 失败。 | 检查远端 shpool daemon 状态。 |

## 安全清理

分离但不杀掉：

```bash
rws d
```

杀掉一个或多个会话：

```bash
rws k
rws kill review build
```

删除设备配置：

```bash
rws remove lab
```

确认不再需要本地 key 文件后再删除：

```bash
rws key remove --identity-file '~/.ssh/rws_lab_ed25519' --force
```

这不会删除远端 `authorized_keys` 中对应的公钥。
