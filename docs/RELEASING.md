# Releasing

[中文](RELEASING.zh-CN.md) | English

This project publishes from the public GitHub repository to the public npm
registry. Do not publish an internal clone or an internal Git history.

## One-Time Public Repository Bootstrap

1. From a sanitized working tree, create a clean public export:

   ```bash
   scripts/export-public-repo.sh /absolute/path/to/empty/export-directory
   ```

   The command creates a new Git repository on `main`, commits only the current
   public snapshot with a generic contributor identity, configures the public
   GitHub URL, scans the complete exported history, and verifies the npm
   tarball. It does not push anything.

2. Create an empty public GitHub repository named `remote-work-sessions`. Do not
   initialize it with generated files, then push the exported `main` branch.
3. Make `main` the default branch. Protect it with pull-request review and the
   required `Quality`, `ShellCheck`, `Public history`, and `Podman E2E` checks.
4. Enable private vulnerability reporting, dependency graph, Dependabot alerts
   and security updates, secret scanning, and push protection where the
   repository plan supports them.
5. Confirm Actions can run the workflows in `.github/workflows/`. Keep workflow
   permissions restricted to each job's declared permissions.

The source repository can keep its original remote. Never mirror its existing
history to the public repository; repeat the clean export if the public
bootstrap must be recreated.

## One-Time npm Bootstrap

The npm package name is `remote-work-sessions`. Before publishing, verify that
the package is still available and that the intended npm account or
organization owns the name.

A trusted publisher is configured on an existing npm package, so the first
release needs a maintainer bootstrap:

1. Run `npm run test:release` and `npm run test:e2e` from the clean public
   repository.
2. Sign in with an npm account protected by two-factor authentication.
3. Publish the exact reviewed tarball with `npm publish --access public`.
4. In the npm package settings, add a GitHub Actions trusted publisher for this
   repository, workflow `publish.yml`, and environment `npm`.
5. In GitHub, create the `npm` environment and restrict deployment to protected
   tags or approved maintainers as appropriate.
6. Remove any npm automation token or GitHub `NPM_TOKEN` secret used during
   bootstrap. Normal releases use OIDC and must not depend on a long-lived npm
   token.

See npm's official documentation for
[trusted publishing](https://docs.npmjs.com/trusted-publishers/) and
[provenance](https://docs.npmjs.com/generating-provenance-statements/).

## Normal Release

1. Start from a clean `main` checkout on the public repository.
2. Choose a SemVer version and update `package.json`, `package-lock.json`,
   `RWS_VERSION` in `bin/rws`, setup-version examples, and `CHANGELOG.md`.
3. Run:

   ```bash
   npm ci --ignore-scripts
   npm run test:release
   npm run test:e2e
   scripts/verify-public-release.sh --history
   ```

4. Merge the reviewed release change after all required checks pass.
5. Create a GitHub release only for a commit already reachable from the
   protected public `main` branch, using a tag exactly matching
   `v<package-version>`, for example `v1.2.3` for package version `1.2.3`.
6. The `Publish npm` workflow verifies the tag, tests the package, scans the
   public history, and publishes through npm trusted publishing. npm generates
   provenance for the published package.
7. Confirm the package version and provenance on npm, install it in a clean
   environment, and run `rws --version`.

Do not rerun a failed publish by changing the contents under an existing npm
version. Fix the cause, choose a new version when a package version was already
accepted, and keep the release evidence in the public Actions run.
