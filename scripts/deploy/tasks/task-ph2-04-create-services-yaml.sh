#!/bin/bash
# Task: Create services.yaml configuration file
# Phase: 2 (Infrastructure)
# Number: 04
# Prerequisites:
#   - Phase 1 complete
#   - Configuration loaded (DOMAIN, INTERNAL_SUBDOMAIN, SMTP2GO_HOST, SMTP2GO_PORT)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   DOMAIN, INTERNAL_SUBDOMAIN, SMTP2GO_HOST, SMTP2GO_PORT
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
validate_required_vars "DOMAIN" "INTERNAL_SUBDOMAIN" "SMTP2GO_HOST" "SMTP2GO_PORT" "SMTP2GO_USER" "SMTP2GO_FROM" || exit 3

# Check idempotency
if [[ -f /opt/homeserver/configs/services.yaml ]]; then
    print_info "services.yaml already exists"
    if [[ "$DRY_RUN" == false ]]; then
        read -rp "Overwrite? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            print_info "Skipping services.yaml creation"
            exit 0
        fi
    fi
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create /opt/homeserver/configs/services.yaml"
else
    print_info "Creating services.yaml..."
    mkdir -p /opt/homeserver/configs
    
    cat > /opt/homeserver/configs/services.yaml << 'EOFSERVICES'
# Infrastructure Services Configuration
# Single source of truth for all service definitions

services:
  # Internal DNS (Pi-hole)
  pihole:
    name: pihole
    image: pihole/pihole:latest
    network_mode: host
    volumes:
      - /opt/homeserver/configs/pihole/etc-pihole:/etc/pihole
      - /opt/homeserver/configs/pihole/etc-dnsmasq.d:/etc/dnsmasq.d
    environment:
      TZ: "America/New_York"
      WEBPASSWORD: "${PIHOLE_PASSWORD}"
      DNSMASQ_LISTENING: "all"
      DNS1: "8.8.8.8"
      DNS2: "1.1.1.1"
      WEB_PORT: "8080"
    hostname: pihole.${INTERNAL_SUBDOMAIN}
    dns_record: true
    caddy_proxy: true
    restart: unless-stopped
    
  # Reverse Proxy (Caddy)
  caddy:
    name: caddy
    image: caddy:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/homeserver/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - /opt/homeserver/configs/caddy/data:/data
      - /opt/homeserver/configs/caddy/config:/config
      - /var/log/caddy:/var/log/caddy
    hostname: null
    dns_record: false
    caddy_proxy: false
    restart: unless-stopped
    
  # SMTP Relay
  smtp:
    name: smtp
    image: namshi/smtp:latest
    ports:
      - "25:25"
    environment:
      RELAY_HOST: "${SMTP2GO_HOST}"
      RELAY_PORT: "${SMTP2GO_PORT}"
      RELAY_USERNAME: "${SMTP2GO_USER}"
      RELAY_FROM: "${SMTP2GO_FROM}"
    hostname: null
    dns_record: false
    caddy_proxy: false
    restart: unless-stopped
    
  # Monitoring (Netdata)
  netdata:
    name: netdata
    image: netdata/netdata:latest
    ports:
      - "19999:19999"
    cap_add:
      - SYS_PTRACE
    security_opt:
      - apparmor:unconfined
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/homeserver/configs/netdata:/etc/netdata
    hostname: monitor.${INTERNAL_SUBDOMAIN}
    dns_record: true
    caddy_proxy: true
    restart: unless-stopped
    
  # Test Service (for validation)
  test:
    name: test-service
    image: nginx:alpine
    ports:
      - "8081:80"
    hostname: test.${INTERNAL_SUBDOMAIN}
    dns_record: true
    caddy_proxy: true
    restart: unless-stopped
EOFSERVICES
    
    print_success "Created /opt/homeserver/configs/services.yaml"
    print_info "Review and customize services.yaml as needed"
fi

print_success "Task complete"
exit 0
