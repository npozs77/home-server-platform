#!/bin/bash
set -euo pipefail
# Deploy Update — converge the server to exactly match origin/<branch> (IaC).
# The Git repo is the source of truth; the server is a disposable checkout that
# must equal origin. This does fetch + checkout + reset --hard (not a merge), so
# the working tree becomes identical to the remote — no merge commits, no drift.
#
# Usage: sudo bash scripts/operations/utils/deploy-update.sh [branch] [--force]
#   branch   — Git branch to converge to (default: main)
#   --force  — approve discarding local changes without the interactive prompt
#
# Local changes are a violation of the IaC model. If any are present this script
# WARNS, shows what would be discarded, and STOPS — it only discards them after
# explicit approval (interactive confirmation, or --force for automation).
#
# Exit Codes: 0=success, 1=git failure / local changes not approved for removal
# Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, Prerequisites (deploy-update.sh branch support)

SCRIPT_NAME="deploy-update"
REPO_DIR="/opt/homeserver"

# Parse args: first non-flag positional is the branch; --force approves removal.
BRANCH="${1:-main}"
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        -*) ;;
        *) BRANCH="$arg" ;;
    esac
done

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/log-utils.sh"

if [[ ! -d "${REPO_DIR}/.git" ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "Git repository not found at ${REPO_DIR}"
    exit 1
fi

cd "$REPO_DIR"

# Detect local drift: modified/staged tracked files OR untracked files.
LOCAL_CHANGES="$(git status --porcelain 2>/dev/null)"
if [[ -n "$LOCAL_CHANGES" ]]; then
    log_msg "WARN" "$SCRIPT_NAME" "Local changes detected on the server (violates the IaC model)"
    echo "  The following local changes would be DISCARDED to match origin/${BRANCH}:"
    echo "$LOCAL_CHANGES" | sed 's/^/    /'

    if ! $FORCE; then
        if [[ -t 0 ]]; then
            read -r -p "  Discard these local changes? [y/N]: " confirm
            case "$confirm" in
                y|Y|yes|YES) log_msg "INFO" "$SCRIPT_NAME" "Approved — discarding local changes" ;;
                *) log_msg "INFO" "$SCRIPT_NAME" "Aborted — no changes made. Investigate with: git status"; exit 1 ;;
            esac
        else
            log_msg "ERROR" "$SCRIPT_NAME" "Local changes present and not approved. Re-run with --force to discard, or investigate: git status"
            exit 1
        fi
    fi
fi

# Fetch the source of truth.
log_msg "INFO" "$SCRIPT_NAME" "Fetching origin..."
if ! git fetch origin 2>&1; then
    log_msg "ERROR" "$SCRIPT_NAME" "git fetch failed — check network connectivity or deploy key"
    exit 1
fi

# Switch branch if needed (the caller declares the target; the server obeys).
CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED")"
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
    log_msg "INFO" "$SCRIPT_NAME" "Switching from '${CURRENT_BRANCH}' to '${BRANCH}'..."
    if ! git checkout "$BRANCH" 2>&1; then
        log_msg "ERROR" "$SCRIPT_NAME" "git checkout ${BRANCH} failed"
        exit 1
    fi
fi

# Converge the working tree to exactly match the remote (discards approved drift).
log_msg "INFO" "$SCRIPT_NAME" "Resetting to origin/${BRANCH}..."
if ! git reset --hard "origin/${BRANCH}" 2>&1; then
    log_msg "ERROR" "$SCRIPT_NAME" "git reset --hard origin/${BRANCH} failed"
    exit 1
fi

# Report the deployed commit.
DEPLOYED_COMMIT="$(git log -1 --oneline)"
log_msg "INFO" "$SCRIPT_NAME" "Deployed: ${DEPLOYED_COMMIT}"
