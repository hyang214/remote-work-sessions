# Security

## Supported Versions

Security fixes are released on the latest published minor version. Older
versions may receive a fix only when the same patch applies safely.

| Version | Supported |
| --- | --- |
| Latest published minor | Yes |
| Older versions | No guaranteed support |

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/hyang214/remote-work-sessions/security/advisories/new)
and include the affected version, impact, reproduction steps, and any proposed
mitigation. Remove credentials, private hostnames, addresses, usernames, and
other environment-specific data from the report.

The maintainers will acknowledge a complete report within seven days, assess
severity and affected versions, and coordinate a fix and disclosure timeline.
If the report is not a vulnerability, the maintainers will explain why and may
redirect the discussion to a public issue after removing sensitive details.

## Security Model

Remote Work Sessions does not store passwords, private keys, API tokens, or other secrets.

The tool relies on your existing SSH configuration and authentication. Keep using normal SSH security practices:

- prefer key-based authentication;
- protect private keys with appropriate file permissions;
- avoid exposing SSH directly to the public internet without a hardened access model;
- use VPN, private networks, or approved bastion hosts when needed;
- audit remote profiles before sharing them.

During `rws setup --install-key`, the tool may start SSH in interactive mode so SSH can ask for the remote password or host-key confirmation. Those prompts are handled by SSH itself; `rws` never accepts, logs, or stores the password. Non-interactive setup should use `--bootstrap-identity` with an already authorized key.

Interactive setup may keep a temporary OpenSSH control connection open while it installs the selected public key and remote dependencies. The control connection is closed before final verification, so the saved profile must work on its own.

`rws setup` can install local OpenSSH client tools and remote `shpool` when they are missing. Remote `shpool` installation is pinned to the version documented in `docs/DEPENDENCIES.md`.

Interactive setup may also trigger a remote `sudo` password prompt when administrator rights are needed to install Cargo. That prompt is handled by the remote `sudo` command through SSH; `rws` does not read or store the sudo password.

## Coding Agent Full Access

`rws new SESSION --agent AGENT` gives the selected agent full access by default
and is therefore an explicit high-risk operation. It persists the provider's
tool-approval bypass for both initial launch and recovery: Codex uses the
official `--dangerously-bypass-approvals-and-sandbox` flag, Claude Code uses
`--dangerously-skip-permissions`, and Kiro CLI 2.x uses `--trust-all-tools`.

This does not grant new operating-system credentials, but it lets the coding
agent act without its normal approval prompts anywhere the remote account can
access. Use it only on a trusted, isolated development device with scoped
credentials and recoverable data. Use `--no-full-access` to preserve normal
provider permissions. The older explicit `--full-access` option remains a
compatible but redundant spelling. `rws` never treats `cc` as Claude Code
because `cc` is commonly the system C compiler.

This option does not script provider-owned safety prompts. A provider may still
ask once for onboarding, workspace trust, or acknowledgement of the bypass
mode. In particular, Codex can ask whether a new cwd is trusted, and Kiro 2.x
can ask the user to accept trust-all mode; choosing Kiro's "don't ask again"
option stores that acknowledgement in Kiro's own settings. These are distinct
from the per-tool approvals disabled by full access.
