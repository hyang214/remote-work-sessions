# Dependencies

[中文](DEPENDENCIES.zh-CN.md) | English

Remote Work Sessions keeps its dependency surface intentionally small.

## npm Package

The npm package has no runtime npm dependencies. The lockfile is committed so package metadata stays deterministic.

Security check:

```bash
npm audit --omit=dev --audit-level=moderate
```

## Local Runtime

Required local commands:

- `bash`;
- `ssh`;
- `ssh-keygen`.

`rws setup` installs OpenSSH client tools when they are missing and a supported local package manager is available. The release gate currently verifies this with Alpine/apk in a clean container.

If `bash` itself is missing, the operating system reports `env: bash: No such
file or directory` before `rws` can start. If Bash is older than 3.2, `rws`
exits with `missing local dependency: Bash 3.2+ required`.

Daily commands that need SSH fail before connecting when `ssh` is missing:

```text
rws: missing local dependency: ssh (run: rws setup)
```

Key-management commands fail before key work when `ssh-keygen` is missing:

```text
rws: missing local dependency: ssh-keygen (run: rws setup)
```

## Remote Runtime

Required remote services and commands:

- OpenSSH server;
- `shpool`.

When `shpool` is missing and `--remote-install auto` is used, setup installs Cargo if needed, installs native build dependencies, and then installs the pinned shpool version:

```bash
cargo install shpool --version 0.9.8 --locked
```

`--locked` makes Cargo use the dependency versions selected by the upstream package lockfile when available.

The release-supported automatic remote install path is Alpine/apk. It is verified by Podman E2E with a clean server container.

When the remote SSH service is missing or unreachable, `rws` reports a
classified SSH error such as `ssh_error=connection_refused` or
`ssh_error=connection_timeout`. When SSH works but remote `shpool` is missing,
`rws doctor`, `rws check`, and session commands report:

```text
rws: remote dependency missing: shpool (<configured path>). Run: rws setup
```

The CLI contains best-effort installer branches for `apt-get`, `dnf`, `yum`, `pacman`, `zypper`, and `brew`, but those branches are not release-supported until a real E2E job covers that platform. Do not report them as fully verified without such a run.

Repeated setup first checks `shpool` on `PATH` and `~/.cargo/bin/shpool`. If either matches the pinned version, it is reused and Cargo installation is skipped.

## Optional Coding Agents

`rws new <session> --agent <agent>` additionally requires the selected coding
agent on the remote host:

| Agent | Required remote command | Recovery command |
| --- | --- | --- |
| `codex` | `codex` | `codex resume --last --dangerously-bypass-approvals-and-sandbox` |
| `claude` | `claude` | `claude --dangerously-skip-permissions --continue` |
| `kiro` | `kiro-cli` | `kiro-cli chat --trust-all-tools --resume` |

By default, `--agent codex` invokes the installed official `codex` binary with
`--dangerously-bypass-approvals-and-sandbox`; recovery invokes `codex resume
--last` with the same option. Personal aliases or wrappers are not discovered
or treated as supported Codex commands. `--no-full-access` uses each provider's
plain launcher and recovery command instead. Claude still requires `claude`;
`rws` never treats `cc` as Claude because that name is commonly the system C
compiler. Kiro CLI 2.x must support
`--trust-all-tools` for its default full-access launch.

These commands are optional for ordinary shell sessions. `rws setup` does not
install or authenticate coding agents; install and sign in to the selected
provider on the remote host first. A missing command fails before session
creation with `remote dependency missing: coding agent ...`.

Conversation history belongs to the provider and remains in its normal remote
storage. `rws` stores only the selected agent and remote cwd needed to invoke
the provider's recovery command and access mode.

Remote administrator rights:

- interactive setup supports a normal sudo password prompt;
- non-interactive setup requires root, passwordless sudo, or preinstalled Cargo/shpool;
- passwordless sudo is a CI convenience, not a user requirement.

## Version Policy

- npm runtime dependencies: none.
- remote shpool version: `0.9.8`.
- remote installation mode defaults to `auto`.
- users can choose `--remote-install check` to verify without installing, or `--remote-install skip` for pre-managed environments.
