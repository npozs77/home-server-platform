#!/bin/bash
# Task: Configure msmtp for SMTP2GO email relay
# Phase: 2 (Infrastructure)
# Number: 10
# Prerequisites:
#   - msmtp installed
#   - Configuration loaded (SMTP2GO_HOST, SMTP2GO_PORT, SMTP2GO_FROM, SMTP2GO_USER, SMTP2GO_PASS_ITEM_ID, HOMESERVER_PASS_SHARE_ID, ADMIN_USER)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   2 = Prerequisites not met
#   3 = Configuration error
# Environment Variables Required:
#   SMTP2GO_HOST, SMTP2GO_PORT, SMTP2GO_FROM, SMTP2GO_USER, SMTP2GO_PASS_ITEM_ID, HOMESERVER_PASS_SHARE_ID, ADMIN_USER
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
source /opt/homeserver/scripts/operations/utils/password-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate prerequisites
validate_required_vars "SMTP2GO_HOST" "SMTP2GO_PORT" "SMTP2GO_FROM" "SMTP2GO_USER" "SMTP2GO_PASS_ITEM_ID" "HOMESERVER_PASS_SHARE_ID" "ADMIN_USER" || exit 3

if ! command -v msmtp &> /dev/null; then
    print_error "msmtp not installed. Run Task 6.1 first."
    exit 2
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create /etc/msmtprc"
    exit 0
fi

# Fetch SMTP password from Proton Pass
print_info "Fetching SMTP2GO password from Proton Pass..."
SMTP2GO_PASSWORD=$(fetch_secret "$SMTP2GO_PASS_ITEM_ID" "password" "$ADMIN_USER")
if [[ -z "$SMTP2GO_PASSWORD" ]]; then
    print_error "Failed to fetch SMTP2GO password from Proton Pass"
    print_info "Ensure user $ADMIN_USER is logged into pass-cli"
    exit 1
fi
print_success "Password fetched successfully"

# Create msmtp configuration
print_info "Creating /etc/msmtprc..."
cat > /etc/msmtprc << EOF
# msmtp configuration for SMTP2GO
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

# SMTP2GO account
account        smtp2go
host           $SMTP2GO_HOST
port           $SMTP2GO_PORT
from           $SMTP2GO_FROM
user           $SMTP2GO_USER
password       $SMTP2GO_PASSWORD

# Set default account
account default : smtp2go
EOF

chmod 600 /etc/msmtprc
print_success "Created /etc/msmtprc (600 permissions)"

# Create log file
touch /var/log/msmtp.log
chmod 666 /var/log/msmtp.log
print_success "Created /var/log/msmtp.log"

print_success "Task complete"
exit 0
