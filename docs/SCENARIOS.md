# Scenarios

[中文](SCENARIOS.zh-CN.md) | English

This guide starts from user tasks rather than command categories. For a
complete command reference, see [`COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md).

## First Setup With Password Login

Use this when the remote machine accepts a username and password, and you want
`rws` to create a stable SSH key for later reconnects.

```bash
rws setup
```

Answer the wizard:

```text
Device name: devbox
Remote host or IP: devbox.example.net
Remote SSH user (default is local user): developer
Connecting to developer@devbox.example.net. Enter the remote SSH password if prompted.
Use compact prompt for remote sessions: Y
Use SSH key authentication for stable reconnects: Y
Choose: create a dedicated key
Create an initial session now: Y
Initial session name: coding
Remote cwd: /home/developer
rws cwd> cd ~/src/sample-project
rws cwd> <press Enter>
```

What happens:

- SSH asks for the remote password or host-key confirmation before any session cwd selection.
- `rws` creates or reuses the selected local key.
- `rws` appends the public key to remote `authorized_keys` when absent.
- `rws` prepares pinned `shpool` and verifies the saved device.
- If you create an initial session, the remote cwd picker lets you browse with `ls`, `cd`, `mkdir`, and `pwd`; the session is created in the background and setup prints the attach command without auto-attaching.

After setup:

```bash
rws attach coding
rws s
```

If setup fails after writing a device config, rerun `rws setup`, enter the same
device name, and choose whether to continue with saved values or reset the
device.

## Setup With An Existing SSH Key

Use this when `ssh user@host` already works with a key.

```bash
rws setup \
  --host user@workstation \
  --key-mode existing \
  --identity-file '~/.ssh/id_ed25519'
```

Then check the saved device:

```bash
rws doctor
```

## Setup In A Pre-Managed Remote Environment

Use this when remote SSH and `shpool` are managed outside `rws`.

Check without installing anything:

```bash
rws setup \
  --host user@workstation \
  --key-mode skip \
  --remote-install check \
  --shpool-bin /opt/homebrew/bin/shpool
```

Write config without remote verification only for isolated config-generation
or test environments:

```bash
rws setup \
  --host user@workstation \
  --key-mode skip \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes
```

## Daily Work On A Session

Create a session in a picked directory, then attach to it later without creating anything accidentally:

```bash
rws new project --pick-cwd
rws attach project
```

Leave the session without killing it by using shpool's detach sequence:

```text
Ctrl-Space Ctrl-q
```

Check state later:

```bash
rws s
rws sessions
```

Attach to an existing named session without creating it accidentally:

```bash
rws attach review
```

If `review` does not exist, the command fails and prints the `rws new review`
next action.

Kill the session when it is no longer needed:

```bash
rws k project
```

## Create A Separate Review Session

Use a separate session when you want another shell state on the same remote
device.

```bash
rws new review --pick-cwd
```

List sessions:

```bash
rws sessions
rws sessions --json
```

Delete it when finished:

```bash
rws session delete review
```

## Pick A Remote Directory You Do Not Remember

Use `--pick-cwd` when you know the host but do not remember the full remote
path.

```bash
rws new review --pick-cwd
```

At the prompt:

```text
rws cwd> pwd
rws cwd> ls ..
rws cwd> cd ../review-work
rws cwd>
```

Press Enter to use the displayed directory. This creates the session in that
directory without changing the saved device cwd.

## Recover A Coding Agent After Remote Reboot Or Power Loss

Declare the agent once when creating the Session. This enters the selected cwd
and starts the agent with full access by default, so use it only when the remote
device is trusted:

```bash
rws new coding --pick-cwd --agent codex
# or --agent claude / --agent kiro
```

To keep provider approval prompts instead, add `--no-full-access` when first
creating the Session.

Leave normally with shpool's detach sequence. While the remote host stays up,
`rws attach coding` reconnects to the running process. If reboot or power loss
removes the shpool session, the same command automatically runs the saved cwd's
recovery command and saved access mode:

```text
codex resume --last --dangerously-bypass-approvals-and-sandbox
claude --dangerously-skip-permissions --continue
kiro-cli chat --trust-all-tools --resume
```

For Codex full access, `rws` invokes the official `codex` command with
`--dangerously-bypass-approvals-and-sandbox`; it does not depend on a personal
alias or wrapper. With
`--no-full-access`, all three providers use their normal permission behavior.
On first use, Codex may still ask whether a new cwd is trusted, and Kiro may ask
for a trust-all risk acknowledgement. Select Kiro's "don't ask again" choice if
you want its own CLI to remember that acknowledgement. These one-time
provider-owned prompts are not per-tool approvals and are not auto-answered by
`rws`.

Each command selects the provider-native latest conversation for the current cwd. If the agent was exited and restarted several times inside one rws session, recovery therefore selects the latest one, not the first. Separate rws sessions that share one provider and cwd also resolve to the same latest conversation; use different directories when isolation matters.

Recovery requires the remote system disk, workspace, agent executable, and provider-native history to survive. Power loss can still lose the last unflushed conversation fragment or unsaved file; `rws` cannot restore process-only memory. Commit important code to Git and back up the remote disk.

To finish deliberately and disable automatic recovery:

```bash
rws kill coding
```

## Correct A Parameter Error

When a command has an unknown option, a missing value, or an invalid argument,
`rws` prints the error and then the current command's syntax, parameters, and
typical scenarios:

```bash
rws new coding --agent unknown
```

The output identifies `codex`, `claude`, and `kiro` as valid values, explains
that full access is the default, shows `--no-full-access`, and includes creation
and recovery examples. The same contract applies to setup, key, device,
session, attach, diagnostics, run, and cleanup commands. Help can also be read
directly without initialized config:

```bash
rws help new
rws help attach
rws help scenarios
```

## Recover After Laptop Sleep Or Network Switch

First check what the remote thinks:

```bash
rws s
```

If the session exists but another client is still marked attached, force attach:

```bash
rws f
```

For a named session:

```bash
rws f review
```

If you intentionally want a new named session, use:

```bash
rws new review
```

Do not use `rws attach review` to create a session. `attach` fails when the
ordinary named Session does not already exist and prints the `rws new review`
next action. A Session with saved coding-agent metadata is the recovery
exception: `attach` recreates it from that metadata.

## Run One Remote Command From Automation

Use `rws run -- ...` for scripts that need remote execution without entering an
interactive shell.

```bash
rws --cwd '~/repo' run -- git status --short
```

Automation contracts:

- stdout is preserved;
- stderr is preserved;
- the exit code is the remote command exit code.

Example:

```bash
if ! rws --cwd '~/repo' run -- test -f package.json; then
  echo "remote project is not initialized" >&2
  exit 1
fi
```

## Use Multiple Devices

Create a second device:

```bash
rws setup \
  --device lab \
  --host user@lab-box
```

Use it:

```bash
rws --device lab new review --pick-cwd
rws --device lab attach review
```

Make it default:

```bash
rws device update lab --default
```

Remove it:

```bash
rws remove lab
```

## Shorten A Crowded Remote Prompt

Enable compact prompt during setup:

```bash
rws setup --prompt-mode compact --prompt-label devbox
```

Or update an existing device:

```bash
rws device update devbox --prompt-mode compact --prompt-label devbox
```

`device update` changes local config only. To install or refresh the remote
shell rc block and shpool prompt config, rerun setup with the compact prompt
options:

```bash
rws setup --device devbox --prompt-mode compact --prompt-label devbox
```

Compact mode keeps device/session context visible while giving the command line
more room. Existing shpool daemons may keep the old prompt prefix until they are
restarted.

## Troubleshoot Setup Or Connection Failures

Start with:

```bash
rws doctor
```

Common failures:

| Symptom | Meaning | Next action |
| --- | --- | --- |
| `Run: rws setup` | No initialized device. | Run `rws setup`. |
| `ssh_error=dns_failed` | Host cannot be resolved. | Check `host` or SSH alias. |
| `ssh_error=connection_refused` | SSH service is not accepting connections. | Check remote SSH server and port. |
| `ssh_error=connection_timeout` | Network, VPN, firewall, or routing issue. | Verify network path and SSH options. |
| `ssh_error=authentication_failed` | SSH auth failed. | Check username, key, password, or ssh-agent. |
| `ssh_error=host_key_changed` | Known host identity changed. | Verify the host before updating `known_hosts`. |
| `ssh_error=connection_reset` | SSH service or Podman VM may still be warming up. | Wait and retry. |
| `remote cwd missing` | Saved cwd no longer exists. | Recreate it or update the device cwd. |
| `remote cwd not accessible` | Permission denied or inaccessible directory. | Fix permissions or choose another cwd. |
| `shpool command failed` | Configured `shpool` path is missing or not executable. | Rerun setup, fix `shpool_bin`, or point `--shpool-bin` to a working binary. |
| `expected shpool ... but found ...` | Remote shpool version mismatch. | Rerun setup or point `--shpool-bin` to the pinned version. |
| `shpool daemon check failed` | `shpool list --json` failed. | Inspect remote shpool daemon state. |

## Safe Cleanup

Detach without killing:

```bash
rws d
```

Kill one or more sessions:

```bash
rws k
rws kill review build
```

Remove a device config:

```bash
rws remove lab
```

Remove a local key file only when you are sure it is no longer needed:

```bash
rws key remove --identity-file '~/.ssh/rws_lab_ed25519' --force
```

This does not remove the corresponding public key from remote
`authorized_keys`.
