#!/usr/bin/env bash

# EXECUTE THIS ON SERVER

set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo 'Run this as your regular login user, without sudo.' >&2
    exit 1
fi

. /etc/os-release
[[ "$ID" == debian && "$VERSION_ID" == 13 ]] || { echo 'Debian 13 required.' >&2; exit 1; }

SETUP_USER="$(id -un)"
SERVER_HOSTNAME="$(hostname -s)"
SERVER_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
[[ -n "$SERVER_IP" ]] || { echo 'Could not determine the primary IPv4 address.' >&2; exit 1; }

echo "Server: $SERVER_HOSTNAME | user: $SETUP_USER | IPv4: $SERVER_IP"
echo 'A DHCP reservation/static LAN IP is recommended for both computers.'
read -r -p 'Enter the CLIENT IPv4 address to allow through the SSH firewall: ' CLIENT_IP
if ! [[ "$CLIENT_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || ! python3 - "$CLIENT_IP" <<'PY'
import ipaddress, sys
try:
    address = ipaddress.IPv4Address(sys.argv[1])
    assert not (address.is_multicast or address.is_unspecified or address.is_loopback)
except (ValueError, AssertionError):
    sys.exit(1)
PY
then
    echo 'Invalid client IPv4 address.' >&2
    exit 1
fi
printf 'Allow SSH ONLY from %s to %s:22?\n' "$CLIENT_IP" "$SERVER_IP"
read -r -p 'Type YES to continue: ' CONFIRM
[[ "$CONFIRM" == YES ]] || { echo 'Cancelled.'; exit 1; }

sudo -v
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y openssh-server ufw ca-certificates curl
sudo systemctl enable --now ssh
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from "$CLIENT_IP" to any port 22 proto tcp
sudo ufw --force enable

# Install Docker Engine and Compose from Docker's official Debian repository.
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<DOCKER_REPO
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
DOCKER_REPO
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$SETUP_USER"

sudo systemctl is-active ssh docker
sudo ufw status verbose
sudo docker --version
sudo docker compose version
printf '\nServer setup complete. SSH user: %s | server IP: %s\n' "$SETUP_USER" "$SERVER_IP"
echo 'Log out and back in to use docker without sudo.'
