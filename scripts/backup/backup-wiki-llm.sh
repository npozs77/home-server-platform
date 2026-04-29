#!/bin/bash
# Wiki + LLM Platform Backup Script
# Purpose: Backup Wiki.js database + wiki content + Open WebUI data
# Usage: backup-wiki-llm.sh [--dry-run]
# Exit Codes: 0=success, 1=backup failure, 2=mount unavailable, 3=prerequisites not met
# Requirements: 15.1-15.11

set -euo pipefail

SCRIPT_NAME="backup-wiki-llm"
DRY_RUN=false
DRY_RUN_FLAG=""

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true; DRY_RUN_FLAG="--dry-run" ;;
        *) ;;
    esac
done

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../operations/utils"
source "${UTILS_DIR}/log-utils.sh"

# Load only foundation.env and services.env (backup script does not need secrets.env)
[[ -f /opt/homeserver/configs/foundation.env ]] && source /opt/homeserver/configs/foundation.env
[[ -f /opt/homeserver/configs/services.env ]] && source /opt/homeserver/configs/services.env

BACKUP_MOUNT="${BACKUP_MOUNT:-/mnt/backup}"
BACKUP_DEST="${BACKUP_MOUNT}/wiki-llm"

# Data source directories
WIKI_CONTENT_DIR="/mnt/data/services/wiki/content"
OPENWEBUI_DATA_DIR="/mnt/data/services/openwebui/data"

# Database config
WIKI_DB_CONTAINER="wiki-db"
DB_USER="${WIKI_DB_USER:-wikijs}"
DB_NAME="${WIKI_DB_NAME:-wikijs}"

# Mount guard — verify backup destination is mounted and writable
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
log_msg "INFO" "$SCRIPT_NAME" "Starting Wiki + LLM backup${DRY_LABEL} → ${BACKUP_DEST}"
START_TIME=$(date +%s)
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

mkdir -p "$BACKUP_DEST" 2>/dev/null || true

# Step 1: Wiki PostgreSQL dump (pg_dump — NOT filesystem copy of postgres dir)
if docker inspect --format='{{.State.Running}}' "$WIKI_DB_CONTAINER" 2>/dev/null | grep -q true; then
    DB_DUMP_FILE="${BACKUP_DEST}/wiki-db-${TIMESTAMP}.sql"
    if $DRY_RUN; then
        log_msg "INFO" "$SCRIPT_NAME" "dry-run: would pg_dump to ${DB_DUMP_FILE}"
    else
        log_msg "INFO" "$SCRIPT_NAME" "Running pg_dump against ${WIKI_DB_CONTAINER}..."
        if ! docker exec "$WIKI_DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$DB_DUMP_FILE" 2>&1; then
            PG_EXIT=$?
            rm -f "$DB_DUMP_FILE"
            cleanup_on_failure "pg_dump failed for ${WIKI_DB_CONTAINER} (exit code: ${PG_EXIT})"
        fi
        DB_DUMP_SIZE=$(du -sh "$DB_DUMP_FILE" | cut -f1)
        log_msg "INFO" "$SCRIPT_NAME" "pg_dump complete: ${DB_DUMP_SIZE}"
    fi
else
    log_msg "WARN" "$SCRIPT_NAME" "Container ${WIKI_DB_CONTAINER} not running — skipping pg_dump"
fi

# Step 2: Rsync wiki content (markdown page exports from Local File System storage)
if [[ -d "$WIKI_CONTENT_DIR" ]]; then
    log_msg "INFO" "$SCRIPT_NAME" "Syncing wiki content directory..."
    if ! rsync -a --delete $DRY_RUN_FLAG "$WIKI_CONTENT_DIR/" "${BACKUP_DEST}/wiki-content/"; then
        cleanup_on_failure "rsync failed for wiki content directory"
    fi
else
    log_msg "WARN" "$SCRIPT_NAME" "Wiki content directory not found: ${WIKI_CONTENT_DIR} — skipping"
fi

# Step 3: Rsync Open WebUI data (chat history, RAG embeddings, uploaded docs)
if [[ -d "$OPENWEBUI_DATA_DIR" ]]; then
    log_msg "INFO" "$SCRIPT_NAME" "Syncing Open WebUI data directory..."
    if ! rsync -a --delete $DRY_RUN_FLAG "$OPENWEBUI_DATA_DIR/" "${BACKUP_DEST}/openwebui-data/"; then
        cleanup_on_failure "rsync failed for Open WebUI data directory"
    fi
else
    log_msg "WARN" "$SCRIPT_NAME" "Open WebUI data directory not found: ${OPENWEBUI_DATA_DIR} — skipping"
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
