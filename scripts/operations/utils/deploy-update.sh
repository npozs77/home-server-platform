#!/bin/bash
set -euo pipefail
# Deploy Update — pull latest from Private_Repo and report deployed commit
# Usage: sudo bash scripts/operations/utils/deploy-update.sh [branch]
#   branch — optional Git branch to pull (default: main)
#   Examples:
#     deploy-update.sh                     # pulls origin/main
#     deploy-update.sh dev/phase6-helper   # pulls origin/dev/phase6-helper
# Exit Codes: 0=success, 1=git pull failed (network, merge conflict, deploy key)
# Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, Prerequisites (deploy-update.sh branch support)

SCRIPT_NAME="deploy-update"
REPO_DIR="/opt/homeserver"
BRANCH="${1:-main}"

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/log-utils.sh"

# Verify repo directory exists
if [[ ! -d "${REPO_DIR}/.git" ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "Git repository not found at ${REPO_DIR}"
    exit 1
fi

cd "$REPO_DIR"

# Pull latest from origin
log_msg "INFO" "$SCRIPT_NAME" "Pulling latest from origin/${BRANCH}..."
if ! git pull origin "${BRANCH}" 2>&1; then
    log_msg "ERROR" "$SCRIPT_NAME" "git pull failed — check network connectivity, deploy key, or merge conflicts"
    exit 1
fi

# Report deployed commit
DEPLOYED_COMMIT="$(git log -1 --oneline)"
log_msg "INFO" "$SCRIPT_NAME" "Deployed: ${DEPLOYED_COMMIT}"
