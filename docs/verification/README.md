# Verification Evidence

Release evidence is produced by the repository's GitHub Actions workflows and
attached to the corresponding public commit, pull request, or release.

Do not commit raw machine-specific verification logs. Evidence must not include
usernames, device names, private network addresses, absolute home-directory
paths, authentication endpoints, credentials, or other environment-specific
identifiers. Use reserved example domains and generic paths in durable docs.

This directory contains policy only and is excluded from the npm package.
Package consumers receive the user and maintainer documentation under `docs/`,
while maintainers use CI logs for execution evidence.
