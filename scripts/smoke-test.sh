#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp_npm_prefix=

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

expect_exit_2() {
  local stdout_file=$1
  local stderr_file=$2
  shift 2
  local rc
  set +e
  "$@" </dev/null >"$stdout_file" 2>"$stderr_file"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    fail "expected command to fail: $*"
  fi
  [[ "$rc" -eq 2 ]] || fail "expected exit 2, got $rc: $*"
}

expect_failure() {
  local stdout_file=$1
  local stderr_file=$2
  shift 2
  local rc
  set +e
  "$@" </dev/null >"$stdout_file" 2>"$stderr_file"
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || fail "expected command to fail: $*"
}

require_file_contains() {
  local file=$1
  local pattern=$2
  grep -Eq -- "$pattern" "$file" || fail "expected $file to contain pattern: $pattern"
}

require_error_help() {
  local file=$1
  local usage_pattern=$2
  require_file_contains "$file" '^Usage:$'
  require_file_contains "$file" '^Parameters and options:$'
  require_file_contains "$file" '^Typical scenarios:$'
  require_file_contains "$file" "$usage_pattern"
}

verify_pack_contents() {
  local pack_json=$1
  (cd "$ROOT" && npm pack --dry-run --json >"$pack_json")
  node - "$pack_json" <<'NODE'
const fs = require('fs');
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))[0];
const files = new Set(report.files.map((entry) => entry.path));
const required = [
  'README.md',
  'README.zh-CN.md',
  'LICENSE',
  'SECURITY.md',
  'package.json',
  'bin/rws',
  'docs/COMMAND_REFERENCE.md',
  'docs/COMMAND_REFERENCE.zh-CN.md',
  'docs/CONFIGURATION.md',
  'docs/CONFIGURATION.zh-CN.md',
  'docs/DEPENDENCIES.md',
  'docs/DEPENDENCIES.zh-CN.md',
  'docs/DESIGN.md',
  'docs/DESIGN.zh-CN.md',
  'docs/SCENARIOS.md',
  'docs/SCENARIOS.zh-CN.md',
  'docs/SETUP.md',
  'docs/SETUP.zh-CN.md',
  'docs/TESTING.md',
  'docs/TESTING.zh-CN.md',
  'docs/QUALITY_GATES.md',
  'docs/QUALITY_GATES.zh-CN.md',
  'docs/RELEASING.md',
  'docs/RELEASING.zh-CN.md',
  'docs/USER_STORIES.md',
  'docs/USER_STORIES.zh-CN.md',
];
const forbiddenPrefixes = ['tests/', 'docs/verification/', '.git/', 'node_modules/'];
const missing = required.filter((path) => !files.has(path));
const forbidden = [...files].filter((path) =>
  forbiddenPrefixes.some((prefix) => path.startsWith(prefix))
);
if (missing.length || forbidden.length) {
  if (missing.length) console.error(`missing package files: ${missing.join(', ')}`);
  if (forbidden.length) console.error(`unexpected package files: ${forbidden.join(', ')}`);
  process.exit(1);
}
NODE
}

verify_release_metadata() {
  node - "$ROOT" <<'NODE'
const fs = require('fs');
const path = require('path');

const root = process.argv[2];
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const lock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'), 'utf8'));

function expect(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}

expect(lock.name === pkg.name, `package-lock name ${lock.name} does not match package.json ${pkg.name}`);
expect(lock.version === pkg.version, `package-lock version ${lock.version} does not match package.json ${pkg.version}`);

const rootLock = lock.packages && lock.packages[''];
expect(rootLock, 'package-lock missing packages[""] metadata');
expect(rootLock.name === pkg.name, `package-lock packages[""].name ${rootLock.name} does not match package.json ${pkg.name}`);
expect(rootLock.version === pkg.version, `package-lock packages[""].version ${rootLock.version} does not match package.json ${pkg.version}`);
expect(JSON.stringify(rootLock.bin || {}) === JSON.stringify(pkg.bin || {}), 'package-lock packages[""].bin does not match package.json bin');
expect(JSON.stringify(rootLock.engines || {}) === JSON.stringify(pkg.engines || {}), 'package-lock packages[""].engines does not match package.json engines');

const rws = fs.readFileSync(path.join(root, 'bin/rws'), 'utf8');
const versionMatch = rws.match(/^RWS_VERSION=([0-9]+\.[0-9]+\.[0-9]+)$/m);
expect(versionMatch, 'bin/rws missing RWS_VERSION metadata');
expect(versionMatch[1] === pkg.version, `bin/rws RWS_VERSION ${versionMatch[1]} does not match package.json ${pkg.version}`);

for (const rel of ['docs/CONFIGURATION.md', 'docs/CONFIGURATION.zh-CN.md']) {
  const text = fs.readFileSync(path.join(root, rel), 'utf8');
  expect(text.includes(`setup_version=${pkg.version}`), `${rel} missing setup_version=${pkg.version}`);
}

const e2e = fs.readFileSync(path.join(root, 'tests/e2e/podman-e2e.sh'), 'utf8');
expect(e2e.includes('PACKAGE_VERSION='), 'tests/e2e/podman-e2e.sh must derive expected setup_version from package.json');

const packageNames = [
  ['package.json', pkg.name],
  ['package-lock.json', lock.name],
  ['package-lock.json packages[""]', rootLock.name],
];
for (const [source, name] of packageNames) {
  expect(name === 'remote-work-sessions', `${source} package name changed unexpectedly: ${name}`);
}
expect(pkg.bin && pkg.bin.rws === 'bin/rws', 'package.json bin.rws must point to bin/rws');
expect(pkg.engines && pkg.engines.node === '>=22.14.0', 'package.json engines.node must remain >=22.14.0');
NODE
}

verify_upgrade_existing_config_gate() {
  local previous_version=0.1.6
  local upgrade_root="$tmp_npm_prefix/upgrade-existing-config"
  local upgrade_prefix="$upgrade_root/prefix"
  local upgrade_home="$upgrade_root/home"
  local previous_pkg="$upgrade_root/previous-package"
  local previous_tgz current_tgz before_config after_config

  mkdir -p "$previous_pkg/bin" "$upgrade_home/bin" "$upgrade_home/.config/rws/devices" "$upgrade_home/.ssh"
  node - "$ROOT" "$previous_pkg" "$previous_version" <<'NODE'
const fs = require('fs');
const path = require('path');

const root = process.argv[2];
const target = process.argv[3];
const version = process.argv[4];
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));

const previousPkg = {
  name: pkg.name,
  version,
  description: 'Upgrade compatibility fixture for Remote Work Sessions.',
  license: pkg.license,
  type: pkg.type,
  bin: pkg.bin,
  engines: pkg.engines,
  files: ['bin']
};
fs.writeFileSync(path.join(target, 'package.json'), `${JSON.stringify(previousPkg, null, 2)}\n`);

const binDir = path.join(target, 'bin');
fs.mkdirSync(binDir, { recursive: true });
const rws = fs.readFileSync(path.join(root, 'bin/rws'), 'utf8')
  .replace(/^RWS_VERSION=.*$/m, `RWS_VERSION=${version}`);
const rwsPath = path.join(binDir, 'rws');
fs.writeFileSync(rwsPath, rws);
fs.chmodSync(rwsPath, 0o755);
NODE

  previous_tgz=$(cd "$upgrade_root" && npm pack "$previous_pkg" --silent)
  npm install -g --prefix "$upgrade_prefix" "$upgrade_root/$previous_tgz" >"$upgrade_root/install-previous.out" 2>"$upgrade_root/install-previous.err"
  PATH="$upgrade_prefix/bin:$PATH" rws --version | grep -qx "rws $previous_version"

  cat > "$upgrade_home/bin/ssh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/ssh.log"
printf 'host=fake\nuser=fake\ncwd=/work\nshpool=shpool 0.9.8\nsessions={"sessions":[]}\n'
SH
  chmod +x "$upgrade_home/bin/ssh"

  cat > "$upgrade_home/.config/rws/default.conf" <<'EOF_DEFAULT'
# Default device for rws.
device=default
EOF_DEFAULT
  cat > "$upgrade_home/.config/rws/devices/default.conf" <<'EOF_DEVICE'
host=fake.example
cwd=/work
default_session=legacy
identity_file=~/.ssh/legacy_ed25519
shpool_bin=shpool
shpool_version=0.9.8
setup_version=0.1.6
prompt_mode=compact
prompt_label=legacy
ssh_option=StrictHostKeyChecking=no
ssh_option=UserKnownHostsFile=/dev/null
EOF_DEVICE

  before_config=$(cat "$upgrade_home/.config/rws/devices/default.conf")
  current_tgz=$(cd "$upgrade_root" && npm pack "$ROOT" --silent)
  npm install -g --prefix "$upgrade_prefix" "$upgrade_root/$current_tgz" >"$upgrade_root/install-current.out" 2>"$upgrade_root/install-current.err"
  PATH="$upgrade_prefix/bin:$PATH" rws --version | grep -qx "rws $PACKAGE_VERSION"
  after_config=$(cat "$upgrade_home/.config/rws/devices/default.conf")
  [[ "$before_config" == "$after_config" ]] || fail "upgrade install rewrote existing device config"

  PATH="$upgrade_prefix/bin:$upgrade_home/bin:$PATH" HOME="$upgrade_home" rws devices | grep -qx default
  PATH="$upgrade_prefix/bin:$upgrade_home/bin:$PATH" HOME="$upgrade_home" rws device get default >"$upgrade_root/device-get.out"
  grep -qx "host=fake.example" "$upgrade_root/device-get.out"
  grep -qx "cwd=/work" "$upgrade_root/device-get.out"
  grep -qx "default_session=legacy" "$upgrade_root/device-get.out"
  grep -qx "identity_file=~/.ssh/legacy_ed25519" "$upgrade_root/device-get.out"
  grep -qx "shpool_version=0.9.8" "$upgrade_root/device-get.out"
  grep -qx "setup_version=0.1.6" "$upgrade_root/device-get.out"
  grep -qx "prompt_label=legacy" "$upgrade_root/device-get.out"
  grep -qx "ssh_option=StrictHostKeyChecking=no" "$upgrade_root/device-get.out"
  grep -qx "ssh_option=UserKnownHostsFile=/dev/null" "$upgrade_root/device-get.out"

  PATH="$upgrade_prefix/bin:$upgrade_home/bin:$PATH" HOME="$upgrade_home" rws c >"$upgrade_root/check.out" 2>"$upgrade_root/check.err"
  grep -qx "shpool=shpool 0.9.8" "$upgrade_root/check.out"
  grep -Fxq 'sessions={"sessions":[]}' "$upgrade_root/check.out"

  PATH="$upgrade_prefix/bin:$upgrade_home/bin:$PATH" HOME="$upgrade_home" rws device update default \
    --cwd /work/upgraded \
    --session upgraded \
    --prompt-mode skip \
    --clear-ssh-options \
    >"$upgrade_root/device-update.out" 2>"$upgrade_root/device-update.err"
  grep -qx "updated default" "$upgrade_root/device-update.out"
  grep -qx "cwd=/work/upgraded" "$upgrade_home/.config/rws/devices/default.conf"
  grep -qx "default_session=upgraded" "$upgrade_home/.config/rws/devices/default.conf"
  grep -qx "prompt_mode=skip" "$upgrade_home/.config/rws/devices/default.conf"
  if grep -q "^ssh_option=" "$upgrade_home/.config/rws/devices/default.conf"; then
    fail "upgraded device update kept cleared ssh_option"
  fi
}

verify_bilingual_docs() {
  node - "$ROOT" <<'NODE'
const fs = require('fs');
const path = require('path');

const root = process.argv[2];
const docsDir = path.join(root, 'docs');
const englishDocs = fs.readdirSync(docsDir)
  .filter((name) => name.endsWith('.md'))
  .filter((name) => !name.endsWith('.zh-CN.md'))
  .filter((name) => !name.startsWith('verification/'))
  .sort();

for (const englishName of englishDocs) {
  const chineseName = englishName.replace(/\.md$/, '.zh-CN.md');
  const englishPath = path.join(docsDir, englishName);
  const chinesePath = path.join(docsDir, chineseName);
  if (!fs.existsSync(chinesePath)) {
    console.error(`missing Chinese doc: docs/${chineseName}`);
    process.exit(1);
  }
  const englishText = fs.readFileSync(englishPath, 'utf8');
  const chineseText = fs.readFileSync(chinesePath, 'utf8');
  if (!englishText.includes(`[中文](${chineseName}) | English`)) {
    console.error(`missing English-to-Chinese switch: docs/${englishName}`);
    process.exit(1);
  }
  if (!chineseText.includes(`[English](${englishName}) | 中文`)) {
    console.error(`missing Chinese-to-English switch: docs/${chineseName}`);
    process.exit(1);
  }
}

const readmeZh = fs.readFileSync(path.join(root, 'README.zh-CN.md'), 'utf8');
const requiredReadmeLinks = [
  'docs/SCENARIOS.zh-CN.md',
  'docs/COMMAND_REFERENCE.zh-CN.md',
  'docs/SETUP.zh-CN.md',
  'docs/CONFIGURATION.zh-CN.md',
  'docs/DEPENDENCIES.zh-CN.md',
  'docs/DESIGN.zh-CN.md',
  'docs/TESTING.zh-CN.md',
  'docs/USER_STORIES.zh-CN.md',
  'docs/QUALITY_GATES.zh-CN.md',
];
for (const link of requiredReadmeLinks) {
  if (!readmeZh.includes(link)) {
    console.error(`README.zh-CN.md missing Chinese doc link: ${link}`);
    process.exit(1);
  }
}

const topLevelChineseWithoutEnglish = fs.readdirSync(docsDir)
  .filter((name) => name.endsWith('.zh-CN.md'))
  .filter((name) => !fs.existsSync(path.join(docsDir, name.replace(/\.zh-CN\.md$/, '.md'))));
if (topLevelChineseWithoutEnglish.length) {
  console.error(`Chinese docs without English peer: ${topLevelChineseWithoutEnglish.join(', ')}`);
  process.exit(1);
}
NODE
}

verify_readme_command_table() {
  local command
  for command in \
    'rws' \
    'rws help' \
	  'rws a' \
	  'rws attach' \
	  'rws new' \
	  'rws new <session> --pick-cwd' \
	  'rws f' \
    'rws force' \
    'rws s' \
    'rws status' \
    'rws c' \
    'rws check' \
    'rws sh' \
    'rws shell' \
    'rws sessions' \
    'rws ls' \
    'rws list' \
    'rws bg' \
    'rws background' \
    'rws --cwd' \
    'rws d' \
    'rws detach' \
    'rws k' \
    'rws kill' \
	  'rws setup' \
    'rws doctor' \
    'rws key create' \
    'rws key get' \
    'rws key list' \
    'rws key update' \
    'rws key remove' \
    'rws devices' \
    'rws device create' \
    'rws device get' \
    'rws device update' \
    'rws device list' \
    'rws remove' \
    'rws rm' \
    'rws device remove' \
    'rws session create' \
    'rws session get' \
    'rws session list' \
    'rws session update' \
    'rws session delete' \
    'rws session attach' \
    'rws init'
  do
    grep -Fq "| \`$command" "$ROOT/README.md" || fail "README command table missing: $command"
  done
}

verify_usage_docs() {
  require_file_contains "$ROOT/README.md" 'README.zh-CN.md'
  require_file_contains "$ROOT/README.md" '^npm install -g remote-work-sessions$'
  require_file_contains "$ROOT/README.zh-CN.md" '^# Remote Work Sessions$'
  require_file_contains "$ROOT/README.zh-CN.md" '^## 安装$'
  require_file_contains "$ROOT/README.zh-CN.md" '^## 快速开始$'
  require_file_contains "$ROOT/README.zh-CN.md" 'docs/SCENARIOS.zh-CN.md'
  require_file_contains "$ROOT/README.zh-CN.md" 'docs/DEPENDENCIES.zh-CN.md'
  require_file_contains "$ROOT/README.zh-CN.md" '^npm install -g remote-work-sessions$'
  require_file_contains "$ROOT/README.zh-CN.md" '`rws setup`'
  require_file_contains "$ROOT/docs/SETUP.md" '^npm install -g remote-work-sessions$'
  require_file_contains "$ROOT/docs/SETUP.zh-CN.md" '^npm install -g remote-work-sessions$'
  require_file_contains "$ROOT/README.md" 'docs/SCENARIOS.md'
  require_file_contains "$ROOT/README.md" 'docs/COMMAND_REFERENCE.md'
  require_file_contains "$ROOT/README.md" 'docs/DESIGN.md'
  require_file_contains "$ROOT/README.md" 'docs/TESTING.md'
  require_file_contains "$ROOT/README.md" 'docs/QUALITY_GATES.md'
  require_file_contains "$ROOT/docs/COMMAND_REFERENCE.md" '^## Global Options$'
  require_file_contains "$ROOT/docs/COMMAND_REFERENCE.md" '^### `rws setup \[options\]`$'
  require_file_contains "$ROOT/docs/COMMAND_REFERENCE.md" '^### `rws run -- COMMAND \[ARG...\]`$'
  require_file_contains "$ROOT/docs/COMMAND_REFERENCE.md" '^### `rws a` / `rws attach \[session\]`$'
  require_file_contains "$ROOT/docs/COMMAND_REFERENCE.md" '--no-install-key'
  require_file_contains "$ROOT/docs/COMMAND_REFERENCE.md" 'ssh_error=connection_timeout'
  require_file_contains "$ROOT/docs/COMMAND_REFERENCE.md" 'shpool 0.9.8'
  require_file_contains "$ROOT/docs/SCENARIOS.md" '^## First Setup With Password Login$'
  require_file_contains "$ROOT/docs/SCENARIOS.md" '^## Recover After Laptop Sleep Or Network Switch$'
  require_file_contains "$ROOT/docs/SCENARIOS.md" '^## Run One Remote Command From Automation$'
  require_file_contains "$ROOT/docs/SCENARIOS.md" '^## Troubleshoot Setup Or Connection Failures$'
  require_file_contains "$ROOT/docs/SCENARIOS.md" 'rws attach review'
  require_file_contains "$ROOT/docs/SCENARIOS.md" 'shpool command failed'
  require_file_contains "$ROOT/docs/SCENARIOS.md" 'rws new review --pick-cwd'
  require_file_contains "$ROOT/docs/SCENARIOS.zh-CN.md" 'rws new review --pick-cwd'
  require_file_contains "$ROOT/docs/DEPENDENCIES.zh-CN.md" 'missing local dependency: ssh'
  require_file_contains "$ROOT/README.md" 'docs/RELEASING.md'
  require_file_contains "$ROOT/README.zh-CN.md" 'docs/RELEASING.zh-CN.md'
}

verify_help_command_surface() {
  local help_file=$1
  local pattern
  for pattern in \
    'rws setup' \
    'rws new SESSION --pick-cwd' \
    'rws attach SESSION' \
    'rws sessions' \
    'rws --cwd DIR run -- CMD' \
    'rws help scenarios' \
    'rws help commands' \
    '--config-dir DIR' \
    '-d, --device DEVICE' \
    '-H, --host HOST' \
    '-C, --cwd DIR' \
    '-s, --session SESSION' \
    '-i, --identity-file FILE' \
    '-B, --shpool-bin FILE' \
    '-o, --ssh-option OPTION'
  do
    require_file_contains "$help_file" "$pattern"
  done
}

verify_help_commands_surface() {
  local help_file=$1
  local pattern
  for pattern in \
    'rws setup \[-d DEVICE\]' \
    'rws device create DEVICE' \
    'rws device update DEVICE' \
    'rws new SESSION \[-C CWD\] \[-p\]' \
    'rws session create SESSION \[-C CWD\] \[-p\]' \
    'rws session list \[-j\|--json\]' \
    'rws key create \[-i FILE\] \[-f\]' \
    'rws --cwd DIR run -- COMMAND'
  do
    require_file_contains "$help_file" "$pattern"
  done
}

verify_security_claims() {
  require_file_contains "$ROOT/SECURITY.md" 'does not store passwords, private keys, API tokens, or other secrets'
  require_file_contains "$ROOT/SECURITY.md" 'never accepts, logs, or stores the password'
  require_file_contains "$ROOT/SECURITY.md" 'does not read or store the sudo password'
  require_file_contains "$ROOT/SECURITY.md" 'agent.*full access by default'
  require_file_contains "$ROOT/SECURITY.md" 'Use `--no-full-access` to preserve normal'
  require_file_contains "$ROOT/SECURITY.md" 'provider permissions'
  if grep -En '(password|secret|token).*(>|>>).*\.config|password=|secret=|token=' "$ROOT/bin/rws"; then
    fail "potential secret storage pattern found in bin/rws"
  fi
}

verify_verification_policy() {
  require_file_contains "$ROOT/docs/verification/README.md" 'GitHub Actions workflows'
  require_file_contains "$ROOT/docs/verification/README.md" 'Do not commit raw machine-specific verification logs'
  require_file_contains "$ROOT/docs/verification/README.md" 'excluded from the npm package'
}

verify_public_export_gate() {
  local target="$tmp_npm_prefix/public-export"
  "$ROOT/scripts/export-public-repo.sh" "$target" >"$tmp_npm_prefix/public-export.out"
  [[ "$(git -C "$target" branch --show-current)" == main ]] || fail "public export branch is not main"
  [[ "$(git -C "$target" rev-list --count HEAD)" == 1 ]] || fail "public export does not have a single clean commit"
  [[ "$(git -C "$target" log -1 --format=%an)" == "Remote Work Sessions contributors" ]] || fail "public export uses a machine-specific author"
  [[ "$(git -C "$target" remote get-url origin)" == "https://github.com/hyang214/remote-work-sessions.git" ]] || fail "public export origin does not match package metadata"
  [[ -z "$(git -C "$target" status --short)" ]] || fail "public export working tree is not clean"
}

verify_public_export_rejects_symlinks() {
  local before_status after_status
  local final_link="$tmp_npm_prefix/public-export-final-link"
  local parent_link="$tmp_npm_prefix/public-export-parent-link"
  before_status=$(git -C "$ROOT" status --porcelain=v1)

  ln -s "$ROOT" "$final_link"
  expect_failure \
    "$tmp_npm_prefix/export-final-link.out" \
    "$tmp_npm_prefix/export-final-link.err" \
    "$ROOT/scripts/export-public-repo.sh" "$final_link"
  grep -Fq 'target must not be a symbolic link' "$tmp_npm_prefix/export-final-link.err"
  rm -f "$final_link"

  ln -s "$ROOT" "$parent_link"
  expect_failure \
    "$tmp_npm_prefix/export-parent-link.out" \
    "$tmp_npm_prefix/export-parent-link.err" \
    "$ROOT/scripts/export-public-repo.sh" "$parent_link/nested-export"
  grep -Fq 'target must be outside the source repository' "$tmp_npm_prefix/export-parent-link.err"
  rm -f "$parent_link"

  after_status=$(git -C "$ROOT" status --porcelain=v1)
  [[ "$before_status" == "$after_status" ]] \
    || fail "rejected public export changed the source repository"
}

verify_public_scanner_rejects_private_data() {
  local fixture="$tmp_npm_prefix/public-scan-fixture"
  local case_entry case_name case_value leaked_file
  local cases=(
    "internal-name|yupa""o"
    "private-ip|10"".23.45.67"
    "public-ip|203"".0.113.42"
    "ipv6|2001:""db8:""1:""2:""3:""4:""5:""6"
    "home-path|/Users""/example/project"
    "windows-home|C:""\\Users\\example\\project"
    "github-token|ghp_""000000000000000000000000000000000000"
    "github-fine-grained|github_""pat_000000000000000000000000000000000000"
    "gitlab-token|gl""pat-00000000000000000000"
    "npm-token|npm_""000000000000000000000000000000000000"
    "npm-auth|_auth""Token=npm_""000000000000000000000000000000000000"
    "aws-secret|aws_secret_access_""key=0000000000000000000000000000000000000000"
    "credential-url|https:""//user:password@example.invalid/repository"
    "unknown-url|https:""//source.example-corp.invalid/repository"
  )

  mkdir -p "$fixture/scripts"
  cp "$ROOT/scripts/verify-public-release.sh" "$fixture/scripts/verify-public-release.sh"
  chmod +x "$fixture/scripts/verify-public-release.sh"

  for case_entry in "${cases[@]}"; do
    case_name=${case_entry%%|*}
    case_value=${case_entry#*|}
    leaked_file="$fixture/leaked-$case_name.txt"
    printf '%s\n' "$case_value" > "$leaked_file"
    expect_failure \
      "$tmp_npm_prefix/scanner-$case_name.out" \
      "$tmp_npm_prefix/scanner-$case_name.err" \
      "$fixture/scripts/verify-public-release.sh" --source
    grep -Fq "source: forbidden content in leaked-$case_name.txt" \
      "$tmp_npm_prefix/scanner-$case_name.err"
    rm -f "$leaked_file"
  done

  ln -s "/Users""/example/project" "$fixture/leaked-symlink"
  expect_failure \
    "$tmp_npm_prefix/scanner-symlink.out" \
    "$tmp_npm_prefix/scanner-symlink.err" \
    "$fixture/scripts/verify-public-release.sh" --source
  grep -Fq 'source: forbidden content in leaked-symlink' \
    "$tmp_npm_prefix/scanner-symlink.err"
  rm -f "$fixture/leaked-symlink"

  git -C "$fixture" init --initial-branch=main >/dev/null
  git -C "$fixture" config user.name test
  git -C "$fixture" config user.email test@example.invalid
  printf '%s\n' "yupa""o" > "$fixture/history-only.txt"
  git -C "$fixture" add --all
  git -C "$fixture" commit -m "add private fixture" >/dev/null
  rm -f "$fixture/history-only.txt"
  git -C "$fixture" add --all
  git -C "$fixture" commit -m "remove private fixture" >/dev/null
  expect_failure \
    "$tmp_npm_prefix/scanner-history.out" \
    "$tmp_npm_prefix/scanner-history.err" \
    "$fixture/scripts/verify-public-release.sh" --history
  grep -Fq 'Git history contains private, user-specific, or secret-like data' \
    "$tmp_npm_prefix/scanner-history.err"

  local url_fixture="$tmp_npm_prefix/public-url-history-fixture"
  mkdir -p "$url_fixture/scripts"
  cp "$ROOT/scripts/verify-public-release.sh" "$url_fixture/scripts/verify-public-release.sh"
  chmod +x "$url_fixture/scripts/verify-public-release.sh"
  git -C "$url_fixture" init --initial-branch=main >/dev/null
  git -C "$url_fixture" config user.name test
  git -C "$url_fixture" config user.email test@example.invalid
  printf '%s\n' "https:""//gitlab.acme.example/repository" > "$url_fixture/history-url.txt"
  git -C "$url_fixture" add --all
  git -C "$url_fixture" commit -m "add private URL fixture" >/dev/null
  rm -f "$url_fixture/history-url.txt"
  git -C "$url_fixture" add --all
  git -C "$url_fixture" commit -m "remove private URL fixture" >/dev/null
  expect_failure \
    "$tmp_npm_prefix/scanner-url-history.out" \
    "$tmp_npm_prefix/scanner-url-history.err" \
    "$url_fixture/scripts/verify-public-release.sh" --history
  grep -Fq 'Git history contains private, user-specific, or secret-like data' \
    "$tmp_npm_prefix/scanner-url-history.err"

  local binary_fixture="$tmp_npm_prefix/public-binary-history-fixture"
  local binary_blob
  mkdir -p "$binary_fixture/scripts"
  cp "$ROOT/scripts/verify-public-release.sh" "$binary_fixture/scripts/verify-public-release.sh"
  chmod +x "$binary_fixture/scripts/verify-public-release.sh"
  git -C "$binary_fixture" init --initial-branch=main >/dev/null
  git -C "$binary_fixture" config user.name test
  git -C "$binary_fixture" config user.email test@example.invalid
  git -C "$binary_fixture" add --all
  git -C "$binary_fixture" commit -m "initial" >/dev/null
  printf '\0%s\0' "github_""pat_000000000000000000000000000000000000" \
    > "$binary_fixture/deleted-secret.bin"
  git -C "$binary_fixture" add --all
  git -C "$binary_fixture" commit -m "add binary" >/dev/null
  rm -f "$binary_fixture/deleted-secret.bin"
  git -C "$binary_fixture" add --all
  git -C "$binary_fixture" commit -m "remove binary" >/dev/null
  binary_blob=$(git -C "$binary_fixture" rev-list --objects --all \
    | awk '$2 == "deleted-secret.bin" { print $1; exit }')
  [[ -n "$binary_blob" ]] || fail "binary history fixture blob is not reachable"
  git -C "$binary_fixture" cat-file blob "$binary_blob" \
    | LC_ALL=C grep -aEq 'github[_]pat_[A-Za-z0-9_]{20,}' \
    || fail "binary history fixture does not contain the expected token"
  expect_failure \
    "$tmp_npm_prefix/scanner-binary-history.out" \
    "$tmp_npm_prefix/scanner-binary-history.err" \
    "$binary_fixture/scripts/verify-public-release.sh" --history
  grep -Fq 'Git history contains private, user-specific, or secret-like data' \
    "$tmp_npm_prefix/scanner-binary-history.err"

  local tag_fixture="$tmp_npm_prefix/public-tag-history-fixture"
  mkdir -p "$tag_fixture/scripts"
  cp "$ROOT/scripts/verify-public-release.sh" "$tag_fixture/scripts/verify-public-release.sh"
  chmod +x "$tag_fixture/scripts/verify-public-release.sh"
  git -C "$tag_fixture" init --initial-branch=main >/dev/null
  git -C "$tag_fixture" config user.name test
  git -C "$tag_fixture" config user.email test@example.invalid
  git -C "$tag_fixture" add --all
  git -C "$tag_fixture" commit -m "initial" >/dev/null
  git -C "$tag_fixture" tag -a v0.0.0 -m \
    "npm_""000000000000000000000000000000000000"
  expect_failure \
    "$tmp_npm_prefix/scanner-tag-history.out" \
    "$tmp_npm_prefix/scanner-tag-history.err" \
    "$tag_fixture/scripts/verify-public-release.sh" --history
  grep -Fq 'Git history contains private, user-specific, or secret-like data' \
    "$tmp_npm_prefix/scanner-tag-history.err"
}

verify_publish_ref_gate() {
  local fixture="$tmp_npm_prefix/publish-ref-fixture"
  local main_sha unreviewed_sha
  mkdir -p "$fixture/scripts"
  cp "$ROOT/package.json" "$fixture/package.json"
  cp "$ROOT/scripts/verify-publish-ref.sh" "$fixture/scripts/verify-publish-ref.sh"
  chmod +x "$fixture/scripts/verify-publish-ref.sh"
  test -x "$ROOT/scripts/verify-publish-ref.sh"
  require_file_contains "$ROOT/.github/workflows/publish.yml" \
    'scripts/verify-publish-ref.sh'
  require_file_contains "$ROOT/.github/workflows/publish.yml" \
    'main:refs/remotes/origin/main'
  git -C "$fixture" init --initial-branch=main >/dev/null
  git -C "$fixture" config user.name test
  git -C "$fixture" config user.email test@example.invalid
  git -C "$fixture" add --all
  git -C "$fixture" commit -m "reviewed main" >/dev/null
  main_sha=$(git -C "$fixture" rev-parse HEAD)

  env GITHUB_REF_NAME="v$PACKAGE_VERSION" GITHUB_SHA="$main_sha" \
    RWS_PUBLISH_MAIN_REF=main "$fixture/scripts/verify-publish-ref.sh" \
    > "$tmp_npm_prefix/publish-main.out"

  git -C "$fixture" switch -c unreviewed >/dev/null
  printf 'unreviewed\n' > "$fixture/unreviewed.txt"
  git -C "$fixture" add --all
  git -C "$fixture" commit -m "unreviewed" >/dev/null
  unreviewed_sha=$(git -C "$fixture" rev-parse HEAD)
  expect_failure \
    "$tmp_npm_prefix/publish-unreviewed.out" \
    "$tmp_npm_prefix/publish-unreviewed.err" \
    env GITHUB_REF_NAME="v$PACKAGE_VERSION" GITHUB_SHA="$unreviewed_sha" \
      RWS_PUBLISH_MAIN_REF=main "$fixture/scripts/verify-publish-ref.sh"
  grep -Fq 'is not reachable from main' "$tmp_npm_prefix/publish-unreviewed.err"

  expect_failure \
    "$tmp_npm_prefix/publish-tag.out" \
    "$tmp_npm_prefix/publish-tag.err" \
    env GITHUB_REF_NAME=v9.9.9 GITHUB_SHA="$main_sha" \
      RWS_PUBLISH_MAIN_REF=main "$fixture/scripts/verify-publish-ref.sh"
  grep -Fq "does not match v$PACKAGE_VERSION" "$tmp_npm_prefix/publish-tag.err"
}

verify_quality_gate_split() {
  require_file_contains "$ROOT/docs/USER_STORIES.md" '^# User Stories$'
  require_file_contains "$ROOT/docs/USER_STORIES.md" 'Open User-Scenario Gaps'
  require_file_contains "$ROOT/docs/USER_STORIES.md" 'US-027'
  require_file_contains "$ROOT/docs/USER_STORIES.md" 'US-034'
  require_file_contains "$ROOT/docs/USER_STORIES.md" 'US-035'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" '^# Quality Gates$'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'QG-001'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'User story coverage and execution correctness'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'npm test'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'npm audit --omit=dev --audit-level=moderate'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'npm pack --dry-run'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'tests/e2e/podman-e2e.sh'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'QG-008'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'Bilingual documentation coverage'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'QG-009'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'Upgrade compatibility with existing config'
  require_file_contains "$ROOT/docs/QUALITY_GATES.zh-CN.md" 'QG-008'
  require_file_contains "$ROOT/docs/QUALITY_GATES.zh-CN.md" '中英文文档覆盖'
  require_file_contains "$ROOT/docs/QUALITY_GATES.zh-CN.md" 'QG-009'
  require_file_contains "$ROOT/docs/QUALITY_GATES.zh-CN.md" '已有配置升级兼容'
  require_file_contains "$ROOT/docs/USER_STORIES.md" '\| US-031 \| Verified \|'
  require_file_contains "$ROOT/docs/USER_STORIES.zh-CN.md" '\| US-031 \| Verified \|'
  require_file_contains "$ROOT/docs/QUALITY_GATES.md" 'GitHub Actions'
  require_file_contains "$ROOT/docs/QUALITY_GATES.zh-CN.md" 'GitHub Actions'
  if grep -Eq -- 'As a maintainer|^## Gate Rules$|^## Required Gate By Change Type$|^## Reporting Format$|npm audit --omit=dev|npm pack --dry-run' "$ROOT/docs/USER_STORIES.md"; then
    fail "USER_STORIES.md contains quality-gate-only content"
  fi
}

bash -n "$ROOT/bin/rws"
help_tmp=$(mktemp)
"$ROOT/bin/rws" --help >"$help_tmp"
"$ROOT/bin/rws" --version >/dev/null
verify_help_command_surface "$help_tmp"
"$ROOT/bin/rws" help commands >"$help_tmp"
verify_help_commands_surface "$help_tmp"
"$ROOT/bin/rws" help scenarios >"$help_tmp"
require_file_contains "$help_tmp" 'Start a recoverable coding agent in a picked directory'
require_file_contains "$help_tmp" 'rws new coding --pick-cwd --agent codex'
require_file_contains "$help_tmp" "rws new coding-safe --cwd '~/repo' --agent codex --no-full-access"
require_file_contains "$help_tmp" 'Recover coding work after reboot or lost shpool state'
if grep -Eq -- "--profile|--name|profiles" "$help_tmp"; then
  fail "legacy profile/name surface appeared in help"
fi
rm -f "$help_tmp"

tmp_home=$(mktemp -d)
tmp_home_key=
tmp_home_legacy=
tmp_home_verify=
tmp_home_diag=
tmp_home_deps=
tmp_config=
tmp_npm_prefix=$(mktemp -d)
tmp_pack_json="$tmp_npm_prefix/pack.json"
PACKAGE_VERSION=$(node -e "console.log(require(process.argv[1]).version)" "$ROOT/package.json")
trap 'rm -rf "$tmp_home" "${tmp_home_key-}" "${tmp_home_legacy-}" "${tmp_home_verify-}" "${tmp_home_diag-}" "${tmp_home_deps-}" "${tmp_config-}" "${tmp_npm_prefix-}" "${help_tmp-}"' EXIT
verify_release_metadata
verify_pack_contents "$tmp_pack_json"
verify_bilingual_docs
verify_readme_command_table
verify_usage_docs
verify_security_claims
verify_verification_policy
verify_quality_gate_split
"$ROOT/scripts/verify-public-release.sh" --source
verify_public_scanner_rejects_private_data
verify_public_export_rejects_symlinks
verify_public_export_gate
verify_publish_ref_gate
verify_upgrade_existing_config_gate
npm install -g --prefix "$tmp_npm_prefix" "$ROOT" >"$tmp_npm_prefix/install.out" 2>"$tmp_npm_prefix/install.err"
PATH="$tmp_npm_prefix/bin:$PATH" rws --version | grep -qx "rws $PACKAGE_VERSION"
test -x "$tmp_npm_prefix/bin/rws"
test ! -e "$tmp_npm_prefix/bin/rsw"

HOME="$tmp_home" "$ROOT/bin/rws" setup --help | grep -q "Usage:"
HOME="$tmp_home" "$ROOT/bin/rws" setup --help | grep -q -- "--no-install-key"
HOME="$tmp_home" "$ROOT/bin/rws" setup --help | grep -q -- "--force-key"
HOME="$tmp_home" "$ROOT/bin/rws" key --help | grep -q "Usage:"
HOME="$tmp_home" "$ROOT/bin/rws" device --help | grep -q "Usage:"
HOME="$tmp_home" "$ROOT/bin/rws" device update --help | grep -q "Parameters and options:"
HOME="$tmp_home" "$ROOT/bin/rws" session --help | grep -q "Usage:"
HOME="$tmp_home" "$ROOT/bin/rws" new --help | grep -q "Usage:"
HOME="$tmp_home" "$ROOT/bin/rws" new --help | grep -q -- "--no-full-access"
HOME="$tmp_home" "$ROOT/bin/rws" run --help | grep -q "exit code"
HOME="$tmp_home" "$ROOT/bin/rws" help setup | grep -q "remote-install"

for topic in setup key device session new attach force background check doctor status shell sessions run detach kill remove init; do
  HOME="$tmp_home" "$ROOT/bin/rws" help "$topic" >"$help_tmp"
  require_error_help "$help_tmp" '^  rws '
done

expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --unknown
require_error_help "$tmp_home/stderr" 'rws \[--config-dir DIR\]'
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" new coding --agent unknown
require_error_help "$tmp_home/stderr" 'rws new SESSION'
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" run
require_error_help "$tmp_home/stderr" 'rws run -- COMMAND'
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" attach one two
require_error_help "$tmp_home/stderr" 'rws attach \[SESSION\]'
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" check extra
require_error_help "$tmp_home/stderr" 'rws check'
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" remove one two
require_error_help "$tmp_home/stderr" 'rws remove \[DEVICE\]'

expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" c
grep -q "Run: rws setup" "$tmp_home/stderr"

tmp_home_deps=$(mktemp -d)
mkdir -p "$tmp_home_deps/bin" "$tmp_home_deps/.config/rws/devices"
for dep in bash dirname pwd sed cat mktemp awk grep chmod mkdir rm; do
  ln -s "$(command -v "$dep")" "$tmp_home_deps/bin/$dep"
done
printf 'device=default\n' > "$tmp_home_deps/.config/rws/default.conf"
printf 'host=example.invalid\ncwd=~/work/project\ndefault_session=test\n' > "$tmp_home_deps/.config/rws/devices/default.conf"
expect_exit_2 "$tmp_home_deps/stdout" "$tmp_home_deps/stderr" env PATH="$tmp_home_deps/bin" HOME="$tmp_home_deps" "$ROOT/bin/rws" c
grep -q "missing local dependency: ssh (run: rws setup)" "$tmp_home_deps/stderr"
ln -s "$(command -v ssh)" "$tmp_home_deps/bin/ssh"
expect_exit_2 "$tmp_home_deps/stdout" "$tmp_home_deps/stderr" env PATH="$tmp_home_deps/bin" HOME="$tmp_home_deps" "$ROOT/bin/rws" key create --identity-file '~/.ssh/missing_key'
grep -q "missing local dependency: ssh-keygen (run: rws setup)" "$tmp_home_deps/stderr"
require_error_help "$tmp_home_deps/stderr" 'rws key create'

HOME="$tmp_home" "$ROOT/bin/rws" setup \
  --host example.invalid \
  --cwd '~/work/project' \
  --session project \
  --key-mode skip \
  --no-install-key \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes \
  >"$tmp_home/stdout" 2>"$tmp_home/stderr"
grep -q "Setup complete" "$tmp_home/stdout"
grep -qx "device=default" "$tmp_home/.config/rws/default.conf"
if grep -q "^default_session=" "$tmp_home/.config/rws/devices/default.conf"; then
  fail "setup without initial session wrote default_session"
fi
if grep -q "^cwd=" "$tmp_home/.config/rws/devices/default.conf"; then
  fail "setup wrote device cwd"
fi
grep -qx "shpool_version=0.9.8" "$tmp_home/.config/rws/devices/default.conf"
grep -qx "prompt_mode=skip" "$tmp_home/.config/rws/devices/default.conf"
HOME="$tmp_home" "$ROOT/bin/rws" devices | grep -qx default
HOME="$tmp_home" "$ROOT/bin/rws" device get default | grep -qx "host=example.invalid"

tmp_home_progress=$(mktemp -d)
mkdir -p "$tmp_home_progress/bin"
cat > "$tmp_home_progress/bin/ssh" <<'SH'
#!/usr/bin/env bash
sleep "${RWS_FAKE_SSH_SLEEP:-0}"
printf 'remote cwd: /fake/work\n'
printf 'remote shpool: /fake/shpool\n'
SH
chmod +x "$tmp_home_progress/bin/ssh"
PATH="$tmp_home_progress/bin:$PATH" \
HOME="$tmp_home_progress" \
RWS_SETUP_PROGRESS_INTERVAL=1 \
RWS_FAKE_SSH_SLEEP=2 \
"$ROOT/bin/rws" setup \
  --host fake.example \
  --cwd '~/work/project' \
  --session progress \
  --key-mode skip \
  --no-install-key \
  --remote-install auto \
  --prompt-mode skip \
  --no-create-session \
  --no-verify \
  --yes \
  >"$tmp_home_progress/stdout" 2>"$tmp_home_progress/stderr"
grep -Fq "[8/12] Preparing remote dependencies" "$tmp_home_progress/stdout"
grep -q "rws: still preparing remote dependencies on fake.example" "$tmp_home_progress/stderr"

expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --profile default c
grep -q "unknown option: --profile" "$tmp_home/stderr"

expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --name other c
grep -q "unknown option: --name" "$tmp_home/stderr"

expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" profiles
grep -q "unknown command: profiles" "$tmp_home/stderr"

tmp_home_legacy=$(mktemp -d)
mkdir -p "$tmp_home_legacy/.config/rws/devices"
printf 'profile=default\n' > "$tmp_home_legacy/.config/rws/default.conf"
printf 'host=example.invalid\ncwd=~/work\ndefault_session=work\n' > "$tmp_home_legacy/.config/rws/devices/default.conf"
expect_exit_2 "$tmp_home_legacy/stdout" "$tmp_home_legacy/stderr" env HOME="$tmp_home_legacy" "$ROOT/bin/rws" c
grep -q "unknown config key.*profile" "$tmp_home_legacy/stderr"

printf 'device=default\n' > "$tmp_home_legacy/.config/rws/default.conf"
printf 'host=example.invalid\ncwd=~/work\nname=work\n' > "$tmp_home_legacy/.config/rws/devices/default.conf"
expect_exit_2 "$tmp_home_legacy/stdout" "$tmp_home_legacy/stderr" env HOME="$tmp_home_legacy" "$ROOT/bin/rws" c
grep -q "unknown config key.*name" "$tmp_home_legacy/stderr"

tmp_config=$(mktemp -d)
HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" init \
  --device custom \
  --host example.invalid \
  --cwd '~/work/custom' \
  --session custom \
  --key-mode skip \
  >"$tmp_home/stdout" 2>"$tmp_home/stderr"
grep -qx "device=custom" "$tmp_config/default.conf"
grep -qx "default_session=custom" "$tmp_config/devices/custom.conf"
grep -qx "prompt_mode=compact" "$tmp_config/devices/custom.conf" && fail "unexpected compact prompt mode before prompt init test"
test ! -e "$tmp_home/.config/rws/devices/custom.conf"
HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" devices | grep -qx custom
HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" device get custom | grep -qx "cwd=~/work/custom"
HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" device update custom \
  --cwd '~/work/updated' \
  --session updated \
  --prompt-mode compact \
  --prompt-label updated \
  --ssh-option ServerAliveInterval=30 \
  --ssh-option ServerAliveCountMax=2 \
  --default \
  >"$tmp_home/stdout" 2>"$tmp_home/stderr"
grep -q "updated custom" "$tmp_home/stdout"
grep -qx "device=custom" "$tmp_config/default.conf"
grep -qx "cwd=~/work/updated" "$tmp_config/devices/custom.conf"
grep -qx "default_session=updated" "$tmp_config/devices/custom.conf"
grep -qx "prompt_mode=compact" "$tmp_config/devices/custom.conf"
grep -qx "prompt_label=updated" "$tmp_config/devices/custom.conf"
grep -qx "ssh_option=ServerAliveInterval=30" "$tmp_config/devices/custom.conf"
grep -qx "ssh_option=ServerAliveCountMax=2" "$tmp_config/devices/custom.conf"
HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" device update custom --prompt-mode skip --clear-ssh-options >"$tmp_home/stdout" 2>"$tmp_home/stderr"
grep -qx "prompt_mode=skip" "$tmp_config/devices/custom.conf"
if grep -q "^prompt_label=" "$tmp_config/devices/custom.conf"; then
  fail "device update prompt-mode skip kept prompt_label"
fi
if grep -q "^ssh_option=" "$tmp_config/devices/custom.conf"; then
  fail "device update --clear-ssh-options kept ssh_option"
fi
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" device update custom --cwd $'bad\ecwd'
grep -q "invalid cwd" "$tmp_home/stderr"
require_error_help "$tmp_home/stderr" 'rws device update DEVICE'
HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" device create created \
  --host example.invalid \
  --cwd '~/work/created' \
  --session created \
  --key-mode skip \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes \
  >"$tmp_home/stdout" 2>"$tmp_home/stderr"
grep -q "Setup complete" "$tmp_home/stdout"
grep -qx "device=created" "$tmp_config/default.conf"
if grep -q "^cwd=" "$tmp_config/devices/created.conf"; then
  fail "device create through setup wrote device cwd"
fi
HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" device update custom --default >"$tmp_home/stdout" 2>"$tmp_home/stderr"
grep -qx "device=custom" "$tmp_config/default.conf"
before_config=$(cat "$tmp_config/devices/custom.conf")
if HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" \
  --host 127.0.0.1 --cwd '~/override' --session override --ssh-option Port=1 --ssh-option ConnectTimeout=1 \
  c >"$tmp_home/stdout" 2>"$tmp_home/stderr"; then
  fail "expected one-off override check to fail without rewriting config"
fi
after_config=$(cat "$tmp_config/devices/custom.conf")
[[ "$before_config" == "$after_config" ]] || fail "one-off overrides rewrote device config"

expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" init --device ../bad --host example.invalid --key-mode skip
grep -q "invalid device name" "$tmp_home/stderr"
require_error_help "$tmp_home/stderr" 'rws init --host HOST'
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" init --device bad --host example.invalid --session bad/name --key-mode skip
grep -q "invalid session name" "$tmp_home/stderr"
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" --device ../bad c
grep -q "invalid device name" "$tmp_home/stderr"
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" remove bad/name
grep -q "invalid device name" "$tmp_home/stderr"
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" new bad/name
grep -q "invalid session name" "$tmp_home/stderr"
require_error_help "$tmp_home/stderr" 'rws new SESSION'
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" new -pick-cwd
grep -q "new requires exactly one session name" "$tmp_home/stderr"
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" init --device bad --host example.invalid --session ok --key-mode skip --prompt-mode bad
grep -q "invalid prompt mode" "$tmp_home/stderr"
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" init --device bad --host example.invalid --session ok --key-mode skip --prompt-mode compact --prompt-label bad/name
grep -q "invalid prompt label" "$tmp_home/stderr"
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" init --device bad --host example.invalid --cwd $'bad\ecwd' --session ok --key-mode skip
grep -q "invalid cwd" "$tmp_home/stderr"
HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" init \
  --device prompt \
  --host example.invalid \
  --cwd '~/work/prompt' \
  --session prompt \
  --key-mode skip \
  --prompt-mode compact \
  --prompt-label devbox \
  >"$tmp_home/stdout" 2>"$tmp_home/stderr"
grep -qx "prompt_mode=compact" "$tmp_config/devices/prompt.conf"
grep -qx "prompt_label=devbox" "$tmp_config/devices/prompt.conf"
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" bg bad/name
grep -q "invalid session name" "$tmp_home/stderr"
require_error_help "$tmp_home/stderr" 'rws background \[SESSION\]'
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" d bad/name
grep -q "invalid session name" "$tmp_home/stderr"
require_error_help "$tmp_home/stderr" 'rws detach \[SESSION\.\.\.\]'
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" --config-dir "$tmp_config" k bad/name
grep -q "invalid session name" "$tmp_home/stderr"
require_error_help "$tmp_home/stderr" 'rws kill \[SESSION\.\.\.\]'

HOME="$tmp_home" "$ROOT/bin/rws" setup \
  --host example.invalid \
  --cwd '~/work/project' \
  --session project \
  --key-mode skip \
  --no-install-key \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes \
  >"$tmp_home/stdout" 2>"$tmp_home/stderr"
grep -q "Setup complete" "$tmp_home/stdout"

HOME="$tmp_home" "$ROOT/bin/rws" setup \
  --device lab \
  --host example.invalid \
  --cwd '~/work/lab' \
  --session lab \
  --key-mode skip \
  --no-install-key \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes \
  >"$tmp_home/stdout" 2>"$tmp_home/stderr"
grep -qx "device=lab" "$tmp_home/.config/rws/default.conf"
HOME="$tmp_home" "$ROOT/bin/rws" setup \
  --device default \
  --host example.invalid \
  --cwd '~/work/project' \
  --session project \
  --key-mode skip \
  --no-install-key \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes \
  >"$tmp_home/stdout" 2>"$tmp_home/stderr"
HOME="$tmp_home" "$ROOT/bin/rws" remove | grep -q "removed default; default device is now lab"
grep -qx "device=lab" "$tmp_home/.config/rws/default.conf"
HOME="$tmp_home" "$ROOT/bin/rws" devices | grep -qx lab
if HOME="$tmp_home" "$ROOT/bin/rws" devices | grep -qx default; then
  fail "expected removed default device to be absent"
fi
HOME="$tmp_home" "$ROOT/bin/rws" --device lab remove | grep -q "removed lab; no devices remain"
test ! -e "$tmp_home/.config/rws/default.conf"
expect_exit_2 "$tmp_home/stdout" "$tmp_home/stderr" env HOME="$tmp_home" "$ROOT/bin/rws" c
grep -q "Run: rws setup" "$tmp_home/stderr"

tmp_home_diag=$(mktemp -d)
mkdir -p "$tmp_home_diag/bin"
cat > "$tmp_home_diag/bin/ssh" <<'SH'
#!/usr/bin/env bash
case "${RWS_FAKE_SSH_MODE:-ok}" in
  dns)
    echo "ssh: Could not resolve hostname fake.example: nodename nor servname provided, or not known" >&2
    exit 255
    ;;
  refused)
    echo "ssh: connect to host fake.example port 22: Connection refused" >&2
    exit 255
    ;;
  timeout)
    echo "ssh: connect to host fake.example port 22: Operation timed out" >&2
    exit 255
    ;;
  auth)
    echo "fake.example: Permission denied (publickey,password)." >&2
    exit 255
    ;;
  hostkey)
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@" >&2
    echo "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!" >&2
    echo "Host key verification failed." >&2
    exit 255
    ;;
  reset)
    echo "kex_exchange_identification: read: Connection reset by peer" >&2
    exit 255
    ;;
  remote-cwd)
    echo "rws: remote cwd missing: /missing" >&2
    exit 2
    ;;
  shpool-missing)
    echo "rws: remote dependency missing: shpool (shpool). Run: rws setup" >&2
    exit 2
    ;;
  shpool-version)
    echo "rws: expected shpool 0.9.8 but found: shpool 9.9.9" >&2
    exit 2
    ;;
  *)
    printf 'host=fake\nuser=fake\ncwd=/work\nshpool=shpool 0.9.8\nsessions={"sessions":[]}\n'
    ;;
esac
SH
chmod +x "$tmp_home_diag/bin/ssh"
HOME="$tmp_home_diag" "$ROOT/bin/rws" init \
  --device diag \
  --host fake.example \
  --cwd /work \
  --session diag \
  --key-mode skip \
  --shpool-version 0.9.8 \
  >"$tmp_home_diag/init.out" 2>"$tmp_home_diag/init.err"
for spec in \
  dns:dns_failed \
  refused:connection_refused \
  timeout:connection_timeout \
  auth:authentication_failed \
  hostkey:host_key_changed \
  reset:connection_reset
do
  mode=${spec%%:*}
  expected=${spec#*:}
  set +e
  PATH="$tmp_home_diag/bin:$PATH" HOME="$tmp_home_diag" RWS_FAKE_SSH_MODE="$mode" "$ROOT/bin/rws" c >"$tmp_home_diag/$mode.out" 2>"$tmp_home_diag/$mode.err"
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || fail "expected diagnostic mode to fail: $mode"
  grep -q "ssh_error=$expected" "$tmp_home_diag/$mode.err"
done
set +e
PATH="$tmp_home_diag/bin:$PATH" HOME="$tmp_home_diag" RWS_FAKE_SSH_MODE=remote-cwd "$ROOT/bin/rws" c >"$tmp_home_diag/cwd.out" 2>"$tmp_home_diag/cwd.err"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "expected remote cwd diagnostic to fail"
grep -q "remote cwd missing" "$tmp_home_diag/cwd.err"
if grep -q "ssh_error=unknown" "$tmp_home_diag/cwd.err"; then
  fail "remote cwd diagnostic was mislabeled as unknown SSH failure"
fi
set +e
PATH="$tmp_home_diag/bin:$PATH" HOME="$tmp_home_diag" RWS_FAKE_SSH_MODE=shpool-missing "$ROOT/bin/rws" c >"$tmp_home_diag/shpool-missing.out" 2>"$tmp_home_diag/shpool-missing.err"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "expected missing remote shpool diagnostic to fail"
grep -q "remote dependency missing: shpool" "$tmp_home_diag/shpool-missing.err"
if grep -q "ssh_error=unknown" "$tmp_home_diag/shpool-missing.err"; then
  fail "remote shpool diagnostic was mislabeled as unknown SSH failure"
fi
set +e
PATH="$tmp_home_diag/bin:$PATH" HOME="$tmp_home_diag" RWS_FAKE_SSH_MODE=shpool-version "$ROOT/bin/rws" doctor >"$tmp_home_diag/shpool.out" 2>"$tmp_home_diag/shpool.err"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "expected shpool diagnostic to exit 2"
grep -q "expected shpool 0.9.8" "$tmp_home_diag/shpool.err"
grep -q "remote diagnostic failed" "$tmp_home_diag/shpool.err"

tmp_home_key=$(mktemp -d)
expect_exit_2 "$tmp_home_key/stdout" "$tmp_home_key/stderr" env HOME="$tmp_home_key" "$ROOT/bin/rws" setup \
  --host example.invalid \
  --create-session \
  --key-mode skip \
  --no-install-key \
  --remote-install skip \
  --no-verify \
  --yes
grep -q -- "setup --create-session requires --cwd in non-interactive mode" "$tmp_home_key/stderr"
expect_exit_2 "$tmp_home_key/stdout" "$tmp_home_key/stderr" env HOME="$tmp_home_key" "$ROOT/bin/rws" setup \
  --host example.invalid \
  --cwd '~/work/project' \
  --key-mode existing \
  --no-install-key \
  --remote-install skip \
  --no-verify \
  --yes
grep -q -- "--key-mode existing requires --identity-file" "$tmp_home_key/stderr"
expect_exit_2 "$tmp_home_key/stdout" "$tmp_home_key/stderr" env HOME="$tmp_home_key" "$ROOT/bin/rws" init \
  --host example.invalid \
  --key-mode existing
grep -q -- "--key-mode existing requires --identity-file" "$tmp_home_key/stderr"
HOME="$tmp_home_key" "$ROOT/bin/rws" key create --identity-file '~/.ssh/manual_ed25519' >"$tmp_home_key/key-create.out"
grep -q "created identity file" "$tmp_home_key/key-create.out"
HOME="$tmp_home_key" "$ROOT/bin/rws" key get --identity-file '~/.ssh/manual_ed25519' >"$tmp_home_key/key-get.out"
grep -qx "identity_file=~/.ssh/manual_ed25519" "$tmp_home_key/key-get.out"
grep -qx "private_key=present" "$tmp_home_key/key-get.out"
grep -qx "public_key=present" "$tmp_home_key/key-get.out"
manual_key_before=$(cat "$tmp_home_key/.ssh/manual_ed25519")
expect_exit_2 "$tmp_home_key/stdout" "$tmp_home_key/stderr" env HOME="$tmp_home_key" "$ROOT/bin/rws" key update --identity-file '~/.ssh/manual_ed25519'
grep -q "pass --force" "$tmp_home_key/stderr"
HOME="$tmp_home_key" "$ROOT/bin/rws" key update --identity-file '~/.ssh/manual_ed25519' --force >"$tmp_home_key/key-update.out"
manual_key_after=$(cat "$tmp_home_key/.ssh/manual_ed25519")
[[ "$manual_key_before" != "$manual_key_after" ]] || fail "key update --force did not regenerate the identity file"
expect_exit_2 "$tmp_home_key/stdout" "$tmp_home_key/stderr" env HOME="$tmp_home_key" "$ROOT/bin/rws" key remove --identity-file '~/.ssh/manual_ed25519'
grep -q "pass --force" "$tmp_home_key/stderr"
HOME="$tmp_home_key" "$ROOT/bin/rws" key remove --identity-file '~/.ssh/manual_ed25519' --force >"$tmp_home_key/key-remove.out"
test ! -e "$tmp_home_key/.ssh/manual_ed25519"
tmp_home_verify=$(mktemp -d)
mkdir -p "$tmp_home_verify/bin"
cat > "$tmp_home_verify/bin/ssh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cmd=
for arg in "$@"; do
  cmd=$arg
done
printf '%s\n' "$cmd" >> "$HOME/ssh.log"

case "$cmd" in
  "echo rws-connect-ok")
    printf 'rws-connect-ok\n'
    ;;
  *"list --json"*)
    printf '{"sessions":[{"name":"verify","status":"Disconnected","started_at_unix_ms":0,"last_connected_at_unix_ms":0,"last_disconnected_at_unix_ms":0},{"name":"mkdirsession","status":"Disconnected","started_at_unix_ms":0,"last_connected_at_unix_ms":0,"last_disconnected_at_unix_ms":0}]}\n'
    ;;
  *"echo rws-echo-ok"*)
    printf 'rws-echo-ok\n'
    ;;
  *)
    ;;
esac
SH
chmod +x "$tmp_home_verify/bin/ssh"
PATH="$tmp_home_verify/bin:$PATH" HOME="$tmp_home_verify" env -u TERM "$ROOT/bin/rws" setup \
  --host fake.example \
  --cwd '~/work/project' \
  --session verify \
  --key-mode skip \
  --no-install-key \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes \
  >"$tmp_home_verify/no-verify.out" 2>"$tmp_home_verify/no-verify.err"
PATH="$tmp_home_verify/bin:$PATH" HOME="$tmp_home_verify" env -u TERM "$ROOT/bin/rws" setup \
  --host fake.example \
  --cwd '~/work/project' \
  --session verify \
  --key-mode skip \
  --no-install-key \
  --remote-install skip \
  --no-create-session \
  --yes \
  >"$tmp_home_verify/verify.out" 2>"$tmp_home_verify/verify.err"
grep -q "verification ok: connect, shpool" "$tmp_home_verify/verify.out"
PATH="$tmp_home_verify/bin:$PATH" HOME="$tmp_home_verify" env -u TERM "$ROOT/bin/rws" setup \
  --host fake.example \
  --cwd '~/work/project' \
  --session verify \
  --key-mode skip \
  --no-install-key \
  --remote-install skip \
  --prompt-mode compact \
  --prompt-label devbox \
  --yes \
  >"$tmp_home_verify/compact-verify.out" 2>"$tmp_home_verify/compact-verify.err"
grep -q "verification ok: connect, shpool" "$tmp_home_verify/compact-verify.out"
grep -q "created session: verify" "$tmp_home_verify/compact-verify.out"
grep -q "connect with: rws attach verify" "$tmp_home_verify/compact-verify.out"
grep -Fq "TERM='xterm-256color'" "$tmp_home_verify/ssh.log"
grep -Fq 'RWS_DEVICE_LABEL=devbox sh -lc' "$tmp_home_verify/ssh.log"
grep -Fq 'exec "${SHELL:-/bin/sh}" -i' "$tmp_home_verify/ssh.log"
: > "$tmp_home_verify/ssh.log"
PATH="$tmp_home_verify/bin:$PATH" HOME="$tmp_home_verify" env -u TERM "$ROOT/bin/rws" session create mkdirsession --cwd '~/work/new/session' >"$tmp_home_verify/session-create.out"
grep -qx "created session: mkdirsession" "$tmp_home_verify/session-create.out"
grep -Fq "TERM='xterm-256color'" "$tmp_home_verify/ssh.log"
grep -Fq 'mkdir -p "$rws_cwd"' "$tmp_home_verify/ssh.log"
grep -Fq 'rws_cwd="$HOME/work/new/session"' "$tmp_home_verify/ssh.log"
HOME="$tmp_home_key" "$ROOT/bin/rws" setup \
  --host example.invalid \
  --cwd '~/work/project' \
  --key-mode create \
  --identity-file '~/.ssh/rws_test_ed25519' \
  --no-install-key \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes \
  >"$tmp_home_key/stdout" 2>"$tmp_home_key/stderr"
HOME="$tmp_home_key" "$ROOT/bin/rws" key list >"$tmp_home_key/key-list.out"
grep -q $'default\t~/.ssh/rws_test_ed25519\tpresent' "$tmp_home_key/key-list.out"
key_before=$(cat "$tmp_home_key/.ssh/rws_test_ed25519")
HOME="$tmp_home_key" "$ROOT/bin/rws" setup \
  --host example.invalid \
  --cwd '~/work/project' \
  --key-mode create \
  --identity-file '~/.ssh/rws_test_ed25519' \
  --no-install-key \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes \
  >"$tmp_home_key/stdout" 2>"$tmp_home_key/stderr"
key_after_reuse=$(cat "$tmp_home_key/.ssh/rws_test_ed25519")
[[ "$key_before" == "$key_after_reuse" ]] || fail "expected setup to reuse an existing identity file without --force-key"
HOME="$tmp_home_key" "$ROOT/bin/rws" setup \
  --host example.invalid \
  --cwd '~/work/project' \
  --key-mode create \
  --identity-file '~/.ssh/rws_test_ed25519' \
  --force-key \
  --no-install-key \
  --remote-install skip \
  --no-create-session \
  --no-verify \
  --yes \
  >"$tmp_home_key/stdout" 2>"$tmp_home_key/stderr"
key_after_force=$(cat "$tmp_home_key/.ssh/rws_test_ed25519")
[[ "$key_before" != "$key_after_force" ]] || fail "expected --force-key to recreate the identity file"
if HOME="$tmp_home_key" "$ROOT/bin/rws" setup \
  --host example.invalid \
  --cwd '~/work/project' \
  --key-mode create \
  --identity-file '~/.ssh/rws_test_ed25519' \
  --install-key \
  --remote-install skip \
  --no-create-session \
  --yes \
  >"$tmp_home_key/stdout" 2>"$tmp_home_key/stderr" </dev/null; then
  printf 'expected non-interactive install-key without bootstrap identity to fail\n' >&2
  exit 1
fi
grep -q "requires an interactive terminal" "$tmp_home_key/stderr"

tmp_home_coding=$(mktemp -d)
tmp_config_coding="$tmp_home_coding/config"
mkdir -p "$tmp_home_coding/bin" "$tmp_config_coding/devices"
printf 'device=fake\n' > "$tmp_config_coding/default.conf"
printf 'host=fake.example\nprompt_mode=skip\n' > "$tmp_config_coding/devices/fake.conf"
cat > "$tmp_home_coding/bin/ssh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cmd=
for arg in "$@"; do
  cmd=$arg
done
printf '%s\n' "$cmd" >> "$HOME/ssh.log"

if [[ "$cmd" == *"list --json"* ]]; then
  if [[ -f "$HOME/fail-next-list" ]]; then
    rm -f "$HOME/fail-next-list"
    printf 'simulated unreachable follow-up list\n' >&2
    exit 255
  fi
  first=1
  printf '{"sessions":['
  for state in "$HOME"/remote-session-*; do
    [[ -e "$state" ]] || continue
    name=${state##*/remote-session-}
    [[ "$first" == "1" ]] || printf ','
    printf '{"name":"%s"}' "$name"
    first=0
  done
  printf ']}\n'
  if [[ -f "$HOME/drop-after-list" ]]; then
    drop_name=$(cat "$HOME/drop-after-list")
    rm -f "$HOME/drop-after-list" "$HOME/remote-session-$drop_name"
  fi
  exit 0
fi

for agent in codex claude kiro-cli; do
  if [[ -f "$HOME/fail-preflight-$agent" && "$cmd" != *" attach"* && "$cmd" == *"command -v $agent"* ]]; then
    printf 'rws: remote dependency missing: coding agent %s (%s). Install it before restoring this session.\n' "$agent" "$agent" >&2
    exit 2
  fi
done

if [[ -f "$HOME/fail-cwd-preflight" && "$cmd" != *" attach"* && "$cmd" == *"remote cwd missing"* ]]; then
  printf 'simulated missing remote cwd\n' >&2
  exit 2
fi

for name in codex-work claude-work kiro-work standard-work quoted-cwd legacy-work initial-fail live-fail unreachable-fail resume-fail access-change reconfig-work mixed-live; do
  if [[ "$cmd" == *" attach"* && "$cmd" == *"'$name'"* && ! -e "$HOME/remote-session-$name" ]]; then
    for agent in codex claude kiro-cli; do
      if [[ -f "$HOME/fail-preflight-$agent" && "$cmd" == *"command -v $agent"* ]]; then
        printf 'rws: remote dependency missing: coding agent %s (%s). Install it before restoring this session.\n' "$agent" "$agent" >&2
        exit 2
      fi
    done
    if [[ -f "$HOME/fail-cwd-preflight" && "$cmd" == *"remote cwd missing"* ]]; then
      printf 'simulated missing remote cwd\n' >&2
      exit 2
    fi
  fi
  if [[ -f "$HOME/fail-attach-live-$name" && "$cmd" == *" attach"* && "$cmd" == *"'$name'"* ]]; then
    rm -f "$HOME/fail-attach-live-$name"
    : > "$HOME/remote-session-$name"
    if [[ "$name" == "unreachable-fail" ]]; then
      : > "$HOME/fail-next-list"
    fi
    printf 'simulated dropped client after session start: %s\n' "$name" >&2
    exit 255
  fi
  if [[ -f "$HOME/fail-attach-$name" && "$cmd" == *" attach"* && "$cmd" == *"'$name'"* ]]; then
    rm -f "$HOME/fail-attach-$name"
    printf 'simulated attach failure: %s\n' "$name" >&2
    exit 23
  fi
  if [[ "$cmd" == *" attach"* && "$cmd" == *"'$name'"* ]]; then
    : > "$HOME/remote-session-$name"
  fi
  if [[ "$cmd" == *" kill"* && "$cmd" == *"'$name'"* ]]; then
    rm -f "$HOME/remote-session-$name"
  fi
done
SH
chmod +x "$tmp_home_coding/bin/ssh"

coding_rws=(env PATH="$tmp_home_coding/bin:$PATH" HOME="$tmp_home_coding" "$ROOT/bin/rws" --config-dir "$tmp_config_coding")

"${coding_rws[@]}" new codex-work --cwd '~/work/codex' --agent codex > "$tmp_home_coding/codex-create.out"
printf 'rws-coding-session-v2\ncodex\n~/work/codex\nfull\n' > "$tmp_home_coding/expected-codex.conf"
cmp "$tmp_home_coding/expected-codex.conf" "$tmp_config_coding/sessions/fake/codex-work.conf"
grep -Fq 'command -v codex' "$tmp_home_coding/ssh.log"
grep -Fq 'codex --dangerously-bypass-approvals-and-sandbox' "$tmp_home_coding/ssh.log"
grep -Fq '"${SHELL:-/bin/sh}" -ic' "$tmp_home_coding/ssh.log"
if grep -Fq 'exec "${SHELL:-/bin/sh}" -ic' "$tmp_home_coding/ssh.log"; then
  fail "coding agent fallback control flow unexpectedly ran inside the user shell"
fi
if grep -Fq 'codexd' "$tmp_home_coding/ssh.log"; then
  fail "Codex launch unexpectedly depended on the non-standard codexd alias"
fi
if grep -Fq 'codex resume --last' "$tmp_home_coding/ssh.log"; then
  fail "new codex coding session unexpectedly used resume"
fi

quoted_cwd='~/work/space $dollar `tick` $(touch /tmp/rws-injected) ; "double"'
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" new quoted-cwd --cwd "$quoted_cwd" --agent codex > "$tmp_home_coding/quoted-cwd.out"
{
  printf 'rws-coding-session-v2\n'
  printf 'codex\n'
  printf '%s\n' "$quoted_cwd"
  printf 'full\n'
} > "$tmp_home_coding/expected-quoted-cwd.conf"
cmp "$tmp_home_coding/expected-quoted-cwd.conf" "$tmp_config_coding/sessions/fake/quoted-cwd.conf"
grep -Fq '\$dollar' "$tmp_home_coding/ssh.log"
grep -Fq '\`tick\`' "$tmp_home_coding/ssh.log"
grep -Fq '\$(touch /tmp/rws-injected)' "$tmp_home_coding/ssh.log"
test ! -e /tmp/rws-injected

: > "$tmp_home_coding/ssh.log"
touch "$tmp_home_coding/fail-preflight-codex" "$tmp_home_coding/fail-cwd-preflight"
"${coding_rws[@]}" new codex-work > "$tmp_home_coding/codex-live.out"
grep -Fq 'codex resume --last --dangerously-bypass-approvals-and-sandbox' "$tmp_home_coding/ssh.log"
rm -f "$tmp_home_coding/fail-preflight-codex" "$tmp_home_coding/fail-cwd-preflight"

printf 'codex-work\n' > "$tmp_home_coding/drop-after-list"
touch "$tmp_home_coding/fail-preflight-codex"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" new codex-work
test ! -e "$tmp_home_coding/remote-session-codex-work"
test -e "$tmp_config_coding/sessions/fake/codex-work.conf"
rm -f "$tmp_home_coding/fail-preflight-codex"
"${coding_rws[@]}" new codex-work > /dev/null

printf 'codex-work\n' > "$tmp_home_coding/drop-after-list"
touch "$tmp_home_coding/fail-cwd-preflight"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" new codex-work
test ! -e "$tmp_home_coding/remote-session-codex-work"
test -e "$tmp_config_coding/sessions/fake/codex-work.conf"
rm -f "$tmp_home_coding/fail-cwd-preflight"
"${coding_rws[@]}" new codex-work > /dev/null

printf 'codex-work\n' > "$tmp_home_coding/drop-after-list"
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" new codex-work > "$tmp_home_coding/codex-race-new.out"
grep -Fq 'codex resume --last --dangerously-bypass-approvals-and-sandbox' "$tmp_home_coding/ssh.log"
test -e "$tmp_home_coding/remote-session-codex-work"

printf 'codex-work\n' > "$tmp_home_coding/drop-after-list"
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" attach codex-work > "$tmp_home_coding/codex-race-attach.out"
grep -Fq 'codex resume --last --dangerously-bypass-approvals-and-sandbox' "$tmp_home_coding/ssh.log"
test -e "$tmp_home_coding/remote-session-codex-work"

rm -f "$tmp_home_coding/remote-session-codex-work"
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" new codex-work > "$tmp_home_coding/codex-restore.out" 2> "$tmp_home_coding/codex-restore.err"
grep -q 'restoring session: codex-work (codex, ~/work/codex, access=full)' "$tmp_home_coding/codex-restore.err"
grep -Fq 'codex resume --last --dangerously-bypass-approvals-and-sandbox' "$tmp_home_coding/ssh.log"
if grep -Fq 'codexd' "$tmp_home_coding/ssh.log"; then
  fail "Codex recovery unexpectedly depended on the non-standard codexd alias"
fi
if grep -Fq 'mkdir -p "$rws_cwd"' "$tmp_home_coding/ssh.log"; then
  fail "coding restore recreated a missing workspace instead of requiring it"
fi

: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" new claude-work --cwd '~/work/claude' --agent claude > "$tmp_home_coding/claude-create.out"
grep -Fq 'claude --dangerously-skip-permissions' "$tmp_home_coding/ssh.log"
rm -f "$tmp_home_coding/remote-session-claude-work"
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" new claude-work > /dev/null 2> "$tmp_home_coding/claude-restore.err"
grep -Fq 'claude --dangerously-skip-permissions --continue' "$tmp_home_coding/ssh.log"

: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" new kiro-work --cwd '~/work/kiro' --agent kiro > "$tmp_home_coding/kiro-create.out"
grep -Fq 'kiro-cli chat --trust-all-tools' "$tmp_home_coding/ssh.log"
rm -f "$tmp_home_coding/remote-session-kiro-work"
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" new kiro-work > /dev/null 2> "$tmp_home_coding/kiro-restore.err"
grep -Fq 'kiro-cli chat --trust-all-tools --resume' "$tmp_home_coding/ssh.log"

: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" new standard-work --cwd '~/work/standard' --agent codex --no-full-access > "$tmp_home_coding/standard-create.out"
printf 'rws-coding-session-v2\ncodex\n~/work/standard\ndefault\n' > "$tmp_home_coding/expected-standard.conf"
cmp "$tmp_home_coding/expected-standard.conf" "$tmp_config_coding/sessions/fake/standard-work.conf"
if grep -Eq 'codexd|dangerously-bypass|dangerously-skip|trust-all-tools' "$tmp_home_coding/ssh.log"; then
  fail "standard coding session unexpectedly enabled full access"
fi
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" new standard-work --full-access
grep -q 'kill it before changing its coding-agent configuration' "$tmp_home_coding/stderr"

mkdir -p "$tmp_config_coding/sessions/fake"
printf 'rws-coding-session-v1\ncodex\n~/work/legacy\n' > "$tmp_config_coding/sessions/fake/legacy-work.conf"
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" attach legacy-work > /dev/null 2> "$tmp_home_coding/legacy-restore.err"
grep -q 'access=default' "$tmp_home_coding/legacy-restore.err"
if grep -Eq 'codexd|dangerously-bypass' "$tmp_home_coding/ssh.log"; then
  fail "legacy coding session unexpectedly enabled full access"
fi

rm -f "$tmp_home_coding/remote-session-codex-work"
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" attach codex-work > "$tmp_home_coding/codex-attach.out" 2> "$tmp_home_coding/codex-attach.err"
grep -q 'restoring session: codex-work (codex, ~/work/codex, access=full)' "$tmp_home_coding/codex-attach.err"
grep -Fq 'codex resume --last --dangerously-bypass-approvals-and-sandbox' "$tmp_home_coding/ssh.log"

rm -f "$tmp_home_coding/remote-session-codex-work"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" background codex-work
grep -q 'session with agent metadata must be resumed interactively: rws attach codex-work' "$tmp_home_coding/stderr"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" session create codex-work --cwd '~/work/codex'
grep -q 'session with agent metadata must be resumed interactively: rws attach codex-work' "$tmp_home_coding/stderr"

: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" force codex-work > "$tmp_home_coding/codex-force.out" 2> "$tmp_home_coding/codex-force.err"
grep -q 'restoring session: codex-work (codex, ~/work/codex, access=full)' "$tmp_home_coding/codex-force.err"
grep -Fq 'codex resume --last --dangerously-bypass-approvals-and-sandbox' "$tmp_home_coding/ssh.log"

expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" attach plain-missing
grep -q 'session not found: plain-missing' "$tmp_home_coding/stderr"
touch "$tmp_home_coding/remote-session-foo bar"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" attach foobar
grep -q 'session not found: foobar' "$tmp_home_coding/stderr"
rm -f "$tmp_home_coding/remote-session-foo bar"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" new invalid-agent --cwd '~/work/invalid' --agent other
grep -q 'invalid coding agent: other' "$tmp_home_coding/stderr"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" new invalid-access --cwd '~/work/invalid' --no-full-access
grep -q -- '--no-full-access requires --agent' "$tmp_home_coding/stderr"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" session create invalid-agent --cwd '~/work/invalid' --agent codex
grep -q 'unknown session create option: --agent' "$tmp_home_coding/stderr"
require_error_help "$tmp_home_coding/stderr" 'rws session create SESSION'

touch "$tmp_home_coding/fail-preflight-codex"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" new missing-codex --cwd '~/work/missing-agent' --agent codex
grep -q 'remote dependency missing: coding agent codex (codex)' "$tmp_home_coding/stderr"
test ! -e "$tmp_config_coding/sessions/fake/missing-codex.conf"
rm -f "$tmp_home_coding/fail-preflight-codex"

touch "$tmp_home_coding/fail-attach-initial-fail"
expect_failure "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" new initial-fail --cwd '~/work/initial-fail' --agent codex
grep -q 'simulated attach failure: initial-fail' "$tmp_home_coding/stderr"
test ! -e "$tmp_config_coding/sessions/fake/initial-fail.conf"

touch "$tmp_home_coding/fail-attach-live-live-fail"
expect_failure "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" new live-fail --cwd '~/work/live-fail' --agent codex
grep -q 'simulated dropped client after session start: live-fail' "$tmp_home_coding/stderr"
printf 'rws-coding-session-v2\ncodex\n~/work/live-fail\nfull\n' > "$tmp_home_coding/live-fail-expected.conf"
cmp "$tmp_home_coding/live-fail-expected.conf" "$tmp_config_coding/sessions/fake/live-fail.conf"
test -e "$tmp_home_coding/remote-session-live-fail"
rm -f "$tmp_home_coding/remote-session-live-fail"
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" attach live-fail > /dev/null 2> "$tmp_home_coding/live-fail-restore.err"
grep -q 'restoring session: live-fail (codex, ~/work/live-fail, access=full)' "$tmp_home_coding/live-fail-restore.err"
grep -Fq 'codex resume --last --dangerously-bypass-approvals-and-sandbox' "$tmp_home_coding/ssh.log"

touch "$tmp_home_coding/fail-attach-live-unreachable-fail"
expect_failure "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" new unreachable-fail --cwd '~/work/unreachable-fail' --agent codex
grep -q 'simulated dropped client after session start: unreachable-fail' "$tmp_home_coding/stderr"
printf 'rws-coding-session-v2\ncodex\n~/work/unreachable-fail\nfull\n' > "$tmp_home_coding/unreachable-fail-expected.conf"
cmp "$tmp_home_coding/unreachable-fail-expected.conf" "$tmp_config_coding/sessions/fake/unreachable-fail.conf"
test -e "$tmp_home_coding/remote-session-unreachable-fail"
rm -f "$tmp_home_coding/remote-session-unreachable-fail"

printf 'rws-coding-session-v2\ncodex\n~/work/resume-fail\ndefault\n' > "$tmp_config_coding/sessions/fake/resume-fail.conf"
cp "$tmp_config_coding/sessions/fake/resume-fail.conf" "$tmp_home_coding/resume-fail-before.conf"
touch "$tmp_home_coding/fail-attach-resume-fail"
expect_failure "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" new resume-fail --agent codex --full-access
grep -q 'simulated attach failure: resume-fail' "$tmp_home_coding/stderr"
cmp "$tmp_home_coding/resume-fail-before.conf" "$tmp_config_coding/sessions/fake/resume-fail.conf"

printf 'rws-coding-session-v2\ncodex\n~/work/access-change\ndefault\n' > "$tmp_config_coding/sessions/fake/access-change.conf"
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" new access-change --agent codex --full-access > /dev/null 2> "$tmp_home_coding/access-change.err"
printf 'rws-coding-session-v2\ncodex\n~/work/access-change\nfull\n' > "$tmp_home_coding/access-change-expected.conf"
cmp "$tmp_home_coding/access-change-expected.conf" "$tmp_config_coding/sessions/fake/access-change.conf"
grep -q 'restoring session: access-change (codex, ~/work/access-change, access=full)' "$tmp_home_coding/access-change.err"
grep -Fq 'codex resume --last --dangerously-bypass-approvals-and-sandbox' "$tmp_home_coding/ssh.log"

printf 'rws-coding-session-v2\ncodex\n~/work/old\ndefault\n' > "$tmp_config_coding/sessions/fake/reconfig-work.conf"
: > "$tmp_home_coding/ssh.log"
"${coding_rws[@]}" new reconfig-work --cwd '~/work/new' --agent claude > /dev/null
printf 'rws-coding-session-v2\nclaude\n~/work/new\ndefault\n' > "$tmp_home_coding/reconfig-expected.conf"
cmp "$tmp_home_coding/reconfig-expected.conf" "$tmp_config_coding/sessions/fake/reconfig-work.conf"
if grep -Eq -- 'dangerously-skip-permissions|--continue' "$tmp_home_coding/ssh.log"; then
  fail "dead coding session reconfiguration unexpectedly changed access or resumed the old conversation"
fi

printf 'unknown-version\ncodex\n~/work/corrupt\nfull\n' > "$tmp_config_coding/sessions/fake/corrupt-version.conf"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" attach corrupt-version
grep -q 'invalid coding session metadata' "$tmp_home_coding/stderr"
printf 'rws-coding-session-v2\ncodex\n~/work/corrupt\n' > "$tmp_config_coding/sessions/fake/corrupt-missing-access.conf"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" attach corrupt-missing-access
grep -q 'invalid coding session metadata' "$tmp_home_coding/stderr"
printf 'rws-coding-session-v2\ncodex\n~/work/corrupt\nfull\nextra\n' > "$tmp_config_coding/sessions/fake/corrupt-extra.conf"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" attach corrupt-extra
grep -q 'invalid coding session metadata' "$tmp_home_coding/stderr"
printf 'rws-coding-session-v2\ncodex\n~/work/corrupt\nunsafe\n' > "$tmp_config_coding/sessions/fake/corrupt-access.conf"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" attach corrupt-access
grep -q 'invalid coding agent access mode: unsafe' "$tmp_home_coding/stderr"
printf 'rws-coding-session-v2\nother\n~/work/corrupt\nfull\n' > "$tmp_config_coding/sessions/fake/corrupt-agent.conf"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" attach corrupt-agent
grep -q 'invalid coding agent: other' "$tmp_home_coding/stderr"
printf 'rws-coding-session-v2\ncodex\nbad\tcwd\nfull\n' > "$tmp_config_coding/sessions/fake/corrupt-cwd.conf"
expect_exit_2 "$tmp_home_coding/stdout" "$tmp_home_coding/stderr" "${coding_rws[@]}" attach corrupt-cwd
grep -q 'invalid cwd: control characters are not allowed' "$tmp_home_coding/stderr"
rm -f "$tmp_config_coding/sessions/fake/corrupt-"*.conf

printf 'rws-coding-session-v2\ncodex\n~/work/mixed-live\nfull\n' > "$tmp_config_coding/sessions/fake/mixed-live.conf"
printf 'rws-coding-session-v2\ncodex\n~/work/missing-kill-target\nfull\n' > "$tmp_config_coding/sessions/fake/missing-kill-target.conf"
touch "$tmp_home_coding/remote-session-mixed-live"
"${coding_rws[@]}" kill mixed-live missing-kill-target
test ! -e "$tmp_home_coding/remote-session-mixed-live"
test ! -e "$tmp_config_coding/sessions/fake/mixed-live.conf"
test ! -e "$tmp_config_coding/sessions/fake/missing-kill-target.conf"
printf 'rws-coding-session-v2\ncodex\n~/work/missing-kill-target\nfull\n' > "$tmp_config_coding/sessions/fake/missing-kill-target.conf"
"${coding_rws[@]}" kill missing-kill-target
test ! -e "$tmp_config_coding/sessions/fake/missing-kill-target.conf"

"${coding_rws[@]}" kill quoted-cwd live-fail unreachable-fail access-change reconfig-work

"${coding_rws[@]}" kill codex-work
test ! -e "$tmp_config_coding/sessions/fake/codex-work.conf"
test ! -e "$tmp_home_coding/remote-session-codex-work"
"${coding_rws[@]}" device remove fake
test ! -e "$tmp_config_coding/sessions/fake"

printf 'smoke ok\n'
