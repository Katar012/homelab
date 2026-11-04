#!/usr/bin/env bash

# EXECUTE THIS ON LAPTOP

set -euo pipefail

LABEL='homelab-hdd'
MOUNT_POINT='/mnt/homelab-hdd'
FSTAB='/etc/fstab'
OPTIONS='defaults,nofail,x-systemd.device-timeout=10s'

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

[[ $EUID -eq 0 ]] || fail 'Run with sudo: sudo bash setup-homelab-hdd.sh'
for tool in lsblk blkid findmnt mountpoint mount e2label awk grep cp mkdir systemctl; do
    command -v "$tool" >/dev/null 2>&1 || fail "Missing required command: $tool"
done

info 'Available disks and filesystems'
lsblk -o NAME,PATH,TYPE,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
printf '\nPaste the UUID of the EXISTING ext4 partition to use as %s.\n' "$LABEL"
printf 'Do not choose the Debian root partition. This script does not format anything.\n'
read -r -p 'Partition UUID: ' UUID
[[ $UUID =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || fail 'Invalid ext4 UUID format.'

# Use an exact filesystem UUID, never a potentially changing /dev/sdX name.
DEVICE=$(blkid -c /dev/null -t "UUID=$UUID" -o device | head -n 1)
[[ -n "$DEVICE" && -b "$DEVICE" ]] || fail 'No block device found for that UUID.'
[[ $(lsblk -dn -o TYPE "$DEVICE") == 'part' ]] || fail 'UUID must identify a partition, not an entire disk.'
FS_TYPE=$(blkid -c /dev/null -s TYPE -o value "$DEVICE")
[[ $FS_TYPE == 'ext4' ]] || fail "Expected ext4, found: $FS_TYPE"
CURRENT_LABEL=$(blkid -c /dev/null -s LABEL -o value "$DEVICE" || true)
CURRENT_MOUNT=$(findmnt -rn -S "$DEVICE" -o TARGET | head -n 1 || true)

if [[ -n $CURRENT_MOUNT && $CURRENT_MOUNT != "$MOUNT_POINT" ]]; then
    fail "$DEVICE is already mounted at $CURRENT_MOUNT. Unmount it safely before running this script."
fi
if mountpoint -q "$MOUNT_POINT"; then
    ACTUAL_UUID=$(findmnt -rn --target "$MOUNT_POINT" -o UUID || true)
    [[ $ACTUAL_UUID == "$UUID" ]] || fail "$MOUNT_POINT is already a mount point for another filesystem."
fi
if [[ -L $MOUNT_POINT ]]; then
    fail "$MOUNT_POINT is a symlink; refusing to use it."
fi
if [[ -d $MOUNT_POINT ]] && ! mountpoint -q "$MOUNT_POINT"; then
    [[ -z $(ls -A "$MOUNT_POINT") ]] || fail "$MOUNT_POINT is not empty; refusing to hide its contents with a mount."
fi

# Refuse to overwrite existing fstab arrangements for this UUID or path.
EXISTING=$(awk -v uuid="UUID=$UUID" -v target="$MOUNT_POINT" '
    $1 !~ /^#/ && NF >= 2 && ($1 == uuid || $2 == target) { print }
' "$FSTAB")
EXPECTED="UUID=$UUID $MOUNT_POINT ext4 $OPTIONS 0 2"
if [[ -n $EXISTING && $EXISTING != "$EXPECTED" ]]; then
    printf 'Conflicting /etc/fstab entry:\n%s\n' "$EXISTING" >&2
    fail 'Review the existing entry manually. No changes have been made.'
fi

printf '\nSelected partition: %s\nUUID: %s\nFilesystem: %s\nCurrent label: %s\nTarget label: %s\nMount point: %s\n' \
    "$DEVICE" "$UUID" "$FS_TYPE" "${CURRENT_LABEL:-<none>}" "$LABEL" "$MOUNT_POINT"
read -r -p 'Type YES to configure this partition (no formatting): ' ANSWER
[[ $ANSWER == 'YES' ]] || fail 'Cancelled. No changes made.'

if [[ $CURRENT_LABEL != "$LABEL" ]]; then
    info "Setting ext4 filesystem label to $LABEL"
    e2label "$DEVICE" "$LABEL"
fi

info 'Preparing mount point'
mkdir -p "$MOUNT_POINT"

if [[ -z $EXISTING ]]; then
    BACKUP="${FSTAB}.backup-homelab-hdd-$(date +%Y%m%d-%H%M%S)"
    cp -a "$FSTAB" "$BACKUP"
    info "Backed up /etc/fstab to $BACKUP"
    printf '\n# Homelab USB HDD (configured by setup-homelab-hdd.sh)\n%s\n' "$EXPECTED" >> "$FSTAB"
    # Validate syntax before attempting mount. Revert the addition on failure.
    if ! findmnt --verify --tab-file "$FSTAB"; then
        cp -a "$BACKUP" "$FSTAB"
        fail 'fstab validation failed. Restored backup.'
    fi
else
    info 'Matching fstab entry already exists; leaving it unchanged'
fi

systemctl daemon-reload
if ! mountpoint -q "$MOUNT_POINT"; then
    info 'Mounting HDD'
    if ! mount "$MOUNT_POINT"; then
        fail "Mount failed. Check the device and /etc/fstab; the existing fstab configuration was left in place."
    fi
fi

MOUNTED_UUID=$(findmnt -rn --target "$MOUNT_POINT" -o UUID)
[[ $MOUNTED_UUID == "$UUID" ]] || fail 'Mount verification failed: unexpected UUID mounted.'
info 'Success: homelab-hdd is mounted and configured for future boots'
findmnt --target "$MOUNT_POINT" -o SOURCE,TARGET,FSTYPE,OPTIONS
printf '\nThe filesystem was not formatted and no existing files were deleted.\n'


