#!/bin/bash
set -euo pipefail

# Utility: single-instance locking for scheduled jobs (acquire_lock)
# Usage: source this file, then call acquire_lock "/run/<name>.lock"

# Source guard (idempotent)
[[ -n "${LOCK_UTILS_LOADED:-}" ]] && return 0
readonly LOCK_UTILS_LOADED=1

# Acquire an exclusive, non-blocking flock so a slow run cannot overlap the next
# schedule. The lock lives under /run (root-owned tmpfs, cleared on reboot); the
# held file descriptor is released automatically when the process exits.
# Parameters: $1=lock file path, $2=script name (for log context)
# Behaviour (matches the REDACTED/backup-all convention):
#   - cannot open lock file        → return 2 (caller should treat as prereq fail)
#   - another instance holds it     → return 1 (caller should skip cleanly, exit 0)
#   - acquired                      → return 0
# The lock FD is 9; callers must not reuse FD 9 for other purposes.
acquire_lock() {
    local lock_file="$1"
    local script_name="${2:-${SCRIPT_NAME:-unknown}}"
    if ! exec 9>"$lock_file"; then
        log_msg "ERROR" "$script_name" "Cannot open lock file ${lock_file}"
        return 2
    fi
    if ! flock -n 9; then
        log_msg "WARN" "$script_name" "Another run is already in progress — skipping this run"
        return 1
    fi
    return 0
}
