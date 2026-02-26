#!/bin/bash
# Task: Export Caddy root CA certificate
# Phase: 2 (Infrastructure)
# Number: 06
# Prerequisites:
#   - Caddy container deployed and running
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   2 = Prerequisites not met
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

# Validate prerequisites
if ! docker ps | grep -q caddy; then
    print_error "Caddy container not running. Run Task 4.1 first."
    exit 2
fi

# Check idempotency
if [[ -f /opt/homeserver/configs/caddy/root-ca.crt ]]; then
    print_info "Root CA certificate already exported"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would export root CA certificate"
    exit 0
fi

# Wait for CA to initialize
print_info "Waiting for internal CA to initialize..."
sleep 10

# Export root CA certificate
print_info "Exporting root CA certificate..."
if docker exec caddy test -f /data/caddy/pki/authorities/local/root.crt; then
    docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > /opt/homeserver/configs/caddy/root-ca.crt
    chmod 644 /opt/homeserver/configs/caddy/root-ca.crt
    print_success "Root CA certificate exported to /opt/homeserver/configs/caddy/root-ca.crt"
    print_info "Install this certificate on all client devices"
else
    print_error "Root CA certificate not found. Caddy may still be initializing."
    print_info "Wait a few minutes and try again"
    exit 1
fi

print_success "Task complete"
exit 0
