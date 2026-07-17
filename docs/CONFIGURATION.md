# Configuration

[中文](CONFIGURATION.zh-CN.md) | English

Remote Work Sessions uses plain key-value config files.

## User Config

Default user config location:

```text
~/.config/rws/
  default.conf
  devices/
    default.conf
  sessions/
    default/
      coding.conf
```

Create it with the integrated setup flow:

```bash
rws setup
```

## Device And Session

`rws` keeps device and session separate:

- Device: reusable SSH connection configuration, including host, identity file, SSH options, prompt preferences, and remote `shpool` path.
- Session: a shpool session on a device.
- Remote runtime: setup-managed remote state such as `shpool`, shpool config, and the optional shell prompt block.

After a device has been set up, new sessions on that device do not need `--host`:

```bash
rws new review
rws new review --pick-cwd
rws --device lab new build
rws bg long-build
rws session create review --pick-cwd
rws session update review --detach
rws session delete review
rws sessions
```

Use `--host` only during setup or for a deliberate one-off override.

`rws new <session> --pick-cwd` lets you inspect and change the remote cwd before the new session is created. The chosen directory is temporary for that session creation; the device file does not need or gain a saved `cwd`.

Device and session names must be plain identifiers: letters, numbers, dots, underscores, and hyphens. They cannot be empty, start with `.` or `-`, contain `/`, or contain `..`.

## Optional Session Recovery Metadata

The first `rws new SESSION --agent codex --cwd '~/repo'` writes
`sessions/<device>/SESSION.conf`:

```text
rws-coding-session-v2
codex
~/repo
full
```

These lines extend the existing Session with optional agent, remote cwd, and
access-mode attributes; they do not define another entity. New agent Sessions
record `full` by default. Passing `--no-full-access` records `default`, meaning
the provider's normal permission behavior. The file is created under
`umask 077` and contains no prompts, conversation content, tokens, or secrets.
Provider-native history remains in that provider's remote data directory;
`rws` neither copies nor parses it.

Session recovery metadata is local to the connecting client's config directory.
It is not synchronized to another laptop; register the Session again there with
one `rws new ... --agent ...`. `rws kill`/`session delete` removes the matching
metadata, and device removal removes it for every Session on that device.

Recovery requires the remote cwd, agent executable, and provider-native history to remain on disk. It does not recreate a missing workspace or recover process-only state that was not flushed before power loss.

Legacy `rws-coding-session-v1` files remain readable and map to `default`
access so an upgrade does not silently broaden an existing Session. Existing
v2 files also keep their saved access value. New writes use v2.

## Default Device

`default.conf` selects the device used by `rws`:

```conf
device=default
```

## Device Format

Each device is stored as `devices/<name>.conf`:

```conf
host=workstation
identity_file=~/.ssh/rws_default_ed25519
shpool_bin=shpool
prompt_mode=compact
prompt_label=workstation
setup_version=0.2.0
shpool_version=0.9.8
ssh_option=ServerAliveInterval=30
```

Fields:

| Key | Meaning |
| --- | --- |
| `host` | SSH host or alias. |
| `cwd` | Optional remote working directory. Prefer per-session `--cwd` or `--pick-cwd` when different sessions use different directories. |
| `default_session` | Optional default shpool session name for this device. Setup writes it only when it creates an initial session. |
| `identity_file` | Optional SSH private key path. |
| `shpool_bin` | Remote shpool command or path. Defaults to `shpool`. |
| `prompt_mode` | `compact` or `skip`. Defaults to `skip` when absent. |
| `prompt_label` | Device label shown in compact prompts. Defaults to the device name when `prompt_mode=compact`. |
| `setup_version` | `rws` setup version that last wrote the device. |
| `shpool_version` | Pinned shpool version used by setup when remote install is needed. |
| `ssh_option` | Optional SSH `-o` option. Can appear multiple times. |

Only these current keys are accepted. Unknown keys fail loudly instead of being treated as legacy compatibility.

## SSH Key Setup

`rws setup` asks for a key setup choice when run interactively. In scripts, use one of these explicit modes:

```bash
rws setup --host workstation --key-mode create --identity-file '~/.ssh/rws_workstation_ed25519'
rws setup --host workstation --key-mode existing --identity-file '~/.ssh/id_ed25519'
rws setup --host workstation --key-mode skip --no-install-key
```

To create a device key and install its public key using the remote user's normal SSH password:

```bash
rws setup --host user@workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key
```

SSH handles the interactive password and host-key prompts. `rws` does not read or store the password.

During interactive setup, `rws` opens one temporary SSH control connection after the first successful login. If you choose to install an SSH key, that same connection is used to append the public key and continue remote initialization. Setup closes the temporary connection before final verification, then reconnects with the saved device.

For non-interactive setup, install the public key through an already authorized bootstrap key:

```bash
rws setup --host workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key \
  --bootstrap-identity '~/.ssh/id_ed25519'
```

Both paths append the selected public key to the remote user's `~/.ssh/authorized_keys`. Password storage is intentionally out of scope.

## Setup Idempotency

`rws setup` can be run repeatedly:

- existing device files are rewritten with the selected values;
- existing generated keys are reused unless `--force-key` is set;
- missing `.pub` files are regenerated from the private key;
- public keys are appended to `authorized_keys` only when absent;
- session working directories are created with `mkdir -p` when sessions are created;
- `shpool` is installed only when it is missing and `--remote-install auto` is used;
- compact prompt setup updates only a managed shell rc block and shpool `prompt_prefix`;
- final verification reconnects and checks SSH plus `shpool`.

## Compact Prompt

Interactive setup asks whether to use a compact prompt for remote sessions. Non-interactive setup uses `prompt_mode=skip` unless the mode is set explicitly:

```bash
rws setup --prompt-mode compact --prompt-label workstation
rws setup --prompt-mode skip
```

For zsh remotes, compact mode keeps the current directory on the left and puts device/session context on the right:

```text
project %                                      [workstation:project]
```

For bash remotes, compact mode uses a shorter left prompt because bash does not provide a native right prompt:

```text
[workstation:project] project $
```

The device label is passed into each new shpool session through `RWS_DEVICE_LABEL`. The session name comes from shpool's `SHPOOL_SESSION_NAME`.

Use `--remote-install check` to verify remote dependencies without installing them. Use `--remote-install skip` only for tests or environments where remote setup is handled elsewhere. Use `--no-verify` only when the saved device cannot be verified yet, such as isolated config-generation tests.

## Multiple Devices

Create another device:

```text
~/.config/rws/devices/lab.conf
```

```conf
host=lab-box
```

Use it:

```bash
rws --device lab new review --pick-cwd
rws --device lab attach review
```

List or remove configured devices:

```bash
rws devices
rws device get lab
rws device update lab --cwd '~/work/other' --session other --default
rws remove lab
```

Temporary overrides are available for one-off use:

```bash
rws --host lab-box --cwd '~/work/other' --session other
```

## Entity Commands

The CRUD-style entity surface is:

| Entity | Create | Read | Update | Delete |
| --- | --- | --- | --- | --- |
| SSH key | `rws key create` | `rws key get`, `rws key list` | `rws key update --force` | `rws key remove --force` |
| Device | `rws device create` | `rws device get`, `rws device list` | `rws device update` | `rws device remove` |
| Session | `rws session create` | `rws session get`, `rws session list` | `rws session update --detach` | `rws session delete` |

`rws device get` accepts an optional device name; without one, it reads the default device. `rws device update` modifies local device config fields such as `host`, `cwd`, `default_session`, `identity_file`, `shpool_bin`, prompt settings, and SSH options. Use `--clear-identity-file`, `--clear-prompt-label`, or `--clear-ssh-options` to remove optional fields. Run `rws doctor` after changing connection fields when you want remote verification.

`rws session create SESSION --cwd DIR` creates that session in a one-off directory without rewriting the device default. `rws session get SESSION` returns the matching session object. `rws session delete` accepts one or more session names.

`rws key remove` deletes local key files only. It does not edit the remote user's `authorized_keys`.
