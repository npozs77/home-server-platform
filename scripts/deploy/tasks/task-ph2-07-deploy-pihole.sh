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
    print_info "[DRY-RUN] Would disable systemd-resolved permanently"
    print_info "[DRY-RUN] Would create static /etc/resolv.conf"
    print_info "[DRY-RUN] Would disable Wi-Fi power-saving"
    print_info "[DRY-RUN] Would validate DNS stability"
    print_info "[DRY-RUN] Would deploy Pi-hole container with HEALTHCHECK"
    exit 0
fi

# Step 1: Disable systemd-resolved permanently
print_header "Step 1: Disable systemd-resolved"
if systemctl is-enabled --quiet systemd-resolved 2>/dev/null; then
    print_info "Disabling systemd-resolved permanently..."
    systemctl disable systemd-resolved
    systemctl stop systemd-resolved
    print_success "systemd-resolved disabled and stopped"
else
    print_info "systemd-resolved already disabled"
fi

# Step 2: Create static /etc/resolv.conf (NOT symlink)
print_header "Step 2: Create static /etc/resolv.conf"
if [[ -L /etc/resolv.conf ]]; then
    print_info "Removing /etc/resolv.conf symlink..."
    rm /etc/resolv.conf
fi

if [[ ! -f /etc/resolv.conf ]] || ! grep -q "nameserver 192.168.1.1" /etc/resolv.conf; then
    print_info "Creating static /etc/resolv.conf..."
    cat > /etc/resolv.conf << 'EOF'
nameserver 192.168.1.1
nameserver 1.1.1.1
search home
EOF
    print_success "Static /etc/resolv.conf created"
fi

# Make immutable to prevent systemd from overwriting
if ! lsattr /etc/resolv.conf 2>/dev/null | grep -q 'i'; then
    print_info "Making /etc/resolv.conf immutable..."
    chattr +i /etc/resolv.conf
    print_success "/etc/resolv.conf is now immutable"
else
    print_info "/etc/resolv.conf already immutable"
fi

# Step 3: Disable Wi-Fi power-saving permanently
print_header "Step 3: Disable Wi-Fi power-saving"
WIFI_INTERFACE=$(ip link show | grep -o 'wlp[0-9]s[0-9]' | head -n1 || echo "")
if [[ -n "$WIFI_INTERFACE" ]]; then
    print_info "Found Wi-Fi interface: $WIFI_INTERFACE"
    
    if [[ ! -f /etc/systemd/network/25-wifi.network ]]; then
        print_info "Creating systemd-networkd Wi-Fi config..."
        cat > /etc/systemd/network/25-wifi.network << EOF
[Match]
Name=$WIFI_INTERFACE

[Link]
WirelessPowerSaving=no

[Network]
DHCP=yes
EOF
        print_success "Wi-Fi config created"
        
        print_info "Restarting systemd-networkd..."
        systemctl restart systemd-networkd
        sleep 5
        
        # Verify power-save is off
        if iw dev "$WIFI_INTERFACE" get power_save 2>/dev/null | grep -q "Power save: off"; then
            print_success "Wi-Fi power-saving disabled"
        else
            print_warning "Could not verify Wi-Fi power-saving status"
        fi
    else
        print_info "Wi-Fi config already exists"
    fi
else
    print_info "No Wi-Fi interface found - skipping Wi-Fi power-saving disable"
fi

# Step 4: Validate DNS stability
print_header "Step 4: Validate DNS stability"
print_info "Testing DNS resolution..."
if nslookup google.com >/dev/null 2>&1; then
    print_success "DNS resolution works"
else
    print_error "DNS resolution failed"
    exit 1
fi

print_info "Testing network connectivity..."
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    print_success "Network connectivity works"
else
    print_error "Network connectivity failed"
    exit 1
fi

print_info "Testing packet loss..."
PACKET_LOSS=$(ping -c 50 192.168.1.1 2>/dev/null | grep -oP '\d+(?=% packet loss)' || echo "100")
if [[ "$PACKET_LOSS" -lt 2 ]]; then
    print_success "Packet loss is acceptable ($PACKET_LOSS%)"
else
    print_warning "High packet loss detected ($PACKET_LOSS%) - may cause issues"
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
print_header "Step 5: Deploy Pi-hole container"
print_info "Deploying Pi-hole container with host networking and HEALTHCHECK..."
docker run -d \
    --name pihole \
    --restart unless-stopped \
    --network host \
    -e TZ="America/New_York" \
    -e WEBPASSWORD="$PIHOLE_PASSWORD" \
    -e DNSMASQ_LISTENING="all" \
    -e DNS1="8.8.8.8" \
    -e DNS2="1.1.1.1" \
    -e FTLCONF_webserver_api=1 \
    -e FTLCONF_webserver_port=8888 \
    -v /opt/homeserver/configs/pihole/etc-pihole:/etc/pihole \
    -v /opt/homeserver/configs/pihole/etc-dnsmasq.d:/etc/dnsmasq.d \
    --health-cmd "dig @127.0.0.1 google.com || exit 1" \
    --health-interval 30s \
    --health-timeout 10s \
    --health-retries 3 \
    --health-start-period 60s \
    pihole/pihole:latest

print_success "Pi-hole container deployed"
print_info "Waiting for Pi-hole to initialize (60 seconds)..."
sleep 60

if docker ps | grep -q pihole; then
    print_success "Pi-hole is running"
    
    # Check health status
    HEALTH_STATUS=$(docker inspect pihole --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    if [[ "$HEALTH_STATUS" == "healthy" ]]; then
        print_success "Pi-hole is healthy"
    elif [[ "$HEALTH_STATUS" == "starting" ]]; then
        print_info "Pi-hole health check is starting (this is normal)"
    else
        print_warning "Pi-hole health status: $HEALTH_STATUS"
    fi
else
    print_error "Pi-hole failed to start"
    docker logs pihole
    exit 1
fi

# Step 6: Validate external accessibility
print_header "Step 6: Validate external accessibility"
print_info "IMPORTANT: Test from external device (laptop, phone):"
print_info "  1. Ping test: ping -c 3 192.168.1.2"
print_info "  2. SSH test: time ssh user@192.168.1.2 'echo OK' (should be <3 seconds)"
print_info "  3. DNS test: nslookup google.com 192.168.1.2"
print_info ""
print_info "If any test fails, investigate network/DNS/firewall configuration"

print_success "Task complete"
exit 0
