#!/bin/bash
# Task: Deploy Pi-hole DNS container
# Phase: 2 (Infrastructure)
# Number: 07
# Prerequisites:
#   - Phase 1 complete
#   - Configuration loaded (PIHOLE_PASS_ITEM_ID, HOMESERVER_PASS_SHARE_ID, ADMIN_USER)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   PIHOLE_PASS_ITEM_ID, HOMESERVER_PASS_SHARE_ID, ADMIN_USER
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
source /opt/homeserver/scripts/operations/utils/password-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate prerequisites
validate_required_vars "PIHOLE_PASS_ITEM_ID" "HOMESERVER_PASS_SHARE_ID" "ADMIN_USER" || exit 3

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would check port 53 availability"
    print_info "[DRY-RUN] Would stop systemd-resolved if needed"
    print_info "[DRY-RUN] Would deploy Pi-hole container"
    exit 0
fi

# Check if port 53 is in use
if ss -tulpn | grep -q ':53 '; then
    print_info "Port 53 is in use, checking for systemd-resolved..."
    if systemctl is-active --quiet systemd-resolved; then
        print_info "Stopping systemd-resolved..."
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
        
        # Update resolv.conf to use Google DNS temporarily
        print_info "Updating /etc/resolv.conf..."
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        
        print_success "systemd-resolved stopped and disabled"
    else
        print_error "Port 53 is in use by another service (not systemd-resolved)"
        print_info "Check with: sudo ss -tulpn | grep :53"
        exit 1
    fi
fi

# Create Pi-hole config directory
mkdir -p /opt/homeserver/configs/pihole

# Check if Pi-hole already running
if docker ps | grep -q pihole; then
    print_info "Pi-hole is already running"
    exit 0
fi

if docker ps -a | grep -q pihole; then
    print_info "Starting existing Pi-hole container..."
    docker start pihole
    sleep 30
    if docker ps | grep -q pihole; then
        print_success "Pi-hole is running"
        exit 0
    fi
fi

# Fetch Pi-hole password from Proton Pass
print_info "Fetching Pi-hole password from Proton Pass..."
PIHOLE_PASSWORD=$(fetch_secret "$PIHOLE_PASS_ITEM_ID" "password" "$ADMIN_USER")
if [[ -z "$PIHOLE_PASSWORD" ]]; then
    print_error "Failed to fetch Pi-hole password from Proton Pass"
    print_info "Ensure user $ADMIN_USER is logged into pass-cli"
    exit 1
fi
print_success "Password fetched successfully"

# Deploy Pi-hole container with host networking
print_info "Deploying Pi-hole container with host networking..."
docker run -d \
    --name pihole \
    --restart unless-stopped \
    --network host \
    -e TZ="America/New_York" \
    -e WEBPASSWORD="$PIHOLE_PASSWORD" \
    -e DNSMASQ_LISTENING="all" \
    -e DNS1="8.8.8.8" \
    -e DNS2="1.1.1.1" \
    -e WEB_PORT=8080 \
    -v /opt/homeserver/configs/pihole/etc-pihole:/etc/pihole \
    -v /opt/homeserver/configs/pihole/etc-dnsmasq.d:/etc/dnsmasq.d \
    pihole/pihole:latest

print_success "Pi-hole container deployed"
print_info "Waiting for Pi-hole to initialize (30 seconds)..."
sleep 30

if docker ps | grep -q pihole; then
    print_success "Pi-hole is running"
else
    print_error "Pi-hole failed to start"
    docker logs pihole
    exit 1
fi

print_success "Task complete"
exit 0
