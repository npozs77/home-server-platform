#!/bin/bash
# Task: Update system packages and set timezone/hostname
# Phase: 1 (Foundation)
# Number: 01
# Prerequisites: None (first task)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   TIMEZONE, HOSTNAME
# Environment Variables Optional:
#   None

set -euo pipefail
# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utility libraries
source /opt/homeserver/scripts/operations/utils/output-utils.sh
source /opt/homeserver/scripts/operations/utils/env-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate required environment variables
validate_required_vars "TIMEZONE" "HOSTNAME" || exit 3

# Check if already completed (idempotency)
current_timezone=$(timedatectl show --property=Timezone --value)
current_hostname=$(hostnamectl --static)

if [[ "$current_timezone" == "$TIMEZONE" ]] && [[ "$current_hostname" == "$HOSTNAME" ]]; then
    # Check if essential tools installed
    if command -v git &>/dev/null && command -v vim &>/dev/null && command -v curl &>/dev/null; then
        print_info "System already updated and configured - skip"
        exit 0
    fi
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would update package lists"
    print_info "[DRY-RUN] Would upgrade all packages"
    print_info "[DRY-RUN] Would set timezone to: $TIMEZONE"
    print_info "[DRY-RUN] Would set hostname to: $HOSTNAME"
    print_info "[DRY-RUN] Would install essential tools (git, vim, curl, wget, htop, net-tools)"
    exit 0
fi

print_header "Task 1: Update System Packages and Basic Configuration"
echo ""

# Update package lists
print_info "Updating package lists..."
apt update

# Upgrade packages
print_info "Upgrading packages..."
apt upgrade -y

# Set timezone
print_info "Setting timezone to $TIMEZONE..."
timedatectl set-timezone "$TIMEZONE"

# Set hostname
print_info "Setting hostname to $HOSTNAME..."
hostnamectl set-hostname "$HOSTNAME"

# Install essential tools
print_info "Installing essential tools..."
apt install -y git vim curl wget htop net-tools

print_success "Task 1 complete"
exit 0
