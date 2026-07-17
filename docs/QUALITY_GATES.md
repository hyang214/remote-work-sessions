# Quality Gates

[中文](QUALITY_GATES.zh-CN.md) | English

This document defines project verification gates. Product user scenarios are listed separately in [`USER_STORIES.md`](USER_STORIES.md).

The gates are executed by change type. A gate can pass only when the required commands or reviews were actually run, the result is recorded, and any skipped check is named as a limit.

## Gate Matrix

| ID | Gate | Pass Criteria | Execution Evidence |
| --- | --- | --- | --- |
| QG-001 | User story coverage and execution correctness | Every behavior change lists affected product story IDs from `USER_STORIES.md` or explicitly says no product story is affected. Every story claimed complete has acceptance criteria, implementation, user-visible docs when relevant, and real execution evidence. Open stories cannot be counted as passed. | Review `USER_STORIES.md`, changed files, and the verification report. For SSH/session behavior, require real SSH and real `shpool` evidence. |
| QG-002 | Real SSH/shpool lifecycle verification | Attach, detach, reconnect, background creation, force attach, kill, setup device verification, optional setup session creation, and cleanup behavior use real SSH and real upstream `shpool`; mocks are not enough for release-supported claims. | `tests/e2e/podman-e2e.sh` for setup, SSH, dependency install, and session lifecycle changes. |
| QG-003 | Public CLI surface and naming consistency | User-facing surface stays on the current model: `rws`, device, session, `devices/`, `device=`, and `default_session=`. Legacy `profile`, `name`, and `rsw` surfaces stay rejected. Help, README, parser, and docs stay aligned. | `npm test`; help/README smoke assertions; legacy rejection checks; naming scan when touched. |
| QG-004 | Packaging, dependency, and security hygiene | Runtime dependencies remain minimal; moderate-or-higher npm audit findings block release; package contents include expected docs and binary and exclude tests, `.git`, and `node_modules`; package metadata stays consistent across `package.json`, `package-lock.json`, `bin/rws`, setup-version docs, and E2E assertions; security claims remain true. | `npm audit --omit=dev --audit-level=moderate`; `npm pack --dry-run`; release-metadata checks in `npm test`. |
| QG-005 | Verification evidence quality | Release or completion evidence includes story IDs, gate IDs when relevant, commit, date, environment, commands run, key output, skipped checks, explicit limits, and result. A skipped required check cannot be summarized as passed. | Public GitHub Actions run, pull request checks, or release notes. The repository stores only the evidence policy, not machine-specific raw logs. |
| QG-006 | Platform support honesty | Only platform and installer paths with real E2E coverage can be described as release-supported. Other code branches must be documented as best-effort or open. | `docs/TESTING.md`, `docs/DEPENDENCIES.md`, E2E evidence, and user-story status review. |
| QG-007 | Error, exit-code, and input-safety contracts | User input errors, missing config, invalid device/session names, SSH failures, setup failures, and remote command failures have deterministic exit behavior and actionable stderr. Inputs cannot corrupt config or escape expected paths. | `npm test`; E2E failure-path assertions for SSH/setup/session changes; code review of quoting and path handling. |
| QG-008 | Bilingual documentation coverage | Top-level user/maintainer docs must provide both English `docs/<name>.md` and Chinese `docs/<name>.zh-CN.md` files. The two versions must link to each other; the Chinese README must link to Chinese docs. `docs/verification/` contains only a repository policy and is not shipped in the npm package. | Bilingual-docs check in `npm test`; package contents check; docs link review. |
| QG-009 | Upgrade compatibility with existing config | Every release candidate verifies upgrade over an already installed `rws` and an existing config tree. The upgrade must preserve existing device config during package installation, the new binary must read/list/check/update that config, and unsupported legacy schema changes must fail loudly instead of being silently accepted. | `npm test` upgrade-existing-config fixture: install a previous `remote-work-sessions` package into a temporary global prefix, create an existing config with older `setup_version`, install the current package over it, then verify `rws --version`, `rws devices`, `rws device get`, `rws c`, and `rws device update`. |

## Required Gate By Change Type

| Change Type | Minimum Gate |
| --- | --- |
| Docs only | Run QG-001 by reviewing affected story IDs and limits. Run QG-008. Run `npm test` when command examples, config keys, verification reports, or gate rules are touched. |
| CLI parsing or config | `npm test`; QG-001, QG-003, and QG-007; update affected user-story evidence. |
| Setup, SSH, dependency install, or session lifecycle | `npm test`; `tests/e2e/podman-e2e.sh`; QG-001, QG-002, QG-006, and QG-007; update affected user-story evidence. |
| Diagnostics or machine-readable output | `npm test`; E2E assertions for `doctor`, `status`, and JSON output when touched; QG-001 and QG-007; update affected user-story evidence. |
| Packaging or dependency change | `npm test`; `npm audit --omit=dev --audit-level=moderate`; `npm pack --dry-run`; QG-004. |
| Release candidate | `npm run test:release`; `tests/e2e/podman-e2e.sh`; run QG-001 through QG-009; retain evidence in the public GitHub Actions run and release notes. |

## Reporting Format

Use this checklist in pull requests, completion notes, or release notes:

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
- [ ] upgrade existing config gate through npm test
- [ ] tests/e2e/podman-e2e.sh
- [ ] docs reviewed

Skipped:
- none

Evidence:
- <key output or artifact path>
```
