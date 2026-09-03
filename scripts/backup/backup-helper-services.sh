#!/bin/bash
set -euo pipefail
# Backup Helper-Managed Services — dynamic backup from services.yml
# Purpose: Reads services.yml at runtime, backs up data dirs and runs pre_commands
# Usage: backup-helper-services.sh [--dry-run] [service-name]
#   No args: back up all helper-managed services
#   service-name: back up a single service
# Exit Codes: 0=success, 1=failure
# Requirements: 31.1, 31.4, 31.5, 31.6, 31.7, 31.8

SCRIPT_NAME="backup-helper-services"
DRY_RUN=false
TARGET_SERVICE=""

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../operations/utils"
source "${UTILS_DIR}/log-utils.sh"

# Load configuration
[[ -f /opt/homeserver/configs/foundation.env ]] && source /opt/homeserver/configs/foundation.env
[[ -f /opt/homeserver/configs/services.env ]] && source /opt/homeserver/configs/services.env

BACKUP_MOUNT="${BACKUP_MOUNT:-/mnt/backup}"
SERVICES_CONFIG="/opt/homeserver/configs/helper-services/services.yml"
DATA_BASE="/mnt/data/services"

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        -*) log_msg "WARN" "$SCRIPT_NAME" "Unknown flag: $arg" ;;
        *) TARGET_SERVICE="$arg" ;;
    esac
done

# Preflight: yq required
if ! command -v yq &>/dev/null; then
    log_msg "ERROR" "$SCRIPT_NAME" "yq is required but not installed"
    exit 1
fi

# Preflight: services.yml must exist
if [[ ! -f "$SERVICES_CONFIG" ]]; then
    log_msg "INFO" "$SCRIPT_NAME" "No services.yml found — nothing to back up"
    exit 0
fi

DRY_LABEL=""; $DRY_RUN && DRY_LABEL=" (dry-run)"
log_msg "INFO" "$SCRIPT_NAME" "Starting helper-services backup${DRY_LABEL}"

FAILURES=0
BACKED_UP=0

# Back up a single service
backup_service() {
    local svc="$1"
    local data_dir="${DATA_BASE}/${svc}"
    local backup_dest="${BACKUP_MOUNT}/helper-services/${svc}"
    local timestamp; timestamp=$(date +%Y%m%d_%H%M%S)

    # Skip if data dir does not exist (service not deployed)
    if [[ ! -d "$data_dir" ]]; then
        log_msg "INFO" "$SCRIPT_NAME" "${svc}: no data directory — skipping"
        return 0
    fi

    # Skip disabled services
    local enabled; enabled=$(yq -r ".services.${svc}.enabled" "$SERVICES_CONFIG")
    if [[ "$enabled" == "false" ]]; then
        log_msg "INFO" "$SCRIPT_NAME" "${svc}: disabled — skipping"
        return 0
    fi

    log_msg "INFO" "$SCRIPT_NAME" "${svc}: starting backup"

    if $DRY_RUN; then
        log_msg "INFO" "$SCRIPT_NAME" "${svc}: dry-run — would create ${backup_dest}"
    else
        mkdir -p "$backup_dest"
    fi

    # Run pre_command if defined (app-aware backup step)
    local pre_cmd; pre_cmd=$(yq -r ".services.${svc}.backup.pre_command // \"\"" "$SERVICES_CONFIG")
    local pre_out; pre_out=$(yq -r ".services.${svc}.backup.pre_command_output // \"\"" "$SERVICES_CONFIG")

    if [[ -n "$pre_cmd" ]]; then
        # A pre_command is typically a `docker exec <container> …` snapshot step
        # (e.g. sqlite3 .backup). If that container is not running we skip the
        # pre_command with a clear WARN instead of letting `eval` fail with a
        # cryptic docker error. We deliberately CONTINUE to the rsync below: the
        # live data dir (including the DB file) is still worth backing up, just
        # without the consistent pre-snapshot. This mirrors backup-wiki-llm.sh,
        # which skips pg_dump on a down DB but still rsyncs. See the
        # down-container policy note in docs/12-runbooks.md.
        # Identify the container ONLY for the simple, unambiguous form
        # `docker exec <container> …` (the word immediately after `exec` is not
        # a flag). We deliberately do NOT try to parse flag forms like
        # `docker exec -u postgres <container>` — guessing there risks inspecting
        # the wrong name, so in that case we skip the up-check and just run the
        # pre_command as before (today's behaviour). The repo's pre_commands use
        # the simple form.
        local pre_container=""
        if [[ "$pre_cmd" =~ docker[[:space:]]+exec[[:space:]]+([^-][^[:space:]]*) ]]; then
            pre_container="${BASH_REMATCH[1]}"
        fi

        local skip_pre=false
        if [[ -n "$pre_container" ]]; then
            local pre_state
            pre_state=$(docker inspect --format='{{.State.Status}}' "$pre_container" 2>/dev/null || echo "absent")
            if [[ "$pre_state" != "running" ]]; then
                log_msg "WARN" "$SCRIPT_NAME" "${svc}: pre_command container ${pre_container} is ${pre_state} — skipping snapshot, backing up data dir as-is"
                skip_pre=true
            fi
        fi

        if $DRY_RUN; then
            log_msg "INFO" "$SCRIPT_NAME" "${svc}: dry-run — would run pre_command: ${pre_cmd}"
        elif $skip_pre; then
            : # container down — WARN already logged, fall through to rsync
        else
            log_msg "INFO" "$SCRIPT_NAME" "${svc}: running pre_command"
            if eval "$pre_cmd" > "${data_dir}/${pre_out}" 2>&1; then
                log_msg "INFO" "$SCRIPT_NAME" "${svc}: pre_command completed"
            else
                log_msg "ERROR" "$SCRIPT_NAME" "${svc}: pre_command failed"
                FAILURES=$((FAILURES + 1))
                return 1
            fi
        fi
    fi

    # Rsync data directory
    if $DRY_RUN; then
        log_msg "INFO" "$SCRIPT_NAME" "${svc}: dry-run — would rsync ${data_dir}/ to ${backup_dest}/data-${timestamp}/"
    else
        if rsync -a --delete "${data_dir}/" "${backup_dest}/data-${timestamp}/"; then
            log_msg "INFO" "$SCRIPT_NAME" "${svc}: data dir synced"
        else
            log_msg "ERROR" "$SCRIPT_NAME" "${svc}: rsync failed for data dir"
            FAILURES=$((FAILURES + 1))
            return 1
        fi
    fi

    # Rsync additional paths if defined
    local path_count; path_count=$(yq -r ".services.${svc}.backup.paths | length" "$SERVICES_CONFIG" 2>/dev/null || echo "0")
    if [[ "$path_count" -gt 0 ]]; then
        while IFS= read -r extra_path; do
            [[ -z "$extra_path" ]] && continue
            if $DRY_RUN; then
                log_msg "INFO" "$SCRIPT_NAME" "${svc}: dry-run — would rsync ${extra_path}"
            else
                if rsync -a "$extra_path" "${backup_dest}/"; then
                    log_msg "INFO" "$SCRIPT_NAME" "${svc}: synced additional path ${extra_path}"
                else
                    log_msg "WARN" "$SCRIPT_NAME" "${svc}: rsync failed for ${extra_path}"
                fi
            fi
        done < <(yq -r ".services.${svc}.backup.paths[]" "$SERVICES_CONFIG" 2>/dev/null)
    fi

    BACKED_UP=$((BACKED_UP + 1))
    log_msg "INFO" "$SCRIPT_NAME" "${svc}: backup complete"
}

# Main: back up target service or all services
if [[ -n "$TARGET_SERVICE" ]]; then
    # Verify service exists in services.yml
    if ! yq -e ".services.${TARGET_SERVICE}" "$SERVICES_CONFIG" >/dev/null 2>&1; then
        log_msg "ERROR" "$SCRIPT_NAME" "Service '${TARGET_SERVICE}' not found in ${SERVICES_CONFIG}"
        exit 1
    fi
    backup_service "$TARGET_SERVICE"
else
    # Back up all services
    while IFS= read -r svc; do
        backup_service "$svc" || true  # isolate failures per service
    done < <(yq -r '.services | keys | .[]' "$SERVICES_CONFIG")
fi

# Summary
if [[ $FAILURES -gt 0 ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "Backup completed with ${FAILURES} failure(s), ${BACKED_UP} service(s) backed up"
    exit 1
fi

log_msg "INFO" "$SCRIPT_NAME" "Backup complete: ${BACKED_UP} service(s) backed up"
exit 0
