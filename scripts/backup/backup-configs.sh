#!/bin/bash
# Server Configuration Backup Script
# Purpose: Rsync server configs, scripts, system files, and LUKS headers to DAS
# Usage: backup-configs.sh [--dry-run]
# Exit Codes: 0=success, 1=rsync/copy failure, 2=mount unavailable
# Requirements: 2.1-2.5, 3.1-3.6, 15.4

set -euo pipefail

SCRIPT_NAME="backup-configs"
BACKUP_MOUNT="/mnt/backup"
BACKUP_DEST="${BACKUP_MOUNT}/configs"
DRY_RUN=false
DRY_RUN_FLAG=""

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../operations/utils"
source "${UTILS_DIR}/log-utils.sh"
source "${UTILS_DIR}/env-utils.sh"
load_env_files || log_msg "WARN" "$SCRIPT_NAME" "Could not load env files"

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true; DRY_RUN_FLAG="--dry-run" ;;
        *) log_msg "WARN" "$SCRIPT_NAME" "Unknown argument: $arg" ;;
    esac
done

# Mount guard: verify /mnt/backup/ is mounted and writable
verify_mount() {
    if ! mountpoint -q "$BACKUP_MOUNT"; then
        log_msg "ERROR" "$SCRIPT_NAME" "Mount point ${BACKUP_MOUNT} is not mounted"
        send_alert_email \
            "[HOMESERVER] Backup FAILED - Mount unavailable - $(date '+%Y-%m-%d')" \
            "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nMount point: ${BACKUP_MOUNT}\n\nThe backup mount point is not available. The DAS may be unplugged, corrupted, or the LUKS volume not opened."
        exit 2
    fi
    if ! touch "${BACKUP_MOUNT}/.write-test" 2>/dev/null; then
        log_msg "ERROR" "$SCRIPT_NAME" "Mount point ${BACKUP_MOUNT} is not writable"
        send_alert_email \
            "[HOMESERVER] Backup FAILED - Mount read-only - $(date '+%Y-%m-%d')" \
            "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nMount point: ${BACKUP_MOUNT}\n\nThe backup mount point is mounted but not writable. The DAS may be corrupted."
        exit 2
    fi
    rm -f "${BACKUP_MOUNT}/.write-test"
}

verify_mount

DRY_LABEL=""; $DRY_RUN && DRY_LABEL=" (dry-run)"
log_msg "INFO" "$SCRIPT_NAME" "Starting server config backup${DRY_LABEL}"
FAILURES=0

# Ensure destination directories exist
mkdir -p "${BACKUP_DEST}/homeserver" "${BACKUP_DEST}/system"

# Rsync server configs (mirror)
log_msg "INFO" "$SCRIPT_NAME" "Syncing /opt/homeserver/configs/ ..."
if ! rsync -a --delete $DRY_RUN_FLAG /opt/homeserver/configs/ "${BACKUP_DEST}/homeserver/configs/"; then
    log_msg "ERROR" "$SCRIPT_NAME" "rsync failed for /opt/homeserver/configs/"
    FAILURES=$((FAILURES + 1))
fi

# Rsync server scripts (mirror)
log_msg "INFO" "$SCRIPT_NAME" "Syncing /opt/homeserver/scripts/ ..."
if ! rsync -a --delete $DRY_RUN_FLAG /opt/homeserver/scripts/ "${BACKUP_DEST}/homeserver/scripts/"; then
    log_msg "ERROR" "$SCRIPT_NAME" "rsync failed for /opt/homeserver/scripts/"
    FAILURES=$((FAILURES + 1))
fi

# Copy system files
log_msg "INFO" "$SCRIPT_NAME" "Copying system config files ..."
SYSTEM_FILES=(/etc/fstab /etc/crypttab /etc/ssh/sshd_config)
for f in "${SYSTEM_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        if $DRY_RUN; then
            log_msg "INFO" "$SCRIPT_NAME" "dry-run: would copy $f"
        else
            cp -p "$f" "${BACKUP_DEST}/system/" || { log_msg "WARN" "$SCRIPT_NAME" "Failed to copy $f"; }
        fi
    else
        log_msg "WARN" "$SCRIPT_NAME" "System file not found: $f"
    fi
done

# Copy glob-matched system files: msmtp*, logrotate homeserver-*
for pattern in /etc/msmtp* /etc/logrotate.d/homeserver-*; do
    for f in $pattern; do
        [[ -e "$f" ]] || continue
        if $DRY_RUN; then
            log_msg "INFO" "$SCRIPT_NAME" "dry-run: would copy $f"
        else
            cp -p "$f" "${BACKUP_DEST}/system/" || { log_msg "WARN" "$SCRIPT_NAME" "Failed to copy $f"; }
        fi
    done
done

# Copy LUKS header backups
for f in /root/luks-header-backup-*.img; do
    [[ -e "$f" ]] || continue
    if $DRY_RUN; then
        log_msg "INFO" "$SCRIPT_NAME" "dry-run: would copy $f"
    else
        cp -p "$f" "${BACKUP_DEST}/system/" || { log_msg "WARN" "$SCRIPT_NAME" "Failed to copy $f"; }
    fi
done

# Handle failures
if [[ $FAILURES -gt 0 ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "Config backup completed with $FAILURES rsync failure(s)"
    send_alert_email \
        "[HOMESERVER] Backup FAILED - $(date '+%Y-%m-%d')" \
        "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nComponent: backup-configs\n\nServer config backup had $FAILURES rsync failure(s). Check logs for details."
    exit 1
fi

# Log summary (file count and size)
if ! $DRY_RUN; then
    FILE_COUNT=$(find "$BACKUP_DEST" -type f 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh "$BACKUP_DEST" 2>/dev/null | cut -f1)
    log_msg "INFO" "$SCRIPT_NAME" "Backup complete: ${FILE_COUNT} files, ${TOTAL_SIZE} total"
else
    log_msg "INFO" "$SCRIPT_NAME" "Dry-run complete — no changes made"
fi

exit 0
