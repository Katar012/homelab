#!/usr/bin/env bash

# EXECUTE THIS ON DESKTOP

set -euo pipefail

SSH_DIR="$HOME/.ssh"
KEY="$SSH_DIR/homelab_ed25519"
CONFIG="$SSH_DIR/config"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Generate the key only if it doesn't exist.
if [[ ! -f "$KEY" ]]; then
    ssh-keygen -t ed25519 -a 100 -f "$KEY" -C "desktop-homelab"
fi

# Add the SSH alias only if it doesn't exist.
if [[ ! -f "$CONFIG" ]] || ! grep -Eq '^[[:space:]]*Host[[:space:]]+homelab([[:space:]]|$)' "$CONFIG"; then
    cat >> "$CONFIG" <<'HOST'

Host homelab
    HostName 192.168.1.19
    User juan
    PubkeyAuthentication yes
    IdentityFile ~/.ssh/homelab_ed25519
    IdentitiesOnly yes
    PreferredAuthentications publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
HOST
fi

chmod 600 "$CONFIG"

# Copy the public key to the laptop.
ssh-copy-id -i "$KEY.pub" -p 22 juan@192.168.1.19

echo 'Desktop setup complete. Connect with: ssh homelab'

