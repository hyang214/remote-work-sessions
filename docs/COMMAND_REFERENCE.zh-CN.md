# 命令参考

[English](COMMAND_REFERENCE.md) | 中文

本文说明受支持的 `rws` 命令面、常用选项、副作用和输出契约。按任务场景阅读时，先看 [`SCENARIOS.zh-CN.md`](SCENARIOS.zh-CN.md)。

## 命令模型

`rws` 有三层命令：

- 日常别名：覆盖常见远程会话循环。
- 实体命令：显式管理 SSH key、设备和会话。
- setup 与诊断命令：负责安装、验证和恢复。

大多数日常命令需要已初始化的设备配置。帮助命令不需要：

```bash
rws --help
rws help scenarios
rws help commands
rws help setup
rws help new
rws help attach
rws help check
rws setup --help
rws new --help
rws run --help
```

`rws --help` 展示最高频命令。`rws help scenarios` 展示按任务组织的示例。`rws help commands` 展示完整命令面。每个公共命令族都支持主题 help：`setup`、`init`、`key`、`device`、`session`、`new`、`attach`、`force`、`background`、`check`、`doctor`、`status`、`shell`、`sessions`、`run`、`detach`、`kill` 和 `remove`。每份主题 help 都包含语法、参数/选项和典型场景；短别名指向同一份帮助。

## 全局选项

全局选项放在命令前：

```bash
rws [global options] <command> [command options]
```

| 选项 | 含义 | 持久化 |
| --- | --- | --- |
| `--config-dir DIR` | 使用指定配置目录，而不是 `~/.config/rws`。 | 仅当前命令。 |
| `-d, --device DEVICE` | 使用 `devices/<device>.conf`。 | 仅当前命令。 |
| `-H, --host HOST` | 覆盖所选设备里的 SSH host。 | 仅当前命令。 |
| `-C, --cwd DIR` | 覆盖远端工作目录。 | 仅当前命令。 |
| `-s, --session SESSION` | 覆盖所选设备的默认会话。 | 仅当前命令。 |
| `-i, --identity-file FILE` | 覆盖 SSH 私钥文件。 | 仅当前命令。 |
| `-B, --shpool-bin FILE` | 覆盖远端 `shpool` 命令或路径。 | 仅当前命令。 |
| `-o, --ssh-option OPTION` | 增加一个 OpenSSH `-o` 选项，可重复。 | 仅当前命令，除非由 setup/device update 写入。 |

临时工作使用 override；需要保存到设备配置时，使用 `rws device update`。

## 错误帮助契约

参数及其他 `rws` 校验错误以状态码 `2` 退出。stderr 第一行说明错误，随后自动
输出当前命令的 `Usage`、`Parameters and options` 和 `Typical scenarios`。因此
参数拼错或缺值时，不需要再执行一次 help 查询；`rws run` 仍保留远端命令自身
的退出码。

例如，`rws new coding --agent unknown` 会同时给出正确的 `new` 语法、可选 agent、
默认全权限行为、关闭全权限的参数，以及可复制的创建/恢复示例。全局解析错误输出
根帮助；`device`、`session` 或 `key` 内的错误输出对应命令族帮助。

## Setup 命令

### `rws setup [options]`

创建或更新设备，准备远端运行环境，验证保存后的设备，然后可选在后台创建初始 session。

常用选项：

| 选项 | 含义 |
| --- | --- |
| `-d, --device DEVICE` | 要创建或更新的设备名。 |
| `-H, --host HOST` | SSH 目标，可以是别名、主机名、IP 或 `user@host`。 |
| `-C, --cwd DIR` | 初始 session 工作目录。只有非交互式 `--create-session` 必填。 |
| `-s, --session SESSION` | 初始/默认 shpool 会话名。 |
| `-S, --create-session` | 设备验证后创建初始 session。 |
| `-x, --no-create-session` | 不询问、不创建初始 session。 |
| `-k, --key-mode create|existing|skip` | 选择 SSH key 处理方式。 |
| `-i, --identity-file FILE` | create/existing 模式下的本地私钥路径。 |
| `-K, --install-key` | 远端 `authorized_keys` 缺少该公钥时追加。 |
| `-N, --no-install-key` | 明确跳过公钥安装。 |
| `-b, --bootstrap-identity FILE` | 使用一个已经授权的 key 来安装选中的公钥。 |
| `-F, --force-key` | 本地 key 已存在时重新生成。 |
| `-r, --remote-install auto|check|skip` | 安装缺失的远端依赖、仅检查或跳过远端 setup。 |
| `--shpool-version VERSION` | 高级/测试用 shpool 版本覆盖；正式支持仍固定为 `0.9.8`。 |
| `-B, --shpool-bin FILE` | 远端 `shpool` 命令或绝对路径。 |
| `-m, --prompt-mode compact|skip` | 启用或跳过紧凑提示符。 |
| `-l, --prompt-label LABEL` | 紧凑提示符中展示的设备标签。 |
| `-o, --ssh-option OPTION` | 保存一个 SSH 选项到设备。 |
| `--verify` | 显式执行最终保存设备验证，默认开启。 |
| `-n, --no-verify` | 跳过最终保存设备验证。 |
| `-y, --yes` | 使用提供的选项非交互执行。 |

副作用：

- 写入 `~/.config/rws/default.conf`；
- 写入 `~/.config/rws/devices/<device>.conf`；
- 可能创建本地 SSH key；
- 可能把公钥追加到远端 `~/.ssh/authorized_keys`；
- 可能安装 Cargo/build 依赖和固定版本 `shpool 0.9.8`；
- 可能更新远端 `.zshrc` 或 `.bashrc` 中由 rws 管理的提示符块；
- 按需在选中的 cwd 中创建初始 shpool session；
- 不会自动 attach 到创建的 session。

交互式 setup 会在任何 session cwd 选择前验证首次 SSH 连接，在写远端状态前打印远端变更摘要，并允许在本地提示中输入 `q`、`quit` 或 `exit` 取消。默认 `--remote-install auto` 没有在命令行显式指定时，交互式 setup 会在安装缺失远端依赖前询问，因为 Rust/Cargo 和 `shpool` 安装可能持续数分钟。回答 `n` 会把本次运行切换为只检查模式。设备配置已存在时，会询问继续使用已保存值、重置替换设备或退出。密码和 sudo 密码提示由 SSH 或 sudo 处理；`rws` 不读取、不保存这些密码。

### `rws init ...`

底层配置写入命令，主要供测试和受控脚本使用。普通用户应优先使用 `rws setup`，因为 `init` 不会准备或验证远端主机。`cwd` 和 `default_session` 是可选设备字段。

### `rws doctor`

打印本地配置和远端诊断信息：

```text
device=<device>
host=<host>
cwd=<cwd 或 (not set)>
default_session=<session 或 (not set)>
shpool_bin=<path>
...
```

它会验证 SSH、配置了才验证远端 cwd、设备记录的固定 shpool 版本，以及 `shpool list --json`。失败时返回非零，并把错误写到 stderr。

### `rws c` / `rws check`

执行 `doctor` 的远端检查部分：SSH 连接、可选远端 cwd、`shpool version` 和 `shpool list --json`。

## 日常会话命令

### `rws`

连接或创建所选设备的默认会话。设备必须已有 `default_session`。

### `rws a` / `rws attach [session]`

未传 session 时连接默认会话。传入明确 session 时，先连接已存在的会话。如果命名会话不存在且没有保存 coding-agent 元数据，命令失败并打印：

```text
Run: rws new <session>
```

如果该 Session 之前通过 `--agent` 创建且仍有元数据，shpool Session 缺失时会按保存的 cwd、agent 恢复命令和权限模式重建。`attach` 不会推断或新建 coding-agent 元数据。

### `rws new SESSION [-C CWD] [-p|--pick-cwd] [-A|--agent AGENT] [--no-full-access]`

在所选设备上连接或创建 `SESSION`。

知道目录时使用 `--cwd`/`-C`。加 `--pick-cwd`/`-p` 时，`rws` 会在创建会话前打开远端目录选择器。设备没有保存 cwd 且非交互使用时，必须提供其中一个。支持：

```text
pwd
ls
ls <path>
cd <path>
mkdir <path>
mkdir -p <path>
Enter
q
```

远端有 bash 时，选择器会使用 readline，支持用 Tab 补全文件和路径。

选中的 cwd 只用于本次新建会话，不会改写设备保存的 cwd。

`--agent` 支持 `codex`、`claude`、`kiro`。新建 Session 时，`rws` 会进入选中的
cwd，创建前台 shpool 进程，并立即以全权限启动对应 agent。shpool Session 仍在
时，再次执行 `rws new` 或 `rws attach` 只会重连，不会启动第二个 agent；若
shpool 状态已丢失，则进入保存的 cwd 并执行该 agent 的恢复命令。

| Agent | 默认首次启动 | shpool 状态丢失后的默认恢复 |
| --- | --- | --- |
| `codex` | `codex --dangerously-bypass-approvals-and-sandbox` | `codex resume --last --dangerously-bypass-approvals-and-sandbox` |
| `claude` | `claude --dangerously-skip-permissions` | 同一 launcher 加 `--continue` |
| `kiro` | `kiro-cli chat --trust-all-tools` | 同一 launcher 加 `--resume` |

显式传 `--no-full-access` 时，改为持久化 provider 普通权限行为：

| Agent | 关闭全权限后的首次启动 | 关闭全权限后的恢复 |
| --- | --- | --- |
| `codex` | `codex` | `codex resume --last` |
| `claude` | `claude` | `claude --continue` |
| `kiro` | `kiro-cli chat` | `kiro-cli chat --resume` |

`rws` 不把 `cc` 当作 Claude alias，因为它通常是系统 C 编译器；Claude provider
始终调用 `claude`。全权限会移除 provider 的逐工具授权提示，只应在可信且隔离
的开发设备上使用。provider 首次初始化、新 workspace 信任或首次启用 bypass
的风险确认仍可能出现一次。旧的 `--full-access` 写法继续兼容，但由于 agent
现在默认就是全权限，该参数已是冗余写法。

首次创建必须前台进入，因此 `rws session create --agent ...` 和后台恢复不受支持。之后 `rws attach SESSION`、`rws force SESSION` 或再次执行 `rws new SESSION` 都会使用已保存的 agent/cwd。普通 session 的缺失行为不变。

恢复选择由 agent 自己完成，并限定在保存的 cwd：恢复该目录最近一次对话，不保存固定 conversation ID，也不删除更早历史。若两个 rws session 使用同一 provider 和 cwd，它们会选择同一个最近对话。

### `rws f` / `rws force [session]`

使用 shpool 的 `-f` 行为强制连接。适用于旧客户端残留、笔记本休眠、VPN 切换，或另一客户端仍被标记为 attached 的情况。

### `rws bg` / `rws background [session]`

在后台创建目标会话，然后返回本地 shell。cwd 必须来自设备配置或 `--cwd`。

带 agent 元数据的 Session 如果因重启而不存在，必须用 `rws attach` 前台恢复；`background` 会清晰失败并给出该动作。

### `rws d` / `rws detach [session...]`

分离一个或多个会话。重复分离已经断开的会话是安全的。

### `rws k` / `rws kill [session...]`

杀掉一个或多个会话。未传名称时使用所选默认会话。删除 Session 时也会删除其
本地可选 agent 元数据，因此后续 `attach` 不会重新创建它。

### `rws sessions` / `rws ls` / `rws list`

列出所选设备上的 shpool 会话。

自动化场景使用 JSON：

```bash
rws sessions --json
```

JSON 形状：

```json
{
  "sessions": [
    {
      "name": "project",
      "started_at_unix_ms": 1779762783130,
      "last_connected_at_unix_ms": 1779762790061,
      "last_disconnected_at_unix_ms": 1779762792532,
      "status": "Disconnected"
    }
  ]
}
```

这是已验证的上游 `shpool 0.9.8` JSON 形状。`rws` 直接透传，不做翻译。

### `rws s` / `rws status`

显示三个部分：

```text
== remote ==
== sessions ==
== git ==
```

用于人工查看健康状态快照。

### `rws sh` / `rws shell`

在配置的远端 cwd 中打开普通 SSH shell，不使用 shpool。需要配置或一次性提供 cwd。

### `rws run -- COMMAND [ARG...]`

在所选 cwd 中执行一次性远端命令。需要配置或一次性提供 cwd。

契约：

- stdout 是远端命令的 stdout；
- stderr 是远端命令的 stderr；
- 进程退出码是远端命令的退出码；
- cwd 缺失或不可访问时，命令执行前失败。

示例：

```bash
rws --cwd '~/repo' run -- git status --short
```

## 实体命令

### SSH Key

| 命令 | 行为 |
| --- | --- |
| `rws key create [-i, --identity-file FILE] [-f, --force]` | 创建本地 ed25519 identity 文件。 |
| `rws key get [-i, --identity-file FILE]` | 展示私钥/公钥是否存在和 fingerprint。 |
| `rws key list` | 列出已配置设备引用的 key 文件。 |
| `rws key update [-i, --identity-file FILE] [-f, --force]` | 重新生成本地 identity 文件。 |
| `rws key remove [-i, --identity-file FILE] [-f, --force]` | 删除本地 key 文件。 |

`rws key remove` 不会修改远端 `authorized_keys`。

### Device

| 命令 | 行为 |
| --- | --- |
| `rws device create DEVICE [setup options]` | 通过 setup 创建设备。 |
| `rws device get [DEVICE]` | 展示设备配置，默认读取当前选中设备。 |
| `rws device list` / `rws devices` | 列出已配置设备。 |
| `rws device update DEVICE [options]` | 修改已保存的本地设备字段。 |
| `rws device remove DEVICE` / `rws remove DEVICE` | 删除已配置设备。 |

`rws device update` 选项包括：

```text
-H, --host HOST
-C, --cwd DIR
-s, --session SESSION
-i, --identity-file FILE
--clear-identity-file
-B, --shpool-bin FILE
-m, --prompt-mode compact|skip
-l, --prompt-label LABEL
--clear-prompt-label
-o, --ssh-option OPTION
--clear-ssh-options
--default
```

修改 host、cwd、identity、shpool 或 SSH 选项后，建议运行 `rws doctor`。

### Session

| 命令 | 行为 |
| --- | --- |
| `rws session create SESSION [-C, --cwd DIR] [-p, --pick-cwd]` | 创建后台 shpool 会话；远端 cwd 不存在时会自动创建。 |
| `rws session get SESSION` | 展示单个会话对象。 |
| `rws session list [--json]` | 列出会话。 |
| `rws session update SESSION --detach` | 分离会话。 |
| `rws session delete SESSION [SESSION...]` | 杀掉一个或多个会话。 |
| `rws session attach [SESSION]` | attach 的实体命令形式。 |

## 退出行为

| 场景 | 预期行为 |
| --- | --- |
| 成功 | 退出 `0`。 |
| 用户输入或解析错误 | 退出 `2`，stderr 输出 `rws: ...`。 |
| 缺少配置 | 非零退出，并提示 `Run: rws setup`。 |
| 本地缺少 `ssh` | 退出 `2`，提示 `missing local dependency: ssh (run: rws setup)`。 |
| 本地缺少 `ssh-keygen` | 退出 `2`，提示 `missing local dependency: ssh-keygen (run: rws setup)`。 |
| SSH 失败 | 可分类时非零退出，并输出 `ssh_error=<category>`。 |
| 远端 cwd 缺失或不可访问 | 非零退出，并提示 `remote cwd missing` 或 `remote cwd not accessible`。 |
| 远端缺少 `shpool` | 非零退出，并提示 `remote dependency missing: shpool`。 |
| `rws run` 的远端命令失败 | 使用远端命令的退出码。 |
| 命名 attach 目标不存在且没有 coding-agent 元数据 | 退出 `2`，并提示 `Run: rws new <session>`。 |

常见 SSH 分类：

```text
ssh_error=dns_failed
ssh_error=connection_refused
ssh_error=connection_timeout
ssh_error=authentication_failed
ssh_error=host_key_changed
ssh_error=connection_reset
ssh_error=unknown
```

## 支持路径和尽力路径

正式支持的自动安装路径是 Alpine/apk：本地 OpenSSH、远端 build 依赖，以及通过 Cargo 安装固定版本上游 `shpool 0.9.8`。

代码中可能包含其他包管理器分支来方便用户，但在有真实 E2E 覆盖前，它们都属于 best-effort。

依赖支持矩阵见 [`DEPENDENCIES.zh-CN.md`](DEPENDENCIES.zh-CN.md)。
