# Design

[中文](DESIGN.zh-CN.md) | English

Remote Work Sessions is intentionally small.

## Model

```text
local terminal
  -> rws device
    -> ssh
      -> remote host
        -> remote runtime
        -> shpool session
          -> shell / coding agent / command
```

`rws` does not create a new transport. It composes SSH and shpool into a shorter daily workflow.

A device is the reusable SSH target and setup state. A session is a shpool session on that device. The remote runtime is setup-managed state on the remote account, such as `shpool`, shpool config, and the optional compact prompt block. Creating another session should not require the user to re-enter the host.

## Entities

- SSH key: local identity material that can be created, inspected, regenerated, or removed with `rws key` commands. Remote `authorized_keys` installation is handled by setup.
- Device: reusable local config for host, identity file, SSH options, shpool path, and prompt preferences. A cwd and default session can be saved for compatibility or deliberate defaults, but new setup does not require them.
- Session: a named shpool session on a selected device. Sessions can be attached,
  detached, killed, and listed. A Session may have local optional agent, cwd,
  and access-mode metadata used to reopen the provider-native latest
  conversation after shpool process state is lost; this is not another entity.
- Remote runtime: remote account state prepared by setup, including shpool installation, shpool prompt config, and shell prompt rc blocks.

The default device pointer in `default.conf` is relationship state, not a separate entity. Working directories are session attributes, with optional saved device defaults for compatibility; `rws` does not introduce a project or workspace entity.

## Responsibilities

`rws` handles:

- device selection;
- interactive and non-interactive setup;
- device initialization under the user config directory;
- local OpenSSH client dependency checks and installation when possible;
- SSH key creation or explicit reuse during initialization;
- optional public key installation through interactive SSH/password login or an already authorized bootstrap key;
- remote shpool dependency checks and pinned installation when possible;
- compact prompt setup for supported remote shells;
- final setup verification by reconnecting and checking SSH plus shpool;
- optional initial session creation after device verification, in the background, without auto-attaching;
- device removal;
- SSH command construction;
- shpool attach, force attach, background attach, detach, kill, and list;
- foreground initial launch of Codex, Claude Code, or Kiro CLI with full access by default, plus latest-conversation recovery in the saved cwd and saved access mode when shpool state is lost;
- basic remote status checks;
- working-directory creation when sessions are created;
- one-shot remote commands in an explicitly selected or configured directory.

`rws` does not handle:

- secrets;
- password storage;
- reading or storing interactive passwords;
- public network exposure;
- file sync;
- editor integration;
- terminal panes or layouts.
- copying, parsing, or backing up coding-agent conversation databases;
- recovering unflushed process memory or unsaved files after power loss.

## Why shpool

Many remote workflows need session persistence but not a full terminal multiplexer. shpool keeps a shell session alive while leaving window, pane, and layout concerns out of scope.

Shpool handles network disconnects but does not preserve processes across host reboot. A Session with optional agent metadata adds a second durability layer: local `rws` stores agent/cwd/access mode, while the remote agent stores its own conversations. After reboot, `rws` atomically creates a foreground shpool session and invokes the provider's cwd-scoped latest-resume command with the same explicitly selected access mode. It does not attempt to serialize a terminal process.

## Compatibility

The CLI is written as a POSIX-leaning Bash script and targets macOS and Linux clients. It expects a standard SSH client locally and shpool on the remote host.
