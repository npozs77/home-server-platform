#!/bin/bash
set -euo pipefail
# Drift Detection — detect divergence between server repo and origin
# Usage: check-drift.sh [--warn-only]
#   Default: full checks + email alert on drift (for cron)
#   --warn-only: print warnings to stdout, no email (for deploy script headers)
# Exit Codes: 0=no drift, 1=drift detected
# Requirements: 12.1–12.12

SCRIPT_NAME="check-drift"
WARN_ONLY=false
[[ "${1:-}" == "--warn-only" ]] && WARN_ONLY=true

REPO_DIR="/opt/homeserver"

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../../operations/utils"
source "${UTILS_DIR}/log-utils.sh"

# Load foundation.env for ADMIN_EMAIL
FOUNDATION_ENV="${REPO_DIR}/configs/foundation.env"
[[ -f "$FOUNDATION_ENV" ]] && source "$FOUNDATION_ENV"

DRIFT_FOUND=false
WARNINGS=""

add_warning() {
    local msg="$1"
    WARNINGS="${WARNINGS}${msg}\n"
    DRIFT_FOUND=true
    if $WARN_ONLY; then
        log_msg "WARN" "$SCRIPT_NAME" "$msg"
    fi
}

cd "$REPO_DIR"

# Check 1: Remote configured
if ! git remote get-url origin &>/dev/null; then
    log_msg "INFO" "$SCRIPT_NAME" "No remote configured — skipping drift checks"
    exit 0
fi

# Fetch latest (graceful failure)
FETCH_OK=true
if ! git fetch origin 2>/dev/null; then
    add_warning "git fetch failed — network or deploy key issue, local-only checks follow"
    FETCH_OK=false
fi

# Check 2: Commits behind origin/main
if $FETCH_OK; then
    BEHIND=$(git rev-list HEAD..origin/main --count 2>/dev/null || echo "0")
    if [[ "$BEHIND" -gt 0 ]]; then
        add_warning "Server is ${BEHIND} commit(s) behind origin/main — run: git pull origin main"
    fi
fi

# Check 3: Local modifications
if ! git diff --quiet 2>/dev/null; then
    MODIFIED=$(git diff --name-only 2>/dev/null | head -20)
    add_warning "Local modifications detected (breaks git pull model):\n${MODIFIED}"
fi

# Check 4: Untracked files in scripts/ and configs/
UNTRACKED=$(git ls-files --others --exclude-standard -- scripts/ configs/ 2>/dev/null || true)
if [[ -n "$UNTRACKED" ]]; then
    add_warning "Untracked files in tracked directories:\n${UNTRACKED}"
fi

# Check 5: Detached HEAD
if ! git symbolic-ref HEAD &>/dev/null; then
    add_warning "Detached HEAD — run: git checkout main"
fi

# Report results
if $DRIFT_FOUND; then
    if ! $WARN_ONLY; then
        HOSTNAME_VAL=$(hostname 2>/dev/null || echo "unknown")
        CURRENT_HEAD=$(git log -1 --oneline 2>/dev/null || echo "unknown")
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        BODY="Drift detected on ${HOSTNAME_VAL}\n"
        BODY+="Repo: ${REPO_DIR}\n"
        BODY+="HEAD: ${CURRENT_HEAD}\n"
        BODY+="Timestamp: ${TIMESTAMP}\n\n"
        BODY+="Warnings:\n${WARNINGS}"
        log_msg "WARN" "$SCRIPT_NAME" "Drift detected — sending alert"
        send_alert_email "[homeserver] Drift detected on ${HOSTNAME_VAL}" "$BODY"
    fi
    exit 1
else
    log_msg "INFO" "$SCRIPT_NAME" "No drift — HEAD: $(git log -1 --oneline 2>/dev/null)"
    exit 0
fi
