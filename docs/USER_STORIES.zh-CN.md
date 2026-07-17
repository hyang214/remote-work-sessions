# 用户故事

[English](USER_STORIES.md) | 中文

本文只记录产品用户场景。质量门禁、发布检查和证据格式规则记录在 [`QUALITY_GATES.zh-CN.md`](QUALITY_GATES.zh-CN.md)。

只有验收标准有匹配证据时，用户故事才能标记为 verified。如果一个场景列为 open，表示它目前不是已完成的正式支持范围。

## 故事矩阵

| ID | 状态 | 用户故事 | 验收标准 | 当前证据或缺口 |
| --- | --- | --- | --- | --- |
| US-001 | Verified | 新用户可以安装工具，并获得一个名为 `rws` 的命令。 | 包名是 `remote-work-sessions`；安装后的 binary 是 `rws`；`rws --help` 和 `rws --version` 可用；不引入 `rsw` 命令。 | Smoke 在临时 global prefix 中安装包，检查 binary、版本、help 表面和没有 `rsw`。 |
| US-002 | Verified | 新用户可以运行一个 setup 流程，而不是手工拼多个步骤。 | `rws setup` 覆盖本地配置、本地 SSH 检查、任何 session cwd 选择前的首次远端连接、可选 key setup、dependency/prompt/verification 执行期间的带编号进度、远端依赖 setup、最终 connect/shpool 设备验证，以及设备就绪后的可选初始 session 创建。 | Smoke 覆盖 config-only setup 和不需要 cwd 的非交互 setup。Podman E2E 用真实 SSH、可选 setup session cwd picker、setup 带编号进度消息和真实上游 `shpool` 覆盖干净 client/server setup。 |
| US-003 | Verified | 未初始化用户会得到清晰下一步，而不是混乱命令失败。 | 日常命令在 setup 前失败，并提示用户运行 `rws setup`。 | Smoke 和 E2E 执行未初始化日常命令并断言 setup 引导。 |
| US-004 | Verified | 只有远端用户名/密码访问权限的用户，可以交互式完成首次 setup。 | Setup 在任何 session 目录选择前通过 SSH 提示密码或 host-key 确认；错误密码有清晰错误，且不会继续询问无关的后续问题；`rws` 从不读取、保存或记录密码。 | E2E 覆盖可选 session cwd picker 前的错误密码、host-key 确认、密码登录 setup，并扫描生成配置中没有密码。 |
| US-005 | Verified | 用户可以选择 setup 时如何处理 SSH key。 | Setup 支持创建专用 key、复用已有 key 或跳过 key setup；生成公钥可通过已建立交互 SSH 连接或 bootstrap key 安装；非交互 key 安装缺少 bootstrap identity 时清晰失败。 | Smoke 覆盖 key 复用、`--force-key` 和非交互 install-key 失败。E2E 覆盖 bootstrap-key setup、密码登录 key install、existing-key setup 和真实 SSH config 下的 `--key-mode skip`。 |
| US-006 | Verified | 干净本机或远端机器上，缺失前置条件时 setup 尽量处理。 | Setup 检查本地 OpenSSH tooling；缺失远端 `shpool` 时安装固定版本；需要时通过正式支持包管理器路径安装 Cargo/build 依赖；创建 session 时创建 session 目录。 | E2E 覆盖干净 Alpine 本地 OpenSSH 安装、真实远端 `apk` 依赖安装、真实 `cargo install shpool --version 0.9.8 --locked` 和真实 session cwd 创建。其他包管理器路径仍在已验证支持范围外。 |
| US-007 | Verified | 用户有一个简单配置模型，并且配置位于工具配置目录中。 | 用户配置位于 `~/.config/rws/`；设备文件在 `devices/`；默认选择使用 `device=`；会话使用 `default_session=`；未知历史 key 会清晰失败。 | Smoke 覆盖默认配置、自定义 `--config-dir`、设备文件、默认选择，以及拒绝历史 `profile` 和 `name` config key。 |
| US-008 | Verified | 用户 setup 一次设备后，可以不重复输入 host 创建多个会话。 | `rws new <session> --cwd DIR` 或 `--pick-cwd` 在所选设备上创建或连接另一个会话；`rws --device <device> new <session>` 使用该设备；设备 setup 后不需要 host。 | E2E 运行 `rws --device e2e new review` 和 `rws --device e2e new picked --pick-cwd`，并通过 JSON list 确认会话。 |
| US-009 | Verified | 日常用户可以用短且可预测的语法运行常用远端会话命令。 | `rws`、`rws f`、`rws s`、`rws c`、`rws sh`、`rws sessions`、`rws ls`、`rws bg`、`rws run -- ...`、`rws d`、`rws k`、`rws doctor`、`rws devices`、`rws remove` 和显式 `key`/`device`/`session` 实体命令都有文档，并在适用处测试；常用选项具备标准长短写法。 | Smoke 检查 help、README 命令表覆盖、`rws help scenarios`、`rws help commands` 和短选项 parser 路径。E2E 在真实 SSH/shpool 上运行日常命令集和 session 实体命令。 |
| US-010 | Verified | 长时间远端工作的用户，session 能跨断连保留并重新连接或清理。 | 后台会话创建可用；force attach 更新真实 shpool connection 状态；已经断开的会话可安全重复 detach；kill 会删除会话。 | E2E 验证 `bg`、force reattach timestamp 变化、PTY 关闭后 disconnected 状态、detach 幂等和 kill cleanup。 |
| US-011 | Verified | 有多台远端机器的用户，可以列出、选择和删除设备。 | 从 `devices/` 列出设备；`--device` 选择设备；删除默认设备时若还有其他设备会选择新的默认；没有设备时后续命令提示 setup。 | Smoke 和 E2E 验证 device list、device override、remove alias、default rewrite 和 last-device removal 后返回 setup 引导。 |
| US-012 | Verified | 现有用户可以安全重复执行 setup。 | 重复 setup 允许交互用户继续使用已保存值、重置替换设备或退出；重复非交互 setup 会把所选设备重写为当前格式；已有 key 默认复用，除非 force；公钥不重复追加；已有固定版本 `shpool` 被复用而不是重新安装。 | Smoke 验证本地 key 复用和 `--force-key`。E2E 验证已有设备的继续/重置选择、重复 setup、authorized-key 去重、existing-key setup 和复用已有固定 shpool。 |
| US-013 | Verified | 重视安全的用户可以理解工具处理哪些 secrets。 | `rws` 不保存密码、私钥内容、tokens 或 secret 环境变量；交互式密码和 sudo 提示由 SSH/sudo 处理；setup 在写远端状态前说明可能修改的远端文件。 | Smoke 检查安全声明并扫描明显 secret-storage 模式。E2E 验证密码路径不把密码写入配置，且交互式 setup 在远端写入前打印修改摘要。 |
| US-016 | Verified | 人或 AI agent 从干净环境按文档操作，可以可靠完成 setup。 | Setup 文档描述新用户路径、密码路径、非交互路径、依赖路径、幂等性、设备/会话分离、可选初始 session 创建和命令使用，不依赖聊天上下文。 | E2E 从干净环境完成。README、setup、config、scenario、dependency、command reference 和 testing docs 描述同一流程。 |
| US-018 | Verified | 每个公共 CLI 命令、别名和选项都有清晰故事和稳定契约。 | Help、README、docs 和 parser 暴露同一命令表面；`rws help` 展示高频命令，`rws help scenarios` 展示场景建议，`rws help commands` 展示完整参考；每个公共命令族都有不依赖初始化配置的主题 help，包含语法、参数/选项和典型场景；参数错误会自动附上对应命令帮助。 | Smoke 对比 help 和 README 命令表覆盖，验证所有公共主题 help 及三个固定章节，并覆盖代表性的全局、setup/init、key、device、session、agent、attach、诊断、run 和清理错误路径。 |
| US-019 | Verified | 脚本或 CI 用户可以依赖一致退出码和可执行 stderr。 | 成功命令退出 0；用户输入错误、未知选项、缺失配置、SSH 失败、setup 验证失败和远端依赖失败都非零退出；stderr 说明失败操作和可能的下一步。 | Smoke 断言用户错误退出码 2。E2E 验证错误密码、远端依赖 check 失败、doctor 失败和未初始化配置的 actionable stderr。 |
| US-020 | Verified | 非法设备、会话和配置值不能破坏文件或执行非预期路径。 | 设备名和会话名拒绝空值、`/`、`..`、路径穿越以及破坏配置布局或远端命令构造的值；配置文件拒绝未知 key；一次性 override 不持久化意外值。 | Smoke 验证非法 setup/init/remove/new/bg/d/k 值、未知 config key 和一次性 override 不改写配置。 |
| US-021 | Verified | 预管理环境用户可以使用 setup 和 override，而不会发生非预期安装或配置改写。 | `--remote-install check` 验证并清晰失败但不安装；`--remote-install skip` 跳过远端依赖 setup；`--no-verify` 为配置生成跳过网络验证；`--no-create-session` 避免创建 session；一次性 `--host`、`--cwd`、`--session` override 不改写设备文件。 | Smoke 验证 config-only 路径和一次性 override。E2E 验证 `--remote-install check` 失败且不安装，以及 `--remote-install skip --no-verify --no-create-session` 生成配置而不安装 shpool。 |
| US-022 | Verified | 排查远端访问问题的用户，可以获得清晰且可脚本化的诊断。 | `rws doctor` 打印 config、device、host、可选 cwd、可选 default session、shpool path 和远端检查详情；`rws s` 分离 remote、session 和 git 状态；诊断失败时以非零退出，并在适用处输出分类 SSH、cwd 和 shpool stderr。 | Smoke 通过 fake SSH boundary 验证 DNS、timeout、refused、auth、host-key、reset 分类，以及 `(not set)` 可选 cwd/session 字段。E2E 验证 `rws doctor` 成功字段、cwd failure stderr、shpool failure stderr 和 `rws s` 的 remote/session/git sections。 |
| US-023 | Verified | 自动化用户可以稳定解析 session 列表。 | `rws sessions --json` 返回有效 JSON，包含稳定 `sessions` array，以及 name、timestamps、status 等稳定字段；空状态表示一致。 | E2E 用 `jq` schema 检查 `sessions --json` 和 `ls --json` 的空状态和多会话状态。 |
| US-024 | Verified for current support scope | 受支持客户端和远端平台上的用户，setup 行为与文档支持矩阵一致。 | macOS 和 Linux client 被覆盖；保持 Bash 3.2+ 兼容；正式支持的自动安装路径有真实 E2E 覆盖；没有真实 E2E 的包管理器分支只标为 best-effort。 | macOS smoke gate 和 Alpine Linux container E2E 已覆盖。其他包管理器分支在有真实 E2E job 前不会升级为正式支持。 |
| US-025 | Verified for current support scope | setup 或 attach 被中断的用户，不会留下隐藏的破损状态。 | 本地 setup 提示可以取消；临时 SSH control connection 会关闭；失败 setup 清晰报告 partial state；已有设备配置时重新运行会提供继续/重置选择；可选 setup session 创建发生在设备验证之后，创建失败会清晰失败；attach 被中断不会破坏设备配置或隐藏运行中的远端会话。 | E2E 验证 setup 取消、已有设备继续/重置选择、失败 setup cleanup、可选 setup session 创建、interrupted attach 不改写配置和最终容器 cleanup。远端依赖长时间安装中被中断的 setup 仍 open。 |
| US-035 | Verified | 用户选择远端工作目录时，可以交互式选择，而不必记完整路径。 | `rws new <session> --pick-cwd`、`rws session create <session> --pick-cwd` 和可选 setup 初始 session 创建会打开 cwd picker；支持 `ls`、`ls <path>`、`cd <path>`、`mkdir <path>`、`mkdir -p <path>`、`pwd`，远端有 bash 时支持 Tab 路径补全；Enter 确认，session 在选中目录创建，并且不改写设备保存的 cwd。 | E2E 驱动密码 setup 和 host-key setup 的可选 session cwd picker。E2E 也执行 `rws --device e2e new picked --pick-cwd`，驱动 `pwd`、`ls ..`，用 Tab 将 `cd ../pic` 补全为 `cd ../picked/`，用 `mkdir -p` 创建 `picker-created/nested`，通过真实 shpool daemon log 证明 shell 在 `/home/rws/work/picker-created/nested` 启动，通过 JSON 确认 `picked` session，并 diff 前后设备配置。 |
| US-037 | Verified | 用户可以通过显式实体命令管理核心实体：SSH key、设备和会话。 | `rws key create/get/list/update/remove`、`rws device create/get/list/update/remove`、`rws session create/get/list/update/delete` 存在、有文档、拒绝不安全输入；创建 session 时如果选中 cwd 不存在，会创建该远端 cwd，并映射到真实本地配置或真实 shpool 行为。 | Smoke 在临时配置和 key 文件上验证 key CRUD、device CRUD 和生成的 session-create 命令。Podman E2E 用真实 SSH 和上游 `shpool` 验证 device/session CRUD，包括 `session create --cwd '~/work/session-created/nested'` 会创建远端目录。 |
| US-038 | Verified | setup 用户可以选择是否创建初始 session，并且 setup 不会意外连接进去。 | 设备 setup 和 session 创建分离；SSH key setup 和远端依赖 setup 都发生在任何 session cwd picker 之前；初始 session 创建是可选的，后台创建，只有创建成功后才写入默认 session，打印 `connect with: rws attach <session>`，并且不自动 attach。 | Smoke 验证不创建初始 session 的 setup 不写 `cwd` 或 `default_session`，也验证 `--create-session` 会后台创建 session 且只写 `default_session`。Podman E2E 用真实 SSH/shpool 验证交互式可选 setup session 流程。 |
| US-039 | Verified for current support scope | 远程 coding 用户可以进入选中的 cwd，默认以全权限自动启动 Codex、Claude Code 或 Kiro，并在 shpool 状态丢失或远端重启后恢复最近对话。 | `rws new <session> --agent codex\|claude\|kiro [--no-full-access]` 保存 agent、cwd 和权限模式，创建前台 shpool Session 后立即启动 agent。新 agent 默认全权限，`--no-full-access` 改用 provider 普通权限。Codex 始终使用官方 `codex` binary 和正式的全权限/恢复参数，不依赖个人 alias。Session 仍在时只重连、不重复启动；Session 缺失时，`rws attach`、`rws force` 或再次 `rws new` 使用保存的 cwd、provider 恢复命令和权限模式恢复。普通 Session 的缺失行为不变；`rws kill` 删除 Session 可选元数据。 | Smoke 验证默认全权限、显式关闭、全部 provider 映射、v2 元数据与 v1 兼容、官方 Codex 启动/恢复命令并显式断言不出现 `codexd`、Claude/Kiro 首次启动与恢复逐工具授权绕过参数、live 重连不启动第二个 agent、不重建缺失 cwd、只允许前台恢复和清理。Podman E2E 覆盖公开 SSH/shpool 生命周期；公开 GitHub Actions run 保留执行证据。 |
| US-027 | Verified | 笔记本用户可以在休眠、网络切换或 SSH 断开后恢复远端工作会话。 | 本地连接断开后，远端 shpool session 仍可用；后续 attach 重新连接同一 session，或清晰失败并给出下一步。 | Podman E2E 创建真实 session，非正常关闭本地 attached client，运行 `rws f recover`，验证同一 `started_at_unix_ms` 保持不变，并验证 `last_connected_at_unix_ms` 增加。 |
| US-028 | Verified | SSH 连接损坏的用户，可以理解问题是 DNS、timeout、refused connection、authentication、host-key change 还是 connection reset。 | 诊断区分常见 SSH 失败分类，并提供下一步命令或 setup 动作。 | Smoke 注入 SSH stderr：DNS failure、timeout、connection refused、authentication failure、host-key mismatch、connection reset，并断言分类后的 `ssh_error=...` 输出。 |
| US-029 | Verified | 远端 `shpool` 缺失、停止或版本不兼容时，用户能得到清晰恢复路径。 | `rws c`、`rws doctor` 和 setup 区分缺失 binary、daemon/list 失败和版本不匹配；恢复路径要么修复问题，要么打印需要执行的明确动作。 | E2E 在真实 SSH server 上验证 `/no/such` shpool binary 失败、fake version mismatch 和 fake daemon/list failure。Smoke 也通过 fake SSH boundary 验证 version-mismatch diagnostics。 |
| US-030 | Verified | 自动化用户可以依赖 `rws run -- ...` 的 stdout、stderr 和退出码透传。 | 成功远端命令返回 stdout/stderr 和 0；失败远端命令保留非零退出状态和有用 stderr，不被 wrapper 混淆。 | E2E 验证 `rws run -- pwd` 成功，以及 `rws run -- sh -lc '...; exit 42'` 保留 stdout、stderr 和退出码 42。 |
| US-031 | Verified | 现有用户升级 CLI 时，已有配置会安全迁移或清晰失败。 | 带旧 `setup_version` 和固定 `shpool_version` 的已支持配置文件在包升级过程中保持不被改写；升级后的 CLI 可以读取、列出、检查和修改设备配置；不支持的历史 schema key 仍然清晰失败。 | Smoke 先把旧版本包安装到临时 global prefix，创建 `setup_version=0.1.6` 的已有配置，再覆盖安装当前包，验证新版 `rws --version`，验证 `rws devices`、`rws device get`、通过 fake SSH 边界验证 `rws c`，并验证 `rws device update`。Smoke 同时保留历史未知 key 的 fail-loud 检查。 |
| US-032 | Verified | 日常用户在配置的远端工作目录消失或失去权限时，能得到有用失败。 | Status、check 和 run 路径识别 cwd 问题，不把它掩盖成通用 SSH 或 shpool 失败。 | E2E 验证 `rws c` 对缺失目录报告 `remote cwd missing`，对权限拒绝目录报告 `remote cwd not accessible`。Smoke 验证 remote cwd 错误不会被误标为 unknown SSH failure。 |
| US-033 | Open | 使用非默认 SSH 路由的用户，可以使用非标准端口、jump host 等已有 OpenSSH 配置。 | 文档化的 `--ssh-option` 和 SSH config 路径支持非默认连接路由，且不会意外改写设备配置。 | 需要针对非标准端口和 ProxyJump 风格路由的直接 E2E 或 integration 覆盖。 |
| US-034 | Verified | 日常用户连接命名 session 时，如果 session 不存在，行为可预测。 | 普通 Session 不存在时，`rws attach <session>` 清晰失败并提示 `rws new <session>`；有已保存 coding-agent 元数据的 Session 是明确的恢复例外，会从元数据重建。`rws new <session>` 仍是新建 Session 或注册的入口。 | E2E 验证普通 `rws attach missing` 失败并输出 `session not found: missing` 和 `Run: rws new missing`；coding 恢复 E2E 验证元数据恢复例外。 |
| US-036 | Verified | 日常用户在 attached session 中有足够命令输入空间，因为 prompt 不被重复 session、user、host 和 cwd 信息占满。 | Setup 支持 `prompt_mode=compact`；compact 模式移除 shpool 左侧 prompt prefix，安装受管理远端 shell prompt block，并向新 session 注入 device label，让 prompt 保留 device/session 上下文且不挤占输入区。 | Smoke 验证 prompt config 表面和非法 prompt 值。E2E 验证 compact prompt setup 写入设备配置、远端 shell rc、shpool `prompt_prefix = ""`，以及真实 session 能看到 `RWS_DEVICE_LABEL` 和 `SHPOOL_SESSION_NAME`。 |

## 当前支持覆盖范围

当前 verified scope 是 macOS smoke coverage，加上使用真实 SSH 和真实上游 `shpool` 的 Alpine Linux container E2E。

正式支持的自动安装路径是 Alpine/apk：本地 OpenSSH、远端 Cargo/build 依赖，以及通过 Cargo 安装固定上游 `shpool`。代码中的其他包管理器分支（`apt-get`、`dnf`、`yum`、`pacman`、`zypper` 和 `brew`）在有真实 E2E job 前都属于 best-effort。

## Open 用户场景缺口

以下产品场景尚未完成，不能报告为通过：

- 非默认 SSH 路由，例如非标准端口或 jump hosts（`US-033`）；
- 长时间远端依赖安装中被中断的 setup；`US-025` 只覆盖失败 setup cleanup、可选 setup session 创建和 interrupted attach。

## 历史 ID 说明

早期报告曾把 `US-014`、`US-015`、`US-017` 和 `US-026` 用于技术门禁关注点。这些 ID 不再复用为产品故事。对应规则现在由 [`QUALITY_GATES.zh-CN.md`](QUALITY_GATES.zh-CN.md) 表示。
