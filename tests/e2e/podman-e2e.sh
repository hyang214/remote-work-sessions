#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
IMAGE=${RWS_E2E_IMAGE:-rws-e2e:latest}
BASE_IMAGE=${RWS_E2E_BASE_IMAGE:-alpine:3.22}
APK_MIRROR=${RWS_E2E_APK_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}
DEFAULT_CARGO_REGISTRY_INDEX=sparse+https://index.crates.io/
CARGO_REGISTRY_INDEX=${RWS_E2E_CARGO_REGISTRY_INDEX-$DEFAULT_CARGO_REGISTRY_INDEX}
REMOTE_PASSWORD=${RWS_E2E_REMOTE_PASSWORD:-rws-password-123}
RUN_ID=${RWS_E2E_RUN_ID:-$$}
NETWORK=${RWS_E2E_NETWORK:-rws-e2e-net-$RUN_ID}
SERVER=${RWS_E2E_SERVER:-rws-e2e-server-$RUN_ID}
CLIENT=${RWS_E2E_CLIENT:-rws-e2e-client-$RUN_ID}
PODMAN_READY_TIMEOUT=${RWS_E2E_PODMAN_READY_TIMEOUT:-180}
TMP_DIR=$(mktemp -d)
PACKAGE_VERSION=$(node -e "console.log(require(process.argv[1]).version)" "$ROOT/package.json")

cleanup() {
  status=$?
  if [[ "${RWS_E2E_KEEP_ON_FAIL:-0}" == "1" && "$status" -ne 0 ]]; then
    echo "keeping E2E containers for debugging: $CLIENT $SERVER" >&2
    return
  fi
  podman rm -f "$CLIENT" "$SERVER" >/dev/null 2>&1 || true
  podman network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

wait_for_podman_ready() {
  local deadline=$((SECONDS + PODMAN_READY_TIMEOUT))
  local last_error="$TMP_DIR/podman-ready.err"

  command -v podman >/dev/null 2>&1 || {
    echo "podman command not found; install Podman before running container E2E" >&2
    return 1
  }

  echo "waiting for podman to become ready, timeout ${PODMAN_READY_TIMEOUT}s" >&2
  while (( SECONDS < deadline )); do
    if podman info >/dev/null 2>"$last_error"; then
      return 0
    fi
    sleep 2
  done

  echo "podman did not become ready within ${PODMAN_READY_TIMEOUT}s" >&2
  echo "last podman info error:" >&2
  sed -n '1,20p' "$last_error" >&2 || true
  echo "podman machine list:" >&2
  podman machine list >&2 || true
  echo "try: podman machine start" >&2
  return 1
}

wait_for_podman_ready

ssh-keygen -t ed25519 -N '' -C rws-e2e-bootstrap -f "$TMP_DIR/id_ed25519" >/dev/null

podman build \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "APK_MIRROR=$APK_MIRROR" \
  --build-arg "RWS_PASSWORD=$REMOTE_PASSWORD" \
  -t "$IMAGE" \
  -f "$ROOT/tests/e2e/Containerfile" \
  "$ROOT"
podman network create "$NETWORK" >/dev/null

podman run --rm -v "$ROOT:/workspace:ro" "$BASE_IMAGE" sh -lc "
  sed -i 's|http://dl-cdn.alpinelinux.org/alpine|$APK_MIRROR|g' /etc/apk/repositories
  sed -i 's|https://dl-cdn.alpinelinux.org/alpine|$APK_MIRROR|g' /etc/apk/repositories
  apk add --no-cache bash >/dev/null
  ! command -v ssh >/dev/null 2>&1
  HOME=/tmp/rws-local /workspace/bin/rws setup --host example.invalid --cwd '~/work/project' --session localdeps --no-create-session --key-mode skip --no-install-key --remote-install skip --no-verify --yes >/tmp/rws-local.out 2>/tmp/rws-local.err
  command -v ssh >/dev/null 2>&1
  command -v ssh-keygen >/dev/null 2>&1
  grep -q 'Setup complete' /tmp/rws-local.out
"

podman run -d --name "$SERVER" --network "$NETWORK" \
  -v "$TMP_DIR:/bootstrap:ro" \
  "$IMAGE" /usr/local/bin/rws-server-entrypoint >/dev/null
podman exec "$SERVER" grep -Fq "$APK_MIRROR" /etc/apk/repositories

if [[ -n "$CARGO_REGISTRY_INDEX" && "$CARGO_REGISTRY_INDEX" != "$DEFAULT_CARGO_REGISTRY_INDEX" ]]; then
  podman exec "$SERVER" bash -lc "mkdir -p /home/rws/.cargo && cat > /home/rws/.cargo/config.toml <<EOF
[source.crates-io]
replace-with = \"rws-e2e-mirror\"

[source.rws-e2e-mirror]
registry = \"$CARGO_REGISTRY_INDEX\"

[net]
git-fetch-with-cli = true

[http]
multiplexing = false
timeout = 120
EOF
chown -R rws:rws /home/rws/.cargo"
  podman exec "$SERVER" grep -Fq "$CARGO_REGISTRY_INDEX" /home/rws/.cargo/config.toml
elif [[ -n "$CARGO_REGISTRY_INDEX" ]]; then
  # Cargo already defines crates.io; replacing it with the same registry is
  # rejected as a duplicate source. Keep only transport tuning for the default.
  podman exec "$SERVER" bash -lc "mkdir -p /home/rws/.cargo && cat > /home/rws/.cargo/config.toml <<EOF
[net]
git-fetch-with-cli = true

[http]
multiplexing = false
timeout = 120
EOF
chown -R rws:rws /home/rws/.cargo"
fi

podman run -d --name "$CLIENT" --network "$NETWORK" \
  -v "$ROOT:/workspace:ro" \
  -v "$TMP_DIR:/bootstrap:ro" \
  "$IMAGE" sleep infinity >/dev/null

podman exec "$CLIENT" bash -lc 'mkdir -p ~/.ssh && cp /bootstrap/id_ed25519 ~/.ssh/bootstrap && chmod 600 ~/.ssh/bootstrap'
podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-sessions-schema.jq' <<'JQ'
.sessions | type == "array" and all(.[]; (.name | type == "string") and (.status | type == "string") and (.started_at_unix_ms | type == "number") and (.last_connected_at_unix_ms | type == "number") and ((.last_disconnected_at_unix_ms | type == "number") or (.last_disconnected_at_unix_ms == null)))
JQ

wait_for_server_ssh() {
  local identity_file=$1
  local ssh_ready=0
  for _ in $(seq 1 30); do
    if podman exec "$CLIENT" ssh -i "$identity_file" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "rws@$SERVER" 'echo ssh-ready' >/dev/null 2>&1; then
      ssh_ready=1
      break
    fi
    sleep 1
  done
  [[ "$ssh_ready" -eq 1 ]] || {
    printf 'server SSH was not ready after 30 seconds: %s\n' "$SERVER" >&2
    return 1
  }
}

wait_for_server_ssh /root/.ssh/bootstrap

run_client() {
  printf 'client$ %s\n' "$*"
  podman exec "$CLIENT" bash -lc "cd /workspace && HOME=/root $*"
}

run_client_tty() {
  local command=$1
  shift
  podman exec -t "$@" "$CLIENT" bash -lc "stty rows 24 cols 80 >/dev/null 2>&1 || true; $command"
}

run_client_force_attach() {
  printf 'client-expect$ bin/rws --device e2e f\n'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-force.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e f
after 2500
puts "__rws_force_detached__"
close
catch wait result
exit 0
EXPECT
  before=$(podman exec "$CLIENT" bash -lc "cd /workspace && HOME=/root bin/rws --device e2e ls --json" \
    | jq -r '.sessions[] | select(.name == "e2e") | .last_connected_at_unix_ms')
  if ! run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-force.exp'; then
    return 1
  fi
  after_json=""
  for _ in 1 2 3 4 5; do
    after_json=$(podman exec "$CLIENT" bash -lc "cd /workspace && HOME=/root bin/rws --device e2e ls --json")
    after=$(printf '%s\n' "$after_json" \
      | jq -r '.sessions[] | select(.name == "e2e") | .last_connected_at_unix_ms')
    if [[ -n "$after" && "$after" -gt "$before" ]]; then
      break
    fi
    sleep 1
  done
  printf '%s\n' "$after_json"
  [[ -n "$before" && -n "$after" && "$after" -gt "$before" ]] || {
    printf 'force attach did not update last_connected_at_unix_ms: before=%s after=%s\n' "$before" "$after" >&2
    return 1
  }
  printf '%s\n' "$after_json" | grep -q '"status": "Disconnected"'
  printf '__rws_force_attached__\n'
}

run_client_new_session_attach() {
  printf 'client-expect$ bin/rws --device e2e new review\n'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-new-session.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e new review
after 500
send "\000\021"
expect {
  eof { puts "__rws_new_session_detached__" }
  timeout {
    puts stderr "timeout waiting for new session detach"
    exit 1
  }
}
EXPECT
  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-new-session.exp'
  podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e sessions --json | jq -e -f /tmp/rws-sessions-schema.jq >/dev/null'
  podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e sessions --json | jq -e ".sessions | map(.name) | index(\"review\")" >/dev/null'
  printf '__rws_new_session_created__\n'
}

run_client_pick_cwd_new_session() {
  printf 'client-expect$ bin/rws --device e2e new picked --pick-cwd\n'
  local before_config after_config
  before_config=$(podman exec "$CLIENT" bash -lc 'cat /root/.config/rws/devices/e2e.conf')
  podman exec "$SERVER" bash -lc 'rm -rf /home/rws/work/picked /home/rws/work/picker-created && mkdir -p /home/rws/work/picked && chown -R rws:rws /home/rws/work/picked'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-pick-cwd.exp' <<'EXPECT'
set timeout 90
spawn bin/rws --device e2e new picked --pick-cwd
expect "Tab=complete"
expect "rws cwd>" { send "pwd\r" }
expect "/home/rws/work/project"
expect "rws cwd>" { send "ls ..\r" }
expect "picked"
expect "rws cwd>" { send "cd ../pic\t\r" }
expect "Remote cwd: /home/rws/work/picked"
expect "rws cwd>" { send "cd ..\r" }
expect "Remote cwd: /home/rws/work"
expect "rws cwd>" { send "mkdir -p picker-created/nested\r" }
expect "created directory: /home/rws/work/picker-created/nested"
expect "rws cwd>" { send "cd picker-created/nested\r" }
expect "Remote cwd: /home/rws/work/picker-created/nested"
expect "rws cwd>" { send "\r" }
expect "selected remote cwd: /home/rws/work/picker-created/nested"
set rws_pick_closed 0
set timeout 1
if {[catch {
  expect {
    eof {
      set rws_pick_closed 1
    }
    -re "Connection to .* closed\\." {
      set rws_pick_closed 1
    }
    timeout {}
  }
}]} {
  set rws_pick_closed 1
}
if {$rws_pick_closed} {
  puts "__rws_pick_cwd_detached__"
  exit 0
}
if {[catch {send "\000\021"}]} {
  puts "__rws_pick_cwd_detached__"
  exit 0
}
set timeout 60
expect {
  eof { puts "__rws_pick_cwd_detached__" }
  timeout {
    puts stderr "timeout waiting for pick-cwd session detach"
    exit 1
  }
}
EXPECT
  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-pick-cwd.exp'
  podman exec "$SERVER" bash -lc 'test -d /home/rws/work/picker-created/nested'
  podman exec "$SERVER" bash -lc 'grep -F "spawning shell in '\''/home/rws/work/picker-created/nested'\''" /home/rws/.local/run/shpool/daemonized-shpool.log >/dev/null'
  after_config=$(podman exec "$CLIENT" bash -lc 'cat /root/.config/rws/devices/e2e.conf')
  [[ "$before_config" == "$after_config" ]] || {
    printf 'pick-cwd new session rewrote device config\n' >&2
    printf '%s\n' "$before_config" > "$TMP_DIR/before-pick-cwd.conf"
    printf '%s\n' "$after_config" > "$TMP_DIR/after-pick-cwd.conf"
    diff -u "$TMP_DIR/before-pick-cwd.conf" "$TMP_DIR/after-pick-cwd.conf" >&2 || true
    return 1
  }
  podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e sessions --json | jq -e ".sessions | map(.name) | index(\"picked\")" >/dev/null'
  printf '__rws_pick_cwd_created__\n'
}

run_client_bad_password_setup() {
  printf 'client-expect$ bad password setup\n'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-bad-password.exp' <<'EXPECT'
set timeout 60
spawn env HOME=/tmp/rws-bad-password bin/rws setup --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null --ssh-option NumberOfPasswordPrompts=1
expect "Device name" { send "badpass\r" }
expect "Remote host or IP" { send "$env(RWS_E2E_SERVER)\r" }
expect "Remote SSH user" { send "rws\r" }
expect "Connecting to rws@$env(RWS_E2E_SERVER)"
expect {
  -re "(?i)password:" {
    send "wrong-password\r"
    exp_continue
  }
  "SSH connection failed. Check the host, username, or password" {
    puts "__rws_bad_password_reported__"
  }
  timeout {
    puts stderr "timeout waiting for bad password failure"
    exit 1
  }
}
catch {expect eof}
EXPECT
  run_client_tty 'cd /workspace && expect /tmp/rws-bad-password.exp' -e "RWS_E2E_SERVER=$SERVER"
}

run_client_setup_cancel() {
  printf 'client-expect$ setup cancel\n'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-setup-cancel.exp' <<'EXPECT'
set timeout 30
spawn env HOME=/tmp/rws-setup-cancel bin/rws setup
expect "Device name" { send "q\r" }
expect "rws: setup canceled" {
  puts "__rws_setup_cancel_verified__"
}
catch {expect eof}
EXPECT
  run_client_tty 'cd /workspace && expect /tmp/rws-setup-cancel.exp'
}

run_client_existing_setup_choice() {
  printf 'client-expect$ existing setup choice\n'
  podman exec "$CLIENT" bash -lc 'rm -rf /tmp/rws-existing-continue /tmp/rws-existing-reset && mkdir -p /tmp/rws-existing-continue/.config/rws/devices /tmp/rws-existing-reset/.config/rws/devices'
  podman exec "$CLIENT" bash -lc 'cat > /tmp/rws-existing-continue/.config/rws/devices/resume.conf <<EOF
device=resume
host=saved-user@saved-host
cwd=/saved/cwd
default_session=saved
prompt_mode=skip
EOF'
  podman exec "$CLIENT" bash -lc 'cat > /tmp/rws-existing-reset/.config/rws/devices/resume.conf <<EOF
device=resume
host=saved-user@saved-host
cwd=/saved/cwd
default_session=saved
prompt_mode=skip
EOF'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-existing-choice.exp' <<'EXPECT'
set timeout 30
spawn env HOME=/tmp/rws-existing-continue bin/rws setup
expect "Device name" { send "resume\r" }
expect "Existing device config found: resume"
expect "Choose" { send "\r" }
expect "SSH host, for example user@workstation" { send "q\r" }
expect "rws: setup canceled" {
  puts "__rws_existing_continue_choice_verified__"
}
catch {expect eof}

spawn env HOME=/tmp/rws-existing-reset bin/rws setup
expect "Device name" { send "resume\r" }
expect "Existing device config found: resume"
expect "Choose" { send "2\r" }
expect "Resetting device config: resume"
expect "Remote host or IP" { send "q\r" }
expect "rws: setup canceled" {
  puts "__rws_existing_reset_choice_verified__"
}
catch {expect eof}
EXPECT
  run_client_tty 'cd /workspace && expect /tmp/rws-existing-choice.exp'
}

run_client_decline_remote_install() {
  printf 'client-expect$ decline remote auto install\n'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-decline-install.exp' <<'EXPECT'
set timeout 60
spawn bin/rws setup --device noinstall --host rws@$env(RWS_E2E_SERVER) --no-create-session --key-mode existing --identity-file ~/.ssh/bootstrap --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null
expect "Device name" { send "\r" }
expect "SSH host" { send "\r" }
expect "Use compact prompt for remote sessions" { send "n\r" }
expect -exact {[6/12] Reviewing device changes}
expect "Setup will verify or change device state"
expect "Install missing remote dependencies automatically if needed" { send "n\r" }
expect "Remote auto-install disabled"
expect -exact "\[8/12\] Checking remote dependencies on rws@$env(RWS_E2E_SERVER)"
expect "rws: shpool is missing on the remote host"
expect "remote dependency setup failed"
puts "__rws_decline_remote_install_verified__"
catch {expect eof}
EXPECT
  run_client_tty 'cd /workspace && expect /tmp/rws-decline-install.exp' -e "RWS_E2E_SERVER=$SERVER"
}

run_client_password_setup() {
  printf 'client-expect$ password setup\n'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-password.exp' <<'EXPECT'
set timeout 180
spawn env HOME=/tmp/rws-password bin/rws setup --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null
expect "Device name" { send "password\r" }
expect "Remote host or IP" { send "$env(RWS_E2E_SERVER)\r" }
expect "Remote SSH user" { send "rws\r" }
expect "Connecting to rws@$env(RWS_E2E_SERVER)"
expect -re "(?i)password:" { send "$env(RWS_E2E_REMOTE_PASSWORD)\r" }
expect "Use compact prompt for remote sessions" { send "\r" }
expect "Prompt device label" { send "\r" }
expect "Use SSH key authentication for stable reconnects" { send "\r" }
expect "Choose" { send "\r" }
expect "Install missing remote dependencies automatically if needed" { send "\r" }
expect "verification ok: connect, shpool" {
  puts "__rws_password_device_verified__"
}
expect "Create an initial session now" { send "y\r" }
expect "Initial session name" { send "password\r" }
expect "Remote cwd: /home/rws"
expect "rws cwd>" { send "does-not-exist\r" }
expect "rws: unknown command or directory: does-not-exist"
expect "Remote cwd: /home/rws"
expect "rws cwd>" { send "cd ~/work/project\r" }
expect "Remote cwd: /home/rws/work/project"
expect "rws cwd>" { send "\r" }
expect "selected remote cwd: /home/rws/work/project"
expect {
  "created session: password" {
    puts "__rws_password_setup_verified__"
    exp_continue
  }
  "Setup complete." {
    puts "__rws_password_setup_complete__"
  }
  timeout {
    puts stderr "timeout waiting for password setup"
    exit 1
  }
}
catch {expect eof}
EXPECT
  run_client_tty 'cd /workspace && expect /tmp/rws-password.exp' -e "RWS_E2E_SERVER=$SERVER" -e "RWS_E2E_REMOTE_PASSWORD=$REMOTE_PASSWORD"
  podman exec "$CLIENT" bash -lc 'HOME=/tmp/rws-password test -f ~/.ssh/rws_password_ed25519'
  podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/tmp/rws-password bin/rws --device password c | grep -q "shpool=shpool 0.9.8"'
  podman exec "$CLIENT" bash -lc "! grep -R '$REMOTE_PASSWORD' /tmp/rws-password 2>/dev/null"
}

run_client_hostkey_setup() {
  printf 'client-expect$ host-key setup\n'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-hostkey.exp' <<'EXPECT'
set timeout 180
spawn env HOME=/tmp/rws-hostkey bin/rws setup
expect "Device name" { send "hostkey\r" }
expect "Remote host or IP" { send "$env(RWS_E2E_SERVER)\r" }
expect "Remote SSH user" { send "rws\r" }
expect {
  -re "Are you sure you want to continue connecting.*" {
    send "yes\r"
    exp_continue
  }
  -re "(?i)password:" {
    send "$env(RWS_E2E_REMOTE_PASSWORD)\r"
  }
}
expect "Use compact prompt for remote sessions" { send "\r" }
expect "Prompt device label" { send "\r" }
expect "Use SSH key authentication for stable reconnects" { send "\r" }
expect "Choose" { send "\r" }
expect "Install missing remote dependencies automatically if needed" { send "\r" }
expect "verification ok: connect, shpool" {
  puts "__rws_hostkey_device_verified__"
}
expect "Create an initial session now" { send "y\r" }
expect "Initial session name" { send "hostkey\r" }
expect "Remote cwd: /home/rws"
expect "rws cwd>" { send "cd ~/work/project\r" }
expect "Remote cwd: /home/rws/work/project"
expect "rws cwd>" { send "\r" }
expect "selected remote cwd: /home/rws/work/project"
expect {
  "created session: hostkey" {
    puts "__rws_hostkey_setup_verified__"
    exp_continue
  }
  "Setup complete." {
    puts "__rws_hostkey_setup_complete__"
  }
  timeout {
    puts stderr "timeout waiting for host-key setup"
    exit 1
  }
}
catch {expect eof}
EXPECT
  run_client_tty 'cd /workspace && expect /tmp/rws-hostkey.exp' -e "RWS_E2E_SERVER=$SERVER" -e "RWS_E2E_REMOTE_PASSWORD=$REMOTE_PASSWORD"
  podman exec "$CLIENT" bash -lc "HOME=/tmp/rws-hostkey grep -q '$SERVER' ~/.ssh/known_hosts"
  podman exec "$CLIENT" bash -lc "! grep -R '$REMOTE_PASSWORD' /tmp/rws-hostkey 2>/dev/null"
}

run_client_skip_auth_setup() {
  printf 'client$ key-mode skip with real ssh config\n'
  podman exec "$CLIENT" bash -lc "cat >> /root/.ssh/config <<EOF
Host rws-skipauth-target
  HostName $SERVER
  User rws
  IdentityFile /root/.ssh/bootstrap
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
chmod 600 /root/.ssh/config"
  podman exec "$CLIENT" bash -lc "ssh -G rws@rws-skipauth-target | grep -qx 'identityfile /root/.ssh/bootstrap'"
  podman exec "$CLIENT" bash -lc "cd /workspace && HOME=/tmp/rws-skipauth bin/rws setup --device skipauth --host rws@rws-skipauth-target --cwd '~/work/project' --session skipauth --key-mode skip --no-install-key --remote-install skip --shpool-bin /home/rws/.cargo/bin/shpool --yes"
  podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/tmp/rws-skipauth bin/rws --device skipauth c | grep -q "shpool=shpool 0.9.8"'
  podman exec "$CLIENT" bash -lc '! grep -q "^identity_file=" /tmp/rws-skipauth/.config/rws/devices/skipauth.conf'
}

run_client_default_attach() {
  printf 'client-expect$ bin/rws\n'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-default-attach.exp' <<'EXPECT'
set timeout 60
spawn bin/rws
after 500
send "\000\021"
expect {
  eof { puts "__rws_default_attach_detached__" }
  timeout {
    puts stderr "timeout waiting for default attach detach"
    exit 1
  }
}
EXPECT
  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-default-attach.exp'
}

run_client_compact_prompt_session() {
  printf 'client-expect$ bin/rws --device e2e new promptcheck\n'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-compact-prompt.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e new promptcheck
expect {
  -exact {[e2e:promptcheck]} {}
  timeout {
    puts stderr "timeout waiting for compact prompt"
    exit 1
  }
}
send "printf \"__rws_prompt_env__%s:%s\\n\" \"\$RWS_DEVICE_LABEL\" \"\$SHPOOL_SESSION_NAME\"\r"
expect "__rws_prompt_env__e2e:promptcheck"
send "exit\r"
expect {
  eof { puts "__rws_compact_prompt_verified__" }
  timeout {
    puts stderr "timeout waiting for compact prompt session exit"
    exit 1
  }
}
EXPECT
  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-compact-prompt.exp'
  podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e sessions --json | jq -e -f /tmp/rws-sessions-schema.jq >/dev/null'
}

run_client_background_compact_prompt_session() {
  printf 'client-expect$ bin/rws --device e2e session create bgprompt --cwd ~/work/project; attach bgprompt\n'
  run_client "env -u TERM bin/rws --device e2e session create bgprompt --cwd '~/work/project' | grep -qx 'created session: bgprompt'"
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-bg-compact-prompt.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e attach bgprompt
expect {
  -exact {[e2e:bgprompt]} {}
  timeout {
    puts stderr "timeout waiting for background compact prompt"
    exit 1
  }
}
send "printf \"__rws_bg_prompt_env__%s:%s:%s\\n\" \"\$RWS_DEVICE_LABEL\" \"\$SHPOOL_SESSION_NAME\" \"\$TERM\"\r"
expect "__rws_bg_prompt_env__e2e:bgprompt:xterm-256color"
send "exit\r"
expect {
  eof { puts "__rws_bg_compact_prompt_verified__" }
  timeout {
    puts stderr "timeout waiting for background compact prompt session exit"
    exit 1
  }
}
EXPECT
  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-bg-compact-prompt.exp'
  podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e sessions --json | jq -e -f /tmp/rws-sessions-schema.jq >/dev/null'
}

run_client_interrupted_attach() {
  printf 'client-expect$ interrupted attach\n'
  local before_config after_config
  before_config=$(podman exec "$CLIENT" bash -lc 'cat /root/.config/rws/devices/e2e.conf')
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-interrupt.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e new interrupted
after 1500
catch {close}
catch {wait}
puts "__rws_interrupted_attach_closed__"
EXPECT
  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-interrupt.exp'
  after_config=$(podman exec "$CLIENT" bash -lc 'cat /root/.config/rws/devices/e2e.conf')
  [[ "$before_config" == "$after_config" ]] || {
    printf 'interrupted attach rewrote device config\n' >&2
    printf '%s\n' "$before_config" > "$TMP_DIR/before-interrupt.conf"
    printf '%s\n' "$after_config" > "$TMP_DIR/after-interrupt.conf"
    diff -u "$TMP_DIR/before-interrupt.conf" "$TMP_DIR/after-interrupt.conf" >&2 || true
    return 1
  }
  podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e sessions --json | jq -e ".sessions | map(.name) | index(\"interrupted\")" >/dev/null'
  podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e k interrupted'
}

run_client_recover_after_dropped_attach() {
  printf 'client-expect$ recover after dropped attach\n'
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-dropped-attach.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e new recover
after 1500
catch {close}
catch {wait}
puts "__rws_dropped_attach_closed__"
EXPECT
  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-dropped-attach.exp'
  local before_json before_started before_connected after_json after_started after_connected
  before_json=$(podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e sessions --json')
  printf '%s\n' "$before_json" | jq -e '.sessions | map(.name) | index("recover")' >/dev/null
  before_started=$(printf '%s\n' "$before_json" | jq -r '.sessions[] | select(.name == "recover") | .started_at_unix_ms')
  before_connected=$(printf '%s\n' "$before_json" | jq -r '.sessions[] | select(.name == "recover") | .last_connected_at_unix_ms')

  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-recover-force.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e f recover
after 1500
catch {close}
catch {wait}
puts "__rws_recover_force_closed__"
EXPECT
  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-recover-force.exp'
  after_json=$(podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e sessions --json')
  after_started=$(printf '%s\n' "$after_json" | jq -r '.sessions[] | select(.name == "recover") | .started_at_unix_ms')
  after_connected=$(printf '%s\n' "$after_json" | jq -r '.sessions[] | select(.name == "recover") | .last_connected_at_unix_ms')
  [[ "$after_started" == "$before_started" ]] || {
    printf 'recover session was recreated instead of reattached: before=%s after=%s\n' "$before_started" "$after_started" >&2
    return 1
  }
  [[ "$after_connected" -gt "$before_connected" ]] || {
    printf 'recover force attach did not update last_connected_at_unix_ms: before=%s after=%s\n' "$before_connected" "$after_connected" >&2
    return 1
  }
  printf '%s\n' "$after_json" | grep -q '"status": "Disconnected"'
  printf '__rws_recovered_same_session__\n'
}

run_client_coding_session_recovery() {
  printf 'client-expect$ coding session recovery\n'
  podman exec -i "$SERVER" sh -c 'cat > /usr/local/bin/rws-fake-coding-agent' <<'SH'
#!/usr/bin/env sh
set -eu
printf '%s|%s|%s\n' "$(basename "$0")" "$PWD" "$*" >> /home/rws/coding-agent.log
history_dir=/home/rws/.rws-e2e-provider-history
session=${SHPOOL_SESSION_NAME:-unknown}
marker=$history_dir/$session
mkdir -p "$history_dir"
case " $* " in
  *" resume "*|*" --continue "*|*" --resume "*)
    if [ ! -f "$marker" ]; then
      printf '%s|missing-marker\n' "$session" >> /home/rws/coding-agent-recovery.log
      exit 42
    fi
    printf '%s|%s\n' "$session" "$(cat "$marker")" >> /home/rws/coding-agent-recovery.log
    ;;
  *)
    printf '%s:%s\n' "$session" "$PWD" > "$marker"
    ;;
esac
trap 'exit 0' HUP INT TERM
while :; do
  sleep 1
done
SH
  podman exec "$SERVER" sh -lc '
    chmod +x /usr/local/bin/rws-fake-coding-agent
    ln -sf /usr/local/bin/rws-fake-coding-agent /usr/local/bin/codex
    ln -sf /usr/local/bin/rws-fake-coding-agent /usr/local/bin/claude
    ln -sf /usr/local/bin/rws-fake-coding-agent /usr/local/bin/kiro-cli
    : > /home/rws/coding-agent.log
    : > /home/rws/coding-agent-recovery.log
    rm -rf /home/rws/.rws-e2e-provider-history
    chown rws:rws /home/rws/coding-agent.log /home/rws/coding-agent-recovery.log
  '

  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-coding-new.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e new $env(RWS_E2E_SESSION) --cwd ~/work/coding --agent $env(RWS_E2E_AGENT)
after 1000
send "\000\021"
expect {
  eof { puts "__rws_coding_new_detached__" }
  timeout {
    puts stderr "timeout waiting for coding session detach"
    exit 1
  }
}
EXPECT
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-coding-new-standard.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e new codex-standard --cwd ~/work/coding --agent codex --no-full-access
after 1000
send "\000\021"
expect {
  eof { puts "__rws_coding_standard_detached__" }
  timeout {
    puts stderr "timeout waiting for standard-access coding session detach"
    exit 1
  }
}
EXPECT
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-coding-new-explicit-full.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e new codex-explicit-full --cwd ~/work/coding --agent codex --full-access
after 1000
send "\000\021"
expect {
  eof { puts "__rws_coding_explicit_full_detached__" }
  timeout {
    puts stderr "timeout waiting for explicit-full-access coding session detach"
    exit 1
  }
}
EXPECT
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-coding-live-attach.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e attach codex-recovery
after 1000
send "\000\021"
expect {
  eof { puts "__rws_coding_live_reattached__" }
  timeout {
    puts stderr "timeout waiting for live coding session detach"
    exit 1
  }
}
EXPECT
  podman exec -i "$CLIENT" sh -c 'cat > /tmp/rws-coding-restore.exp' <<'EXPECT'
set timeout 60
spawn bin/rws --device e2e attach $env(RWS_E2E_SESSION)
expect "restoring session: $env(RWS_E2E_SESSION) ($env(RWS_E2E_AGENT), ~/work/coding, access=full)"
after 1000
send "\000\021"
expect {
  eof { puts "__rws_coding_restore_detached__" }
  timeout {
    puts stderr "timeout waiting for recovered coding session detach"
    exit 1
  }
}
EXPECT

  run_client_tty 'cd /workspace && HOME=/root RWS_E2E_SESSION=codex-recovery RWS_E2E_AGENT=codex expect /tmp/rws-coding-new.exp'
  run_client "printf 'rws-coding-session-v2\\ncodex\\n~/work/coding\\nfull\\n' | cmp - ~/.config/rws/sessions/e2e/codex-recovery.conf"
  podman exec "$SERVER" grep -qx 'codex|/home/rws/work/coding|--dangerously-bypass-approvals-and-sandbox' /home/rws/coding-agent.log
  codex_started_before=$(podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e sessions --json' | jq -r '.sessions[] | select(.name == "codex-recovery") | .started_at_unix_ms')
  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-coding-live-attach.exp'
  codex_started_after=$(podman exec "$CLIENT" bash -lc 'cd /workspace && HOME=/root bin/rws --device e2e sessions --json' | jq -r '.sessions[] | select(.name == "codex-recovery") | .started_at_unix_ms')
  [[ "$codex_started_before" == "$codex_started_after" ]]
  [[ "$(podman exec "$SERVER" grep -c '^codex|/home/rws/work/coding|' /home/rws/coding-agent.log)" == "1" ]]
  run_client "ssh -i ~/.ssh/rws_e2e -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null rws@$SERVER '/home/rws/.cargo/bin/shpool kill codex-recovery'"
  run_client_tty 'cd /workspace && HOME=/root RWS_E2E_SESSION=codex-recovery RWS_E2E_AGENT=codex expect /tmp/rws-coding-restore.exp'
  podman exec "$SERVER" grep -qx 'codex|/home/rws/work/coding|resume --last --dangerously-bypass-approvals-and-sandbox' /home/rws/coding-agent.log
  podman exec "$SERVER" grep -qx 'codex-recovery|codex-recovery:/home/rws/work/coding' /home/rws/coding-agent-recovery.log

  run_client_tty 'cd /workspace && HOME=/root RWS_E2E_SESSION=claude-recovery RWS_E2E_AGENT=claude expect /tmp/rws-coding-new.exp'
  podman exec "$SERVER" grep -qx 'claude|/home/rws/work/coding|--dangerously-skip-permissions' /home/rws/coding-agent.log
  run_client "ssh -i ~/.ssh/rws_e2e -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null rws@$SERVER '/home/rws/.cargo/bin/shpool kill claude-recovery'"
  run_client_tty 'cd /workspace && HOME=/root RWS_E2E_SESSION=claude-recovery RWS_E2E_AGENT=claude expect /tmp/rws-coding-restore.exp'
  podman exec "$SERVER" grep -qx 'claude|/home/rws/work/coding|--dangerously-skip-permissions --continue' /home/rws/coding-agent.log

  run_client_tty 'cd /workspace && HOME=/root RWS_E2E_SESSION=kiro-recovery RWS_E2E_AGENT=kiro expect /tmp/rws-coding-new.exp'
  podman exec "$SERVER" grep -qx 'kiro-cli|/home/rws/work/coding|chat --trust-all-tools' /home/rws/coding-agent.log
  run_client "ssh -i ~/.ssh/rws_e2e -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null rws@$SERVER '/home/rws/.cargo/bin/shpool kill kiro-recovery'"
  run_client_tty 'cd /workspace && HOME=/root RWS_E2E_SESSION=kiro-recovery RWS_E2E_AGENT=kiro expect /tmp/rws-coding-restore.exp'
  podman exec "$SERVER" grep -qx 'kiro-cli|/home/rws/work/coding|chat --trust-all-tools --resume' /home/rws/coding-agent.log

  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-coding-new-standard.exp'
  run_client "printf 'rws-coding-session-v2\\ncodex\\n~/work/coding\\ndefault\\n' | cmp - ~/.config/rws/sessions/e2e/codex-standard.conf"
  podman exec "$SERVER" grep -qx 'codex|/home/rws/work/coding|' /home/rws/coding-agent.log

  run_client_tty 'cd /workspace && HOME=/root expect /tmp/rws-coding-new-explicit-full.exp'
  run_client "printf 'rws-coding-session-v2\\ncodex\\n~/work/coding\\nfull\\n' | cmp - ~/.config/rws/sessions/e2e/codex-explicit-full.conf"
  podman exec "$SERVER" grep -qx 'codex|/home/rws/work/coding|--dangerously-bypass-approvals-and-sandbox' /home/rws/coding-agent.log

  run_client 'bin/rws --device e2e kill codex-recovery claude-recovery kiro-recovery codex-standard codex-explicit-full'

  run_client_tty 'cd /workspace && HOME=/root RWS_E2E_SESSION=codex-reboot RWS_E2E_AGENT=codex expect /tmp/rws-coding-new.exp'
  run_client "printf 'rws-coding-session-v2\\ncodex\\n~/work/coding\\nfull\\n' | cmp - ~/.config/rws/sessions/e2e/codex-reboot.conf"
  podman exec "$SERVER" grep -qx 'codex-reboot:/home/rws/work/coding' /home/rws/.rws-e2e-provider-history/codex-reboot
  podman kill --signal KILL "$SERVER" >/dev/null
  podman start "$SERVER" >/dev/null
  wait_for_server_ssh /root/.ssh/rws_e2e
  run_client_tty 'cd /workspace && HOME=/root RWS_E2E_SESSION=codex-reboot RWS_E2E_AGENT=codex expect /tmp/rws-coding-restore.exp'
  podman exec "$SERVER" grep -qx 'codex|/home/rws/work/coding|resume --last --dangerously-bypass-approvals-and-sandbox' /home/rws/coding-agent.log
  podman exec "$SERVER" grep -qx 'codex-reboot|codex-reboot:/home/rws/work/coding' /home/rws/coding-agent-recovery.log
  run_client 'bin/rws --device e2e kill codex-reboot'

  run_client 'test ! -e ~/.config/rws/sessions/e2e'
  printf '__rws_coding_live_reattach_verified__\n'
  printf '__rws_coding_server_restart_verified__\n'
  printf '__rws_coding_session_recovery_verified__\n'
}

authorized_key_count() {
  local pub_key
  pub_key=$(podman exec "$CLIENT" bash -lc 'cat /root/.ssh/rws_e2e.pub')
  podman exec "$SERVER" bash -lc "grep -cF '$pub_key' /home/rws/.ssh/authorized_keys"
}

wait_for_authorized_key_count() {
  local expected=$1
  local count=
  for _ in $(seq 1 10); do
    if count=$(authorized_key_count 2>/dev/null) && [[ "$count" == "$expected" ]]; then
      return 0
    fi
    sleep 0.2
  done
  printf 'expected generated e2e public key count %s, got %s\n' "$expected" "${count:-unavailable}" >&2
  podman exec "$SERVER" bash -lc 'nl -ba /home/rws/.ssh/authorized_keys' >&2 || true
  return 1
}

run_client 'bash -n bin/rws'
run_client 'bin/rws --help >/dev/null'
run_client 'bin/rws c >/tmp/rws-c.out 2>/tmp/rws-c.err && exit 1 || grep -q "Run: rws setup" /tmp/rws-c.err'
setup_cancel_output=$(run_client_setup_cancel | tr -d '\r') || {
  printf '%s\n' "$setup_cancel_output"
  exit 1
}
printf '%s\n' "$setup_cancel_output"
printf '%s\n' "$setup_cancel_output" | grep -q "__rws_setup_cancel_verified__"
existing_choice_output=$(run_client_existing_setup_choice | tr -d '\r') || {
  printf '%s\n' "$existing_choice_output"
  exit 1
}
printf '%s\n' "$existing_choice_output"
printf '%s\n' "$existing_choice_output" | grep -q "__rws_existing_continue_choice_verified__"
printf '%s\n' "$existing_choice_output" | grep -q "__rws_existing_reset_choice_verified__"
bad_password_output=$(run_client_bad_password_setup | tr -d '\r') || {
  printf '%s\n' "$bad_password_output"
  exit 1
}
printf '%s\n' "$bad_password_output"
printf '%s\n' "$bad_password_output" | grep -q "__rws_bad_password_reported__"
printf '%s\n' "$bad_password_output" | grep -q "Connecting to rws@$SERVER"
printf '%s\n' "$bad_password_output" | grep -q "Remote working directory" && exit 1 || true
printf '%s\n' "$bad_password_output" | grep -q "Select remote working directory" && exit 1 || true

decline_install_output=$(run_client_decline_remote_install | tr -d '\r') || {
  printf '%s\n' "$decline_install_output"
  exit 1
}
printf '%s\n' "$decline_install_output"
printf '%s\n' "$decline_install_output" | grep -q "__rws_decline_remote_install_verified__"
run_client 'bin/rws remove noinstall | grep -q "removed noinstall; no devices remain"'
podman exec "$SERVER" test ! -e /home/rws/.cargo/bin/shpool

run_client "bin/rws setup --device checkfail --host rws@$SERVER --no-create-session --key-mode existing --identity-file '~/.ssh/bootstrap' --remote-install check --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null --yes > /tmp/rws-checkfail.out 2>&1 && exit 1 || { grep -q 'shpool is missing' /tmp/rws-checkfail.out && grep -q 'remote dependency setup failed' /tmp/rws-checkfail.out; }"
run_client 'grep -Fq "[8/12] Checking remote dependencies" /tmp/rws-checkfail.out'
run_client 'grep -q "rws: checking remote shpool 0.9.8" /tmp/rws-checkfail.out'
run_client 'bin/rws remove checkfail | grep -q "removed checkfail; no devices remain"'
podman exec "$SERVER" test ! -e /home/rws/.cargo/bin/shpool
run_client "bin/rws setup --device skiponly --host rws@$SERVER --no-create-session --key-mode existing --identity-file '~/.ssh/bootstrap' --remote-install skip --shpool-bin /managed/shpool --no-verify --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null --yes > /tmp/rws-skiponly.out 2>&1"
run_client 'grep -q "Setup complete" /tmp/rws-skiponly.out'
run_client 'grep -Fq "[8/12] Skipping remote dependency setup (--remote-install skip)" /tmp/rws-skiponly.out'
run_client 'grep -Fq "[10/12] Skipping device verification (--no-verify)" /tmp/rws-skiponly.out'
run_client 'grep -qx "shpool_bin=/managed/shpool" ~/.config/rws/devices/skiponly.conf'
podman exec "$SERVER" test ! -e /home/rws/.cargo/bin/shpool
run_client 'bin/rws remove skiponly | grep -q "removed skiponly; no devices remain"'

run_client "bin/rws setup --device e2e --host rws@$SERVER --cwd '~/work/project' --session e2e --no-create-session --key-mode create --identity-file '~/.ssh/rws_e2e' --install-key --bootstrap-identity '~/.ssh/bootstrap' --prompt-mode compact --prompt-label e2e --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null --yes"

run_client 'test -f ~/.ssh/rws_e2e'
run_client 'grep -qx "device=e2e" ~/.config/rws/default.conf'
run_client 'grep -q "^default_session=" ~/.config/rws/devices/e2e.conf && exit 1 || exit 0'
run_client 'grep -q "^cwd=" ~/.config/rws/devices/e2e.conf && exit 1 || exit 0'
run_client 'grep -qx "identity_file=~/.ssh/rws_e2e" ~/.config/rws/devices/e2e.conf'
run_client "grep -qx \"setup_version=$PACKAGE_VERSION\" ~/.config/rws/devices/e2e.conf"
run_client 'grep -qx "shpool_version=0.9.8" ~/.config/rws/devices/e2e.conf'
run_client 'grep -qx "prompt_mode=compact" ~/.config/rws/devices/e2e.conf'
run_client 'grep -qx "prompt_label=e2e" ~/.config/rws/devices/e2e.conf'
run_client 'grep -qx "ssh_option=StrictHostKeyChecking=no" ~/.config/rws/devices/e2e.conf'
run_client 'grep -qx "shpool_bin=/home/rws/.cargo/bin/shpool" ~/.config/rws/devices/e2e.conf'
podman exec "$SERVER" bash -lc 'grep -qx "prompt_prefix = \"\"" /home/rws/.config/shpool/config.toml'
podman exec "$SERVER" bash -lc 'grep -Fq "# >>> rws compact prompt >>>" /home/rws/.bashrc'
wait_for_authorized_key_count 1

run_client 'bin/rws --device e2e c | grep -q "shpool=shpool 0.9.8"'
run_client "bin/rws --device e2e doctor > /tmp/rws-doctor.out && grep -qx 'device=e2e' /tmp/rws-doctor.out && grep -qx 'host=rws@$SERVER' /tmp/rws-doctor.out && grep -qx 'cwd=(not set)' /tmp/rws-doctor.out && grep -qx 'default_session=(not set)' /tmp/rws-doctor.out && grep -qx 'shpool_bin=/home/rws/.cargo/bin/shpool' /tmp/rws-doctor.out && grep -q 'shpool=shpool 0.9.8' /tmp/rws-doctor.out"
run_client 'bin/rws --device e2e device get e2e | grep -q "^cwd=" && exit 1 || exit 0'
run_client "bin/rws --device e2e device update e2e --cwd '~/work/project' --session e2e --prompt-mode compact --prompt-label e2e --ssh-option StrictHostKeyChecking=no --default | grep -qx 'updated e2e'"
run_client 'grep -qx "device=e2e" ~/.config/rws/default.conf'
run_client 'grep -qx "cwd=~/work/project" ~/.config/rws/devices/e2e.conf'
run_client 'grep -qx "default_session=e2e" ~/.config/rws/devices/e2e.conf'
run_client 'grep -qx "ssh_option=StrictHostKeyChecking=no" ~/.config/rws/devices/e2e.conf'
run_client 'bin/rws --device e2e --shpool-bin /no/such doctor >/tmp/rws-doctor-fail.out 2>/tmp/rws-doctor-fail.err && exit 1 || { grep -q "remote dependency missing: shpool (/no/such)" /tmp/rws-doctor-fail.err && ! grep -q "ssh_error=unknown" /tmp/rws-doctor-fail.err; }'
podman exec "$SERVER" bash -lc "printf '#!/usr/bin/env sh\nexit 0\n' > /home/rws/work/project/shpool && chmod +x /home/rws/work/project/shpool && chown rws:rws /home/rws/work/project/shpool"
run_client 'bin/rws --device e2e --shpool-bin shpool doctor >/tmp/rws-doctor-pathless.out 2>/tmp/rws-doctor-pathless.err && exit 1 || { grep -q "remote dependency missing: shpool (shpool)" /tmp/rws-doctor-pathless.err && ! grep -q "shpool command failed" /tmp/rws-doctor-pathless.err; }'
podman exec "$SERVER" rm -f /home/rws/work/project/shpool
podman exec "$SERVER" bash -lc "cat > /home/rws/fake-shpool-version <<'SH'
#!/usr/bin/env sh
case \"\$1\" in
  version) echo 'shpool 9.9.9' ;;
  list) echo '{\"sessions\":[]}' ;;
  *) exit 2 ;;
esac
SH
chmod +x /home/rws/fake-shpool-version
cat > /home/rws/fake-shpool-daemon-fail <<'SH'
#!/usr/bin/env sh
case \"\$1\" in
  version) echo 'shpool 0.9.8' ;;
  list) echo 'daemon unavailable' >&2; exit 2 ;;
  *) exit 2 ;;
esac
SH
chmod +x /home/rws/fake-shpool-daemon-fail
chown rws:rws /home/rws/fake-shpool-version /home/rws/fake-shpool-daemon-fail"
run_client 'bin/rws --device e2e --shpool-bin /home/rws/fake-shpool-version doctor >/tmp/rws-doctor-version.out 2>/tmp/rws-doctor-version.err && exit 1 || grep -q "expected shpool 0.9.8 but found: shpool 9.9.9" /tmp/rws-doctor-version.err'
run_client 'bin/rws --device e2e --shpool-bin /home/rws/fake-shpool-daemon-fail doctor >/tmp/rws-doctor-daemon.out 2>/tmp/rws-doctor-daemon.err && exit 1 || grep -q "shpool daemon check failed" /tmp/rws-doctor-daemon.err'
run_client 'bin/rws --device e2e --cwd /home/rws/work/missing c >/tmp/rws-cwd-missing.out 2>/tmp/rws-cwd-missing.err && exit 1 || grep -q "remote cwd missing: /home/rws/work/missing" /tmp/rws-cwd-missing.err'
podman exec "$SERVER" bash -lc 'mkdir -p /home/rws/work/private && chmod 000 /home/rws/work/private'
run_client 'bin/rws --device e2e --cwd /home/rws/work/private c >/tmp/rws-cwd-private.out 2>/tmp/rws-cwd-private.err && exit 1 || grep -q "remote cwd not accessible: /home/rws/work/private" /tmp/rws-cwd-private.err'
podman exec "$SERVER" bash -lc 'chmod 755 /home/rws/work/private'
run_client 'bin/rws --device e2e run -- pwd | grep -qx "/home/rws/work/project"'
run_client "set +e; bin/rws --device e2e run -- sh -lc 'printf \"out-line\\\\n\"; printf \"err-line\\\\n\" >&2; exit 42' > /tmp/rws-run-fail.out 2>/tmp/rws-run-fail.err; rc=\$?; set -e; test \"\$rc\" -eq 42; grep -qx out-line /tmp/rws-run-fail.out; grep -qx err-line /tmp/rws-run-fail.err"
run_client 'printf "pwd\nexit\n" | bin/rws --device e2e sh | grep -qx "/home/rws/work/project"'
run_client 'bin/rws --device e2e s > /tmp/rws-status.out && grep -qx "== remote ==" /tmp/rws-status.out && grep -qx "== sessions ==" /tmp/rws-status.out && grep -qx "== git ==" /tmp/rws-status.out'
run_client 'bin/rws --device e2e sessions --json | jq -e -f /tmp/rws-sessions-schema.jq >/dev/null'
run_client 'bin/rws --device e2e sessions --json | jq -e ".sessions == []" >/dev/null'
run_client 'bin/rws --device e2e sessions --json | grep -q "rws-verify" && exit 1 || exit 0'
run_client 'bin/rws --device e2e attach missing >/tmp/rws-attach-missing.out 2>/tmp/rws-attach-missing.err && exit 1 || { grep -q "session not found: missing" /tmp/rws-attach-missing.err && grep -q "Run: rws new missing" /tmp/rws-attach-missing.err; }'
run_client 'bin/rws --device e2e session create managed | grep -qx "created session: managed"'
run_client 'bin/rws --device e2e session list --json | jq -e -f /tmp/rws-sessions-schema.jq >/dev/null'
run_client 'bin/rws --device e2e session list --json | jq -e ".sessions | map(.name) | index(\"managed\")" >/dev/null'
run_client 'bin/rws --device e2e session get managed | jq -e ".name == \"managed\"" >/dev/null'
run_client 'bin/rws --device e2e session update managed --detach'
run_client 'bin/rws --device e2e session delete managed'
run_client 'bin/rws --device e2e session list --json | jq -e ".sessions | map(.name) | index(\"managed\") == null" >/dev/null'
run_client "bin/rws --device e2e session create mkdirsession --cwd '~/work/session-created/nested' | grep -qx 'created session: mkdirsession'"
podman exec "$SERVER" bash -lc 'test -d /home/rws/work/session-created/nested'
run_client 'bin/rws --device e2e session delete mkdirsession'
coding_recovery_log="$TMP_DIR/coding-recovery.out"
run_client_coding_session_recovery 2>&1 | tr -d '\r' | tee "$coding_recovery_log"
grep -q "__rws_coding_restore_detached__" "$coding_recovery_log"
grep -q "__rws_coding_live_reattach_verified__" "$coding_recovery_log"
grep -q "__rws_coding_server_restart_verified__" "$coding_recovery_log"
grep -q "__rws_coding_session_recovery_verified__" "$coding_recovery_log"
compact_prompt_output=$(run_client_compact_prompt_session | tr -d '\r') || {
  printf '%s\n' "$compact_prompt_output"
  exit 1
}
printf '%s\n' "$compact_prompt_output"
printf '%s\n' "$compact_prompt_output" | grep -q "__rws_compact_prompt_verified__"
run_client 'bin/rws --device e2e k promptcheck >/dev/null 2>&1 || true'
bg_compact_prompt_output=$(run_client_background_compact_prompt_session | tr -d '\r') || {
  printf '%s\n' "$bg_compact_prompt_output"
  exit 1
}
printf '%s\n' "$bg_compact_prompt_output"
printf '%s\n' "$bg_compact_prompt_output" | grep -q "__rws_bg_compact_prompt_verified__"
run_client 'bin/rws --device e2e k bgprompt >/dev/null 2>&1 || true'
run_client 'bin/rws --device e2e bg'
run_client 'bin/rws --device e2e ls --json | jq -e -f /tmp/rws-sessions-schema.jq >/dev/null'
run_client 'bin/rws --device e2e ls --json | jq -e ".sessions | map(.name) | index(\"e2e\")" >/dev/null'
default_attach_output=$(run_client_default_attach | tr -d '\r') || {
  printf '%s\n' "$default_attach_output"
  exit 1
}
printf '%s\n' "$default_attach_output"
printf '%s\n' "$default_attach_output" | grep -q "__rws_default_attach_detached__"
new_session_output=$(run_client_new_session_attach | tr -d '\r') || {
  printf '%s\n' "$new_session_output"
  exit 1
}
printf '%s\n' "$new_session_output"
printf '%s\n' "$new_session_output" | grep -q "__rws_new_session_created__"
printf '%s\n' "$new_session_output" | grep -q "__rws_new_session_detached__"
pick_cwd_output=$(run_client_pick_cwd_new_session | tr -d '\r') || {
  printf '%s\n' "$pick_cwd_output"
  exit 1
}
printf '%s\n' "$pick_cwd_output"
printf '%s\n' "$pick_cwd_output" | grep -qx "__rws_pick_cwd_created__"
printf '%s\n' "$pick_cwd_output" | grep -qx "__rws_pick_cwd_detached__"
force_output=$(run_client_force_attach | tr -d '\r') || {
  printf '%s\n' "$force_output"
  exit 1
}
printf '%s\n' "$force_output"
printf '%s\n' "$force_output" | grep -q "__rws_force_attached__"
printf '%s\n' "$force_output" | grep -q "__rws_force_detached__"
interrupt_output=$(run_client_interrupted_attach | tr -d '\r') || {
  printf '%s\n' "$interrupt_output"
  exit 1
}
printf '%s\n' "$interrupt_output"
printf '%s\n' "$interrupt_output" | grep -q "__rws_interrupted_attach_closed__"
recover_output=$(run_client_recover_after_dropped_attach | tr -d '\r') || {
  printf '%s\n' "$recover_output"
  exit 1
}
printf '%s\n' "$recover_output"
printf '%s\n' "$recover_output" | grep -q "__rws_dropped_attach_closed__"
printf '%s\n' "$recover_output" | grep -q "__rws_recover_force_closed__"
printf '%s\n' "$recover_output" | grep -q "__rws_recovered_same_session__"
run_client 'bin/rws --device e2e d e2e'
run_client 'bin/rws --device e2e d review'
run_client 'bin/rws --device e2e d picked'
run_client 'bin/rws --device e2e d recover'
run_client 'bin/rws --device e2e ls --json | jq -e -f /tmp/rws-sessions-schema.jq >/dev/null'
run_client 'bin/rws --device e2e ls --json | jq -e ".sessions | map(.name) | index(\"e2e\")" >/dev/null'
run_client 'bin/rws --device e2e k'
run_client 'bin/rws --device e2e k review'
run_client 'bin/rws --device e2e k picked'
run_client 'bin/rws --device e2e k recover'
run_client 'bin/rws --device e2e ls --json | jq -e -f /tmp/rws-sessions-schema.jq >/dev/null'
run_client 'bin/rws --device e2e ls --json | jq -e ".sessions == []" >/dev/null'
password_output=$(run_client_password_setup | tr -d '\r') || {
  printf '%s\n' "$password_output"
  exit 1
}
printf '%s\n' "$password_output"
printf '%s\n' "$password_output" | grep -Fq "[1/12] Collecting device and SSH target"
printf '%s\n' "$password_output" | grep -Fq "[4/12] Collecting device prompt settings"
printf '%s\n' "$password_output" | grep -Fq "[6/12] Reviewing device changes"
printf '%s\n' "$password_output" | grep -q "Setup will verify or change device state"
printf '%s\n' "$password_output" | grep -q "selected remote cwd: /home/rws/work/project"
printf '%s\n' "$password_output" | grep -Fq "[7/12] Writing local config and SSH key setup"
printf '%s\n' "$password_output" | grep -Fq "[8/12] Preparing remote dependencies"
printf '%s\n' "$password_output" | grep -q "rws: checking remote shpool 0.9.8"
printf '%s\n' "$password_output" | grep -Fq "[9/12] Configuring compact prompt"
printf '%s\n' "$password_output" | grep -Fq "[10/12] Verifying saved device"
printf '%s\n' "$password_output" | grep -Fq "[11/12] Creating initial session password"
printf '%s\n' "$password_output" | grep -Fq "[12/12] Setup complete"
printf '%s\n' "$password_output" | grep -q "__rws_password_setup_verified__"
printf '%s\n' "$password_output" | grep -q "__rws_password_setup_complete__"
hostkey_output=$(run_client_hostkey_setup | tr -d '\r') || {
  printf '%s\n' "$hostkey_output"
  exit 1
}
printf '%s\n' "$hostkey_output"
printf '%s\n' "$hostkey_output" | grep -Fq "[1/12] Collecting device and SSH target"
printf '%s\n' "$hostkey_output" | grep -q "selected remote cwd: /home/rws/work/project"
printf '%s\n' "$hostkey_output" | grep -Fq "[8/12] Preparing remote dependencies"
printf '%s\n' "$hostkey_output" | grep -q "rws: checking remote shpool 0.9.8"
printf '%s\n' "$hostkey_output" | grep -Fq "[10/12] Verifying saved device"
printf '%s\n' "$hostkey_output" | grep -Fq "[11/12] Creating initial session hostkey"
printf '%s\n' "$hostkey_output" | grep -Fq "[12/12] Setup complete"
printf '%s\n' "$hostkey_output" | grep -q "__rws_hostkey_setup_verified__"
printf '%s\n' "$hostkey_output" | grep -q "__rws_hostkey_setup_complete__"
run_client_skip_auth_setup

run_client "bin/rws setup --device e2e --host rws@$SERVER --cwd '~/work/project' --session e2e --no-create-session --key-mode create --identity-file '~/.ssh/rws_e2e' --install-key --bootstrap-identity '~/.ssh/bootstrap' --prompt-mode compact --prompt-label e2e --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null --yes > /tmp/rws-repeat-setup.out 2>&1"
run_client 'grep -q "remote shpool: /home/rws/.cargo/bin/shpool" /tmp/rws-repeat-setup.out'
run_client 'grep -q "verification ok: connect, shpool" /tmp/rws-repeat-setup.out'
run_client 'grep -Eq "Installing shpool|Ignored package" /tmp/rws-repeat-setup.out; status=$?; if [ "$status" -eq 0 ]; then exit 1; elif [ "$status" -eq 1 ]; then exit 0; else exit "$status"; fi'
wait_for_authorized_key_count 1
run_client 'bin/rws devices | grep -qx e2e'

run_client "bin/rws setup --device oldkey --host rws@$SERVER --cwd '~/work/project' --session oldkey --no-create-session --key-mode existing --identity-file '~/.ssh/rws_e2e' --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null --yes > /tmp/rws-oldkey-setup.out 2>&1"
run_client 'grep -q "remote shpool: /home/rws/.cargo/bin/shpool" /tmp/rws-oldkey-setup.out'
run_client 'grep -q "verification ok: connect, shpool" /tmp/rws-oldkey-setup.out'
run_client 'grep -Eq "Installing shpool|Ignored package" /tmp/rws-oldkey-setup.out; status=$?; if [ "$status" -eq 0 ]; then exit 1; elif [ "$status" -eq 1 ]; then exit 0; else exit "$status"; fi'
run_client 'grep -qx "device=oldkey" ~/.config/rws/default.conf'
run_client 'bin/rws --device e2e doctor > /tmp/rws-e2e-after-oldkey-doctor.out && grep -qx "device=e2e" /tmp/rws-e2e-after-oldkey-doctor.out && grep -q "shpool=shpool 0.9.8" /tmp/rws-e2e-after-oldkey-doctor.out'
run_client 'bin/rws --device oldkey c > /tmp/rws-oldkey-check.out && grep -q "host=" /tmp/rws-oldkey-check.out'
run_client 'bin/rws devices | grep -qx oldkey'
run_client 'bin/rws device list | grep -qx oldkey'
run_client 'bin/rws remove oldkey | grep -q "removed oldkey; default device is now e2e"'
run_client 'grep -qx "device=e2e" ~/.config/rws/default.conf'
run_client 'bin/rws devices | grep -qx e2e'
run_client 'bin/rws devices | grep -qx oldkey && exit 1 || exit 0'
run_client 'bin/rws device remove e2e | grep -q "removed e2e; no devices remain"'
run_client 'test ! -e ~/.config/rws/default.conf'
run_client 'bin/rws c >/tmp/rws-after-remove.out 2>/tmp/rws-after-remove.err && exit 1 || grep -q "Run: rws setup" /tmp/rws-after-remove.err'

printf 'podman e2e ok\n'
