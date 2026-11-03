#!/usr/bin/env bash

# Este script configura un Laptop Linux para que funcione como nodo servidor en este mini-homelab
# Correr como usuario regular con chmod +x setup-laptop.sh y ./setup-laptop.sh

# Este mini script homelab asume que el servidor, cuyo sistema operativo tambien es Linux, tiene como ip 192.168.1.19 y como usuario por defecto "juan"

# Ejecutar desde una cuenta con permisos sudo desde la consola física de la laptop durante la instalación.

# Funcion principal:
# 1. Prepara la laptop para recibir conexiones SSH desde el escritorio, sin desactivar el acceso por contraseña.

# Opciones mediante variables de entorno:
#   SSH_USER=juan            Usuario que recibirá las claves.
#   SSH_PORT=22             Puerto del servidor SSH.
#   PUBLIC_KEY_FILE=ruta    Clave pública opcional para autorizar.
#   RUN_FULL_UPGRADE=1      Actualizar paquetes (valor por defecto).
#   ENABLE_UFW=0           No activar UFW automáticamente.

# EJEMPLO: ENABLE_UFW=1 ./setup-laptop.sh para activar el firewall despues de preparar Laptop

set -Eeuo pipefail

SSH_USER="${SSH_USER:-juan}"
SSH_PORT="${SSH_PORT:-22}"
PUBLIC_KEY_FILE="${PUBLIC_KEY_FILE:-}"
RUN_FULL_UPGRADE="${RUN_FULL_UPGRADE:-1}"
ENABLE_UFW="${ENABLE_UFW:-0}"

info() { printf '[INFO] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# 1. Validaciones y herramientas administrativas.
[[ -r /etc/os-release ]] || fail 'No se encontró /etc/os-release.'
# shellcheck source=/dev/null
. /etc/os-release
[[ "${ID:-}" == debian && "${VERSION_ID:-}" == 13 ]] || fail 'Este script está diseñado para Debian 13.'
[[ "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*\$?$ ]] || fail 'SSH_USER no es válido.'
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || fail 'SSH_PORT debe ser numérico.'
(( 10#$SSH_PORT >= 1 && 10#$SSH_PORT <= 65535 )) || fail 'SSH_PORT debe estar entre 1 y 65535.'
[[ "$RUN_FULL_UPGRADE" =~ ^[01]$ && "$ENABLE_UFW" =~ ^[01]$ ]] || fail 'RUN_FULL_UPGRADE y ENABLE_UFW deben ser 0 o 1.'
command -v sudo >/dev/null 2>&1 || fail 'Falta sudo.'
sudo -v || fail 'La cuenta necesita permisos de sudo.'
getent passwd "$SSH_USER" >/dev/null || fail "El usuario $SSH_USER no existe."
USER_HOME="$(getent passwd "$SSH_USER" | cut -d: -f6)"
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || fail 'El directorio personal del usuario no existe.'

# 2. Actualización del sistema e instalación de OpenSSH y UFW.
info 'Actualizando los índices de paquetes...'
sudo apt-get update
if [[ "$RUN_FULL_UPGRADE" == 1 ]]; then
  info 'Ejecutando la actualización completa de paquetes...'
  sudo apt-get full-upgrade -y
fi
info 'Instalando OpenSSH Server y UFW...'
sudo apt-get install -y openssh-server ufw

# 3. Activación del servicio de OpenSSH.
# Este script no cambia el puerto de sshd. SSH_PORT debe
# coincidir con el puerto real ya configurado en sshd.
info 'Activando e iniciando el servicio SSH...'
sudo systemctl enable --now ssh
sudo systemctl is-active --quiet ssh || fail 'El servicio SSH no está activo.'

# 4. Visualización de la huella de identidad del servidor.
# Comparar esta huella con la que muestre el escritorio al
# establecer su primera conexión SSH.
info 'Fingerprint de la clave ED25519 del servidor:'
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub

# 5. Preparación de las claves autorizadas del usuario.
# install -d crea el directorio con propietario y permisos
# correctos. No elimina las claves autorizadas existentes.
info "Preparando el acceso SSH del usuario $SSH_USER..."
sudo install -d -m 700 -o "$SSH_USER" -g "$(id -gn "$SSH_USER")" "$USER_HOME/.ssh"
if ! sudo test -e "$USER_HOME/.ssh/authorized_keys"; then
  sudo install -m 600 -o "$SSH_USER" -g "$(id -gn "$SSH_USER")" /dev/null "$USER_HOME/.ssh/authorized_keys"
fi
sudo chown "$SSH_USER:$(id -gn "$SSH_USER")" "$USER_HOME/.ssh/authorized_keys"
sudo chmod 600 "$USER_HOME/.ssh/authorized_keys"

# Se puede proporcionar una clave pública ya disponible en la
# laptop. En el flujo habitual, setup-desktop.sh la enviará
# después mediante ssh-copy-id; por tanto es opcional.
if [[ -n "$PUBLIC_KEY_FILE" ]]; then
  [[ -f "$PUBLIC_KEY_FILE" && -r "$PUBLIC_KEY_FILE" ]] || fail 'PUBLIC_KEY_FILE no es un archivo legible.'
  KEY_LINE="$(tr -d '\r' < "$PUBLIC_KEY_FILE" | sed -n '/[^[:space:]]/p' | head -n 1)"
  [[ "$KEY_LINE" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^[:space:]]+)[[:space:]] ]] || fail 'El archivo no parece contener una clave pública SSH válida.'
  # Validar que OpenSSH puede interpretar la clave pública.
  ssh-keygen -lf "$PUBLIC_KEY_FILE" >/dev/null || fail 'Clave pública inválida.'
  if sudo grep -Fqx -- "$KEY_LINE" "$USER_HOME/.ssh/authorized_keys"; then
    info 'La clave pública ya está autorizada.'
  else
    printf '%s\n' "$KEY_LINE" | sudo tee -a "$USER_HOME/.ssh/authorized_keys" >/dev/null
    info 'Clave pública agregada a authorized_keys.'
  fi
fi

# 6. Regla de firewall. Se prepara ANTES de activar UFW.
# No se activa automáticamente para evitar cortar otras
# conexiones o servicios de la laptop sin revisión previa.
info "Permitiendo el puerto TCP $SSH_PORT en UFW..."
sudo ufw allow "${SSH_PORT}/tcp"
if [[ "$ENABLE_UFW" == 1 ]]; then
  info 'Activando UFW por solicitud explícita...'
  sudo ufw --force enable
else
  info 'UFW no se ha activado. Revísalo antes de ejecutar sudo ufw enable.'
fi

# 7. Estado final y siguientes pasos.
info 'Estado del servicio SSH:'
sudo systemctl --no-pager --full status ssh | head -n 12 || true
info 'Estado del firewall:'
sudo ufw status
printf '\n[OK] Preparación del servidor SSH finalizada.\n'
printf '[INFO] Cuenta remota: %s\n' "$SSH_USER"
printf '[INFO] Puerto previsto: %s (verifica que sshd lo esté utilizando)\n' "$SSH_PORT"
printf '[INFO] Desde el escritorio, ejecuta setup-desktop.sh y después: ssh homelab\n'
printf '[INFO] No desactives PasswordAuthentication hasta verificar el acceso con clave pública.\n'
