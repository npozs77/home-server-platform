#!/bin/bash
# Task: Configure local DNS records in Pi-hole
# Phase: 2 (Infrastructure)
# Number: 08
# Prerequisites:
#   - Pi-hole container deployed and running
#   - Configuration loaded (SERVER_IP, INTERNAL_SUBDOMAIN)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   2 = Prerequisites not met
#   3 = Configuration error
# Environment Variables Required:
#   SERVER_IP, INTERNAL_SUBDOMAIN
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
validate_required_vars "SERVER_IP" "INTERNAL_SUBDOMAIN" || exit 3

if ! docker ps | grep -q pihole; then
    print_error "Pi-hole container not running. Run Task 5.1 first."
    exit 2
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create custom.list"
    print_info "[DRY-RUN] Would restart Pi-hole DNS"
    exit 0
fi

# Add custom DNS records using Pi-hole v6 FTL command
print_info "Adding custom DNS records..."
docker exec pihole pihole-FTL --config dns.hosts "[\"$SERVER_IP $INTERNAL_SUBDOMAIN\", \"$SERVER_IP test.$INTERNAL_SUBDOMAIN\", \"$SERVER_IP pihole.$INTERNAL_SUBDOMAIN\", \"$SERVER_IP monitor.$INTERNAL_SUBDOMAIN\"]"

print_success "DNS records configured"
print_info "Test with: nslookup test.$INTERNAL_SUBDOMAIN $SERVER_IP"
print_success "Task complete"
exit 0
