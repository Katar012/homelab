#!/usr/bin/env bash
# SFTPGo deployment/management for the Debian homelab laptop.
# Usage: sudo ./service-sftpgo.sh install|start|stop|status|logs
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HDD_MOUNT=/mnt/homelab-hdd
HDD_LABEL=homelab-hdd
UNIT_NAME=homelab-sftpgo.service
UNIT_FILE="/etc/systemd/system/$UNIT_NAME"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

[[ "${EUID}" -eq 0 ]] || fail "Run with sudo, for example: sudo ./service-sftpgo.sh install"
command -v docker >/dev/null || fail 'Docker is not installed; run setup-laptop.sh first.'
command -v findmnt >/dev/null || fail 'findmnt is required.'
command -v blkid >/dev/null || fail 'blkid is required.'

check_hdd() {
  local source fstype uuid label fstab_source
  # --mountpoint requires an exact mount, not its parent filesystem.
  source="$(findmnt -n -M "$HDD_MOUNT" -o SOURCE || true)"
  [[ -n "$source" ]] || fail "$HDD_MOUNT is not mounted. Check setup-homelab-hdd.sh."
  fstype="$(findmnt -n -M "$HDD_MOUNT" -o FSTYPE)"
  source="${source%%\[*}"
  [[ -b "$source" ]] || fail "Unexpected mount source $source"
  uuid="$(blkid -s UUID -o value "$source" || true)"
  label="$(blkid -s LABEL -o value "$source" || true)"
  [[ "$fstype" == ext4 && "$label" == "$HDD_LABEL" && -n "$uuid" ]] || \
    fail "Expected ext4 filesystem labeled $HDD_LABEL; found $fstype ($label)."
  # Match the UUID in /etc/fstab so another drive with the same label cannot be used.
  fstab_source="$(findmnt --fstab -n -M "$HDD_MOUNT" -o SOURCE || true)"
  [[ "$fstab_source" == "UUID=$uuid" ]] || \
    fail "Mounted UUID $uuid differs from fstab entry ($fstab_source)."
  printf 'Verified HDD: %s (UUID %s) at %s\n' "$source" "$uuid" "$HDD_MOUNT"
}

prepare_dirs() {
  local uid=1000 gid=1000
  [[ -f "$PROJECT_DIR/compose.yaml" ]] || fail "Missing $PROJECT_DIR/compose.yaml"
  # Do not recursively alter permissions of the existing HDD contents.
  install -d -m 0750 -o "$uid" -g "$gid" "$PROJECT_DIR/state" "$PROJECT_DIR/config"
  install -d -m 0750 -o "$uid" -g "$gid" "$HDD_MOUNT/sftpgo-data"
  # Existing directories might have been created by a different user.
  chown "$uid:$gid" "$PROJECT_DIR/state" "$PROJECT_DIR/config" "$HDD_MOUNT/sftpgo-data"
}

compose() { docker compose -f "$PROJECT_DIR/compose.yaml" "$@"; }

start_project() {
  check_hdd
  prepare_dirs
  compose config --quiet
  compose up -d
  compose ps
}

install_unit() {
  check_hdd
  prepare_dirs
  compose config --quiet
  command -v systemd-escape >/dev/null || fail 'systemd-escape is required.'
  local mount_unit
  mount_unit="$(systemd-escape --path --suffix=mount "$HDD_MOUNT")"
  # The resolved project directory is reused on every reboot; keep this folder on the SSD.
  [[ "$PROJECT_DIR" != *$'\n'* && "$PROJECT_DIR" != *' '* ]] || \
    fail 'Use a project directory without spaces or newlines.'
  cat > "$UNIT_FILE" <<UNIT
[Unit]
Description=Homelab SFTPGo (Docker Compose)
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
UNIT
  systemctl daemon-reload
  systemctl enable --now "$UNIT_NAME"
  systemctl --no-pager --full status "$UNIT_NAME" || true
}

case "${1:-}" in
  install)
    info 'Installing SFTPGo systemd/Compose service'
    install_unit
    info 'Installed. Service starts automatically after the HDD is mounted.'
    ;;
  start)
    info 'Verifying storage and starting SFTPGo'
    start_project
    ;;
  stop)
    info 'Stopping SFTPGo'
    compose down
    ;;
  status)
    systemctl --no-pager --full status "$UNIT_NAME" || true
    compose ps
    ;;
  logs)
    compose logs -f --tail=100
    ;;
  *)
    printf 'Usage: sudo %s {install|start|stop|status|logs}\n' "${0##*/}" >&2
    exit 2
    ;;
esac
