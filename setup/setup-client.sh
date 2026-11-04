#!/usr/bin/env bash

# EXECUTE THIS ON CLIENT

set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo 'Run this as your regular login user, without sudo.' >&2
    exit 1
fi

CLIENT_USER="$(id -un)"
CLIENT_HOSTNAME="$(hostname -s)"
CLIENT_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
[[ -n "$CLIENT_IP" ]] || { echo 'Could not determine the primary IPv4 address.' >&2; exit 1; }

echo "Client: $CLIENT_HOSTNAME | user: $CLIENT_USER | IPv4: $CLIENT_IP"
echo 'The server must already allow this client IP through its SSH firewall.'
read -r -p 'Server IP address or resolvable hostname: ' SERVER_HOST
[[ -n "$SERVER_HOST" && "$SERVER_HOST" != *[[:space:]]* && "$SERVER_HOST" != -* ]] || { echo 'Invalid server address.' >&2; exit 1; }
read -r -p 'Server SSH username: ' SERVER_USER
[[ "$SERVER_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || { echo 'Invalid SSH username.' >&2; exit 1; }

SSH_DIR="$HOME/.ssh"
KEY="$SSH_DIR/homelab_ed25519"
CONFIG="$SSH_DIR/config"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
if [[ ! -f "$KEY" ]]; then
    ssh-keygen -t ed25519 -a 100 -f "$KEY" -C "${CLIENT_USER}@${CLIENT_HOSTNAME}-homelab"
fi
[[ -f "$KEY.pub" ]] || { echo "Missing public key: $KEY.pub" >&2; exit 1; }

# Bootstrap directly to the supplied server (existing Host homelab settings
# may disable password login, so do not use the alias for ssh-copy-id).
ssh-copy-id -i "$KEY.pub" -p 22 "${SERVER_USER}@${SERVER_HOST}"

# Replace only the exact 'Host homelab' stanza in an existing SSH config.
# Keep all other SSH aliases and create a backup before editing.
if [[ -f "$CONFIG" ]]; then
    cp -p "$CONFIG" "${CONFIG}.backup-homelab"
    TEMP_CONFIG="$(mktemp "$SSH_DIR/config.XXXXXX")"
    awk '
        /^[[:space:]]*Host[[:space:]]+homelab[[:space:]]*($|#)/ { skip=1; next }
        /^[[:space:]]*(Host|Match)[[:space:]]/ { skip=0 }
        !skip { print }
    ' "$CONFIG" > "$TEMP_CONFIG"
    mv "$TEMP_CONFIG" "$CONFIG"
fi
cat >> "$CONFIG" <<SSH_CONFIG

Host homelab
    HostName $SERVER_HOST
    User $SERVER_USER
    PubkeyAuthentication yes
    IdentityFile ~/.ssh/homelab_ed25519
    IdentitiesOnly yes
    PreferredAuthentications publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
SSH_CONFIG
chmod 600 "$CONFIG"

echo 'Client setup complete. Connect with: ssh homelab'
echo "Client IPv4: $CLIENT_IP | server: ${SERVER_USER}@${SERVER_HOST}"
