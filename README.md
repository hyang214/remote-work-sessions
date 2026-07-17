# Remote Work Sessions

[中文](README.zh-CN.md) | English

Persistent remote work sessions over SSH.

Remote Work Sessions (`rws`) is a small CLI for creating, reconnecting to, checking, and cleaning up persistent remote shell sessions. It keeps the connection layer simple: SSH gets you to the machine, and `shpool` keeps the remote shell session alive.

## Why

Remote workstations are useful, but the daily command flow often gets noisy:

- SSH commands become long and hard to remember.
- A laptop sleep, network switch, or dropped connection can detach you from a useful shell state.
- `tmux` and `zellij` are powerful, but many workflows only need one persistent shell session.
- Status checks are scattered across SSH, session manager commands, and project commands.

`rws` keeps the common path short:

```bash
rws new review --pick-cwd
rws attach review
rws f
rws s
rws --cwd '~/repo' run -- git status --short
```

## Requirements

Local machine:

- Node.js 22.14+ when installing from npm
- Bash 3.2+
- OpenSSH client

Remote machine:

- OpenSSH server
- an SSH account that can either use an existing key or accept a first-time password login
- [`shpool`](https://github.com/shell-pool/shpool) available on `PATH`, or a supported package manager so `rws setup` can install the pinned version

If remote dependency installation needs sudo, interactive setup supports the normal remote sudo password prompt. Non-interactive setup needs root, passwordless sudo, or preinstalled Cargo/shpool.

When local `ssh` or `ssh-keygen` is missing, `rws` reports the missing command
and points back to `rws setup`. When SSH works but remote `shpool` is missing,
check and session commands report `remote dependency missing: shpool`.

## Install

Install from the public npm registry:

```bash
npm install -g remote-work-sessions
rws setup
```

The installed command is `rws`.

Update an existing install:

```bash
npm install -g remote-work-sessions@latest
rws --version
```

Install from source:

```bash
git clone https://github.com/hyang214/remote-work-sessions.git
cd remote-work-sessions
ln -sfn "$PWD/bin/rws" "$HOME/.local/bin/rws"
```

Make sure `~/.local/bin` is on your `PATH`.

## Quick Start

Run the setup wizard:

```bash
rws setup
```

The wizard handles:

- local OpenSSH client checks and installation when possible;
- device creation under `~/.config/rws/`;
- an existing-device choice to continue with saved values, reset and replace, or quit;
- SSH key creation or reuse, with an interactive choice to enable key-based reconnects;
- first-time public-key installation through the established SSH connection or a bootstrap key;
- remote `shpool` check or pinned installation;
- optional compact remote prompt setup for persistent sessions;
- final device verification: reconnect with the saved config and check remote `shpool`;
- optional initial session creation after the device is ready. If you choose it,
  setup asks for the session name and cwd, creates the session in the
  background, and prints the attach command. It does not auto-attach.

Check the completed setup:

```bash
rws doctor
```

Create or enter a persistent session:

```bash
rws new review --pick-cwd
rws attach review
```

Bind a remote coding CLI to a recoverable session by declaring its agent once:

```bash
rws new coding --pick-cwd --agent codex
# after a remote reboot or power loss
rws attach coding
```

`codex`, `claude`, and `kiro` are supported. Declaring an agent defaults to full
access and persists that choice for this session. `rws` enters the selected cwd,
creates/attaches the foreground shpool Session, then starts the agent inside it:
Codex uses the official `codex --dangerously-bypass-approvals-and-sandbox`, Claude
uses its bypass permission mode, and Kiro trusts all tools. Pass
`--no-full-access` to keep the provider's normal permission behavior. Attach
reconnects to the original process while the shpool session exists; after a
reboot it resumes the latest conversation in the original cwd with the same
access mode. Provider onboarding, a new-workspace trust prompt, or Kiro's first
trust-all safety acknowledgement may still require one-time confirmation;
per-tool approvals remain disabled after that.

Start another session on the same remote device without re-entering the host:

```bash
rws new review --pick-cwd
```

Reconnect after a laptop sleep, network switch, or stale client:

```bash
rws f
```

Show the remote, sessions, and git state:

```bash
rws s
```

Run one command in a remote directory:

```bash
rws --cwd '~/repo' run -- git status --short
```

## Documentation Map

- [`docs/SCENARIOS.md`](docs/SCENARIOS.md): task-oriented usage flows for first setup, daily work, reconnects, multiple devices, automation, and troubleshooting.
- [`docs/COMMAND_REFERENCE.md`](docs/COMMAND_REFERENCE.md): detailed command surface, options, side effects, output contracts, and exit behavior.
- [`docs/SETUP.md`](docs/SETUP.md): setup flow, dependency setup, compact prompt, repeated setup, and entity management.
- [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md): config file format, device/session model, and CRUD-style entity commands.
- [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md): local/remote dependency policy and supported installer scope.
- [`docs/DESIGN.md`](docs/DESIGN.md): architecture model, entity boundaries, and responsibility scope.
- [`docs/TESTING.md`](docs/TESTING.md): smoke and container E2E test layers.
- [`docs/QUALITY_GATES.md`](docs/QUALITY_GATES.md): verification gates, including bilingual docs coverage.
- [`docs/RELEASING.md`](docs/RELEASING.md): clean public export, GitHub setup, and npm trusted publishing.
- [`docs/USER_STORIES.md`](docs/USER_STORIES.md): product scenarios, status, acceptance criteria, and verification evidence.

## Configuration

User configuration lives in:

```text
~/.config/rws/
  default.conf
  devices/
    default.conf
  sessions/
    default/
      coding.conf
```

The repository includes example defaults under `config/` for source checkout usage.

`default.conf` selects the default device:

```conf
device=default
```

A device defines the reusable SSH target and remote prerequisites. It does not
need a default cwd:

```conf
host=workstation
identity_file=~/.ssh/rws_default_ed25519
prompt_mode=compact
prompt_label=workstation
ssh_option=ServerAliveInterval=30
```

Device and session are different:

- Device: the reusable SSH connection config, such as `workstation` or `lab`.
- Session: a shpool session on that device, such as `project`, `review`, or `build`.

Use a different device:

```bash
rws --device lab new review --pick-cwd
```

Temporarily override a device:

```bash
rws --host other-host --cwd '~/work/other-project' --session other
```

## Commands

Every public command has topic help such as `rws help new` or
`rws help attach`. If `rws` detects a parameter error, stderr automatically
includes that command's usage, parameters/options, and typical scenarios after
the error message.

| Command | Use Case |
| --- | --- |
| `rws` | Attach to the configured default session when one exists. |
| `rws help [topic]` | Show general help or topic help without requiring initialized config. |
| `rws help scenarios` | Show scenario-oriented usage guidance. |
| `rws help commands` | Show the full command and option reference. |
| `rws a` | Short alias for `rws attach`. |
| `rws attach [session]` | Attach to the default or named session. A missing ordinary session fails; a Session with agent metadata is restored automatically. |
| `rws new <session> [--cwd <dir>] [--agent codex\|claude\|kiro] [--no-full-access]` | Attach to or create another session; `--agent` launches the agent with persisted full access by default, while `--no-full-access` selects normal provider permissions. |
| `rws new <session> --pick-cwd` | Browse the remote filesystem before creating a session in a different cwd. |
| `rws f` | Force reattach when another client is attached or stale. |
| `rws force [session]` | Long form of `rws f`. |
| `rws s` | Show remote health, shpool sessions, and git status. |
| `rws status` | Long form of `rws s`. |
| `rws c` | Check SSH, remote directory, and shpool availability. |
| `rws check` | Long form of `rws c`. |
| `rws sh` | Open a normal SSH shell in the configured directory. |
| `rws shell` | Long form of `rws sh`. |
| `rws sessions` | List shpool sessions on the selected device. |
| `rws ls` | Alias for `rws sessions`. |
| `rws list` | Alias for `rws sessions`. |
| `rws session create <session> [--cwd <dir>] [--pick-cwd]` | Create a background shpool session on the selected device. Missing directories are created. |
| `rws session get <session>` | Read a named shpool session object from the selected device. |
| `rws session list` | Entity form of `rws sessions`. |
| `rws session update <session> --detach` | Change a session to detached state. |
| `rws session delete <session...>` | Kill one or more named shpool sessions. |
| `rws session attach [session]` | Entity form of `rws attach`. |
| `rws bg` | Create the default session in the background. |
| `rws background [session]` | Long form of `rws bg`. |
| `rws --cwd <dir> run -- <command>` | Run a one-shot command in a remote directory, preserving stdout, stderr, and the remote exit code. |
| `rws d` | Detach the configured session. Safe to rerun when already disconnected. |
| `rws detach [session...]` | Long form of `rws d`; accepts one or more sessions. |
| `rws k` | Kill the configured session. |
| `rws kill [session...]` | Long form of `rws k`. |
| `rws setup` | Configure local and remote prerequisites. Safe to rerun. |
| `rws doctor` | Verify local config, SSH, remote directory, and shpool. |
| `rws key create` | Create a local SSH identity file; pass `--force` to replace it. |
| `rws key get` | Show local SSH identity file status and fingerprint. |
| `rws key list` | List identity files referenced by configured devices. |
| `rws key update` | Regenerate a local identity file with `--force`. |
| `rws key remove` | Delete local identity files with `--force`. |
| `rws devices` | List configured devices. |
| `rws device create <device>` | Create a device through setup. |
| `rws device get [device]` | Show a device config. |
| `rws device update <device>` | Modify local device config fields. |
| `rws device list` | Alias for `rws devices`. |
| `rws remove <device>` | Delete a configured device. |
| `rws rm <device>` | Alias for `rws remove`. |
| `rws device remove <device>` | Alias for `rws remove`. |
| `rws init ...` | Low-level config writer. Prefer `rws setup`. |

## SSH Key Setup

`rws setup` supports three key modes:

| Mode | Use Case |
| --- | --- |
| `--key-mode create` | Create a dedicated ed25519 key for this device. |
| `--key-mode existing` | Reuse an existing key that the user selects. |
| `--key-mode skip` | Write config only and leave SSH setup to the user. |

Create a dedicated key:

```bash
rws setup --host workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519'
```

Reuse an existing key:

```bash
rws setup --host workstation \
  --key-mode existing \
  --identity-file '~/.ssh/id_ed25519'
```

Install a newly created public key on a remote host with the remote user's normal SSH password:

```bash
rws setup --host user@workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key
```

This uses SSH's own interactive password and host-key prompts. `rws` does not read or store the password.

For non-interactive setup, install the public key through an already authorized bootstrap key:

```bash
rws setup --host workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key \
  --bootstrap-identity '~/.ssh/id_ed25519'
```

`rws setup` is idempotent. Existing keys are reused unless `--force-key` is provided, existing public keys are not duplicated in `authorized_keys`, and session directories are created with `mkdir -p` when a session is created.

## Compact Prompt

Interactive `rws setup` asks whether to install a compact prompt for remote sessions. When enabled for a zsh remote shell, a session prompt is shortened to:

```text
project %                                      [workstation:project]
```

The left side keeps the current directory short. The right side shows the device label and shpool session. For bash remotes, the fallback is a compact left prompt:

```text
[workstation:project] project $
```

Non-interactive setup can enable or skip it explicitly:

```bash
rws setup --prompt-mode compact --prompt-label workstation
rws setup --prompt-mode skip
```

Setup stores `prompt_mode` and `prompt_label` in the device config, installs a managed block in the remote user's shell rc file, and sets remote shpool `prompt_prefix = ""`. Existing shpool daemons may keep their old prompt prefix until they are restarted; active sessions are not interrupted by setup.

## Entity Management

The main entities have explicit management commands:

```bash
rws key create --identity-file '~/.ssh/rws_lab_ed25519'
rws key get --identity-file '~/.ssh/rws_lab_ed25519'
rws key update --identity-file '~/.ssh/rws_lab_ed25519' --force
rws key remove --identity-file '~/.ssh/rws_lab_ed25519' --force

rws device create lab --host user@workstation
rws device get lab
rws device update lab --cwd '~/work/other' --session other --default
rws device remove lab

rws session create review --cwd '~/work/review'
rws session get review
rws session list --json
rws session update review --detach
rws session delete review
```

`rws key remove` deletes only local key files. Remote `authorized_keys` changes are handled by setup's key-install path and are not removed automatically.

Remove a device:

```bash
rws remove lab
```

Create another session in a remote directory you do not remember exactly:

```bash
rws new review --pick-cwd
```

At the `rws cwd>` prompt, use `ls`, `ls <path>`, `cd <path>`, `mkdir <path>`, `mkdir -p <path>`, or `pwd`; press Enter to create the session in the displayed directory. When the remote host has bash, Tab completes files and paths. This does not rewrite the device config.

## Testing

Product user scenarios are tracked in [`docs/USER_STORIES.md`](docs/USER_STORIES.md). Quality gates are tracked separately in [`docs/QUALITY_GATES.md`](docs/QUALITY_GATES.md), including QG-001 for user story coverage and execution correctness.

Fast checks:

```bash
scripts/smoke-test.sh
```

Container end-to-end checks with a client container and a server container:

```bash
tests/e2e/podman-e2e.sh
```

The E2E test verifies clean client/server initialization, local OpenSSH installation, wrong-password handling, host-key confirmation, SSH key creation, SSH key installation through a bootstrap key or password login, `--key-mode skip` with real SSH config, `--remote-install check`, real pinned shpool installation, compact prompt setup, device loading, diagnostics, JSON session contracts, one-shot commands, explicit default attach, coding CLI initial launch and latest-conversation recovery, optional setup session creation without auto-attach, creating another session on an existing device, interactive cwd picking for a new session, interrupted attach, background session creation, force reattach, detach, kill, device override/removal, default rewrite, last-device removal, and final setup verification.

## Goals

- Keep the daily remote-session path short.
- Preserve remote shell state across connection drops.
- Support multiple remote devices and multiple sessions per device.
- Stay compatible with plain SSH and existing shell tools.

## Non-Goals

- Remote desktop.
- File sync.
- A VS Code Remote replacement.
- A terminal multiplexer replacement.
- Public network exposure, tunneling, or bastion management.
- Secret or password management.

## License

MIT
