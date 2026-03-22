#!/bin/bash
# Immich Backup Script
# Purpose: Backup Immich PostgreSQL database (pg_dump) and upload directory (rsync)
# Usage: backup-immich.sh [backup_destination]
# Default destination: /mnt/backup/immich/
# Cron-ready: non-interactive, exit codes, log output
# Prerequisites:
#   - immich-postgres container running
#   - Backup destination mounted and writable
#   - msmtp configured for email alerts (Phase 2)
# Exit Codes:
#   0 = Success
#   1 = Backup failure (pg_dump, rsync, or verification)
#   2 = Destination not available or not writable
#   3 = Prerequisites not met (container not running)

set -euo pipefail

# ============================================================
# Configuration
# ============================================================
BACKUP_DEST="${1:-/mnt/backup/immich}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="/var/log/immich-backup.log"
DB_CONTAINER="immich-postgres"
DB_USER="${DB_USERNAME:-postgres}"
DB_NAME="${DB_DATABASE_NAME:-immich}"
UPLOAD_DIR="/mnt/data/services/immich/upload"
MEDIA_PHOTOS_DIR="/mnt/data/media/Photos"
FAMILY_PHOTOS_DIR="/mnt/data/family/Photos"

# Source foundation.env for admin email (if available)
FOUNDATION_ENV="/opt/homeserver/configs/foundation.env"
if [[ -f "$FOUNDATION_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$FOUNDATION_ENV"
fi
ALERT_EMAIL="${ADMIN_EMAIL:-root}"

# ============================================================
# Functions
# ============================================================
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

send_alert() {
    local subject="$1"
    local body="$2"
    if command -v msmtp &> /dev/null; then
        echo -e "Subject: ${subject}\n\n${body}" | msmtp "$ALERT_EMAIL" 2>/dev/null || true
    fi
}

cleanup_on_failure() {
    local msg="$1"
    log "ERROR: ${msg}"
    send_alert "Immich Backup FAILED" "Backup failed at $(date).\n\nError: ${msg}\nDestination: ${BACKUP_DEST}\nHost: $(hostname)"
    exit 1
}

# ============================================================
# Pre-flight checks
# ============================================================
log "=== Immich Backup Starting ==="
log "Destination: ${BACKUP_DEST}"
START_TIME=$(date +%s)

# Check immich-postgres container is running
if ! docker inspect --format='{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null | grep -q true; then
    log "ERROR: Container $DB_CONTAINER is not running"
    send_alert "Immich Backup FAILED" "Container $DB_CONTAINER is not running."
    exit 3
fi

# Verify backup destination is mounted and writable
if [[ ! -d "$BACKUP_DEST" ]]; then
    mkdir -p "$BACKUP_DEST" 2>/dev/null || true
fi
if [[ ! -d "$BACKUP_DEST" ]] || [[ ! -w "$BACKUP_DEST" ]]; then
    log "ERROR: Backup destination ${BACKUP_DEST} not available or not writable"
    send_alert "Immich Backup FAILED" "Destination ${BACKUP_DEST} not available or not writable."
    exit 2
fi

# Verify upload directory exists
if [[ ! -d "$UPLOAD_DIR" ]]; then
    log "ERROR: Upload directory ${UPLOAD_DIR} does not exist"
    send_alert "Immich Backup FAILED" "Upload directory ${UPLOAD_DIR} does not exist."
    exit 3
fi

# ============================================================
# Step 1: PostgreSQL dump (NOT filesystem copy)
# ============================================================
log "Running pg_dump against ${DB_CONTAINER}..."
DB_DUMP_FILE="${BACKUP_DEST}/immich-db-${TIMESTAMP}.sql"

if ! docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$DB_DUMP_FILE" 2>>"$LOG_FILE"; then
    rm -f "$DB_DUMP_FILE"
    cleanup_on_failure "pg_dump failed"
fi

DB_DUMP_SIZE=$(du -sh "$DB_DUMP_FILE" | cut -f1)
log "pg_dump complete: ${DB_DUMP_SIZE} (${DB_DUMP_FILE})"

# ============================================================
# Step 2: Rsync upload directory
# ============================================================
log "Syncing upload directory to ${BACKUP_DEST}/upload/..."

if ! rsync -a --delete "$UPLOAD_DIR/" "${BACKUP_DEST}/upload/" 2>>"$LOG_FILE"; then
    cleanup_on_failure "rsync of upload directory failed"
fi

UPLOAD_SYNC_SIZE=$(du -sh "${BACKUP_DEST}/upload/" | cut -f1)
log "Upload sync complete: ${UPLOAD_SYNC_SIZE}"

# ============================================================
# Step 3: Rsync external library - Media Photos (incremental)
# ============================================================
log "Syncing Media Photos to ${BACKUP_DEST}/media-photos/..."

if [[ -d "$MEDIA_PHOTOS_DIR" ]]; then
    if ! rsync -a --delete "$MEDIA_PHOTOS_DIR/" "${BACKUP_DEST}/media-photos/" 2>>"$LOG_FILE"; then
        cleanup_on_failure "rsync of Media Photos directory failed"
    fi
    MEDIA_SYNC_SIZE=$(du -sh "${BACKUP_DEST}/media-photos/" | cut -f1)
    log "Media Photos sync complete: ${MEDIA_SYNC_SIZE}"
else
    log "WARNING: Media Photos directory not found: ${MEDIA_PHOTOS_DIR} — skipping"
fi

# ============================================================
# Step 4: Rsync external library - Family Photos (incremental)
# ============================================================
log "Syncing Family Photos to ${BACKUP_DEST}/family-photos/..."

if [[ -d "$FAMILY_PHOTOS_DIR" ]]; then
    if ! rsync -a --delete "$FAMILY_PHOTOS_DIR/" "${BACKUP_DEST}/family-photos/" 2>>"$LOG_FILE"; then
        cleanup_on_failure "rsync of Family Photos directory failed"
    fi
    FAMILY_SYNC_SIZE=$(du -sh "${BACKUP_DEST}/family-photos/" | cut -f1)
    log "Family Photos sync complete: ${FAMILY_SYNC_SIZE}"
else
    log "WARNING: Family Photos directory not found: ${FAMILY_PHOTOS_DIR} — skipping"
fi

# ============================================================
# Step 5: Verification and summary
# ============================================================
UPLOAD_FILE_COUNT=$(find "${BACKUP_DEST}/upload/" -type f 2>/dev/null | wc -l)
MEDIA_FILE_COUNT=$(find "${BACKUP_DEST}/media-photos/" -type f 2>/dev/null | wc -l)
FAMILY_FILE_COUNT=$(find "${BACKUP_DEST}/family-photos/" -type f 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_DEST" | cut -f1)
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log "Backup verification:"
log "  Database dump: ${DB_DUMP_SIZE}"
log "  Upload files: ${UPLOAD_FILE_COUNT} files (${UPLOAD_SYNC_SIZE})"
log "  Media Photos: ${MEDIA_FILE_COUNT} files (${MEDIA_SYNC_SIZE:-skipped})"
log "  Family Photos: ${FAMILY_FILE_COUNT} files (${FAMILY_SYNC_SIZE:-skipped})"
log "  Total backup size: ${TOTAL_SIZE}"
log "  Duration: ${DURATION} seconds"
log "=== Immich Backup Complete ==="

exit 0
