#!/bin/bash
# Task: Configure Caddy reverse proxy for Jellyfin
# Phase: 3 (Core Services)
# Number: 12
# Prerequisites:
#   - Phase 2 complete
#   - Caddy running
#   - Jellyfin container running (Task 6.2)
#   - Configuration loaded (INTERNAL_SUBDOMAIN)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   INTERNAL_SUBDOMAIN
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
if [[ -z "${INTERNAL_SUBDOMAIN:-}" ]]; then
    print_error "INTERNAL_SUBDOMAIN environment variable not set"
    exit 3
fi

# Validate prerequisites
print_info "Validating prerequisites..."

# Check Caddy is running
if ! docker ps --format '{{.Names}}' | grep -q '^caddy$'; then
    print_error "Caddy container is not running (should be deployed in Phase 2)"
    exit 3
fi

# Check Jellyfin is running
if ! docker ps --format '{{.Names}}' | grep -q '^jellyfin$'; then
    print_error "Jellyfin container is not running (run Task 6.2 first)"
    exit 3
fi

# Check Caddyfile exists
if [[ ! -f /opt/homeserver/configs/caddy/Caddyfile ]]; then
    print_error "/opt/homeserver/configs/caddy/Caddyfile does not exist (should be created in Phase 2)"
    exit 3
fi

# Define Jellyfin domain
JELLYFIN_DOMAIN="media.${INTERNAL_SUBDOMAIN}"

# Check idempotency
if grep -q "^${JELLYFIN_DOMAIN}" /opt/homeserver/configs/caddy/Caddyfile; then
    print_info "Jellyfin entry already exists in Caddyfile"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would add Jellyfin entry to Caddyfile"
    print_info "[DRY-RUN] Domain: $JELLYFIN_DOMAIN"
    print_info "[DRY-RUN] Upstream: jellyfin:8096"
else
    print_info "Adding Jellyfin entry to Caddyfile..."
    
    # Backup Caddyfile
    cp /opt/homeserver/configs/caddy/Caddyfile /opt/homeserver/configs/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S)
    
    # Add Jellyfin entry
    cat >> /opt/homeserver/configs/caddy/Caddyfile << EOFCADDY

# Jellyfin Media Streaming Service
${JELLYFIN_DOMAIN} {
    redir / /web/ 302
    reverse_proxy jellyfin:8096
    tls internal
    log {
        output file /var/log/caddy/media-access.log
    }
    handle_errors {
        root * /srv/pages
        rewrite * /starting.html
        file_server
    }
}
EOFCADDY
    
    print_success "Added Jellyfin entry to Caddyfile"
    
    # Validate Caddyfile syntax
    print_info "Validating Caddyfile syntax..."
    if docker exec caddy caddy validate --config /etc/caddy/Caddyfile &> /dev/null; then
        print_success "Caddyfile syntax valid"
    else
        print_error "Caddyfile syntax invalid"
        print_error "Restoring backup..."
        mv /opt/homeserver/configs/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S) /opt/homeserver/configs/caddy/Caddyfile
        exit 1
    fi
    
    # Reload Caddy configuration
    print_info "Reloading Caddy configuration..."
    if docker exec caddy caddy reload --config /etc/caddy/Caddyfile; then
        print_success "Caddy configuration reloaded"
    else
        print_error "Failed to reload Caddy configuration"
        print_error "Restoring backup..."
        mv /opt/homeserver/configs/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S) /opt/homeserver/configs/caddy/Caddyfile
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile
        exit 1
    fi
    
    print_success "Jellyfin reverse proxy configured"
    print_info "Jellyfin will be accessible at: https://${JELLYFIN_DOMAIN}"
fi

print_success "Task complete"
exit 0
