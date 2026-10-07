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
    WARNINGS="${WARNINGS}${msg}"$'\n'
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
# When running as root (sudo/cron), the user's SSH config isn't available.
# The remote URL may use an SSH alias (e.g. github-deploy) that only resolves
# via the user's ~/.ssh/config. We detect the deploy key and resolve the alias
# to the real hostname so git fetch works without SSH config.
FETCH_OK=true
_GIT_SSH_CMD=""
_FETCH_URL="origin"
# Fetch as the checkout's owner, never as root: a root fetch creates root-owned
# refs/objects for every new branch, and the owner's next `git pull` then fails
# with "cannot lock ref … Permission denied".
_AS_OWNER=()
if [[ $EUID -eq 0 ]]; then
    REPO_OWNER=$(stat -c '%U' "$REPO_DIR/.git" 2>/dev/null || echo "")
    if [[ -n "$REPO_OWNER" ]] && [[ "$REPO_OWNER" != "root" ]]; then
        _AS_OWNER=(runuser -u "$REPO_OWNER" --)
    fi
    DEPLOY_KEY="/home/${REPO_OWNER}/.ssh/deploy_key"
    if [[ -n "$REPO_OWNER" ]] && [[ -f "$DEPLOY_KEY" ]]; then
        _GIT_SSH_CMD="ssh -i ${DEPLOY_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
        # Resolve SSH alias in remote URL (e.g. git@github-deploy:org/repo → git@github.com:org/repo)
        _REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
        _SSH_HOST=$(echo "$_REMOTE_URL" | sed -n 's/^git@\([^:]*\):.*/\1/p')
        if [[ -n "$_SSH_HOST" ]] && [[ "$_SSH_HOST" != *"."* ]]; then
            # It's an alias (no dots) — look up real hostname from user's SSH config
            _REAL_HOST=$(sed -n "/^Host ${_SSH_HOST}\$/,/^Host /{ s/^[[:space:]]*HostName[[:space:]]*//p; }" "/home/${REPO_OWNER}/.ssh/config" 2>/dev/null || echo "")
            if [[ -n "$_REAL_HOST" ]]; then
                _FETCH_URL=$(echo "$_REMOTE_URL" | sed "s/^git@${_SSH_HOST}:/git@${_REAL_HOST}:/")
            fi
        fi
    fi
fi
if [[ -n "$_GIT_SSH_CMD" ]]; then
    ${_AS_OWNER[@]+"${_AS_OWNER[@]}"} env GIT_SSH_COMMAND="$_GIT_SSH_CMD" git fetch "$_FETCH_URL" "+refs/heads/*:refs/remotes/origin/*" 2>/dev/null || { add_warning "git fetch failed — network or deploy key issue, local-only checks follow"; FETCH_OK=false; }
else
    ${_AS_OWNER[@]+"${_AS_OWNER[@]}"} git fetch origin 2>/dev/null || { add_warning "git fetch failed — network or deploy key issue, local-only checks follow"; FETCH_OK=false; }
fi

# Check 2: Commits behind origin/{current branch}
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if $FETCH_OK && [[ -n "$CURRENT_BRANCH" ]]; then
    if git rev-parse "origin/${CURRENT_BRANCH}" &>/dev/null; then
        BEHIND=$(git rev-list "HEAD..origin/${CURRENT_BRANCH}" --count 2>/dev/null || echo "0")
        if [[ "$BEHIND" -gt 0 ]]; then
            add_warning "Server is ${BEHIND} commit(s) behind origin/${CURRENT_BRANCH} — run: deploy-update.sh ${CURRENT_BRANCH}"
        fi
    fi
    if [[ "$CURRENT_BRANCH" != "main" ]]; then
        log_msg "INFO" "$SCRIPT_NAME" "Server is on branch '${CURRENT_BRANCH}' (not main)"
    fi
fi

# Check 3: Local modifications
if ! git diff --quiet 2>/dev/null; then
    MODIFIED=$(git diff --name-only 2>/dev/null | head -20)
    MODIFIED_ONELINE=$(echo "$MODIFIED" | tr '\n' ', ' | sed 's/,$//')
    add_warning "Local modifications detected (breaks git pull model): ${MODIFIED_ONELINE}"
fi

# Check 4: Untracked files in scripts/ and configs/
UNTRACKED=$(git ls-files --others --exclude-standard -- scripts/ configs/ 2>/dev/null || true)
if [[ -n "$UNTRACKED" ]]; then
    UNTRACKED_ONELINE=$(echo "$UNTRACKED" | tr '\n' ', ' | sed 's/,$//')
    add_warning "Untracked files in tracked directories: ${UNTRACKED_ONELINE}"
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
