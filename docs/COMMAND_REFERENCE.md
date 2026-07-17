# Command Reference

[中文](COMMAND_REFERENCE.zh-CN.md) | English

This reference describes the supported `rws` command surface, common options,
side effects, and output contracts. For task-oriented examples, see
[`SCENARIOS.md`](SCENARIOS.md).

## Command Model

`rws` has three operating layers:

- Daily aliases for the common remote-session loop.
- Entity commands for explicit SSH key, device, and session management.
- Setup and diagnostic commands for installation, verification, and recovery.

Most daily commands require an initialized device config. Help commands do not:

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

`rws --help` shows the highest-frequency commands. `rws help scenarios` shows
task-oriented examples. `rws help commands` shows the full command surface.
Topic help is available for every public command family: `setup`, `init`,
`key`, `device`, `session`, `new`, `attach`, `force`, `background`, `check`,
`doctor`, `status`, `shell`, `sessions`, `run`, `detach`, `kill`, and `remove`.
Each topic includes syntax, parameters/options, and typical scenarios. The
short aliases resolve to the same topic help.

## Global Options

Global options can be placed before the command:

```bash
rws [global options] <command> [command options]
```

| Option | Meaning | Persistence |
| --- | --- | --- |
| `--config-dir DIR` | Use a config directory instead of `~/.config/rws`. | One command. |
| `-d, --device DEVICE` | Use `devices/<device>.conf`. | One command. |
| `-H, --host HOST` | Override the SSH host from the selected device. | One command. |
| `-C, --cwd DIR` | Override the remote working directory. | One command. |
| `-s, --session SESSION` | Override the selected device's default session. | One command. |
| `-i, --identity-file FILE` | Override the SSH identity file. | One command. |
| `-B, --shpool-bin FILE` | Override the remote `shpool` binary path. | One command. |
| `-o, --ssh-option OPTION` | Add an OpenSSH `-o` option. Can be repeated. | One command unless written by setup/device update. |

Use overrides for deliberate one-off work. Use `rws device update` when the
change should become part of the saved device.

## Error Help Contract

Parameter and other `rws` validation errors exit with status `2`. The first
stderr line states the error. It is followed by the current command's `Usage`,
`Parameters and options`, and `Typical scenarios`, so a typo or missing value
can be corrected without a second help lookup. `rws run` still preserves the
remote command's own exit status.

For example, `rws new coding --agent unknown` prints the valid `new` syntax,
the accepted agents, the default full-access behavior, the opt-out flag, and
copyable creation/recovery examples. A global parsing error prints root help;
an error inside `device`, `session`, or `key` prints that command-family help.

## Setup Commands

### `rws setup [options]`

Creates or updates a device, prepares the remote runtime, verifies the saved
device, then optionally creates an initial session in the background.

Common options:

| Option | Meaning |
| --- | --- |
| `-d, --device DEVICE` | Device name to create or update. |
| `-H, --host HOST` | SSH target, either an alias, hostname, IP, or `user@host`. |
| `-C, --cwd DIR` | Initial session working directory. Required only with non-interactive `--create-session`. |
| `-s, --session SESSION` | Initial/default shpool session name. |
| `-S, --create-session` | Create an initial session after device verification. |
| `-x, --no-create-session` | Do not ask for or create an initial session. |
| `-k, --key-mode create|existing|skip` | Choose SSH key handling. |
| `-i, --identity-file FILE` | Local private key path for create/existing modes. |
| `-K, --install-key` | Append the selected public key to remote `authorized_keys` when absent. |
| `-N, --no-install-key` | Explicitly skip public-key installation. |
| `-b, --bootstrap-identity FILE` | Use an already authorized key to install the selected public key. |
| `-F, --force-key` | Recreate the selected local key when it already exists. |
| `-r, --remote-install auto|check|skip` | Install missing remote deps, check only, or skip remote setup. |
| `--shpool-version VERSION` | Advanced/testing override for the shpool version recorded by setup. Release support remains pinned to `0.9.8`. |
| `-B, --shpool-bin FILE` | Remote `shpool` command or absolute path. |
| `-m, --prompt-mode compact|skip` | Enable or skip compact prompt setup. |
| `-l, --prompt-label LABEL` | Device label used by the compact prompt. |
| `-o, --ssh-option OPTION` | Persist an SSH option to the device. |
| `--verify` | Explicitly run final saved-device verification. This is the default. |
| `-n, --no-verify` | Skip final saved-device verification. |
| `-y, --yes` | Run non-interactively with supplied options. |

Side effects:

- writes `~/.config/rws/default.conf`;
- writes `~/.config/rws/devices/<device>.conf`;
- may create a local SSH key;
- may append a public key to remote `~/.ssh/authorized_keys`;
- may install Cargo/build dependencies and pinned `shpool 0.9.8`;
- may update a managed prompt block in remote `.zshrc` or `.bashrc`;
- may create an initial shpool session in the selected cwd when requested;
- does not auto-attach to the created session.

Interactive setup validates the first SSH connection before any session cwd
selection, prints a remote-change summary before remote writes, and accepts `q`, `quit`,
or `exit` at local prompts to cancel. When the default
`--remote-install auto` mode was not explicitly chosen on the command line,
interactive setup asks before installing missing remote dependencies because
Rust/Cargo and `shpool` installation can take several minutes. Answer `n` to
switch that run to check-only mode. When a device config already exists, setup
asks whether to continue with saved values, reset and replace the device, or
quit. Password and sudo prompts are owned by SSH or sudo; `rws` does not read
or store those passwords.

### `rws init ...`

Low-level config writer used by tests and controlled scripts. Prefer
`rws setup` for normal users because `init` does not prepare or verify the
remote host. `cwd` and `default_session` are optional device fields.

### `rws doctor`

Prints local config and remote diagnostics:

```text
device=<device>
host=<host>
cwd=<cwd or (not set)>
default_session=<session or (not set)>
shpool_bin=<path>
...
```

It verifies SSH, the remote cwd when one is configured, the pinned shpool version when the device records one, and
`shpool list --json`. Failures are non-zero and are written to stderr.

### `rws c` / `rws check`

Runs the remote check portion of `doctor`: SSH connectivity, optional remote cwd,
`shpool version`, and `shpool list --json`.

## Daily Session Commands

### `rws`

Attach to or create the selected device's default session. This requires the
device to have a `default_session`.

### `rws a` / `rws attach [session]`

Attach to the default session when no session is passed. With an explicit
session name, attach to an existing session. If the named session is missing
and has no saved coding-agent metadata, the command fails and prints:

```text
Run: rws new <session>
```

For a Session previously created with `--agent`, a missing shpool Session is
instead recreated with the saved cwd, agent recovery command, and access mode.
No new coding-agent metadata is inferred or created by `attach`.

### `rws new SESSION [-C CWD] [-p|--pick-cwd] [-A|--agent AGENT] [--no-full-access]`

Attach to or create `SESSION` on the selected device.

Use `--cwd`/`-C` when you know the directory. With `--pick-cwd`/`-p`, `rws`
opens a remote directory picker before creating the session. If the device has
no saved cwd, one of these is required in non-interactive use. The picker supports:

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

When the remote host has bash, the picker runs with readline and supports Tab
completion for files and paths.

The selected cwd applies to the new session creation only. It does not rewrite
the saved device cwd.

`--agent` accepts `codex`, `claude`, or `kiro`. For a new Session, `rws`
enters the selected cwd, creates the foreground shpool process, and immediately
starts that agent with full access. If the shpool Session is still live, another
`rws new` or `rws attach` only reconnects to it and does not start a second
agent. If shpool state is missing, `rws` enters the saved cwd and runs the saved
agent's recovery command.

| Agent | Default initial launch | Default recovery after shpool state loss |
| --- | --- | --- |
| `codex` | `codex --dangerously-bypass-approvals-and-sandbox` | `codex resume --last --dangerously-bypass-approvals-and-sandbox` |
| `claude` | `claude --dangerously-skip-permissions` | The same launcher plus `--continue` |
| `kiro` | `kiro-cli chat --trust-all-tools` | The same launcher plus `--resume` |

Use `--no-full-access` to persist the provider's normal permission behavior
instead:

| Agent | No-full-access initial launch | No-full-access recovery |
| --- | --- | --- |
| `codex` | `codex` | `codex resume --last` |
| `claude` | `claude` | `claude --continue` |
| `kiro` | `kiro-cli chat` | `kiro-cli chat --resume` |

`cc` is not a Claude alias in rws: it is commonly the system C compiler. The
Claude provider always invokes `claude`. Full access removes per-tool provider
approval prompts and should be used only on a trusted, isolated development
device. Provider onboarding, new-workspace trust, or a first-use bypass safety
acknowledgement can still appear once. The older `--full-access` spelling is
still accepted but redundant because full access is now the agent default.

Initial creation must attach in the foreground, so `rws session create --agent ...` and background recovery are unsupported. Later `rws attach SESSION`, `rws force SESSION`, or another `rws new SESSION` use the saved agent and cwd. Missing ordinary sessions keep their existing fail-loud behavior.

Conversation selection remains provider-native and cwd-scoped: recovery selects that directory's latest conversation, does not pin a conversation ID, and does not delete older history. Two rws sessions with the same provider and cwd therefore select the same latest conversation.

### `rws f` / `rws force [session]`

Force attach with shpool's `-f` behavior. Use this after a stale client,
laptop sleep, VPN switch, or when another client is still marked attached.

### `rws bg` / `rws background [session]`

Create the target session in the background and return to the local shell. A cwd
must be supplied by device config or `--cwd`.

If a Session with agent metadata is absent after a reboot, it must be restored interactively with `rws attach`; `background` fails with that next action.

### `rws d` / `rws detach [session...]`

Detach one or more sessions. Detaching an already disconnected session is safe.

### `rws k` / `rws kill [session...]`

Kill one or more sessions. Without explicit names, the selected default session
is used. Killing a Session also removes its optional local agent metadata, so a
later attach does not recreate it.

### `rws sessions` / `rws ls` / `rws list`

List shpool sessions on the selected device.

Use JSON for automation:

```bash
rws sessions --json
```

The JSON output has this shape:

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

This shape is the verified upstream `shpool 0.9.8` JSON shape. `rws` passes it
through rather than translating it.

### `rws s` / `rws status`

Shows three sections:

```text
== remote ==
== sessions ==
== git ==
```

Use it for a human-readable health snapshot.

### `rws sh` / `rws shell`

Open a normal SSH shell in the configured remote cwd. This does not use shpool.
Requires a configured or one-off cwd.

### `rws run -- COMMAND [ARG...]`

Run one remote command in the selected cwd. Requires a configured or one-off cwd.

Contracts:

- stdout is the remote command stdout;
- stderr is the remote command stderr;
- the process exit code is the remote command exit code;
- missing or inaccessible cwd fails before the command runs.

Example:

```bash
rws --cwd '~/repo' run -- git status --short
```

## Entity Commands

### SSH Key

| Command | Behavior |
| --- | --- |
| `rws key create [-i, --identity-file FILE] [-f, --force]` | Create a local ed25519 identity file. |
| `rws key get [-i, --identity-file FILE]` | Show private/public key presence and fingerprint. |
| `rws key list` | List key files referenced by configured devices. |
| `rws key update [-i, --identity-file FILE] [-f, --force]` | Regenerate the local identity file. |
| `rws key remove [-i, --identity-file FILE] [-f, --force]` | Delete local key files. |

`rws key remove` does not edit remote `authorized_keys`.

### Device

| Command | Behavior |
| --- | --- |
| `rws device create DEVICE [setup options]` | Create a device through setup. |
| `rws device get [DEVICE]` | Show a device config. Defaults to the selected device. |
| `rws device list` / `rws devices` | List configured devices. |
| `rws device update DEVICE [options]` | Modify saved local device fields. |
| `rws device remove DEVICE` / `rws remove DEVICE` | Delete a configured device. |

`rws device update` options include:

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

Run `rws doctor` after changing host, cwd, identity, shpool, or SSH options.

### Session

| Command | Behavior |
| --- | --- |
| `rws session create SESSION [-C, --cwd DIR] [-p, --pick-cwd]` | Create a background shpool session, creating the selected remote cwd when missing. |
| `rws session get SESSION` | Show one session object. |
| `rws session list [--json]` | List sessions. |
| `rws session update SESSION --detach` | Detach a session. |
| `rws session delete SESSION [SESSION...]` | Kill one or more sessions. |
| `rws session attach [SESSION]` | Entity form of attach. |

## Exit Behavior

| Situation | Expected behavior |
| --- | --- |
| Success | Exit `0`. |
| User input or parser error | Exit `2` with `rws: ...` on stderr. |
| Missing config | Non-zero with `Run: rws setup`. |
| Missing local `ssh` | Exit `2` with `missing local dependency: ssh (run: rws setup)`. |
| Missing local `ssh-keygen` | Exit `2` with `missing local dependency: ssh-keygen (run: rws setup)`. |
| SSH failure | Non-zero with `ssh_error=<category>` when classified. |
| Remote cwd missing/inaccessible | Non-zero with `remote cwd missing` or `remote cwd not accessible`. |
| Remote `shpool` missing | Non-zero with `remote dependency missing: shpool`. |
| Remote command failure through `rws run` | Same exit code as the remote command. |
| Missing named attach target without saved coding-agent metadata | Exit `2` with `Run: rws new <session>`. |

Common SSH categories:

```text
ssh_error=dns_failed
ssh_error=connection_refused
ssh_error=connection_timeout
ssh_error=authentication_failed
ssh_error=host_key_changed
ssh_error=connection_reset
ssh_error=unknown
```

## Supported And Best-Effort Paths

The release-supported automatic install path is Alpine/apk for local OpenSSH
and remote build dependencies, plus pinned upstream `shpool 0.9.8` through
Cargo.

Other installer branches may exist for user convenience, but they are
best-effort until real E2E coverage exists for that platform.

See [`DEPENDENCIES.md`](DEPENDENCIES.md) for the dependency support matrix.
