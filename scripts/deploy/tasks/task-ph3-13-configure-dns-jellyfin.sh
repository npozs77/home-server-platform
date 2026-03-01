#!/bin/bash
# Task: Configure DNS record for Jellyfin
# Phase: 3 (Core Services)
# Number: 13
# Prerequisites:
#   - Phase 2 complete
#   - Pi-hole running
#   - Configuration loaded (SERVER_IP, INTERNAL_SUBDOMAIN)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
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

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate required environment variables
if [[ -z "${SERVER_IP:-}" ]]; then
    print_error "SERVER_IP environment variable not set"
    exit 3
fi

if [[ -z "${INTERNAL_SUBDOMAIN:-}" ]]; then
    print_error "INTERNAL_SUBDOMAIN environment variable not set"
    exit 3
fi

# Validate prerequisites
print_info "Validating prerequisites..."

# Check Pi-hole is running
if ! docker ps --format '{{.Names}}' | grep -q '^pihole$'; then
    print_error "Pi-hole container is not running (should be deployed in Phase 2)"
    exit 3
fi

# Check custom.list exists
if [[ ! -f /opt/homeserver/configs/pihole/custom.list ]]; then
    print_error "/opt/homeserver/configs/pihole/custom.list does not exist (should be created in Phase 2)"
    exit 3
fi

# Define Jellyfin domain
JELLYFIN_DOMAIN="media.${INTERNAL_SUBDOMAIN}"

# Check idempotency - verify entry exists in BOTH local file AND Pi-hole container
LOCAL_HAS_ENTRY=false
PIHOLE_HAS_ENTRY=false

if grep -q "${JELLYFIN_DOMAIN}" /opt/homeserver/configs/pihole/custom.list; then
    LOCAL_HAS_ENTRY=true
fi

if docker exec pihole grep -q "${JELLYFIN_DOMAIN}" /etc/pihole/custom.list 2>/dev/null; then
    PIHOLE_HAS_ENTRY=true
fi

if [[ "$LOCAL_HAS_ENTRY" == true ]] && [[ "$PIHOLE_HAS_ENTRY" == true ]]; then
    print_info "Jellyfin DNS record already exists in custom.list and Pi-hole container"
    exit 0
elif [[ "$LOCAL_HAS_ENTRY" == true ]] && [[ "$PIHOLE_HAS_ENTRY" == false ]]; then
    print_info "Jellyfin DNS record exists in local file but not in Pi-hole container - syncing..."
    docker cp /opt/homeserver/configs/pihole/custom.list pihole:/etc/pihole/custom.list
    docker exec pihole pihole reloaddns
    print_success "Jellyfin DNS record synced to Pi-hole"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would add Jellyfin DNS record to custom.list"
    print_info "[DRY-RUN] Record: ${SERVER_IP} ${JELLYFIN_DOMAIN}"
else
    print_info "Adding Jellyfin DNS record to custom.list..."
    
    # Backup custom.list
    cp /opt/homeserver/configs/pihole/custom.list /opt/homeserver/configs/pihole/custom.list.backup.$(date +%Y%m%d_%H%M%S)
    
    # Add Jellyfin DNS record
    echo "${SERVER_IP} ${JELLYFIN_DOMAIN}" >> /opt/homeserver/configs/pihole/custom.list
    
    print_success "Added Jellyfin DNS record to custom.list"
    
    # Copy updated custom.list to Pi-hole container
    print_info "Copying custom.list to Pi-hole container..."
    docker cp /opt/homeserver/configs/pihole/custom.list pihole:/etc/pihole/custom.list
    
    # Reload Pi-hole DNS to apply changes
    print_info "Reloading Pi-hole DNS..."
    if docker exec pihole pihole reloaddns; then
        print_success "Pi-hole DNS reloaded"
    else
        print_error "Failed to reload Pi-hole DNS"
        print_error "Restoring backup..."
        mv /opt/homeserver/configs/pihole/custom.list.backup.$(date +%Y%m%d_%H%M%S) /opt/homeserver/configs/pihole/custom.list
        docker cp /opt/homeserver/configs/pihole/custom.list pihole:/etc/pihole/custom.list
        docker exec pihole pihole reloaddns
        exit 1
    fi
    
    # Verify DNS resolution
    print_info "Verifying DNS resolution..."
    sleep 2  # Wait for DNS to propagate
    
    if nslookup ${JELLYFIN_DOMAIN} 127.0.0.1 &> /dev/null; then
        RESOLVED_IP=$(nslookup ${JELLYFIN_DOMAIN} 127.0.0.1 | grep -A1 "Name:" | grep "Address:" | awk '{print $2}')
        if [[ "$RESOLVED_IP" == "$SERVER_IP" ]]; then
            print_success "DNS resolution verified: ${JELLYFIN_DOMAIN} -> ${SERVER_IP}"
        else
            print_info "DNS resolution returned unexpected IP: ${RESOLVED_IP} (expected: ${SERVER_IP})"
        fi
    else
        print_info "DNS resolution failed (may need time to propagate)"
    fi
    
    print_success "Jellyfin DNS record configured"
    print_info "Jellyfin will be accessible at: https://${JELLYFIN_DOMAIN}"
fi

print_success "Task complete"
exit 0
