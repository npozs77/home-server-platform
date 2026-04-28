#!/bin/bash
# Backup Orchestrator — runs all backup jobs in sequence
# Usage: backup-all.sh [--dry-run]
# Exit Codes: 0=all jobs succeeded, 1=any job failed
# Requirements: 5.1-5.9, 11.2, 12.1-12.4, 14.1-14.4

set -euo pipefail

SCRIPT_NAME="backup-all"
BACKUP_MOUNT="/mnt/backup"
CRON_LOG_DIR="/var/log/homeserver"
LOG_DATE=$(date '+%Y%m%d')
DRY_RUN=false
DRY_RUN_FLAG=""

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true; DRY_RUN_FLAG="--dry-run" ;;
        *) ;;
    esac
done

# Source utilities
BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${BACKUP_DIR}/../operations/utils"
source "${UTILS_DIR}/log-utils.sh"
source "${UTILS_DIR}/env-utils.sh"
load_env_files || log_msg "WARN" "$SCRIPT_NAME" "Could not load env files"

# Ensure log directory exists
mkdir -p "$CRON_LOG_DIR" 2>/dev/null || true

# Mount guard
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

DRY_LABEL=""; $DRY_RUN && DRY_LABEL=" (dry-run)"
log_msg "INFO" "$SCRIPT_NAME" "Starting backup orchestrator${DRY_LABEL}"
START_TIME=$(date +%s)

# Create missing backup subdirectories
mkdir -p "${BACKUP_MOUNT}/configs/homeserver" "${BACKUP_MOUNT}/configs/system"
mkdir -p "${BACKUP_MOUNT}/immich" "${BACKUP_MOUNT}/wiki"

# Job runner with failure isolation
FAILURES=0
JOB_RESULTS=()

run_job() {
    local script="$1"
    local name="$2"
    log_msg "INFO" "$SCRIPT_NAME" "Running ${name}..."
    local exit_code=0
    bash "$script" $DRY_RUN_FLAG || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        JOB_RESULTS+=("${name}:success")
        log_msg "INFO" "$SCRIPT_NAME" "${name} completed successfully"
    else
        JOB_RESULTS+=("${name}:failed:${exit_code}")
        FAILURES=$((FAILURES + 1))
        log_msg "ERROR" "$SCRIPT_NAME" "${name} failed with exit code ${exit_code}"
    fi
}

# Run backup jobs in order
run_job "${BACKUP_DIR}/backup-configs.sh" "backup-configs"
run_job "${BACKUP_DIR}/backup-immich.sh" "backup-immich"
run_job "${BACKUP_DIR}/backup-wiki.sh" "backup-wiki"

# DB dump retention: remove dumps older than 30 days
if ! $DRY_RUN; then
    OLD_DUMPS=$(find "$BACKUP_MOUNT" -name '*-db-*.sql' -mtime +30 2>/dev/null)
    if [[ -n "$OLD_DUMPS" ]]; then
        OLD_COUNT=$(echo "$OLD_DUMPS" | wc -l)
        OLD_SIZE=$(echo "$OLD_DUMPS" | xargs du -ch 2>/dev/null | tail -1 | cut -f1)
        echo "$OLD_DUMPS" | xargs rm -f
        log_msg "INFO" "$SCRIPT_NAME" "Retention: removed ${OLD_COUNT} old dumps (${OLD_SIZE} reclaimed)"
    else
        log_msg "INFO" "$SCRIPT_NAME" "Retention: no old dumps to clean"
    fi
else
    log_msg "INFO" "$SCRIPT_NAME" "dry-run: would check DB dump retention (30 days)"
fi

# Disk space monitoring
USAGE_PCT=$(df "$BACKUP_MOUNT" | awk 'NR==2 {gsub(/%/,""); print $5}')
AVAIL=$(df -h "$BACKUP_MOUNT" | awk 'NR==2 {print $4}')
log_msg "INFO" "$SCRIPT_NAME" "Disk usage: ${USAGE_PCT}% (${AVAIL} available)"

# Purge old .deleted photo backups (>90 days) when disk usage >80%
if ! $DRY_RUN && [[ "$USAGE_PCT" -ge 80 ]]; then
    DELETED_DIR="${BACKUP_MOUNT}/immich/.deleted"
    if [[ -d "$DELETED_DIR" ]]; then
        OLD_DELETED=$(find "$DELETED_DIR" -maxdepth 1 -mindepth 1 -type d -mtime +90 2>/dev/null)
        if [[ -n "$OLD_DELETED" ]]; then
            DEL_SIZE=$(echo "$OLD_DELETED" | xargs du -csh 2>/dev/null | tail -1 | cut -f1)
            DEL_COUNT=$(echo "$OLD_DELETED" | wc -l)
            echo "$OLD_DELETED" | xargs rm -rf
            log_msg "INFO" "$SCRIPT_NAME" "Deleted-photo cleanup: removed ${DEL_COUNT} dirs (${DEL_SIZE} reclaimed)"
        fi
    fi
fi

if [[ "$USAGE_PCT" -ge 95 ]]; then
    send_alert_email "[HOMESERVER] Backup Disk CRITICAL - $(date '+%Y-%m-%d')" \
        "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nMount point: ${BACKUP_MOUNT}\nUsage: ${USAGE_PCT}% (${AVAIL} available)"
elif [[ "$USAGE_PCT" -ge 90 ]]; then
    send_alert_email "[HOMESERVER] Backup Disk Warning - $(date '+%Y-%m-%d')" \
        "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nMount point: ${BACKUP_MOUNT}\nUsage: ${USAGE_PCT}% (${AVAIL} available)"
fi

# Summary
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log_msg "INFO" "$SCRIPT_NAME" "Summary (${DURATION}s):"
for result in "${JOB_RESULTS[@]}"; do
    log_msg "INFO" "$SCRIPT_NAME" "  ${result}"
done

# Send single summary email if any failures
if [[ $FAILURES -gt 0 ]]; then
    FAILED_LIST=""
    SUCCESS_LIST=""
    for result in "${JOB_RESULTS[@]}"; do
        if [[ "$result" == *":success" ]]; then
            SUCCESS_LIST="${SUCCESS_LIST}\n  - ${result%%:*}"
        else
            FAILED_LIST="${FAILED_LIST}\n  - ${result%%:*} (exit ${result##*:})"
        fi
    done
    send_alert_email "[HOMESERVER] Backup FAILED - $(date '+%Y-%m-%d')" \
        "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\n\nFailed jobs:${FAILED_LIST}\n\nSuccessful jobs:${SUCCESS_LIST}\n\nLog: ${CRON_LOG_DIR}/backup-${LOG_DATE}.log"
    log_msg "ERROR" "$SCRIPT_NAME" "Backup completed with ${FAILURES} failure(s)"
    exit 1
fi

log_msg "INFO" "$SCRIPT_NAME" "All backup jobs completed successfully"
exit 0
