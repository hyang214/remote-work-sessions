#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TAG_NAME=${GITHUB_REF_NAME:-}
RELEASE_SHA=${GITHUB_SHA:-}
MAIN_REF=${RWS_PUBLISH_MAIN_REF:-origin/main}

fail() {
  printf 'publish-ref check failed: %s\n' "$*" >&2
  exit 1
}

[[ -n "$TAG_NAME" ]] || fail "GITHUB_REF_NAME is required"
[[ -n "$RELEASE_SHA" ]] || fail "GITHUB_SHA is required"

package_version=$(node -e 'process.stdout.write(require(process.argv[1]).version)' "$ROOT/package.json")
expected_tag="v$package_version"
[[ "$TAG_NAME" == "$expected_tag" ]] \
  || fail "release tag $TAG_NAME does not match $expected_tag"

git -C "$ROOT" cat-file -e "$RELEASE_SHA^{commit}" 2>/dev/null \
  || fail "release commit does not exist: $RELEASE_SHA"
git -C "$ROOT" cat-file -e "$MAIN_REF^{commit}" 2>/dev/null \
  || fail "public main ref does not exist: $MAIN_REF"
git -C "$ROOT" merge-base --is-ancestor "$RELEASE_SHA" "$MAIN_REF" \
  || fail "release commit $RELEASE_SHA is not reachable from $MAIN_REF"

printf 'publish ref check ok: %s at %s\n' "$TAG_NAME" "$RELEASE_SHA"
