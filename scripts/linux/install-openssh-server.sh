#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sudo ./install-openssh-server.sh --allowed-cidr CIDR [--allowed-cidr CIDR ...]

Installs and starts OpenSSH server, then restricts TCP/22 in UFW or firewalld
when one of those firewalls is active. The script supports apt, dnf, yum, and
pacman. It does not create users or authorized_keys files.
EOF
}

allowed_cidrs=()
while (($#)); do
  case "$1" in
    --allowed-cidr) allowed_cidrs+=("${2:?missing CIDR after --allowed-cidr}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if (( ${#allowed_cidrs[@]} == 0 )); then
  echo 'At least one --allowed-cidr is required; refusing to open SSH to every address.' >&2
  exit 2
fi
if (( EUID != 0 )); then
  echo 'Run this script with sudo or as root.' >&2
  exit 1
fi

if command -v apt-get >/dev/null; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
elif command -v dnf >/dev/null; then
  dnf install -y openssh-server
elif command -v yum >/dev/null; then
  yum install -y openssh-server
elif command -v pacman >/dev/null; then
  pacman -Sy --noconfirm openssh
else
  echo 'Unsupported package manager. Install openssh-server manually.' >&2
  exit 1
fi

if systemctl cat ssh.service >/dev/null 2>&1; then
  ssh_service=ssh
elif systemctl cat sshd.service >/dev/null 2>&1; then
  ssh_service=sshd
else
  echo 'Could not find an ssh.service or sshd.service unit.' >&2
  exit 1
fi

sshd -t
systemctl enable --now "$ssh_service"

if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  for cidr in "${allowed_cidrs[@]}"; do
    ufw allow from "$cidr" to any port 22 proto tcp
  done
elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
  for cidr in "${allowed_cidrs[@]}"; do
    firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$cidr port protocol=tcp port=22 accept"
  done
  firewall-cmd --reload
else
  echo 'No active UFW or firewalld detected; review the host firewall for TCP/22.' >&2
fi

systemctl is-active --quiet "$ssh_service"
ss -ltn | awk '$4 ~ /:22$/ { found=1 } END { exit !found }'
printf 'OpenSSH is active; TCP/22 listens; permitted source CIDRs: %s\n' "${allowed_cidrs[*]}"
