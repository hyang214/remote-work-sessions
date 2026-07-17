#!/usr/bin/env bash
set -euo pipefail

mkdir -p /home/rws/.ssh /home/rws/work/project
touch /home/rws/.ssh/authorized_keys

if [[ -f /bootstrap/id_ed25519.pub ]]; then
  bootstrap_key=$(cat /bootstrap/id_ed25519.pub)
  grep -qxF "$bootstrap_key" /home/rws/.ssh/authorized_keys \
    || printf '%s\n' "$bootstrap_key" >> /home/rws/.ssh/authorized_keys
else
  echo "missing /bootstrap/id_ed25519.pub" >&2
  exit 2
fi

cat >/etc/ssh/sshd_config <<'EOF'
Port 22
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PerSourcePenalties no
MaxStartups 100:30:200
Subsystem sftp /usr/lib/ssh/sftp-server
EOF

chown -R rws:rws /home/rws
chmod 700 /home/rws/.ssh
chmod 600 /home/rws/.ssh/authorized_keys

exec /usr/sbin/sshd -D -e
