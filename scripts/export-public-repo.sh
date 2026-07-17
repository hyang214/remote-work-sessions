#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TARGET_INPUT=${1:-}
MANIFEST=

fail() {
  printf 'public export failed: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$MANIFEST" && -f "$MANIFEST" ]]; then
    rm -f "$MANIFEST"
  fi
}
trap cleanup EXIT

[[ -n "$TARGET_INPUT" ]] || fail "usage: scripts/export-public-repo.sh /absolute/path/to/empty/directory"
[[ "$TARGET_INPUT" = /* ]] || fail "target must be an absolute path"

target_parent=$(dirname -- "$TARGET_INPUT")
target_name=$(basename -- "$TARGET_INPUT")
[[ -d "$target_parent" ]] || fail "target parent directory does not exist: $target_parent"
target_parent=$(CDPATH='' cd -- "$target_parent" && pwd -P)
TARGET="$target_parent/$target_name"

case "$TARGET/" in
  "$ROOT/"*) fail "target must be outside the source repository" ;;
esac

if [[ -e "$TARGET" ]]; then
  [[ ! -L "$TARGET" ]] || fail "target must not be a symbolic link: $TARGET"
  [[ -d "$TARGET" ]] || fail "target exists and is not a directory: $TARGET"
  physical_target=$(CDPATH='' cd -- "$TARGET" && pwd -P)
  case "$physical_target/" in
    "$ROOT/"*) fail "target must resolve outside the source repository" ;;
  esac
  [[ -z "$(find "$TARGET" -mindepth 1 -maxdepth 1 -print -quit)" ]] || fail "target directory is not empty: $TARGET"
else
  mkdir "$TARGET"
fi

"$ROOT/scripts/verify-public-release.sh" --source

MANIFEST=$(mktemp)
while IFS= read -r -d '' relative; do
  if [[ -f "$ROOT/$relative" || -L "$ROOT/$relative" ]]; then
    printf '%s\0' "$relative" >> "$MANIFEST"
  fi
done < <(git -C "$ROOT" ls-files -co --exclude-standard -z)

[[ -s "$MANIFEST" ]] || fail "source repository contains no exportable files"
tar -C "$ROOT" --null -T "$MANIFEST" -cf - | tar -C "$TARGET" -xf -

git -C "$TARGET" init --initial-branch=main >/dev/null
git -C "$TARGET" config user.name "Remote Work Sessions contributors"
git -C "$TARGET" config user.email "contributors@remote-work-sessions.invalid"
git -C "$TARGET" add --all
git -C "$TARGET" commit -m "Initial public release" >/dev/null

repository_url=$(node -e '
const pkg = require(process.argv[1]);
const value = typeof pkg.repository === "string" ? pkg.repository : pkg.repository && pkg.repository.url;
if (!value) process.exit(1);
process.stdout.write(value.replace(/^git\+/, ""));
' "$TARGET/package.json") || fail "package.json is missing repository.url"

git -C "$TARGET" remote add origin "$repository_url"
(
  cd "$TARGET"
  npm run verify:package
  scripts/verify-public-release.sh --history
)

printf 'public export ready: %s\n' "$TARGET"
printf 'review, create the empty GitHub repository, then run:\n'
printf '  git -C %q push --set-upstream origin main\n' "$TARGET"
