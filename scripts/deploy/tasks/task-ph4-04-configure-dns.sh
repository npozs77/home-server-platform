#!/bin/bash
# Task: Configure DNS record for Immich
# Phase: 4 (Photo Management)
# Number: 04
# Prerequisites:
#   - Phase 2 complete (Pi-hole running)
#   - Configuration loaded (SERVER_IP, IMMICH_DOMAIN)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   SERVER_IP, IMMICH_DOMAIN
# Environment Variables Optional:
#   None
#
# Pi-hole v6 Note:
#   Pi-hole v6 no longer uses custom.list for local DNS records.
#   Records are managed via pihole-FTL --config dns.hosts (pihole.toml).
#   Phase 2 (task-ph2-08) established this pattern. This script appends
#   the Immich record to the existing dns.hosts array.

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

# Configuration paths
FOUNDATION_ENV="/opt/homeserver/configs/foundation.env"
SERVICES_ENV="/opt/homeserver/configs/services.env"

# Source environment files (only if vars not already exported by orchestrator)
if [[ -z "${IMMICH_DOMAIN:-}" ]]; then
    print_info "Loading configuration..."
    if [[ -f "$SERVICES_ENV" ]]; then
        source "$SERVICES_ENV"
    fi
    if [[ -z "${SERVER_IP:-}" ]] && [[ -f "$FOUNDATION_ENV" ]]; then
        source "$FOUNDATION_ENV"
    fi
fi

# Validate required environment variables
if [[ -z "${SERVER_IP:-}" ]]; then
    print_error "SERVER_IP environment variable not set"
    exit 3
fi

if [[ -z "${IMMICH_DOMAIN:-}" ]]; then
    print_error "IMMICH_DOMAIN environment variable not set"
    exit 3
fi

# Validate prerequisites
print_info "Validating prerequisites..."

# Check Pi-hole is running
if ! docker ps --format '{{.Names}}' | grep -q '^pihole$'; then
    print_error "Pi-hole container is not running (should be deployed in Phase 2)"
    exit 3
fi

# Define the DNS record
DNS_RECORD="${SERVER_IP} ${IMMICH_DOMAIN}"

# Read current dns.hosts JSON array from Pi-hole
CURRENT_JSON=$(docker exec pihole pihole-FTL --config dns.hosts 2>/dev/null || echo "[]")

# Check idempotency
if echo "$CURRENT_JSON" | grep -q "${IMMICH_DOMAIN}"; then
    print_info "Immich DNS record already exists in Pi-hole dns.hosts"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would add Immich DNS record to Pi-hole dns.hosts"
    print_info "[DRY-RUN] Record: ${DNS_RECORD}"
else
    print_info "Adding Immich DNS record to Pi-hole dns.hosts..."

    # Append new entry to the existing JSON array
    # If current is empty "[]", create new array; otherwise inject before closing "]"
    TRIMMED=$(echo "$CURRENT_JSON" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ "$TRIMMED" == "[]" ]]; then
        NEW_HOSTS_JSON="[\"${DNS_RECORD}\"]"
    else
        # Insert new entry before the closing bracket
        NEW_HOSTS_JSON=$(echo "$TRIMMED" | sed "s/]$/, \"${DNS_RECORD}\"]/" )
    fi

    # Apply the updated dns.hosts array
    print_info "Setting dns.hosts: ${NEW_HOSTS_JSON}"
    if docker exec pihole pihole-FTL --config dns.hosts "${NEW_HOSTS_JSON}"; then
        print_success "Immich DNS record added to Pi-hole"
    else
        print_error "Failed to update Pi-hole dns.hosts"
        exit 1
    fi

    # Full container restart required — pihole-FTL --config writes to pihole.toml
    # but FTL does not reload DNS records without a restart.
    # Also reapplies Docker iptables/NAT rules (incident lesson from Phase 3).
    print_info "Restarting Pi-hole container to apply DNS changes..."
    docker restart pihole
    sleep 5

    # Verify DNS resolution
    print_info "Verifying DNS resolution..."
    sleep 3  # Wait for FTL to apply changes

    if nslookup "${IMMICH_DOMAIN}" 127.0.0.1 &> /dev/null; then
        RESOLVED_IP=$(nslookup "${IMMICH_DOMAIN}" 127.0.0.1 | grep -A1 "Name:" | grep "Address:" | awk '{print $2}')
        if [[ "$RESOLVED_IP" == "$SERVER_IP" ]]; then
            print_success "DNS resolution verified: ${IMMICH_DOMAIN} -> ${SERVER_IP}"
        else
            print_info "DNS resolution returned unexpected IP: ${RESOLVED_IP} (expected: ${SERVER_IP})"
        fi
    else
        print_info "DNS resolution not yet working (FTL may need more time)"
    fi

    print_success "Immich DNS record configured"
    print_info "Immich will be accessible at: https://${IMMICH_DOMAIN}"
    print_info ""
    print_info "IMPORTANT: After DNS configuration, restart Caddy to trigger certificate generation:"
    print_info "  docker restart caddy"
fi

print_success "Task complete"
exit 0
