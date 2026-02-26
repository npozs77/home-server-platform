#!/bin/bash
# Task: Harden SSH configuration
# Phase: 1 (Foundation)
# Number: 03
# Prerequisites: Task 1 complete (system updated)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
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
if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null && \
   grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config 2>/dev/null && \
   grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
    print_info "SSH already hardened - skip"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would backup SSH config"
    print_info "[DRY-RUN] Would set PasswordAuthentication no"
    print_info "[DRY-RUN] Would set PubkeyAuthentication yes"
    print_info "[DRY-RUN] Would set PermitRootLogin no"
    print_info "[DRY-RUN] Would set ClientAliveInterval 300"
    print_info "[DRY-RUN] Would restart SSH service"
    exit 0
fi

print_header "Task 3: Harden SSH Access"
echo ""

# Backup SSH config if not already backed up
if [[ ! -f /etc/ssh/sshd_config.backup ]]; then
    print_info "Backing up SSH config..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
fi

# Update SSH config
print_info "Updating SSH configuration..."
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 12/' /etc/ssh/sshd_config

# Add if not present
grep -q "^ClientAliveInterval" /etc/ssh/sshd_config || echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config || echo "ClientAliveCountMax 12" >> /etc/ssh/sshd_config

# Test config
print_info "Testing SSH configuration..."
sshd -t

# Restart SSH
print_info "Restarting SSH service..."
systemctl restart ssh

print_success "Task 3 complete"
print_info "IMPORTANT: Ensure SSH key authentication is working before logging out!"
exit 0
