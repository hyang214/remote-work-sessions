# Testing

[中文](TESTING.zh-CN.md) | English

Remote Work Sessions has two test layers plus a separate quality-gate policy.

Product user scenarios live in [`docs/USER_STORIES.md`](USER_STORIES.md). Quality gates live in [`docs/QUALITY_GATES.md`](QUALITY_GATES.md). QG-001 requires every behavior change to map to affected user stories and to have real execution evidence before any story is called complete.
QG-008 requires top-level user and maintainer docs to keep English and Chinese versions.

## Smoke Tests

Fast local checks:

```bash
scripts/smoke-test.sh
```

These validate shell syntax, help output, README command-table coverage, release metadata consistency across `package.json`, `package-lock.json`, `bin/rws`, setup docs, and E2E assertions, package contents from `npm pack --dry-run --json`, required security claims, the public-release evidence policy, the uninitialized guard, exit code 2 plus command-aware help for user errors, non-interactive setup, repeated setup, key reuse, `--force-key`, explicit key CRUD commands, `--config-dir`, one-off overrides, invalid device/session/prompt values, prompt config writing, device CRUD commands, default-device rewrite, last-device removal, package metadata, coding-agent recovery, full access as the new-agent default, explicit `--no-full-access`, v1 recovery-metadata compatibility, Session cleanup, unchanged ordinary missing-session behavior, and upgrade over an existing installed `rws` with an existing config tree.

Smoke tests also enforce the current-only public surface by rejecting legacy `profile` and `name` config or command forms. They verify topic help for every public command family and require `Usage`, `Parameters and options`, and `Typical scenarios` after representative global, setup/init, key, device, session, agent, attach, diagnostic, run, and cleanup errors. They also classify SSH boundary failures for DNS, timeout, connection refused, authentication failure, host-key mismatch, and connection reset.

QG-009 is the upgrade gate. It installs a previous `remote-work-sessions` package into a temporary global prefix, creates an existing config with an older `setup_version`, installs the current package over it, then verifies that the new `rws` can read, list, check, and update the preserved config.

Smoke tests also enforce the bilingual-docs gate: every top-level English doc must have a matching `*.zh-CN.md` file, both files must link to each other, and the Chinese README must link to Chinese docs. `docs/verification/` contains only the public evidence policy; machine-specific execution logs stay in GitHub Actions and are excluded from the npm package.

## Container E2E

Run:

```bash
tests/e2e/podman-e2e.sh
```

The E2E script first checks that the `podman` command exists, then waits for `podman info` before creating containers. This handles the macOS Podman case where `podman machine start` has returned or `podman machine list` says `running`, but SSH/API forwarding is still warming up and may briefly fail with connection-reset errors. The default readiness timeout is 180 seconds:

```bash
RWS_E2E_PODMAN_READY_TIMEOUT=240 tests/e2e/podman-e2e.sh
```

Each run derives unique client, server, and network names from its process ID,
so a stale or concurrent E2E run does not collide with the current run. Stable
names can still be supplied with `RWS_E2E_CLIENT`, `RWS_E2E_SERVER`, and
`RWS_E2E_NETWORK` when debugging.

The default base image is `alpine:3.22`, because `shpool 0.9.8` requires Rust 1.85+ during installation. Override it when your network has a better mirror:

```bash
RWS_E2E_BASE_IMAGE=docker.m.daocloud.io/library/alpine:3.22 tests/e2e/podman-e2e.sh
```

If your local Podman VM has slow or unreliable writes while installing the full Rust toolchain, use a Rust Alpine base image. This still starts a clean server container without `shpool`; setup will install build dependencies and the real pinned `shpool` package:

```bash
RWS_E2E_BASE_IMAGE=docker.m.daocloud.io/library/rust:1.87-alpine3.22 tests/e2e/podman-e2e.sh
```

The default Alpine package source is the official `https://dl-cdn.alpinelinux.org/alpine`. Override it when needed:

```bash
RWS_E2E_APK_MIRROR=https://dl-cdn.alpinelinux.org/alpine tests/e2e/podman-e2e.sh
```

The default Cargo registry for the E2E server is the official sparse index, `sparse+https://index.crates.io/`. Override it or set it empty when needed:

```bash
RWS_E2E_CARGO_REGISTRY_INDEX= tests/e2e/podman-e2e.sh
```

The E2E test starts two containers:

- a client container that runs `rws`;
- a server container that accepts SSH and starts without `shpool`.

The image includes `expect` only for test automation and `jq` only for JSON contract assertions. It drives real PTYs for attach paths. Default attach and `rws new` are detached with shpool's default `Ctrl-Space Ctrl-q` detach sequence. Force attach is verified by recording `last_connected_at_unix_ms` before and after `rws f`, closing the PTY, and asserting the real shpool session returns to `Disconnected`. The `rws d` command is also executed against the real server session.

It verifies:

- client and server initialization;
- SSH bootstrap key generation;
- local OpenSSH installation in a clean Alpine client;
- uninitialized command failure before setup;
- password-login setup failure with a wrong password and a clear error;
- host-key confirmation through SSH's real prompt;
- `rws setup --remote-install check` failure without installing missing remote dependencies;
- independent `rws setup --remote-install skip --no-verify` without installing shpool;
- `rws setup --key-mode create`;
- compact prompt setup, including device config, remote shell rc block, shpool `prompt_prefix`, and per-session `RWS_DEVICE_LABEL`;
- public key installation through an already authorized bootstrap key;
- setup cancellation at local prompts;
- existing device setup choices for continue-with-saved-values and reset;
- wrong-password setup fails before any session cwd picker;
- interactive password-login setup that installs a generated SSH key through the established SSH connection;
- interactive setup separates device creation from optional initial session creation;
- optional setup session cwd picker runs after device verification, creates the session in the background, and does not auto-attach;
- numbered setup progress messages while dependency, shpool, prompt, verification, and optional session steps are running;
- password paths do not store the remote password in the generated config tree;
- `rws setup --key-mode skip` through a real OpenSSH config entry;
- non-interactive failure when password-based key installation would require a terminal;
- device creation under `~/.config/rws`;
- final setup verification with reconnect and real shpool check;
- `rws c`;
- `rws doctor`;
- missing shpool binary, shpool version mismatch, and shpool daemon/list failure diagnostics;
- missing and inaccessible remote cwd diagnostics;
- `rws s`;
- `rws run -- ...`, including stdout, stderr, and non-zero exit-code passthrough for a failing remote command;
- `rws sh`;
- `rws ls --json` with a JSON schema assertion;
- `rws sessions --json` with empty and multi-session state assertions;
- `rws attach <missing-session>` failing loudly with the `rws new <session>` next action;
- `rws session create/get/list/update/delete` against real upstream `shpool`;
- Codex, Claude Code, and Kiro Session creation, persisted full-access mode, explicit `--no-full-access` and `--full-access`, the official `codex` binary name and provider-specific no-confirmation flags on initial launch and restore, live reattach without a second provider process, simulated shpool state loss, foreground restore through real SSH and upstream `shpool`, and metadata cleanup, using deterministic provider fixtures inside the server container;
- abrupt server loss through `podman kill --signal KILL`, restart of the same container, SSH readiness after restart, lazy Codex recovery, and a durable provider-history marker proving that the recovery command read state written before the restart;
- bare `rws` default attach after an explicit default session exists;
- `rws new <session>` on an existing device without passing `--host`;
- `rws new <session> --pick-cwd` with interactive `pwd`/`ls`/`cd`, proof from the real shpool daemon log that the session shell is spawned in the selected directory, and proof that the device config is not rewritten;
- `rws bg`;
- `rws f`;
- reconnecting to the same remote session after the local attached client is closed without the normal detach sequence;
- interrupted attach without corrupting device config;
- `rws d`, including the already-disconnected idempotency path;
- `rws k`;
- repeated setup with the same generated key;
- generated public key de-duplication in `authorized_keys`;
- `rws setup --key-mode existing`;
- `rws devices`;
- `rws device list`, `rws device get`, `rws device update`, and `rws device remove`;
- `rws --device <device>` override when another device is the default;
- `rws remove`, including default rewrite and last-device removal;
- remote missing-`shpool` installation through the real pinned `cargo install` path.

The container E2E uses upstream `shpool`, not a mock. It is intentionally slower than the smoke test because it validates real dependency installation, SSH setup, session creation, reattach, detach, and kill behavior.

The release-supported automatic install path is the path covered here: Alpine/apk for local OpenSSH and remote Cargo/build dependencies, plus pinned upstream `shpool` through Cargo. Other package-manager branches may exist in the CLI for best-effort user convenience, but they are outside the completed story and quality-gate scope until a real E2E job covers them.

## Quality Gate

Before marking a user story complete, run QG-001 from [`docs/QUALITY_GATES.md`](QUALITY_GATES.md) and confirm:

- the story ID is listed in the change notes;
- acceptance criteria in `docs/USER_STORIES.md` are still accurate;
- required commands or manual checks for that story were run;
- any skipped verification is stated explicitly.

When user or maintainer docs are touched, also run QG-008 and confirm the English and Chinese versions and links stay in sync.
