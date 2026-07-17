# Changelog

## 0.2.0 - 2026-07-16

- Add restart-safe coding sessions for Codex, Claude Code, and Kiro through `rws new <session> --agent <agent>`.
- Restore a missing registered shpool session with the provider's latest conversation in the saved remote working directory.
- Persist only local recovery metadata, keep ordinary shell-session behavior unchanged, and remove recovery metadata with session/device deletion.
- Make full access the persisted default whenever `--agent` is declared: use the official `codex` binary and sandbox/approval bypass option, use Claude Code's permission bypass, and trust all Kiro CLI 2.x tools on both initial launch and recovery.
- Do not discover or depend on a personal `codexd` alias; recover Codex with the official `codex resume --last --dangerously-bypass-approvals-and-sandbox` command.
- Add explicit `--no-full-access` for normal provider permissions, keep legacy v1 recovery metadata on normal access, retain `--full-access` as a compatibility spelling, and never treat the system `cc` compiler as Claude Code.
- Expand topic help to every public command family, document coding-agent launch/recovery behavior and scenarios, and append command-specific usage, parameters, and examples to CLI errors.

## 0.1.10 - 2026-05-29

- Preserve compact prompt context for sessions created in the background by passing a safe `TERM` into remote shpool attach.
- Fall back to `TERM=xterm-256color` inside managed compact prompt blocks when the session starts with an empty or `dumb` terminal type.
- Split setup into device initialization plus optional initial session creation.
- Stop writing device `cwd` and `default_session` during device-only setup.
- Create optional setup sessions in the background and print `rws attach <session>` instead of auto-attaching.
- Add `rws help scenarios` and `rws help commands`.
- Add standard short options for common global, setup, device, key, list, and session commands.

## 0.1.9 - 2026-05-28

- Add visible setup progress messages while remote cwd, dependency, shpool, and prompt steps are running.
- Let interactive setup opt out of slow automatic remote dependency installation and switch to check-only mode.
- Prefix setup stages with `[n/12]` markers so long-running setup shows where it is in the overall flow.
- Add a local setup heartbeat while remote dependency initialization is still running.
- Create the remote cwd automatically when creating or attaching a session.
- Add `mkdir` commands and bash/readline Tab completion to the remote cwd picker.

## 0.1.8 - 2026-05-28

- Add an upgrade compatibility quality gate for existing installed `rws` configs.
- Verify package upgrade preserves existing device config and the upgraded CLI can read, check, and update it.

## 0.1.7 - 2026-05-27

- Validate interactive setup SSH connectivity before remote cwd selection.
- Replace the interactive setup cwd text prompt with the remote cwd picker.
- Allow setup prompts to be canceled and add continue/reset choices for existing device configs.
- Require `--cwd` for non-interactive setup and document package updates.

## 0.1.6 - 2026-05-27

- Add Chinese versions of top-level docs and enforce bilingual docs coverage in the quality gate.
- Report missing local and remote runtime dependencies before falling through to raw shell errors.
- Document installation from npm.
- Add a Chinese README and include it in the npm package.
- Add package repository, issue tracker, and homepage metadata.
- Initial source layout for `rws`.
- Add device-based configuration.
- Add persistent SSH session commands built on shpool.
- Add SSH key creation/reuse support in `rws init`.
- Add Podman-based client/server E2E tests.
- Add npm package metadata for the `rws` command.
- Add `rws setup` as the primary idempotent setup flow.
- Add uninitialized guards, `rws doctor`, and pinned remote shpool setup.
- Add explicit `rws new <session>` and `rws sessions` commands.
- Remove legacy profile/name compatibility; the current config model is device/default_session only.
- Add the user-story quality gate.
- Record review gaps found by Kiro, Codex, and maintainer review.
