#!/bin/bash
# Container Health Check — monitors critical Docker containers, sends consolidated alert
# Usage: check-container-health.sh [--dry-run]
# Exit Codes: 0=all healthy, 1=any unhealthy/missing
# Requirements: 8.1-8.10, 10.2, 10.3

set -euo pipefail

SCRIPT_NAME="check-container-health"
CONFIG_FILE="/opt/homeserver/configs/monitoring/critical-containers.conf"
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        *) ;;
    esac
done

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"
source "${UTILS_DIR}/log-utils.sh"
source "${UTILS_DIR}/env-utils.sh"
load_env_files || log_msg "WARN" "$SCRIPT_NAME" "Could not load env files"

# Read container list from config (skip comments and blank lines)
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "Config file not found: ${CONFIG_FILE}"
    exit 3
fi
mapfile -t CONTAINERS < <(grep -v '^\s*#' "$CONFIG_FILE" | grep -v '^\s*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
    log_msg "WARN" "$SCRIPT_NAME" "No containers listed in ${CONFIG_FILE}"
    exit 0
fi

DRY_LABEL=""; $DRY_RUN && DRY_LABEL=" (dry-run)"
log_msg "INFO" "$SCRIPT_NAME" "Checking ${#CONTAINERS[@]} containers${DRY_LABEL}"

UNHEALTHY=()
MISSING=()
HEALTHY=()

for container in "${CONTAINERS[@]}"; do
    if ! docker inspect --format='{{.State.Status}}' "$container" &>/dev/null; then
        MISSING+=("$container")
        log_msg "WARN" "$SCRIPT_NAME" "${container}: not found (stopped or removed)"
        continue
    fi
    # Check health status if health check is configured, otherwise use running state
    HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null)
    if [[ "$HEALTH" == "healthy" || "$HEALTH" == "running" ]]; then
        HEALTHY+=("$container")
        log_msg "INFO" "$SCRIPT_NAME" "${container}: ${HEALTH}"
    else
        UNHEALTHY+=("${container}: ${HEALTH}")
        log_msg "WARN" "$SCRIPT_NAME" "${container}: ${HEALTH}"
    fi
done

PROBLEM_COUNT=$(( ${#UNHEALTHY[@]} + ${#MISSING[@]} ))

if [[ $PROBLEM_COUNT -eq 0 ]]; then
    log_msg "INFO" "$SCRIPT_NAME" "All ${#CONTAINERS[@]} containers healthy"
    exit 0
fi

# Build consolidated alert
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
SUBJECT="[HOMESERVER] Container Alert - ${TIMESTAMP}"
BODY="Hostname: $(hostname)\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\n"

if [[ ${#UNHEALTHY[@]} -gt 0 ]]; then
    BODY="${BODY}\nUnhealthy containers:"
    for entry in "${UNHEALTHY[@]}"; do BODY="${BODY}\n  - ${entry}"; done
fi
if [[ ${#MISSING[@]} -gt 0 ]]; then
    BODY="${BODY}\nMissing containers:"
    for entry in "${MISSING[@]}"; do BODY="${BODY}\n  - ${entry} (not found)"; done
fi
if [[ ${#HEALTHY[@]} -gt 0 ]]; then
    BODY="${BODY}\n\nHealthy containers:"
    for entry in "${HEALTHY[@]}"; do BODY="${BODY}\n  - ${entry}"; done
fi

if $DRY_RUN; then
    log_msg "INFO" "$SCRIPT_NAME" "dry-run: would send alert — ${SUBJECT}"
    printf "dry-run alert body:\n${BODY}\n"
else
    send_alert_email "$SUBJECT" "$BODY"
fi

log_msg "WARN" "$SCRIPT_NAME" "${PROBLEM_COUNT} container(s) need attention"
exit 1
