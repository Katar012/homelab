#!/usr/bin/env bash
# Run on the Debian server: sudo ./service-sftpgo.sh install|start|stop|restart|status|logs
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HDD_MOUNT='/mnt/homelab-hdd'
HDD_LABEL='homelab-hdd'
UNIT='homelab-sftpgo.service'
UNIT_FILE="/etc/systemd/system/$UNIT"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

[[ $EUID -eq 0 ]] || fail 'Run this script with sudo.'
for cmd in docker findmnt blkid openssl ip systemctl systemd-escape; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Missing command: $cmd"
done
docker compose version >/dev/null 2>&1 || fail 'Docker Compose plugin is not installed.'
[[ -f "$PROJECT_DIR/compose.yaml" ]] || fail 'compose.yaml is missing.'

check_hdd() {
  local source fstype uuid label expected
  source="$(findmnt -rn -M "$HDD_MOUNT" -o SOURCE || true)"
  [[ -n "$source" ]] || fail "$HDD_MOUNT is not mounted. Run setup-hdd.sh from homelab/setup/."
  source="${source%%\[*}"
  [[ -b "$source" ]] || fail "Unexpected HDD mount source: $source"
  fstype="$(findmnt -rn -M "$HDD_MOUNT" -o FSTYPE)"
  uuid="$(blkid -s UUID -o value "$source")"
  label="$(blkid -s LABEL -o value "$source")"
  [[ "$fstype" == ext4 && "$label" == "$HDD_LABEL" && -n "$uuid" ]] || \
    fail "Expected mounted ext4 disk labeled $HDD_LABEL."
  expected="$(findmnt --fstab -rn -M "$HDD_MOUNT" -o SOURCE || true)"
  [[ "$expected" == "UUID=$uuid" ]] || fail "Mounted HDD UUID does not match /etc/fstab ($expected)."
  printf 'HDD verified: %s, UUID %s\n' "$source" "$uuid"
}

get_lan_ip() {
  local ip_addr
  # `ip route get` consults routing locally; it does not send traffic.
  ip_addr="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}' || true)"
  [[ "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
    fail 'Unable to identify primary IPv4 address. Check the default network route.'
  printf '%s' "$ip_addr"
}

prepare_dirs() {
  # SFTPGo's official Docker image normally runs with UID/GID 1000.
  install -d -o 1000 -g 1000 -m 0750 "$PROJECT_DIR/state" "$PROJECT_DIR/config"
  install -d -o 1000 -g 1000 -m 0750 "$HDD_MOUNT/sftpgo-data"
  chown 1000:1000 "$PROJECT_DIR/state" "$PROJECT_DIR/config" "$HDD_MOUNT/sftpgo-data"
}

prepare_https_cert() {
  local lan_ip="$1" dir="$PROJECT_DIR/config/certs" cert key
  cert="$dir/webclient.crt"
  key="$dir/webclient.key"
  install -d -o 1000 -g 1000 -m 0750 "$dir"
  if [[ -f "$cert" && -f "$key" ]]; then
    # Fail explicitly if a changed IP makes the old certificate unsuitable.
    if ! openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null | grep -Fq "IP Address:$lan_ip"; then
      fail "Existing HTTPS certificate does not cover $lan_ip. Back up config/certs and renew its certificate deliberately."
    fi
    return
  fi
  [[ ! -e "$cert" && ! -e "$key" ]] || fail 'Only one HTTPS certificate file exists. Refusing to overwrite it.'
  info "Generating HTTPS certificate for $lan_ip"
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 \
    -keyout "$key" -out "$cert" \
    -subj "/CN=$lan_ip" -addext "subjectAltName=IP:$lan_ip" >/dev/null 2>&1
  chown 1000:1000 "$cert" "$key"
  chmod 0644 "$cert"
  chmod 0600 "$key"
}

write_env() {
  local lan_ip="$1"
  # Use a generated file so every Compose command, including manual ones,
  # selects the same host IPv4 until the next managed start.
  printf 'LAN_IP=%s\n' "$lan_ip" > "$PROJECT_DIR/.env"
  chmod 0644 "$PROJECT_DIR/.env"
}

compose() { docker compose --project-directory "$PROJECT_DIR" -f "$PROJECT_DIR/compose.yaml" "$@"; }

start_project() {
  local lan_ip container_id
  check_hdd
  lan_ip="$(get_lan_ip)"
  prepare_dirs
  prepare_https_cert "$lan_ip"
  write_env "$lan_ip"
  compose config --quiet
  info "Starting SFTPGo on $lan_ip"
  compose up -d
  container_id="$(compose ps -q sftpgo)"
  [[ -n "$container_id" ]] || fail 'Compose did not create an SFTPGo container.'
  # Catch immediate exits (e.g. a configuration or TLS error).
  sleep 2
  if [[ "$(docker inspect -f '{{.State.Running}}' "$container_id")" != true ]]; then
    compose logs --tail=80 >&2 || true
    fail 'SFTPGo container exited during startup.'
  fi
  compose ps
}

install_unit() {
  local mount_unit
  check_hdd
  # Fail before creating a unit when the initial service configuration is unusable.
  prepare_dirs
  local lan_ip
  lan_ip="$(get_lan_ip)"
  prepare_https_cert "$lan_ip"
  write_env "$lan_ip"
  compose config --quiet
  [[ "$PROJECT_DIR" != *$'\n'* && "$PROJECT_DIR" != *' '* ]] || fail 'Project path cannot contain spaces/newlines.'
  mount_unit="$(systemd-escape --path --suffix=mount "$HDD_MOUNT")"
  cat > "$UNIT_FILE" <<UNITFILE
[Unit]
Description=Homelab SFTPGo Docker Compose
Requires=docker.service
After=docker.service $mount_unit
RequiresMountsFor=$HDD_MOUNT
BindsTo=$mount_unit

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR
ExecStart=/bin/bash $PROJECT_DIR/service-sftpgo.sh start
ExecStop=/bin/bash $PROJECT_DIR/service-sftpgo.sh stop
TimeoutStartSec=180
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
UNITFILE
  systemctl daemon-reload
  systemctl enable "$UNIT"
  # A previous successful oneshot unit stays "active (exited)" even if the
  # container was removed. Restart explicitly; enable --now would skip ExecStart.
  systemctl restart "$UNIT" || {
    systemctl --no-pager --full status "$UNIT" >&2 || true
    journalctl -u "$UNIT" -n 50 --no-pager >&2 || true
    fail 'systemd could not start SFTPGo; see logs above.'
  }
  info 'SFTPGo service installed and started'
  compose ps
}

case "${1:-}" in
  install) install_unit ;;
  start) start_project ;;
  restart) systemctl restart "$UNIT"; compose ps ;;
  stop) compose down ;;
  status) systemctl --no-pager --full status "$UNIT" || true; compose ps ;;
  logs) compose logs -f --tail=100 ;;
  *) printf 'Usage: sudo %s {install|start|stop|restart|status|logs}\n' "${0##*/}" >&2; exit 2 ;;
esac
