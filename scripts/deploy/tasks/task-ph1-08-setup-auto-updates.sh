#!/bin/bash
# Task: Setup automated security updates
# Phase: 1 (Foundation)
# Number: 08
# Prerequisites: Task 1 complete (system updated)
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

# Source utility libraries
source /opt/homeserver/scripts/operations/utils/output-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Check if already completed (idempotency)
if dpkg -l | grep -q unattended-upgrades; then
    if systemctl is-active --quiet unattended-upgrades; then
        if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
            print_info "Automated updates already configured - skip"
            exit 0
        fi
    fi
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would install unattended-upgrades"
    print_info "[DRY-RUN] Would configure automatic updates (security only)"
    print_info "[DRY-RUN] Would enable automatic reboot at 3:00 AM"
    print_info "[DRY-RUN] Would start and enable service"
    exit 0
fi

print_header "Task 8: Setup Automated Security Updates"
echo ""

# Install unattended-upgrades
if ! dpkg -l | grep -q unattended-upgrades; then
    print_info "Installing unattended-upgrades..."
    apt install -y unattended-upgrades
else
    print_info "unattended-upgrades already installed"
fi

# Configure unattended-upgrades
print_info "Configuring unattended-upgrades..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

# Enable automatic updates
print_info "Enabling automatic updates..."
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# Start and enable service
print_info "Starting unattended-upgrades service..."
systemctl start unattended-upgrades
systemctl enable unattended-upgrades

print_success "Task 8 complete"
exit 0
