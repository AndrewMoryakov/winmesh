#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sudo ./install-openssh-server.sh --allowed-cidr CIDR [--allowed-cidr CIDR ...]

Installs and starts OpenSSH server, then restricts TCP/22 in UFW or firewalld
when one of those firewalls is active: allows the given CIDRs and removes any
broad allowance for TCP/22 that would keep the port open to everyone. The
script supports apt, dnf, yum, and pacman. It does not create users or
authorized_keys files.
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
  # -S, not -Sy: refreshing the databases without a full -Syu leaves a partial
  # upgrade, which Arch does not support.
  pacman -S --needed --noconfirm openssh
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

# Arch and Fedora create host keys only when the service first starts
# (sshdgenkeys / sshd-keygen), and `sshd -t` fails without them. -A creates
# just the missing ones, so this is a no-op where the package already did it.
ssh-keygen -A
sshd -t
systemctl enable --now "$ssh_service"

# Allow rules add up: a pre-existing broad allowance for TCP/22 (UFW's
# "OpenSSH", firewalld's "ssh" service in the default zone) would keep the
# port open to everyone next to the narrow rules. So add the narrow rules
# first, then remove the broad ones. Established sessions survive the change.
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  for cidr in "${allowed_cidrs[@]}"; do
    ufw allow from "$cidr" to any port 22 proto tcp
  done
  for spec in OpenSSH ssh 22/tcp 22; do
    # Only rules open to Anywhere; the from-CIDR rules above list a source.
    if ufw status | grep -Eq "^${spec}( \(v6\))?[[:space:]]+ALLOW( IN)?[[:space:]]+Anywhere"; then
      ufw delete allow "$spec"
      echo "Removed the broad UFW rule '$spec'."
    fi
  done
elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
  # Every zone that can receive traffic: the default one plus the active ones.
  zones=$( { firewall-cmd --get-default-zone; { firewall-cmd --get-active-zones || true; } | awk '/^[^[:space:]]/ { print $1 }'; } | sort -u)
  for zone in $zones; do
    for cidr in "${allowed_cidrs[@]}"; do
      family=ipv4
      [[ $cidr == *:* ]] && family=ipv6
      firewall-cmd --permanent --zone="$zone" --add-rich-rule="rule family=$family source address=$cidr port protocol=tcp port=22 accept"
    done
    if firewall-cmd --permanent --zone="$zone" --query-service=ssh >/dev/null; then
      firewall-cmd --permanent --zone="$zone" --remove-service=ssh
      echo "Removed the broad 'ssh' service from firewalld zone '$zone'."
    fi
    if firewall-cmd --permanent --zone="$zone" --query-port=22/tcp >/dev/null; then
      firewall-cmd --permanent --zone="$zone" --remove-port=22/tcp
      echo "Removed the broad port 22/tcp from firewalld zone '$zone'."
    fi
  done
  firewall-cmd --reload
else
  echo 'No active UFW or firewalld detected; review the host firewall for TCP/22.' >&2
fi

systemctl is-active --quiet "$ssh_service"
ss -ltn | awk '$4 ~ /:22$/ { found=1 } END { exit !found }'
printf 'OpenSSH is active; TCP/22 listens; permitted source CIDRs: %s\n' "${allowed_cidrs[*]}"
