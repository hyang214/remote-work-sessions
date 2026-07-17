# 依赖

[English](DEPENDENCIES.md) | 中文

Remote Work Sessions 有意保持较小的依赖面。

## npm 包

npm 包没有运行时 npm 依赖。lockfile 已提交，用来保持包元数据确定。

安全检查：

```bash
npm audit --omit=dev --audit-level=moderate
```

## 本地运行时

必需本地命令：

- `bash`；
- `ssh`；
- `ssh-keygen`。

当缺少 OpenSSH client 工具且存在受支持的本地包管理器时，`rws setup` 会尝试安装。当前发布门禁在干净 Alpine/apk 容器里验证这一路径。

如果 `bash` 本身缺失，操作系统会在 `rws` 启动前报告 `env: bash: No such file or directory`。如果 Bash 低于 3.2，`rws` 会退出并提示 `missing local dependency: Bash 3.2+ required`。

需要 SSH 的日常命令会在连接前检查本地 `ssh`：

```text
rws: missing local dependency: ssh (run: rws setup)
```

key 管理命令需要 `ssh-keygen`，缺失时会在处理 key 前失败：

```text
rws: missing local dependency: ssh-keygen (run: rws setup)
```

## 远端运行时

必需远端服务和命令：

- OpenSSH server；
- `shpool`。

当缺少 `shpool` 且使用 `--remote-install auto` 时，setup 会按需安装 Cargo、安装原生 build 依赖，然后安装固定 shpool 版本：

```bash
cargo install shpool --version 0.9.8 --locked
```

`--locked` 会让 Cargo 使用上游包 lockfile 中选定的依赖版本。

正式支持的自动远端安装路径是 Alpine/apk。Podman E2E 使用干净 server 容器验证这一路径。

如果远端 SSH 服务缺失或不可达，`rws` 会报告分类后的 SSH 错误，例如 `ssh_error=connection_refused` 或 `ssh_error=connection_timeout`。如果 SSH 可用但远端缺少 `shpool`，`rws doctor`、`rws check` 和会话命令会报告：

```text
rws: remote dependency missing: shpool (<configured path>). Run: rws setup
```

CLI 中包含 `apt-get`、`dnf`、`yum`、`pacman`、`zypper` 和 `brew` 的 best-effort 安装分支，但这些分支在有真实 E2E 覆盖前不属于正式支持范围。没有这类运行证据时，不要宣称已完整验证。

重复 setup 会先检查 `PATH` 上的 `shpool` 和 `~/.cargo/bin/shpool`。只要其中一个匹配固定版本，就会复用并跳过 Cargo 安装。

## 可选 Coding Agent

使用 `rws new <session> --agent <agent>` 时，远端还必须安装所选 coding
agent：

| Agent | 远端必需命令 | 恢复命令 |
| --- | --- | --- |
| `codex` | `codex` | `codex resume --last --dangerously-bypass-approvals-and-sandbox` |
| `claude` | `claude` | `claude --dangerously-skip-permissions --continue` |
| `kiro` | `kiro-cli` | `kiro-cli chat --trust-all-tools --resume` |

默认情况下，`--agent codex` 调用已安装的官方 `codex` binary，并传入
`--dangerously-bypass-approvals-and-sandbox`；恢复时调用 `codex resume --last`
并携带同一参数。个人 alias 或 wrapper 不会被探测，也不属于受支持的 Codex
命令。`--no-full-access` 则改用各 provider 的普通启动和恢复命令。Claude 仍要求
`claude`；`rws` 绝不把常见的系统 C 编译器命令 `cc`
当成 Claude。Kiro CLI 2.x 的默认全权限启动必须支持 `--trust-all-tools`。

普通 shell session 不依赖这些命令。`rws setup` 不安装 coding agent，也不替
provider 登录；请先在远端安装所选工具并完成登录。命令缺失时，session 创建前
会以 `remote dependency missing: coding agent ...` 清晰失败。

对话历史仍由 provider 保存在其正常远端目录。`rws` 只保存调用 provider 恢复
命令所需的 agent 类型、远端 cwd 和权限模式。

远端管理员权限：

- 交互式 setup 支持正常 sudo 密码提示；
- 非交互式 setup 需要 root、免密 sudo，或预先安装好 Cargo/shpool；
- 免密 sudo 是 CI 便利条件，不是用户使用要求。

## 版本策略

- npm 运行时依赖：无。
- 远端 shpool 版本：`0.9.8`。
- 远端安装模式默认是 `auto`。
- 用户可以选择 `--remote-install check` 只检查不安装，或在预管理环境里选择 `--remote-install skip`。
