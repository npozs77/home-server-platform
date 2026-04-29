#!/bin/bash
# Backup Status Watchdog
# Purpose: Independent check that today's backup ran and succeeded
# Schedule: Daily at 06:00 (after backup window at 02:00)
# Logic:
#   1. Check if today's backup log exists
#   2. If missing → backup never ran (alert)
#   3. If exists but no "All backup jobs completed successfully" → backup failed (alert)
#   4. If success marker found → all good, no alert
#
# This is a safety net — catches cases where the backup script itself
# crashes before its own error handling can send an alert (e.g. set -e
# killing the process during env sourcing).
#
# Usage: check-backup-status.sh
# Exit Codes: 0=OK or alert sent, 1=alert send failure

set -euo pipefail

SCRIPT_NAME="check-backup-status"

# Source only what we need (no secrets.env — learned that lesson)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"
source "${UTILS_DIR}/log-utils.sh"
[[ -f /opt/homeserver/configs/foundation.env ]] && source /opt/homeserver/configs/foundation.env

LOG_DIR="/var/log/homeserver"
TODAY=$(date '+%Y%m%d')
BACKUP_LOG="${LOG_DIR}/backup-${TODAY}.log"
SUCCESS_MARKER="All backup jobs completed successfully"

# Check 1: Does today's log exist?
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

# Check 3: Log exists but no success — backup failed or is still running
# Check if backup-all.sh is still running (unlikely at 06:00, but possible)
if pgrep -f "backup-all.sh" > /dev/null 2>&1; then
    log_msg "WARN" "$SCRIPT_NAME" "Backup still running at $(date '+%H:%M') — skipping alert"
    exit 0
fi

# Backup failed — extract last few lines for context
TAIL_LINES=$(tail -5 "$BACKUP_LOG" 2>/dev/null || echo "(could not read log)")

log_msg "ERROR" "$SCRIPT_NAME" "Backup FAILED for $(date '+%Y-%m-%d')"
send_alert_email \
    "[HOMESERVER] Backup FAILED - $(date '+%Y-%m-%d')" \
    "Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\n\nBackup log exists but success marker not found.\nLog: ${BACKUP_LOG}\n\nLast 5 lines:\n${TAIL_LINES}\n\nCheck full log: sudo cat ${BACKUP_LOG}"

exit 0
