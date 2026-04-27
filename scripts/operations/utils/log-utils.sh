#!/bin/bash
set -euo pipefail

# Utility: Structured logging (log_msg) and email alerts (send_alert_email)
# Usage: source this file, then call log_msg "INFO" "script" "message"

# Source guard (idempotent)
[[ -n "${LOG_UTILS_LOADED:-}" ]] && return 0
readonly LOG_UTILS_LOADED=1

# Structured log: YYYY-MM-DD HH:MM:SS - [LEVEL] - [SCRIPT] - message
# Parameters: $1=level (INFO|WARN|ERROR), $2=script_name, $3=message
# Output goes to stdout (INFO/WARN) or stderr (ERROR)
log_msg() {
    local level="$1"
    local script_name="$2"
    local message="$3"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local entry="${timestamp} - [${level}] - [${script_name}] - ${message}"
    if [[ "$level" == "ERROR" ]]; then
        echo "$entry" >&2
    else
        echo "$entry"
    fi
}

# Send email alert via msmtp (graceful fallback if msmtp unavailable)
# Parameters: $1=subject, $2=body
# Uses ADMIN_EMAIL from environment (sourced from foundation.env)
# Does NOT fail the calling script if msmtp is missing or send fails
send_alert_email() {
    local subject="$1"
    local body="$2"
    if [[ -z "${ADMIN_EMAIL:-}" ]]; then
        log_msg "WARN" "${SCRIPT_NAME:-unknown}" "ADMIN_EMAIL not set — alert logged locally only: ${subject}"
        return 0
    fi
    if ! command -v msmtp &>/dev/null; then
        log_msg "WARN" "${SCRIPT_NAME:-unknown}" "msmtp not available — alert logged locally only: ${subject}"
        return 0
    fi
    printf "Subject: %s\n\n%s" "$subject" "$body" | msmtp "${ADMIN_EMAIL}" 2>/dev/null || {
        log_msg "WARN" "${SCRIPT_NAME:-unknown}" "msmtp send failed — alert logged locally only: ${subject}"
    }
    return 0
}
