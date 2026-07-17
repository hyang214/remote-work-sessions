# Contributing

Contributions are welcome.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before You Start

- Search existing issues and pull requests before opening a duplicate.
- Use a GitHub issue for a bug report or feature proposal.
- Use GitHub private vulnerability reporting for security findings; do not
  disclose them in an issue or pull request.
- Keep examples and test fixtures generic. Do not commit real usernames,
  device names, private addresses, absolute home paths, credentials, or private
  package and source-control endpoints.

## Scope

Remote Work Sessions should stay focused on persistent remote shell sessions over SSH.

Good contributions:

- improve device handling;
- improve diagnostics;
- improve install and packaging;
- add tests for command construction and config parsing;
- document real remote-session workflows.

Out of scope:

- secret management;
- remote desktop;
- file sync;
- tunnel or bastion management;
- terminal pane or layout management.

## Development

Use [`docs/USER_STORIES.md`](docs/USER_STORIES.md) to identify affected product
stories and [`docs/QUALITY_GATES.md`](docs/QUALITY_GATES.md) to select the
required checks. A pull request should state the affected story IDs, or say
that no product story changes.

Run basic checks:

```bash
npm ci --ignore-scripts
npm test
npm run audit
npm run verify:package
```

Run the container lifecycle test for setup, SSH, dependency installation,
session lifecycle, or release changes:

```bash
npm run test:e2e
```

The E2E suite requires Podman. If a required check cannot run, name it and the
reason in the pull request; do not report it as passed.

Use a temporary config for local smoke tests:

```bash
rws --config-dir /path/to/test-config c
```

## Pull Requests

- Keep changes focused and match the existing shell and documentation style.
- Add or update tests that prove the intended behavior and failure path.
- Update both English and Chinese top-level docs when either version changes.
- Keep commits free of generated archives and machine-specific logs.
- Confirm `npm run verify:package` passes before requesting review.

Pull requests require passing CI and maintainer review. Maintainers may ask for
a smaller change when unrelated work makes behavior or security harder to
review.

## Releases

Only maintainers publish releases. See [`docs/RELEASING.md`](docs/RELEASING.md)
for the public GitHub and npm release process.
