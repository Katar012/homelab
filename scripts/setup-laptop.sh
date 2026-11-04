#!/usr/bin/env bash

# EXECUTE THIS ON LAPTOP

set -euo pipefail

# Run on the Debian 13 laptop as juan, from its local terminal.
. /etc/os-release
[[ "$ID" == debian && "$VERSION_ID" == 13 ]] || { echo 'Debian 13 required.'; exit 1; }
sudo -v

# Update the host and enable SSH.
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y openssh-server ufw ca-certificates curl
sudo systemctl enable --now ssh
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub

# Allow SSH from the Desktop only, then enable the firewall.
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.5 to any port 22 proto tcp
sudo ufw --force enable

# Install Docker Engine and Compose from Docker's official Debian repository.
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

# Show the resulting service and firewall state.
sudo systemctl is-active ssh docker
sudo ufw status verbose
sudo docker --version
sudo docker compose version

echo 'Laptop setup complete, continue with Desktop setup'

