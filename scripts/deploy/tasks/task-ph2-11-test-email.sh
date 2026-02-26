#!/bin/bash
# Task: Test msmtp email delivery
# Phase: 2 (Infrastructure)
# Number: 11
# Prerequisites:
#   - msmtp configured
#   - Configuration loaded (ADMIN_EMAIL, ADMIN_USER)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   2 = Prerequisites not met
#   3 = Configuration error
# Environment Variables Required:
#   ADMIN_EMAIL, ADMIN_USER
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
source /opt/homeserver/scripts/operations/utils/env-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate prerequisites
validate_required_vars "ADMIN_EMAIL" "ADMIN_USER" || exit 3

if ! command -v msmtp &> /dev/null; then
    print_error "msmtp not installed. Run Task 6.1 first."
    exit 2
fi

if [[ ! -f /etc/msmtprc ]]; then
    print_error "msmtp not configured. Run Task 7.1 first."
    exit 2
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would send test email to $ADMIN_EMAIL as $ADMIN_USER"
    exit 0
fi

print_info "Sending test email to $ADMIN_EMAIL..."
sudo -u "$ADMIN_USER" bash -c "echo -e 'Subject: Home Server Test Email\n\nThis is a test email from your home server.\nIf you receive this, msmtp is configured correctly.' | msmtp '$ADMIN_EMAIL'"

if [[ $? -eq 0 ]]; then
    print_success "Test email sent successfully"
    print_info "Check $ADMIN_EMAIL for the test message"
else
    print_error "Failed to send test email"
    print_info "Check /var/log/msmtp.log for details"
    exit 1
fi

print_success "Task complete"
exit 0
