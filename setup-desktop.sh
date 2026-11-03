#!/usr/bin/env bash
# Este script configura un Desktop Linux para que funcione como nodo de "control" en este mini-homelab
# Correr como usuario regular con chmod +x setup-desktop.sh y ./setup-desktop.sh

# Este mini script homelab asume que el servidor, cuyo sistema operativo tambien es Linux, tiene como ip 192.168.1.19 y como usuario por defecto "juan"

# Funciones principales:
# 1. Verificar dependencias de OpenSSH.
# 2. Crear y proteger el directorio ~/.ssh.
# 3. Generar o reutilizar un par de claves SSH.
# 4. Configurar el alias del servidor en ~/.ssh/config.
# 5. Copiar la clave pública al servidor remoto.
# 6. Verificar la autenticación mediante clave pública.
#
# IMPORTANTE: Ejecutar como usuario normal, sin sudo.

# Detener la ejecución ante errores, variables no definidas
set -Eeuo pipefail

# ------------------------------------------------------------
# 1. VARIABLES
# ------------------------------------------------------------

# Permite personalizar los datos del servidor mediante variables de entorno. Si no se definen, utiliza los valores predeterminados.

SERVER_ALIAS="${SERVER_ALIAS:-homelab}"
SERVER_HOST="${SERVER_HOST:-192.168.1.19}"
SERVER_USER="${SERVER_USER:-juan}"
SERVER_PORT="${SERVER_PORT:-22}"

# Rutas locales de las claves y archivos de configuración SSH.
KEY_PATH="${HOME}/.ssh/homelab_ed25519"
SSH_DIR="${HOME}/.ssh"
CONFIG_FILE="${SSH_DIR}/config"

# Marcadores para identificar el bloque administrado por este script dentro del archivo ~/.ssh/config.
BEGIN_MARKER="# BEGIN HOMELAB MANAGED: ${SERVER_ALIAS}"
END_MARKER="# END HOMELAB MANAGED: ${SERVER_ALIAS}"

# ------------------------------------------------------------
# 2. FUNCIONES AUXILIARES
# ------------------------------------------------------------

# Mostrar mensajes informativos.
info() {
  printf '[INFO] %s\n' "$*"
}

# Mostrar un mensaje de error y finalizar la ejecucion.
fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

# ------------------------------------------------------------
# 3. VALIDACIONES
# ------------------------------------------------------------

# Evitar la ejecución con sudo o root
[[ ${EUID} -ne 0 ]] || fail \
  'Ejecuta este script como usuario normal, sin sudo'

# Validar que el alias unicamente contenga caracteres regulares
[[ ${SERVER_ALIAS} =~ ^[A-Za-z0-9_-]+$ ]] || fail \
  'SERVER_ALIAS solo puede contener letras, números, guiones y guiones bajos'

# Validar el nombre del usuario remoto
[[ ${SERVER_USER} =~ ^[A-Za-z_][A-Za-z0-9_-]*\$?$ ]] || fail \
  'SERVER_USER contiene caracteres no permitidos'

# Verificar que el puerto SSH esté dentro del rango valido
[[ ${SERVER_PORT} =~ ^[0-9]+$ ]] &&
  ((10#${SERVER_PORT} >= 1 && 10#${SERVER_PORT} <= 65535)) || fail \
  'SERVER_PORT debe estar entre 1 y 65535.'

# Comprobar que las herramientas de OpenSSH esten instaladas
for cmd in ssh ssh-keygen ssh-copy-id; do
  command -v "$cmd" >/dev/null 2>&1 || fail \
    "Instala $cmd. con : sudo apt install openssh-client"
done

# ------------------------------------------------------------
# 4. PREPARACIoN DEL DIRECTORIO SSH
# ------------------------------------------------------------

# Establecer permisos restrictivos para los archivos nuevos
umask 077

# Crear ~/.ssh si todavía no existe
mkdir -p "$SSH_DIR"

# Permitir que únicamente el propietario acceda al directorio
chmod 700 "$SSH_DIR"

# ------------------------------------------------------------
# 5. GENERACION O RECUPERACIÓN DE CLAVES SSH
# ------------------------------------------------------------

# Evitar conflictos si la ruta de la clave privada existe, pero no corresponde a un archivo regular
if [[ -e "$KEY_PATH" && ! -f "$KEY_PATH" ]]; then
  fail "La ruta de la clave existe, pero no es un archivo regular: $KEY_PATH"
fi

if [[ -f "$KEY_PATH" ]]; then

  # Reutilizar la clave privada cuando ya existe
  # Esto evita generar claves diferentes en cada ejecucion
  info "Utilizando la clave privada existente: $KEY_PATH"

  # La clave privada solo debe ser accesible por su propietario
  chmod 600 "$KEY_PATH"

  # Si falta la clave publica, recuperarla desde la privada
  if [[ ! -f "${KEY_PATH}.pub" ]]; then
    info 'No se encontro la clave pública. Intentando recuperarla desde la clave privada'

    # Puede solicitar contraseña de la clave privada
    ssh-keygen -y -f "$KEY_PATH" > "${KEY_PATH}.pub" || fail \
      'No fue posible recuperar la clave pública'
  fi

else

  # No sobrescribir una clave publica que haya quedado sin su clave privada correspondiente
  [[ ! -e "${KEY_PATH}.pub" ]] || fail \
    "Existe una clave publica sin clave privada: ${KEY_PATH}.pub. Resolver manualmente"

  # Generar un nuevo par de claves Ed25519
  # -t ed25519 : algoritmo criptografico utilizado
  # -a 100     : número de rondas KDF para proteger la clave
  # -f         : ubicación donde se guardarán las claves
  # -C         : comentario identificador de la clave
  info 'Generando una clave SSH Ed25519 (puedes establecer una frase de contraseña).'

  ssh-keygen \
    -t ed25519 \
    -a 100 \
    -f "$KEY_PATH" \
    -C 'desktop-homelab'

fi

# La clave publica puede ser legible por otros usuarios locales
chmod 644 "${KEY_PATH}.pub"

# ------------------------------------------------------------
# 6. VALIDACION DE LA CONFIGURACION SSH EXISTENTE
# ------------------------------------------------------------

# Evitar sobrescribir silenciosamente un bloque Host
# administrado manualmente por el usuario.
if [[ -f "$CONFIG_FILE" ]]; then

  # Proteger el archivo de configuracion SSH.
  chmod 600 "$CONFIG_FILE"

  # Comprobar si el script ya administra este alias.
  if grep -Fqx "$BEGIN_MARKER" "$CONFIG_FILE"; then

    # Verificar que el bloque administrado esté completo.
    grep -Fqx "$END_MARKER" "$CONFIG_FILE" || fail \
      "Falta el marcador de cierre en $CONFIG_FILE"

  elif awk -v target="$SERVER_ALIAS" '
      tolower($1)=="host" {
        for (i=2;i<=NF;i++) {
          if ($i==target) found=1
        }
      }
      END { exit !found }
    ' "$CONFIG_FILE"; then

    # Si el alias existe fuera del bloque administrado,
    # detener el proceso para evitar configuraciones duplicadas.
    fail "El Host $SERVER_ALIAS ya existe fuera del bloque administrado. Modifícalo o cámbiale el nombre manualmente."

  fi
fi

# ------------------------------------------------------------
# 7. CONSTRUCCION DEL BLOQUE SSH
# ------------------------------------------------------------

# Crear la configuración que se añadirá a ~/.ssh/config.
# Se utiliza un heredoc para conservar el formato SSH.
block=$(cat <<BLOCK
${BEGIN_MARKER}
Host ${SERVER_ALIAS}
    HostName ${SERVER_HOST}
    User ${SERVER_USER}
    Port ${SERVER_PORT}
    PubkeyAuthentication yes
    IdentityFile ${KEY_PATH}
    IdentitiesOnly yes
    PreferredAuthentications publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
${END_MARKER}
BLOCK
)

# ------------------------------------------------------------
# 8. ACTUALIZACION SEGURA DE ~/.ssh/config
# ------------------------------------------------------------

# Crear un archivo temporal dentro del directorio SSH.
tmp=$(mktemp "${SSH_DIR}/config.XXXXXX")

# Eliminar el archivo temporal al finalizar el script, incluso si ocurre un error durante la ejecución.
trap 'rm -f "$tmp"' EXIT

if [[ -f "$CONFIG_FILE" ]]; then

  # Copiar la configuracion existente, eliminando unicamente
  # el bloque administrado previamente por este script.
  # Así se conservan las configuraciones de otros servidores.
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0==begin {
      skipping=1
      next
    }

    $0==end && skipping {
      skipping=0
      next
    }

    !skipping {
      print
    }
  ' "$CONFIG_FILE" > "$tmp"

fi

# Añadir el bloque actualizado al archivo temporal.
printf '\n%s\n' "$block" >> "$tmp"

# Restringir los permisos del archivo temporal.
chmod 600 "$tmp"

# Validar la sintaxis antes de reemplazar la configuración real.
ssh -F "$tmp" -G "$SERVER_ALIAS" >/dev/null || fail \
  'La configuración SSH generada no es válida.'

# Reemplazar la configuración por la versión validada.
mv -f "$tmp" "$CONFIG_FILE"

info "Alias SSH configurado: ${SERVER_ALIAS} -> ${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}"

# ------------------------------------------------------------
# 9. INSTALACIÓN DE LA CLAVE PÚBLICA EN EL SERVIDOR
# ------------------------------------------------------------

info 'Comprobando si la clave pública ya está autorizada en el servidor...'

# Intentar una conexión sin solicitar contraseñas.
# Si funciona, la clave ya está autorizada y no es necesario
# copiarla nuevamente.
if ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=8 \
  "$SERVER_ALIAS" true 2>/dev/null; then

  info 'La autenticación mediante clave pública ya funciona.'
  info 'No es necesario copiar nuevamente la clave.'

else

  # Si la autenticación falla, intentar instalar la clave pública
  # en el archivo authorized_keys del usuario remoto.
  info "Instalando la clave pública en ${SERVER_USER}@${SERVER_HOST}."

  # Durante la configuración inicial puede ser necesario
  # ingresar una vez la contraseña del usuario del servidor.
  info 'Es posible que se solicite la contraseña del usuario del servidor.'

  # Habilitar temporalmente la autenticación por contraseña
  # para permitir que ssh-copy-id instale la clave pública.
  #
  # Estas opciones solo afectan a esta operación y no modifican
  # permanentemente la configuración SSH del cliente.
  ssh-copy-id \
    -i "${KEY_PATH}.pub" \
    -p "$SERVER_PORT" \
    -o PreferredAuthentications=publickey,password,keyboard-interactive \
    -o PasswordAuthentication=yes \
    -o KbdInteractiveAuthentication=yes \
    "${SERVER_USER}@${SERVER_HOST}" || fail \
    'No se pudo instalar la clave. Verifica la cuenta remota, la configuración SSH y la conexión de red.'

fi

# ------------------------------------------------------------
# 10. VERIFICACIÓN FINAL DE LA CONEXIÓN SSH
# ------------------------------------------------------------

info 'Verificando la autenticación mediante clave pública...'

# Realizar una conexión de prueba utilizando el alias SSH.
# BatchMode=yes evita solicitar contraseñas interactivamente.
if ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=8 \
  "$SERVER_ALIAS" true; then

  printf '\n[SUCCESS] La autenticación SSH mediante clave pública funciona.\n'
  printf '[SUCCESS] Puedes conectarte utilizando: ssh %s\n' "$SERVER_ALIAS"

else

  # Si la clave privada tiene una frase de contraseña,
  # podría ser necesario cargarla previamente en ssh-agent.
  printf '\n[WARNING] Falló la verificación automática de SSH.\n' >&2
  printf '[WARNING] Si tu clave tiene una frase de contraseña, ejecuta: ssh-add %s\n' "$KEY_PATH" >&2
  printf '[WARNING] En caso contrario, revisa authorized_keys, sshd y los permisos del servidor.\n' >&2

  exit 1
fi

