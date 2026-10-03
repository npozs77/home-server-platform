#!/bin/bash
# Daily Watchdog
# Purpose: Independent daily verification of system health
# Schedule: Daily at 06:00 (before family wakes up)
# Checks:
#   0. Container health check freshness (cron still firing?)
#   1. Backup log exists for today
#   2. Backup completed successfully (success marker present)
#   3. Distinguishes: still-running (skip), empty/no-output (interrupted), failed
#
# This is a safety net — catches silent failures that individual
# scripts can't report (crashed cron, hung processes, missing logs).
#
# Usage: watchdog.sh
# Log: /var/log/homeserver/watchdog.log
# Exit Codes: 0=OK or alert sent, 1=alert send failure

set -euo pipefail

SCRIPT_NAME="watchdog"

# Source only what we need (no secrets.env — learned that lesson)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"
source "${UTILS_DIR}/log-utils.sh"
[[ -f /opt/homeserver/configs/foundation.env ]] && source /opt/homeserver/configs/foundation.env

LOG_DIR="/var/log/homeserver"
TODAY=$(date '+%Y%m%d')
BACKUP_LOG="${LOG_DIR}/backup-${TODAY}.log"
SUCCESS_MARKER="All backup jobs completed successfully"

# Check 0: Is the container health check still running?
# Health check runs every 15 minutes — last entry should be <20 min old
HEALTH_LOG="${LOG_DIR}/health-check.log"
HEALTH_MAX_AGE_MIN=20

if [[ -f "$HEALTH_LOG" ]]; then
    LAST_HEALTH_LINE=$(tail -1 "$HEALTH_LOG" 2>/dev/null || echo "")
    if [[ -n "$LAST_HEALTH_LINE" ]]; then
        # Extract timestamp from structured log format: "2026-04-30 12:15:01 - [INFO] - ..."
        LAST_HEALTH_TS=$(echo "$LAST_HEALTH_LINE" | grep -oP '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' || echo "")
        if [[ -n "$LAST_HEALTH_TS" ]]; then
            LAST_HEALTH_EPOCH=$(date -d "$LAST_HEALTH_TS" '+%s' 2>/dev/null || echo "0")
            NOW_EPOCH=$(date '+%s')
            AGE_MIN=$(( (NOW_EPOCH - LAST_HEALTH_EPOCH) / 60 ))
            if (( AGE_MIN > HEALTH_MAX_AGE_MIN )); then
                log_msg "ERROR" "$SCRIPT_NAME" "Health check stale: last entry ${AGE_MIN}m ago (threshold: ${HEALTH_MAX_AGE_MIN}m)"
                send_alert_email \
                    "[HOMESERVER] Health Check STALE - $(date '+%Y-%m-%d %H:%M')" \
                    "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\n\nContainer health check log has not been updated in ${AGE_MIN} minutes.\nThreshold: ${HEALTH_MAX_AGE_MIN} minutes\nLast entry: ${LAST_HEALTH_LINE}\n\nPossible causes:\n- Cron daemon not running: systemctl status cron\n- Cron file removed: ls -la /etc/cron.d/homeserver-cron\n- Health check script error: bash -n /opt/homeserver/scripts/operations/monitoring/check-container-health.sh"
            else
                log_msg "INFO" "$SCRIPT_NAME" "Health check OK: last entry ${AGE_MIN}m ago"
            fi
        else
            log_msg "WARN" "$SCRIPT_NAME" "Could not parse timestamp from health-check.log last line"
        fi
    else
        log_msg "WARN" "$SCRIPT_NAME" "health-check.log is empty"
    fi
else
    log_msg "ERROR" "$SCRIPT_NAME" "health-check.log not found — health check may never have run"
    send_alert_email \
        "[HOMESERVER] Health Check MISSING - $(date '+%Y-%m-%d %H:%M')" \
        "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\n\nNo health-check.log found at: ${HEALTH_LOG}\n\nContainer health monitoring may not be configured.\nCheck cron: cat /etc/cron.d/homeserver-cron\nCheck script: ls -la /opt/homeserver/scripts/operations/monitoring/check-container-health.sh"
fi

# Check 1: Does today's backup log exist?
if [[ ! -f "$BACKUP_LOG" ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "No backup log found for today: ${BACKUP_LOG}"
    send_alert_email \
        "[HOMESERVER] Backup MISSING - $(date '+%Y-%m-%d')" \
        "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\n\nNo backup log found for today.\nExpected: ${BACKUP_LOG}\n\nBackup may not have run at all.\nCheck cron: cat /etc/cron.d/homeserver-cron\nCheck cron log: grep CRON /var/log/syslog | tail -20"
    exit 0
fi

# Check 2: Does the log contain the success marker?
if grep -q "$SUCCESS_MARKER" "$BACKUP_LOG"; then
    log_msg "INFO" "$SCRIPT_NAME" "Backup OK for $(date '+%Y-%m-%d')"
    exit 0
fi

# Check 3: Log exists but no success — backup failed or is still running.
# Probe backup-all.sh's lock: if we CANNOT acquire it, a backup is still in
# progress, so the missing success marker is expected — skip the alert. This
# is more precise than matching the process name (which also matches manual
# runs, editors, or greps). The subshell releases the lock immediately on exit,
# so this probe never blocks a real backup.
BACKUP_LOCK="/run/backup-all.lock"
if [[ -e "$BACKUP_LOCK" ]] && ! ( flock -n 9 ) 9>"$BACKUP_LOCK"; then
    log_msg "WARN" "$SCRIPT_NAME" "Backup still running at $(date '+%H:%M') — skipping alert"
    exit 0
fi

# Check 3a: Log exists, backup is NOT still running, but the log is empty (0 bytes)
# or contains no log lines. This means the run produced no output at all — it was
# interrupted (server shutdown/kill) or died before logging. Distinct from
# "ran but a job failed", so it gets its own clear message.
if [[ ! -s "$BACKUP_LOG" ]] || ! grep -q '\[INFO\]\|\[ERROR\]' "$BACKUP_LOG" 2>/dev/null; then
    log_msg "ERROR" "$SCRIPT_NAME" "Backup log empty for $(date '+%Y-%m-%d') — run produced no output"
    send_alert_email \
        "[HOMESERVER] Backup NO OUTPUT - $(date '+%Y-%m-%d')" \
        "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\n\nToday's backup log exists but is empty (no log lines).\nLog: ${BACKUP_LOG}\n\nThe backup ran (log file was created) but produced no output — it was likely interrupted (server shutdown, OOM kill, or hung and killed) before completing.\n\nCheck:\n- cron execution: grep backup-all /var/log/syslog\n- system was up at 02:00: last reboot\n- run manually: sudo /opt/homeserver/scripts/backup/backup-all.sh --dry-run"
    exit 0
fi

# Backup failed — extract last few lines for context
TAIL_LINES=$(tail -5 "$BACKUP_LOG" 2>/dev/null || echo "(could not read log)")

log_msg "ERROR" "$SCRIPT_NAME" "Backup FAILED for $(date '+%Y-%m-%d')"
send_alert_email \
    "[HOMESERVER] Backup FAILED - $(date '+%Y-%m-%d')" \
    "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\n\nBackup log exists but success marker not found.\nLog: ${BACKUP_LOG}\n\nLast 5 lines:\n${TAIL_LINES}\n\nCheck full log: sudo cat ${BACKUP_LOG}"

exit 0
