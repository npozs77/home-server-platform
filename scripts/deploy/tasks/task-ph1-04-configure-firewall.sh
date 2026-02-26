#!/bin/bash
# Task: Configure UFW firewall
# Phase: 1 (Foundation)
# Number: 04
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
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    print_info "UFW firewall already configured and active - skip"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would install UFW"
    print_info "[DRY-RUN] Would set default policies (deny incoming, allow outgoing)"
    print_info "[DRY-RUN] Would allow SSH from LAN (192.168.1.0/24)"
    print_info "[DRY-RUN] Would allow HTTP/HTTPS from LAN"
    print_info "[DRY-RUN] Would allow Samba from LAN"
    print_info "[DRY-RUN] Would allow DNS from LAN"
    print_info "[DRY-RUN] Would enable UFW"
    exit 0
fi

print_header "Task 4: Configure Firewall (UFW)"
echo ""

# Install UFW
if ! command -v ufw &>/dev/null; then
    print_info "Installing UFW..."
    apt install -y ufw
else
    print_info "UFW already installed"
fi

# Set default policies
print_info "Setting default policies..."
ufw default deny incoming
ufw default allow outgoing

# Allow SSH from LAN
print_info "Allowing SSH from LAN..."
ufw allow from 192.168.1.0/24 to any port 22

# Allow HTTP/HTTPS from LAN
print_info "Allowing HTTP/HTTPS from LAN..."
ufw allow from 192.168.1.0/24 to any port 80
ufw allow from 192.168.1.0/24 to any port 443

# Allow Samba from LAN
print_info "Allowing Samba from LAN..."
ufw allow from 192.168.1.0/24 to any port 139
ufw allow from 192.168.1.0/24 to any port 445

# Allow DNS from LAN (for Pi-hole in Phase 2)
print_info "Allowing DNS from LAN..."
ufw allow from 192.168.1.0/24 to any port 53 proto tcp
ufw allow from 192.168.1.0/24 to any port 53 proto udp

# Enable UFW
print_info "Enabling UFW..."
echo "y" | ufw enable

print_success "Task 4 complete"
exit 0
