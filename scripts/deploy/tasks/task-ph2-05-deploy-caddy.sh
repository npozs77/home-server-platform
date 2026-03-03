#!/bin/bash
# Task: Deploy Caddy reverse proxy container
# Phase: 2 (Infrastructure)
# Number: 05
# Prerequisites:
#   - Phase 1 complete
#   - Configuration loaded (ADMIN_EMAIL, INTERNAL_SUBDOMAIN, SERVER_IP)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   ADMIN_EMAIL, INTERNAL_SUBDOMAIN, SERVER_IP
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
validate_required_vars "ADMIN_EMAIL" "INTERNAL_SUBDOMAIN" "SERVER_IP" || exit 3

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create Caddyfile"
    print_info "[DRY-RUN] Would deploy Caddy container"
    exit 0
fi

# Create Caddy config directory
mkdir -p /opt/homeserver/configs/caddy
mkdir -p /var/log/caddy

# Create minimal Caddyfile
if [[ ! -f /opt/homeserver/configs/caddy/Caddyfile ]]; then
    print_info "Creating Caddyfile..."
    cat > /opt/homeserver/configs/caddy/Caddyfile << EOF
# Global options
{
    email $ADMIN_EMAIL
    local_certs
}

# Test service (for validation)
test.$INTERNAL_SUBDOMAIN {
    reverse_proxy test-service:80
    tls internal
    log {
        output file /var/log/caddy/test-access.log
    }
}

# Pi-hole web interface (host networking, port 8080)
pihole.$INTERNAL_SUBDOMAIN {
    reverse_proxy $SERVER_IP:8080
    tls internal
    log {
        output file /var/log/caddy/pihole-access.log
    }
}
EOF
    print_success "Created Caddyfile"
else
    print_info "Caddyfile already exists"
fi

# Create custom network if not exists
if ! docker network ls | grep -q homeserver; then
    print_info "Creating homeserver network..."
    docker network create homeserver
    print_success "Network created"
fi

# Check if Caddy already exists
if docker ps -a | grep -q caddy; then
    print_info "Caddy container already exists"
    if docker ps | grep -q caddy; then
        print_info "Caddy is already running"
        exit 0
    else
        print_info "Starting existing Caddy container..."
        docker start caddy
        sleep 5
        if docker ps | grep -q caddy; then
            print_success "Caddy is running"
            exit 0
        fi
    fi
fi

# Deploy Caddy container
print_info "Deploying Caddy container..."
docker run -d \
    --name caddy \
    --restart unless-stopped \
    --network homeserver \
    -p 80:80 \
    -p 443:443 \
    -v /opt/homeserver/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
    -v /opt/homeserver/configs/caddy/data:/data \
    -v /opt/homeserver/configs/caddy/config:/config \
    -v /var/log/caddy:/var/log/caddy \
    --health-cmd "curl -f http://localhost:80 || exit 1" \
    --health-interval 30s \
    --health-timeout 10s \
    --health-retries 3 \
    --health-start-period 30s \
    caddy:alpine

print_success "Caddy container deployed"
sleep 5

if docker ps | grep -q caddy; then
    print_success "Caddy is running"
else
    print_error "Caddy failed to start"
    docker logs caddy
    exit 1
fi

print_success "Task complete"
exit 0
