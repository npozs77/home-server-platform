#!/bin/bash
# Immich Backup Script — pg_dump + rsync of uploads, media photos, family photos
# Usage: backup-immich.sh [--dry-run] [backup_destination]
# Exit Codes: 0=success, 1=backup failure, 2=mount unavailable, 3=prerequisites not met
# Requirements: 13.1-13.6

set -euo pipefail
SCRIPT_NAME="backup-immich"
BACKUP_MOUNT="/mnt/backup"
DRY_RUN=false
DRY_RUN_FLAG=""
BACKUP_DEST=""

# Parse arguments (preserve backward compat: positional = destination)
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true; DRY_RUN_FLAG="--dry-run" ;;
        *) BACKUP_DEST="$arg" ;;
    esac
done
BACKUP_DEST="${BACKUP_DEST:-${BACKUP_MOUNT}/immich}"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DELETED_DIR="${BACKUP_DEST}/.deleted/$(date '+%Y%m%d')"
DB_CONTAINER="immich-postgres"
DB_USER="${DB_USERNAME:-postgres}"
DB_NAME="${DB_DATABASE_NAME:-immich}"
UPLOAD_DIR="/mnt/data/services/immich/upload"
MEDIA_PHOTOS_DIR="/mnt/data/media/Photos"
FAMILY_PHOTOS_DIR="/mnt/data/family/Photos"

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../operations/utils"
source "${UTILS_DIR}/log-utils.sh"
source "${UTILS_DIR}/env-utils.sh"
load_env_files || log_msg "WARN" "$SCRIPT_NAME" "Could not load env files"

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

cleanup_on_failure() {
    local msg="$1"
    log_msg "ERROR" "$SCRIPT_NAME" "$msg"
    send_alert_email \
        "[HOMESERVER] Backup FAILED - $(date '+%Y-%m-%d')" \
        "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nComponent: ${SCRIPT_NAME}\n\nError: ${msg}\nDestination: ${BACKUP_DEST}"
    exit 1
}

# Pre-flight checks
verify_mount

DRY_LABEL=""; $DRY_RUN && DRY_LABEL=" (dry-run)"
log_msg "INFO" "$SCRIPT_NAME" "Starting Immich backup${DRY_LABEL} → ${BACKUP_DEST}"
START_TIME=$(date +%s)

# Check immich-postgres container is running
if ! docker inspect --format='{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null | grep -q true; then
    log_msg "ERROR" "$SCRIPT_NAME" "Container $DB_CONTAINER is not running"
    send_alert_email "[HOMESERVER] Backup FAILED - $(date '+%Y-%m-%d')" "Container $DB_CONTAINER is not running."
    exit 3
fi

mkdir -p "$BACKUP_DEST" 2>/dev/null || true

# Verify upload directory exists
if [[ ! -d "$UPLOAD_DIR" ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "Upload directory ${UPLOAD_DIR} does not exist"
    send_alert_email "[HOMESERVER] Backup FAILED - $(date '+%Y-%m-%d')" "Upload directory ${UPLOAD_DIR} does not exist."
    exit 3
fi

# Step 1: PostgreSQL dump
DB_DUMP_FILE="${BACKUP_DEST}/immich-db-${TIMESTAMP}.sql"
if $DRY_RUN; then
    log_msg "INFO" "$SCRIPT_NAME" "dry-run: would pg_dump to ${DB_DUMP_FILE}"
else
    log_msg "INFO" "$SCRIPT_NAME" "Running pg_dump against ${DB_CONTAINER}..."
    if ! docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$DB_DUMP_FILE" 2>&1; then
        rm -f "$DB_DUMP_FILE"
        cleanup_on_failure "pg_dump failed"
    fi
    DB_DUMP_SIZE=$(du -sh "$DB_DUMP_FILE" | cut -f1)
    log_msg "INFO" "$SCRIPT_NAME" "pg_dump complete: ${DB_DUMP_SIZE}"
fi

# Step 2: Rsync upload directory (deleted files moved to .deleted/)
log_msg "INFO" "$SCRIPT_NAME" "Syncing upload directory..."
if ! rsync -a --delete --backup --backup-dir="$DELETED_DIR" $DRY_RUN_FLAG "$UPLOAD_DIR/" "${BACKUP_DEST}/upload/"; then
    cleanup_on_failure "rsync of upload directory failed"
fi

# Step 3: Rsync Media Photos
MEDIA_SYNC_SIZE="skipped"
if [[ -d "$MEDIA_PHOTOS_DIR" ]]; then
    log_msg "INFO" "$SCRIPT_NAME" "Syncing Media Photos..."
    if ! rsync -a --delete --backup --backup-dir="$DELETED_DIR" $DRY_RUN_FLAG "$MEDIA_PHOTOS_DIR/" "${BACKUP_DEST}/media-photos/"; then
        cleanup_on_failure "rsync of Media Photos failed"
    fi
else
    log_msg "WARN" "$SCRIPT_NAME" "Media Photos directory not found: ${MEDIA_PHOTOS_DIR} — skipping"
fi

# Step 4: Rsync Family Photos
FAMILY_SYNC_SIZE="skipped"
if [[ -d "$FAMILY_PHOTOS_DIR" ]]; then
    log_msg "INFO" "$SCRIPT_NAME" "Syncing Family Photos..."
    if ! rsync -a --delete --backup --backup-dir="$DELETED_DIR" $DRY_RUN_FLAG "$FAMILY_PHOTOS_DIR/" "${BACKUP_DEST}/family-photos/"; then
        cleanup_on_failure "rsync of Family Photos failed"
    fi
else
    log_msg "WARN" "$SCRIPT_NAME" "Family Photos directory not found: ${FAMILY_PHOTOS_DIR} — skipping"
fi

# Summary
if ! $DRY_RUN; then
    TOTAL_FILES=$(find "$BACKUP_DEST" -type f 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh "$BACKUP_DEST" 2>/dev/null | cut -f1)
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log_msg "INFO" "$SCRIPT_NAME" "Backup complete: ${TOTAL_FILES} files, ${TOTAL_SIZE} total, ${DURATION}s"
else
    log_msg "INFO" "$SCRIPT_NAME" "Dry-run complete — no changes made"
fi

exit 0
