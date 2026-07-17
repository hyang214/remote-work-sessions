# 测试

[English](TESTING.md) | 中文

Remote Work Sessions 有两层测试，另有独立质量门禁策略。

产品用户场景在 [`docs/USER_STORIES.zh-CN.md`](USER_STORIES.zh-CN.md)。质量门禁在 [`docs/QUALITY_GATES.zh-CN.md`](QUALITY_GATES.zh-CN.md)。QG-001 要求每个行为变更映射到受影响用户故事，并在把故事标记为完成前提供真实执行证据。QG-008 要求顶层用户/维护者文档都有中英文版本。

## Smoke Tests

快速本地检查：

```bash
scripts/smoke-test.sh
```

这些检查覆盖 shell 语法、help 输出、README 命令表覆盖、`package.json`、`package-lock.json`、`bin/rws`、setup docs 和 E2E 断言之间的发布元数据一致性、`npm pack --dry-run --json` 的包内容、必要安全声明、公开发布证据策略、未初始化保护、用户错误退出码 2 及按命令输出的帮助、非交互 setup、重复 setup、key 复用、`--force-key`、显式 key CRUD、`--config-dir`、一次性覆盖、非法设备/session/prompt 值、prompt config 写入、device CRUD、默认设备重写、最后一个设备删除、包元数据、coding-agent 恢复、新 agent 默认全权限、显式 `--no-full-access`、v1 恢复元数据兼容、Session 清理、普通缺失 session 行为不变，以及在已有 `rws` 安装和已有配置树上的升级。

Smoke tests 也会拒绝历史 `profile` 和 `name` 配置或命令形式，确保公共表面只保留当前模型。它们验证每个公共命令族的主题 help，并要求代表性的全局、setup/init、key、device、session、agent、attach、诊断、run 和清理错误都附带 `Usage`、`Parameters and options` 和 `Typical scenarios`。同时分类 SSH 边界失败：DNS、timeout、connection refused、authentication failure、host-key mismatch 和 connection reset。

QG-009 是升级门禁。它会先把旧版 `remote-work-sessions` 包安装到临时 global prefix，创建带旧 `setup_version` 的已有配置，再覆盖安装当前包，然后验证新版 `rws` 可以读取、列出、检查和修改保留下来的配置。

此外，smoke tests 执行 bilingual-docs 门禁：每个顶层英文 doc 必须有对应 `*.zh-CN.md`，双方必须互链，中文 README 必须链接中文 docs。`docs/verification/` 只保存公开证据策略；机器相关执行日志保留在 GitHub Actions 中，并从 npm package 排除。

## Container E2E

运行：

```bash
tests/e2e/podman-e2e.sh
```

E2E 脚本先检查 `podman` 命令是否存在，再等待 `podman info` 成功后创建容器。这处理了 macOS Podman 的情况：`podman machine start` 已返回或 `podman machine list` 显示 `running`，但 SSH/API forwarding 仍在启动，短时间可能出现 connection reset。默认 readiness timeout 是 180 秒：

```bash
RWS_E2E_PODMAN_READY_TIMEOUT=240 tests/e2e/podman-e2e.sh
```

每次运行都会根据进程 ID 生成独立的 client、server 和 network 名，避免遗留资源或并发 E2E 相互冲突。调试时仍可通过 `RWS_E2E_CLIENT`、`RWS_E2E_SERVER` 和 `RWS_E2E_NETWORK` 指定固定名称。

默认 base image 是 `alpine:3.22`，因为安装 `shpool 0.9.8` 需要 Rust 1.85+。网络镜像更好时可覆盖：

```bash
RWS_E2E_BASE_IMAGE=docker.m.daocloud.io/library/alpine:3.22 tests/e2e/podman-e2e.sh
```

如果本地 Podman VM 在安装完整 Rust toolchain 时写入慢或不稳定，使用 Rust Alpine base image。这仍然会启动一个没有 `shpool` 的干净 server 容器；setup 会安装 build 依赖和真实固定版本 `shpool` package：

```bash
RWS_E2E_BASE_IMAGE=docker.m.daocloud.io/library/rust:1.87-alpine3.22 tests/e2e/podman-e2e.sh
```

默认 Alpine package source 是官方 `https://dl-cdn.alpinelinux.org/alpine`。需要时覆盖：

```bash
RWS_E2E_APK_MIRROR=https://dl-cdn.alpinelinux.org/alpine tests/e2e/podman-e2e.sh
```

E2E server 默认 Cargo registry 是官方 sparse index：`sparse+https://index.crates.io/`。需要时覆盖或置空：

```bash
RWS_E2E_CARGO_REGISTRY_INDEX= tests/e2e/podman-e2e.sh
```

E2E 测试启动两个容器：

- client 容器运行 `rws`；
- server 容器接受 SSH，并且启动时没有 `shpool`。

镜像中的 `expect` 只用于测试自动化，`jq` 只用于 JSON 契约断言。测试会为 attach 路径驱动真实 PTY。默认 attach 和 `rws new` 使用 shpool 默认 `Ctrl-Space Ctrl-q` detach 序列分离。Force attach 通过记录 `rws f` 前后的 `last_connected_at_unix_ms`、关闭 PTY、并断言真实 shpool 会话回到 `Disconnected` 来验证。`rws d` 也会在真实 server 会话上执行。

它验证：

- client 和 server 初始化；
- SSH bootstrap key 生成；
- 干净 Alpine client 上的本地 OpenSSH 安装；
- setup 前未初始化命令失败；
- 密码登录 setup 的错误密码失败和清晰错误；
- SSH 真实 host-key 确认提示；
- `rws setup --remote-install check` 在缺失远端依赖时失败且不安装；
- 独立 `rws setup --remote-install skip --no-verify` 不安装 shpool；
- `rws setup --key-mode create`；
- 紧凑提示符 setup，包括设备配置、远端 shell rc block、shpool `prompt_prefix` 和每个 session 的 `RWS_DEVICE_LABEL`；
- 通过已授权 bootstrap key 安装公钥；
- 本地 setup 提示中取消 setup；
- 已有设备 setup 的继续使用已保存值和重置选择；
- 错误密码 setup 在任何 session cwd picker 前失败；
- 交互式密码登录 setup 通过已建立 SSH 连接安装生成的 SSH key；
- 交互式 setup 区分设备创建和可选初始 session 创建；
- 可选 setup session 的 cwd picker 在设备验证后执行，session 后台创建，且不会自动 attach；
- dependency、shpool、prompt、verification 和可选 session 步骤执行期间有带编号的 setup 进度消息；
- 密码路径不会把远端密码写入生成配置树；
- 通过真实 OpenSSH config entry 执行 `rws setup --key-mode skip`；
- 非交互式路径中，如果基于密码的 key 安装需要终端，会失败；
- 在 `~/.config/rws` 下创建设备；
- 最终 setup 验证：重连并真实检查 shpool；
- `rws c`；
- `rws doctor`；
- 缺失 shpool binary、shpool 版本不匹配和 shpool daemon/list 失败诊断；
- 缺失和不可访问远端 cwd 诊断；
- `rws s`；
- `rws run -- ...`，包括 stdout、stderr 和失败远端命令非零退出码透传；
- `rws sh`；
- `rws ls --json` 的 JSON schema 断言；
- `rws sessions --json` 的空状态和多会话状态断言；
- `rws attach <missing-session>` 失败并给出 `rws new <session>` 下一步；
- 基于真实上游 `shpool` 的 `rws session create/get/list/update/delete`；
- 在 server 容器内使用确定性的 provider fixture，通过真实 SSH 和上游 `shpool` 验证 Codex、Claude Code、Kiro Session 创建、全权限模式持久化、显式 `--no-full-access` 与 `--full-access`、只调用官方 `codex` binary、首次启动和恢复都携带 provider 免确认参数、live reattach 不重复启动 provider、模拟 shpool 状态丢失、前台恢复和元数据清理；
- 通过 `podman kill --signal KILL` 模拟 server 异常退出，重启同一容器，等待 SSH 恢复，lazy 恢复 Codex，并用持久化 provider-history marker 证明恢复命令读取了重启前写入的状态；
- 显式存在默认 session 后，裸 `rws` 可以默认 attach；
- 已有设备上执行 `rws new <session>`，不传 `--host`；
- `rws new <session> --pick-cwd` 交互式 `pwd`/`ls`/`cd`，通过真实 shpool daemon log 证明 session shell 在选中目录启动，并证明设备配置未改写；
- `rws bg`；
- `rws f`；
- 本地 attached client 未按正常 detach 序列关闭后，重新连接到同一个远端会话；
- attach 被中断时不破坏设备配置；
- `rws d`，包括 already-disconnected 幂等路径；
- `rws k`；
- 使用同一生成 key 重复 setup；
- `authorized_keys` 中生成公钥去重；
- `rws setup --key-mode existing`；
- `rws devices`；
- `rws device list`、`rws device get`、`rws device update` 和 `rws device remove`；
- 另一个设备是默认设备时的 `rws --device <device>` override；
- `rws remove`，包括默认设备重写和最后一个设备删除；
- 通过真实固定 `cargo install` 路径安装远端缺失的 `shpool`。

Container E2E 使用上游 `shpool`，不是 mock。它比 smoke 慢，因为它验证真实依赖安装、SSH setup、会话创建、重连、detach 和 kill 行为。

正式支持的自动安装路径就是这里覆盖的路径：本地 OpenSSH 和远端 Cargo/build 依赖走 Alpine/apk，固定上游 `shpool` 通过 Cargo 安装。CLI 中可能存在其他包管理器分支作为 best-effort 便利，但在有真实 E2E 覆盖前，它们不属于已完成故事和质量门禁范围。

## 质量门禁

标记用户故事完成前，运行 [`docs/QUALITY_GATES.zh-CN.md`](QUALITY_GATES.zh-CN.md) 中的 QG-001，并确认：

- 变更说明中列出 story ID；
- `docs/USER_STORIES.md` 中的验收标准仍准确；
- 该故事要求的命令或人工检查已经运行；
- 所有跳过的验证都被明确说明。

涉及用户/维护者文档时，也运行 QG-008，并确认中英文版本和链接同步。
