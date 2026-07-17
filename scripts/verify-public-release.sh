#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MODE=${1:---source}
TMP_DIR=

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

fail() {
  printf 'public-release check failed: %s\n' "$*" >&2
  exit 1
}

# Keep sensitive literals split or expressed as regular expressions so this
# guard does not match its own source.
FORBIDDEN_PATTERNS=(
  'yupa[o]'
  'auto[h]yang'
  'ocha[-]hyang'
  'mac[-]mini'
  'talent[-]workshop'
  'zhao[g]ong'
  'vrt[b]bs'
  'packages[.]ali[y]un[.]com'
  'internal[[:space:]]+(npm[[:space:]]+)?registry'
  'internal[[:space:]]+gitlab'
  '/Users'"/"
  '10[.][0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}'
  '192[.]168[.][0-9]{1,3}[.][0-9]{1,3}'
  '172[.](1[6-9]|2[0-9]|3[01])[.][0-9]{1,3}[.][0-9]{1,3}'
  'BEGIN[[:space:]]+(RSA[[:space:]]+|OPENSSH[[:space:]]+|EC[[:space:]]+)?PRIVATE[[:space:]]+KEY'
  'AKIA[0-9A-Z]{16}'
  'gh[pousr]_[A-Za-z0-9_]{20,}'
  'github[_]pat_[A-Za-z0-9_]{20,}'
  'gl[p]at-[A-Za-z0-9_-]{20,}'
  'npm_[A-Za-z0-9]{20,}'
  'sk-[A-Za-z0-9_-]{20,}'
  '(_authToken|npm_config_auth_token)[[:space:]]*=[[:space:]]*[^[:space:]]+'
  'aws_secret_access_key[[:space:]]*=[[:space:]]*[^[:space:]]+'
  'https?://[^/@[:space:]]+:[^/@[:space:]]+@'
  'g[i]t@[^:[:space:]]+:'
  '[A-Za-z0-9.-]+[.](internal|corp|lan|local)([^A-Za-z0-9.-]|$)'
  '[A-Za-z]:\\Users\\[^\\[:space:]]+'
  '([0-9]{1,3}[.]){3}[0-9]{1,3}'
  '([[:xdigit:]]{1,4}:){2,7}[[:xdigit:]]{1,4}'
)

build_pattern() {
  local pattern=
  local item
  for item in "${FORBIDDEN_PATTERNS[@]}"; do
    if [[ -n "$pattern" ]]; then
      pattern="$pattern|$item"
    else
      pattern=$item
    fi
  done
  printf '%s' "$pattern"
}

find_unallowlisted_url_hosts() {
  local url url_host
  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    url_host=${url#*://}
    url_host=${url_host##*@}
    case "$url_host" in
      dl-cdn.alpinelinux.org|docs.npmjs.com|github.com|index.crates.io|registry.npmjs.org|www.contributor-covenant.org|example.com|example.invalid|example.org|localhost)
        ;;
      *)
        printf 'URL host is not allowlisted: %s\n' "$url_host"
        ;;
    esac
  done < <(LC_ALL=C grep -aEo 'https?://([^/@[:space:]]+@)?[A-Za-z0-9.-]+' || true)
}

scan_tree() {
  local tree=$1
  local label=$2
  local pattern
  local file relative matches target url_matches
  local found=0
  pattern=$(build_pattern)

  while IFS= read -r -d '' file; do
    relative=${file#"$tree"/}
    if printf '%s\n' "$relative" | grep -Eiq -- "$pattern"; then
      printf '%s: forbidden path: %s\n' "$label" "$relative" >&2
      found=1
    fi
    if [[ -L "$file" ]]; then
      target=$(readlink "$file")
      matches=$(printf '%s\n' "$target" | LC_ALL=C grep -aEni -- "$pattern" || true)
    else
      matches=$(LC_ALL=C grep -aEni -- "$pattern" "$file" 2>/dev/null || true)
    fi
    matches=$(printf '%s\n' "$matches" \
      | grep -Ev '127[.]0[.]0[.]1|0[.]0[.]0[.]0|MaxStartups[[:space:]]+100:''30:''200' || true)
    if [[ -L "$file" ]]; then
      url_matches=$(printf '%s\n' "$target" | find_unallowlisted_url_hosts)
    else
      url_matches=$(find_unallowlisted_url_hosts < "$file")
    fi
    matches="${matches}${matches:+$'\n'}${url_matches}"
    if [[ -n "$matches" ]]; then
      printf '%s: forbidden content in %s\n' "$label" "$relative" >&2
      printf '%s\n' "$matches" >&2
      found=1
    fi
  done < <(find "$tree" \
    \( -type f -o -type l \) \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -print0)

  [[ "$found" -eq 0 ]] || fail "$label contains private, user-specific, or secret-like data"
}

verify_source() {
  scan_tree "$ROOT" source
  printf 'public source check ok\n'
}

verify_package() {
  local package_dir tarball
  TMP_DIR=$(mktemp -d)
  (
    cd "$ROOT"
    npm pack --ignore-scripts --json --pack-destination "$TMP_DIR" > "$TMP_DIR/pack.json"
  )
  tarball=$(find "$TMP_DIR" -maxdepth 1 -name '*.tgz' -print -quit)
  [[ -n "$tarball" ]] || fail "npm pack did not create a tarball"
  mkdir -p "$TMP_DIR/unpacked"
  tar -xzf "$tarball" -C "$TMP_DIR/unpacked"
  package_dir="$TMP_DIR/unpacked/package"
  [[ -d "$package_dir" ]] || fail "npm tarball is missing the package directory"
  [[ ! -e "$package_dir/docs/verification" ]] || fail "machine-specific verification logs are packaged"
  [[ ! -e "$package_dir/tests" ]] || fail "tests are packaged"
  [[ -x "$package_dir/bin/rws" ]] || fail "packaged rws binary is not executable"
  scan_tree "$package_dir" package
  printf 'public package check ok\n'
}

verify_history() {
  local object_id object_type pattern matches url_matches
  verify_source
  TMP_DIR=$(mktemp -d)
  pattern=$(build_pattern)
  git -C "$ROOT" for-each-ref --format='%(refname) %(objectname) %(subject)' \
    > "$TMP_DIR/history.txt"
  git -C "$ROOT" rev-list --objects --all >> "$TMP_DIR/history.txt"
  while read -r object_id object_type; do
    case "$object_type" in
      blob|commit|tag)
        printf '\nobject %s %s\n' "$object_id" "$object_type" >> "$TMP_DIR/history.txt"
        git -C "$ROOT" cat-file -p "$object_id" >> "$TMP_DIR/history.txt"
        ;;
    esac
  done < <(git -C "$ROOT" cat-file --batch-all-objects --batch-check='%(objectname) %(objecttype)')

  matches=$(LC_ALL=C grep -aEni -- "$pattern" "$TMP_DIR/history.txt" \
    | grep -Ev '127[.]0[.]0[.]1|0[.]0[.]0[.]0|MaxStartups[[:space:]]+100:''30:''200' || true)
  url_matches=$(find_unallowlisted_url_hosts < "$TMP_DIR/history.txt")
  matches="${matches}${matches:+$'\n'}${url_matches}"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    fail "Git history contains private, user-specific, or secret-like data; publish a clean exported history"
  fi
  printf 'public history check ok\n'
}

case "$MODE" in
  --source)
    verify_source
    ;;
  --package)
    verify_source
    verify_package
    ;;
  --history)
    verify_history
    ;;
  *)
    fail "usage: scripts/verify-public-release.sh --source|--package|--history"
    ;;
esac
