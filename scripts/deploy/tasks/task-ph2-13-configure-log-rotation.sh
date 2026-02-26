#!/bin/bash
# Task: Configure log rotation for all services
# Phase: 2 (Infrastructure)
# Number: 13
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

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create logrotate configs for Caddy, Pi-hole, msmtp"
    exit 0
fi

# Configure log rotation for Caddy
print_info "Configuring log rotation for Caddy..."
cat > /etc/logrotate.d/caddy << 'EOF'
/var/log/caddy/*.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
    endscript
}
EOF
print_success "Created /etc/logrotate.d/caddy"

# Configure log rotation for Pi-hole
print_info "Configuring log rotation for Pi-hole..."
cat > /etc/logrotate.d/pihole << 'EOF'
/opt/homeserver/configs/pihole/etc-pihole/pihole.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        docker exec pihole pihole restartdns 2>/dev/null || true
    endscript
}
EOF
print_success "Created /etc/logrotate.d/pihole"

# Configure log rotation for msmtp
print_info "Configuring log rotation for msmtp..."
cat > /etc/logrotate.d/msmtp << 'EOF'
/var/log/msmtp.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    create 666 root root
}
EOF
print_success "Created /etc/logrotate.d/msmtp"

# Test logrotate configuration
print_info "Testing logrotate configuration..."
if logrotate -d /etc/logrotate.conf &> /dev/null; then
    print_success "Logrotate configuration is valid"
else
    print_error "Logrotate configuration has errors"
    exit 1
fi

print_success "Task complete"
exit 0
