#!/usr/bin/env bash

# ==========================================================
# HOMELAB - Hardening de OpenSSH (Debian 13)
# ==========================================================

set -Eeuo pipefail

SSH_USER="${SSH_USER:-juan}"
CONFIG="/etc/ssh/sshd_config.d/00-homelab.conf"

# 1. Verificar que exista una clave pública autorizada.
KEYS="/home/${SSH_USER}/.ssh/authorized_keys"

[[ -s "$KEYS" ]] || {
    echo "[ERROR] No hay claves SSH autorizadas para $SSH_USER."
    exit 1
}

# 2. Confirmar que SSH mediante clave pública ya funciona.
echo "[AVISO] Confirma que 'ssh homelab' funciona desde tu escritorio."
read -r -p "¿Ya verificaste la conexión? (si/no): " CONFIRM

[[ "$CONFIRM" == "si" ]] || exit 1

# 3. Crear configuración de seguridad independiente.
sudo tee "$CONFIG" > /dev/null <<EOF
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF

# 4. Validar configuración antes de aplicarla.
if ! sudo sshd -t; then
    echo "[ERROR] Configuración inválida. Revisa $CONFIG."
    exit 1
fi

# 5. Comprobar los valores efectivos.
SETTINGS=$(sudo sshd -T)
for OPTION in \
    "pubkeyauthentication yes" \
    "passwordauthentication no" \
    "kbdinteractiveauthentication no" \
    "permitrootlogin no"; do
    grep -qx "$OPTION" <<< "$SETTINGS" || {
        echo "[ERROR] No se aplicó: $OPTION"
        exit 1
    }
done

# 6. Recargar el servicio sin cerrar las sesiones activas.
sudo systemctl reload ssh

echo "[OK] Hardening SSH aplicado correctamente."
echo "[INFO] Verifica una conexión nueva: ssh homelab"

