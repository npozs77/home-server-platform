#!/bin/bash
set -euo pipefail

# DAS LUKS Setup Script — One-time setup for backup partition
# Usage: setup-das-luks.sh [--dry-run] [--no-luks]
# Exit: 0=success, 1=failure, 2=prerequisites not met

SCRIPT_NAME="setup-das-luks"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../operations/utils"

source "${UTILS_DIR}/log-utils.sh"
source "${UTILS_DIR}/output-utils.sh"
source "${UTILS_DIR}/env-utils.sh"

DRY_RUN=false; NO_LUKS=false
DEVICE="/dev/sdb2"; MAPPER_NAME="backup_crypt"; MAPPER_DEV="/dev/mapper/${MAPPER_NAME}"
MOUNT_POINT="/mnt/backup"; KEY_FILE="/root/.luks-key"; DATA_DEVICE="/dev/nvme0n1p3"

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --no-luks) NO_LUKS=true ;;
        *) log_msg "ERROR" "$SCRIPT_NAME" "Unknown flag: $arg"; exit 1 ;;
    esac
done

# Root check
if [[ $EUID -ne 0 ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "Must be run as root"
    exit 2
fi

# Validate device exists
if [[ ! -b "$DEVICE" ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "$DEVICE does not exist"
    exit 2
fi

run_cmd() {
    if $DRY_RUN; then
        log_msg "INFO" "$SCRIPT_NAME" "[DRY-RUN] $*"
    else
        "$@"
    fi
}

log_msg "INFO" "$SCRIPT_NAME" "Starting DAS setup (dry-run=$DRY_RUN, no-luks=$NO_LUKS)"

if $NO_LUKS; then
    # --- No-LUKS path: format ext4 directly ---
    log_msg "INFO" "$SCRIPT_NAME" "No-LUKS mode: formatting $DEVICE as ext4 directly"
    if ! blkid -o value -s TYPE "$DEVICE" 2>/dev/null | grep -q ext4; then
        run_cmd mkfs.ext4 -F "$DEVICE"
    else
        log_msg "INFO" "$SCRIPT_NAME" "$DEVICE already formatted as ext4 — skipping"
    fi
    run_cmd mkdir -p "$MOUNT_POINT"
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log_msg "INFO" "$SCRIPT_NAME" "$MOUNT_POINT already mounted — skipping"
    else
        run_cmd mount "$DEVICE" "$MOUNT_POINT"
    fi
    # UUID-based fstab entry (no crypttab)
    local_uuid=$(blkid -o value -s UUID "$DEVICE" 2>/dev/null || echo "UNKNOWN")
    if ! grep -q "$MOUNT_POINT" /etc/fstab 2>/dev/null; then
        run_cmd bash -c "echo 'UUID=${local_uuid} ${MOUNT_POINT} ext4 defaults,nofail 0 2' >> /etc/fstab"
        log_msg "INFO" "$SCRIPT_NAME" "Added fstab entry for $MOUNT_POINT (UUID=${local_uuid}, nofail)"
    else
        log_msg "INFO" "$SCRIPT_NAME" "fstab entry for $MOUNT_POINT already exists — skipping"
    fi
else
    # --- LUKS path ---
    if cryptsetup isLuks "$DEVICE" 2>/dev/null; then
        log_msg "INFO" "$SCRIPT_NAME" "$DEVICE already has LUKS header — skipping luksFormat"
    else
        log_msg "INFO" "$SCRIPT_NAME" "Creating LUKS container on $DEVICE"
        run_cmd cryptsetup luksFormat "$DEVICE"
    fi
    # Open LUKS
    if [[ -b "$MAPPER_DEV" ]]; then
        log_msg "INFO" "$SCRIPT_NAME" "$MAPPER_NAME already open — skipping luksOpen"
    else
        run_cmd cryptsetup luksOpen "$DEVICE" "$MAPPER_NAME"
    fi
    # Format ext4 if needed
    if ! blkid -o value -s TYPE "$MAPPER_DEV" 2>/dev/null | grep -q ext4; then
        run_cmd mkfs.ext4 "$MAPPER_DEV"
    else
        log_msg "INFO" "$SCRIPT_NAME" "$MAPPER_DEV already formatted as ext4 — skipping"
    fi
    # Mount
    run_cmd mkdir -p "$MOUNT_POINT"
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log_msg "INFO" "$SCRIPT_NAME" "$MOUNT_POINT already mounted — skipping"
    else
        run_cmd mount "$MAPPER_DEV" "$MOUNT_POINT"
    fi
    # Add key file (slot 1)
    if [[ -f "$KEY_FILE" ]]; then
        log_msg "INFO" "$SCRIPT_NAME" "Adding key file to LUKS slot 1"
        run_cmd cryptsetup luksAddKey "$DEVICE" "$KEY_FILE"
    else
        log_msg "WARN" "$SCRIPT_NAME" "Key file $KEY_FILE not found — skipping luksAddKey"
    fi
    # crypttab entry
    local_uuid=$(blkid -o value -s UUID "$DEVICE" 2>/dev/null || echo "UNKNOWN")
    if ! grep -q "$MAPPER_NAME" /etc/crypttab 2>/dev/null; then
        run_cmd bash -c "echo '${MAPPER_NAME} UUID=${local_uuid} ${KEY_FILE} luks,nofail,noauto' >> /etc/crypttab"
        log_msg "INFO" "$SCRIPT_NAME" "Added crypttab entry for $MAPPER_NAME (nofail,noauto)"
    else
        log_msg "INFO" "$SCRIPT_NAME" "crypttab entry for $MAPPER_NAME already exists — skipping"
    fi
    # fstab entry
    if ! grep -q "$MOUNT_POINT" /etc/fstab 2>/dev/null; then
        run_cmd bash -c "echo '${MAPPER_DEV} ${MOUNT_POINT} ext4 defaults,nofail 0 2' >> /etc/fstab"
        log_msg "INFO" "$SCRIPT_NAME" "Added fstab entry for $MOUNT_POINT (nofail)"
    else
        log_msg "INFO" "$SCRIPT_NAME" "fstab entry for $MOUNT_POINT already exists — skipping"
    fi
    # LUKS header backups
    for dev_part in "$DEVICE" "$DATA_DEVICE"; do
        local_name=$(basename "$dev_part")
        backup_file="/root/luks-header-backup-${local_name}.img"
        if [[ -b "$dev_part" ]]; then
            run_cmd cryptsetup luksHeaderBackup "$dev_part" --header-backup-file "$backup_file"
            run_cmd chmod 600 "$backup_file"
            log_msg "INFO" "$SCRIPT_NAME" "Created LUKS header backup: $backup_file"
        fi
    done
fi

# Verify mount writable
if ! $DRY_RUN; then
    if touch "${MOUNT_POINT}/.write-test" 2>/dev/null; then
        rm -f "${MOUNT_POINT}/.write-test"
        log_msg "INFO" "$SCRIPT_NAME" "Mount verified writable at $MOUNT_POINT"
    else
        log_msg "ERROR" "$SCRIPT_NAME" "$MOUNT_POINT is not writable"
        exit 1
    fi
fi

log_msg "INFO" "$SCRIPT_NAME" "DAS setup complete"
if ! $NO_LUKS; then
    echo ""
    echo "IMPORTANT: Store your LUKS passphrase in a password manager."
    echo "Copy header backups to a USB drive and store offline."
fi
