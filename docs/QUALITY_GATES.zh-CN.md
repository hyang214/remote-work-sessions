# 质量门禁

[English](QUALITY_GATES.md) | 中文

本文定义项目验证门禁。产品用户场景单独记录在 [`USER_STORIES.zh-CN.md`](USER_STORIES.zh-CN.md)。

门禁按变更类型执行。只有实际运行了要求的命令或评审、记录了结果，并且明确列出所有跳过项，门禁才能算通过。

## 门禁矩阵

| ID | 门禁 | 通过标准 | 执行证据 |
| --- | --- | --- | --- |
| QG-001 | 用户故事覆盖和执行正确性 | 每个行为变更都列出受影响的 `USER_STORIES.md` 产品故事 ID，或明确说明不影响产品故事。每个声称完成的故事必须有验收标准、实现、必要的用户可见文档和真实执行证据。Open 状态故事不能算通过。 | Review `USER_STORIES.md`、变更文件和验证报告。SSH/session 行为必须有真实 SSH 和真实 `shpool` 证据。 |
| QG-002 | 真实 SSH/shpool 生命周期验证 | attach、detach、reconnect、background creation、force attach、kill、setup 设备验证、可选 setup session 创建和 cleanup 使用真实 SSH 和真实上游 `shpool`；mock 不足以支撑正式支持声明。 | `tests/e2e/podman-e2e.sh` 覆盖 setup、SSH、依赖安装和会话生命周期变更。 |
| QG-003 | 公共 CLI 表面和命名一致性 | 用户可见表面保持当前模型：`rws`、device、session、`devices/`、`device=`、`default_session=`。历史 `profile`、`name` 和 `rsw` 表面继续拒绝。Help、README、parser 和 docs 保持一致。 | `npm test`；help/README smoke 断言；历史命名拒绝检查；涉及命名时进行扫描。 |
| QG-004 | 包、依赖和安全卫生 | 运行时依赖保持最小；moderate 及以上 npm audit 问题阻塞发布；包内容包含预期 docs 和 binary，并排除 tests、`.git`、`node_modules`；`package.json`、`package-lock.json`、`bin/rws`、setup-version 文档和 E2E 断言中的发布元数据保持一致；安全声明仍然成立。 | `npm audit --omit=dev --audit-level=moderate`；`npm pack --dry-run`；`npm test` 中的 release-metadata 检查。 |
| QG-005 | 验证证据质量 | 发布或完成证据包含故事 ID、相关门禁 ID、commit、日期、环境、运行命令、关键输出、跳过项、明确限制和结果。跳过的必需检查不能总结为通过。 | 公开 GitHub Actions run、pull request checks 或 release notes。仓库只保存证据策略，不提交机器相关的原始日志。 |
| QG-006 | 平台支持诚实性 | 只有具备真实 E2E 覆盖的平台和安装路径，才能描述为正式支持。其他代码分支必须标为 best-effort 或 open。 | `docs/TESTING.md`、`docs/DEPENDENCIES.md`、E2E 证据和 user-story 状态 review。 |
| QG-007 | 错误、退出码和输入安全契约 | 用户输入错误、缺失配置、非法设备/会话名、SSH 失败、setup 失败和远端命令失败都有确定退出行为和可执行的 stderr。输入不能破坏配置或逃逸预期路径。 | `npm test`；SSH/setup/session 变更需要 E2E failure-path 断言；代码评审 quoting 和路径处理。 |
| QG-008 | 中英文文档覆盖 | 顶层用户/维护者文档必须同时提供英文 `docs/<name>.md` 和中文 `docs/<name>.zh-CN.md`。两个版本必须互链；中文 README 必须链接中文 docs。`docs/verification/` 只保存仓库策略，不随 npm package 发布。 | `npm test` 中的 bilingual-docs 检查；package contents 检查；文档链接 review。 |
| QG-009 | 已有配置升级兼容 | 每个 release candidate 都要验证在已经安装过 `rws` 且已有配置树的情况下升级。升级安装不能改写已有设备配置；新版 binary 必须能读取、列出、检查和修改该配置；不支持的历史 schema 变化必须清晰失败，不能静默接受。 | `npm test` 中的 upgrade-existing-config fixture：先把旧版 `remote-work-sessions` 包安装到临时 global prefix，创建带旧 `setup_version` 的已有配置，再覆盖安装当前包，验证 `rws --version`、`rws devices`、`rws device get`、`rws c` 和 `rws device update`。 |

## 按变更类型要求的门禁

| 变更类型 | 最低门禁 |
| --- | --- |
| 仅文档 | 通过 review 运行 QG-001，确认受影响 story 和限制；运行 QG-008；涉及命令示例、配置 key、验证报告或门禁规则时运行 `npm test`。 |
| CLI 解析或配置 | `npm test`；QG-001、QG-003 和 QG-007；更新受影响 user-story 证据。 |
| Setup、SSH、依赖安装或会话生命周期 | `npm test`；`tests/e2e/podman-e2e.sh`；QG-001、QG-002、QG-006 和 QG-007；更新受影响 user-story 证据。 |
| 诊断或机器可读输出 | `npm test`；涉及 `doctor`、`status` 和 JSON 输出时补 E2E 断言；QG-001 和 QG-007；更新受影响 user-story 证据。 |
| 包或依赖变更 | `npm test`；`npm audit --omit=dev --audit-level=moderate`；`npm pack --dry-run`；QG-004。 |
| 发布候选 | `npm run test:release`；`tests/e2e/podman-e2e.sh`；运行 QG-001 到 QG-009；在公开 GitHub Actions run 和 release notes 中保留证据。 |

## 报告格式

PR、完成说明或 release note 使用这个 checklist：

```text
Stories:
- US-___:

Gates:
- QG-___:

Commit:
- <sha>

Environment:
- OS:
- Node:
- Podman/base image:
- Cargo registry:

Verification:
- [ ] npm test
- [ ] npm audit --omit=dev --audit-level=moderate
- [ ] npm pack --dry-run
- [ ] 通过 npm test 执行已有配置升级门禁
- [ ] tests/e2e/podman-e2e.sh
- [ ] docs reviewed

Skipped:
- none

Evidence:
- <key output or artifact path>
```
