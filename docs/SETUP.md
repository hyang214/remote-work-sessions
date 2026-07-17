# Setup

[中文](SETUP.zh-CN.md) | English

This is the new-user path.

## Install

Install from the public npm registry:

```bash
npm install -g remote-work-sessions
rws setup
```

Update an existing install:

```bash
npm install -g remote-work-sessions@latest
rws --version
```

`rws setup` writes user config under `~/.config/rws/` and then verifies the remote host. Setup prints numbered stage markers such as `[1/12]` and `[9/12]` so a long first install shows where it is in the overall flow. During remote dependency setup, it also prints a periodic `still preparing remote dependencies` reminder when the remote command stays quiet.

Setup is intentionally split into a device stage and an optional initial-session stage:

1. prepare local SSH tooling;
2. collect the device and remote SSH target;
3. validate the first SSH connection;
4. collect compact-prompt settings;
5. collect SSH key settings;
6. create or update the local device config;
7. optionally install the selected SSH public key through that connection;
8. install or verify remote dependencies;
9. optionally install the compact prompt remote runtime config;
10. reconnect with the saved device and verify SSH plus `shpool`;
11. ask whether to create an initial session; if yes, pick or use a one-off cwd and create the session in the background;
12. print the attach command without auto-attaching.

Interactive setup prints a short remote-change summary before it writes remote state. The summary names whether setup may append a public key to `~/.ssh/authorized_keys`, install or check `shpool`, update the managed compact-prompt shell block, and create an initial session after device verification.

When interactive setup uses the default `--remote-install auto`, it asks before
installing missing remote dependencies. Choose `n` to switch the current run to
check-only mode; setup then reports missing `shpool` or Cargo instead of
starting a slow install.

## Interactive Setup

The wizard asks for:

- device name;
- when that device already exists, whether to continue with saved values, reset and replace it, or quit;
- remote host or IP;
- SSH username when the host was not entered as `user@host`;
- remote password or host-key confirmation through SSH when needed;
- whether to use a compact prompt for remote sessions;
- device label to show in the compact prompt;
- whether to enable SSH key authentication for stable reconnects;
- SSH key mode when key authentication is enabled.
- whether to create an initial session after the device is verified;
- when creating an initial session, the session name and remote working directory through the remote cwd picker.

At any local setup prompt, enter `q`, `quit`, or `exit` to cancel. If setup
previously wrote a partial device config, the next interactive `rws setup` for
that device asks whether to continue with saved values or reset the device.

For a remote host that only has username and password access, choose key creation and allow setup to install the public key:

```bash
rws setup --host user@workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key
```

SSH handles the password prompt. `rws` does not read or store the password.

If the first SSH connection fails, setup stops before any session directory selection with a message to check the host, username, or password. If public-key installation fails after login, setup reports the remote `~/.ssh/authorized_keys` permission problem instead of continuing silently.

## Non-Interactive Setup

Use a bootstrap key when setup must run without a terminal:

```bash
rws setup --host user@workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key \
  --bootstrap-identity '~/.ssh/id_ed25519' \
  --yes
```

Non-interactive setup creates a device by default. Add `--create-session --cwd DIR`
when you also want setup to create an initial session. Enable compact prompts
explicitly when desired:

For compatibility with older scripts, non-interactive setup also creates an
initial session when `--cwd` or `--session` is supplied without either
`--create-session` or `--no-create-session`. Use `--no-create-session` when you
want those values to be ignored during device-only setup.

```bash
rws setup --host user@workstation \
  --key-mode create \
  --identity-file '~/.ssh/rws_project_ed25519' \
  --install-key \
  --bootstrap-identity '~/.ssh/id_ed25519' \
  --prompt-mode compact \
  --prompt-label workstation \
  --yes
```

## Dependency Setup

Local dependencies:

- `ssh`
- `ssh-keygen`

When either is missing, `rws setup` tries to install OpenSSH client tools with the local package manager. The current release gate verifies this path on Alpine/apk.

If a daily command needs SSH and local `ssh` is missing, it fails before any
remote connection attempt with `missing local dependency: ssh (run: rws setup)`.
If a key command needs `ssh-keygen` and it is missing, it reports
`missing local dependency: ssh-keygen (run: rws setup)`.

Remote dependencies:

- SSH server;
- `shpool`;
- `cargo` only when `shpool` is missing and must be installed;
- native build dependencies for `shpool` installation, such as a C compiler, `pkg-config`/`pkgconf`, and OpenSSL development headers.

`rws setup` checks for `shpool` during the device stage. If `shpool` is missing, setup installs the pinned shpool version with:

```bash
cargo install shpool --version 0.9.8 --locked
```

If SSH works but the configured remote `shpool` is missing, check and session
commands report `remote dependency missing: shpool (<configured path>). Run:
rws setup`. If the remote SSH server itself is missing or unreachable, the
failure is classified as an SSH error such as `connection_refused` or
`connection_timeout`.

The release-supported automatic remote install path is Alpine/apk. Other installer branches may exist for best-effort use, but they are not release-supported until they have real E2E coverage.

If installing Cargo requires administrator rights, interactive setup allocates a remote TTY so `sudo` can ask for the remote user's sudo password. Non-interactive setup cannot answer a sudo password prompt; in that mode the remote user must be root, have passwordless sudo, or already have Cargo/shpool installed.

When the pinned version already exists at `~/.cargo/bin/shpool`, setup reuses it and updates the device to that path instead of reinstalling.

## Compact Prompt Setup

Compact prompt setup is part of the remote runtime configuration. In compact mode, setup:

- stores `prompt_mode=compact` and `prompt_label=<label>` in the device config;
- writes a managed block to the remote user's `.zshrc` or `.bashrc`;
- writes `prompt_prefix = ""` to the remote shpool config;
- passes `RWS_DEVICE_LABEL=<label>` when creating shpool sessions.

The intended zsh prompt is:

```text
project %                                      [workstation:project]
```

For bash remotes, the fallback is:

```text
[workstation:project] project $
```

Setup does not interrupt active shpool sessions. If a shpool daemon is already running with an older config, the old `shpool:` prompt prefix may remain until that daemon is restarted.

## After Setup

Setup automatically verifies the saved device by reconnecting and checking SSH plus `shpool`. If you chose to create an initial session, setup creates it in the background and prints `connect with: rws attach <session>`; it does not automatically attach. Typical commands after that:

```bash
rws new review --pick-cwd
rws attach review
rws f
rws s
rws --cwd '~/repo' run -- git status --short
```

`rws attach <session>` attaches to an existing named session. If an ordinary named Session is absent, it fails and prints `Run: rws new <session>` so accidental creation stays explicit. A missing Session that has saved coding-agent metadata is the exception: `attach` recreates it with the saved cwd, recovery command, and access mode. `rws new <session>` is the explicit path for creating a new Session or coding-agent registration.

Run a full check:

```bash
rws doctor
```

Full project documentation: <https://github.com/hyang214/remote-work-sessions/blob/main/README.md>

## New Sessions On Existing Devices

Setup creates a device. A device stores the SSH host, auth, prompt preferences, and remote `shpool` path. It does not need a default working directory.

Sessions are separate. To create or attach another session on the default device, provide only the session name:

```bash
rws new review
rws new review --pick-cwd
rws session create review --cwd '~/work/review'
rws session get review
rws session update review --detach
rws session delete review
rws bg long-build
rws sessions
```

Use `--pick-cwd` when you want to browse the remote filesystem first. The picker accepts `ls`, `ls <path>`, `cd <path>`, `mkdir <path>`, `mkdir -p <path>`, and `pwd`; Enter confirms the displayed directory without rewriting the device default. When the remote host has bash, Tab completes files and paths.

Use another configured device without re-entering its host:

```bash
rws --device lab new review
```

## Device Removal

List devices:

```bash
rws devices
```

Remove a device:

```bash
rws remove lab
```

If the removed device was the default and other devices remain, `rws` picks the next available device as the default. If no devices remain, daily commands will ask you to run `rws setup` again.

## Entity Management

Use the entity commands when you want direct management instead of the daily aliases:

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

`rws key remove` only deletes local key files. It does not remove entries from the remote user's `authorized_keys`.

## Repeated Setup

`rws setup` is safe to rerun:

- it rewrites the selected device with the same format;
- it reuses existing keys unless `--force-key` is used;
- it does not duplicate authorized keys;
- it creates missing remote directories when creating sessions;
- it installs `shpool` only when missing;
- it may repair missing native build dependencies before installing the pinned `shpool` package;
- it refreshes the managed compact prompt block when compact mode is enabled;
- it reruns the final connect/shpool verification unless `--no-verify` is used for tests or pre-managed environments.
