#!/bin/bash
# Wiki.js Backup Script (stub — Wiki.js not yet deployed)
# Purpose: Backup Wiki.js database + data directory to DAS
# Usage: backup-wiki.sh [--dry-run]
# Exit Codes: 0=success/skip, 1=backup failure, 2=mount unavailable
# Requirements: 4.1-4.7

set -euo pipefail

SCRIPT_NAME="backup-wiki"
WIKI_DATA_DIR="/mnt/data/services/wiki"
WIKI_DB_CONTAINER="wiki-db"
DRY_RUN=false
DRY_RUN_FLAG=""

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true; DRY_RUN_FLAG="--dry-run" ;;
        *) log_msg "WARN" "$SCRIPT_NAME" "Unknown argument: $arg" 2>/dev/null || true ;;
    esac
done

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../operations/utils"
source "${UTILS_DIR}/log-utils.sh"
source "${UTILS_DIR}/env-utils.sh"
load_env_files || log_msg "WARN" "$SCRIPT_NAME" "Could not load env files"

BACKUP_MOUNT="${BACKUP_MOUNT:-/mnt/backup}"
BACKUP_DEST="${BACKUP_MOUNT}/wiki"

# Mount guard
verify_mount() {
    if ! mountpoint -q "$BACKUP_MOUNT"; then
        log_msg "ERROR" "$SCRIPT_NAME" "Mount point ${BACKUP_MOUNT} is not mounted"
        send_alert_email "[HOMESERVER] Backup FAILED - Mount unavailable - $(date '+%Y-%m-%d')" \
            "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nMount point: ${BACKUP_MOUNT}\n\nDAS may be unplugged, corrupted, or LUKS volume not opened."
        exit 2
    fi
    if ! touch "${BACKUP_MOUNT}/.write-test" 2>/dev/null; then
        log_msg "ERROR" "$SCRIPT_NAME" "Mount point ${BACKUP_MOUNT} is not writable"
        send_alert_email "[HOMESERVER] Backup FAILED - Mount read-only - $(date '+%Y-%m-%d')" \
            "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nMount point: ${BACKUP_MOUNT}\n\nMount point is mounted but not writable."
        exit 2
    fi
    rm -f "${BACKUP_MOUNT}/.write-test"
}

verify_mount
DRY_LABEL=""; $DRY_RUN && DRY_LABEL=" (dry-run)"
log_msg "INFO" "$SCRIPT_NAME" "Starting Wiki.js backup${DRY_LABEL}"

# Check if Wiki.js data directory exists (Wiki.js not yet deployed)
if [[ ! -d "$WIKI_DATA_DIR" ]]; then
    log_msg "WARN" "$SCRIPT_NAME" "Wiki.js data directory not found — skipping (Wiki.js not yet deployed)"
    exit 0
fi

mkdir -p "$BACKUP_DEST" 2>/dev/null || true
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Database dump (if wiki-db container is running)
if docker inspect --format='{{.State.Running}}' "$WIKI_DB_CONTAINER" 2>/dev/null | grep -q true; then
    DB_DUMP_FILE="${BACKUP_DEST}/wiki-db-${TIMESTAMP}.sql"
    if $DRY_RUN; then
        log_msg "INFO" "$SCRIPT_NAME" "dry-run: would pg_dump to ${DB_DUMP_FILE}"
    else
        log_msg "INFO" "$SCRIPT_NAME" "Running pg_dump against ${WIKI_DB_CONTAINER}..."
        if ! docker exec "$WIKI_DB_CONTAINER" pg_dump -U wiki wiki > "$DB_DUMP_FILE" 2>&1; then
            rm -f "$DB_DUMP_FILE"
            log_msg "ERROR" "$SCRIPT_NAME" "pg_dump failed for ${WIKI_DB_CONTAINER}"
            send_alert_email "[HOMESERVER] Backup FAILED - $(date '+%Y-%m-%d')" \
                "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nComponent: ${SCRIPT_NAME}\n\npg_dump failed for ${WIKI_DB_CONTAINER}"
            exit 1
        fi
    fi
else
    log_msg "WARN" "$SCRIPT_NAME" "Container ${WIKI_DB_CONTAINER} not running — skipping pg_dump"
fi

# Rsync wiki data
log_msg "INFO" "$SCRIPT_NAME" "Syncing wiki data directory..."
if ! rsync -a --delete $DRY_RUN_FLAG "${WIKI_DATA_DIR}/" "${BACKUP_DEST}/data/"; then
    log_msg "ERROR" "$SCRIPT_NAME" "rsync failed for wiki data"
    send_alert_email "[HOMESERVER] Backup FAILED - $(date '+%Y-%m-%d')" \
        "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nComponent: ${SCRIPT_NAME}\n\nrsync failed for wiki data directory"
    exit 1
fi

# Summary
if ! $DRY_RUN; then
    FILE_COUNT=$(find "$BACKUP_DEST" -type f 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh "$BACKUP_DEST" 2>/dev/null | cut -f1)
    log_msg "INFO" "$SCRIPT_NAME" "Backup complete: ${FILE_COUNT} files, ${TOTAL_SIZE} total"
else
    log_msg "INFO" "$SCRIPT_NAME" "Dry-run complete — no changes made"
fi

exit 0
