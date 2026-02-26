#!/bin/bash
# Task: Setup fail2ban for SSH protection
# Phase: 1 (Foundation)
# Number: 05
# Prerequisites: Task 1 complete (system updated), Task 3 complete (SSH hardened)
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
if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban; then
    if [[ -f /etc/fail2ban/jail.d/sshd.local ]]; then
        print_info "fail2ban already configured and running - skip"
        exit 0
    fi
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would install fail2ban"
    print_info "[DRY-RUN] Would create local configuration"
    print_info "[DRY-RUN] Would configure SSH jail (maxretry=3, bantime=3600)"
    print_info "[DRY-RUN] Would start and enable fail2ban"
    exit 0
fi

print_header "Task 5: Setup fail2ban"
echo ""

# Install fail2ban
if ! command -v fail2ban-client &>/dev/null; then
    print_info "Installing fail2ban..."
    apt install -y fail2ban
else
    print_info "fail2ban already installed"
fi

# Create local configuration if not exists
if [[ ! -f /etc/fail2ban/jail.local ]]; then
    print_info "Creating local configuration..."
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
fi

# Configure SSH jail
print_info "Configuring SSH jail..."
cat > /etc/fail2ban/jail.d/sshd.local << 'EOF'
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 3600
EOF

# Start and enable fail2ban
print_info "Starting fail2ban..."
systemctl start fail2ban
systemctl enable fail2ban

print_success "Task 5 complete"
exit 0
