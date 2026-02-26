#!/bin/bash
# Task: Install msmtp package for email notifications
# Phase: 2 (Infrastructure)
# Number: 09
# Prerequisites:
#   - Phase 1 complete
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
# Environment Variables Required:
#   None
# Environment Variables Optional:
#   None

set -euo pipefail
# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utilities (absolute paths)
source /opt/homeserver/scripts/operations/utils/output-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Check idempotency
if command -v msmtp &> /dev/null; then
    print_info "msmtp already installed"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would install msmtp and msmtp-mta packages"
    exit 0
fi

print_info "Installing msmtp packages..."
apt-get update -qq
apt-get install -y msmtp msmtp-mta

if command -v msmtp &> /dev/null; then
    print_success "msmtp installed successfully"
else
    print_error "msmtp installation failed"
    exit 1
fi

print_success "Task complete"
exit 0
