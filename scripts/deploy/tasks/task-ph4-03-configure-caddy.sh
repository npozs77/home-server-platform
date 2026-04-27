#!/bin/bash
# Task: Configure Caddy reverse proxy for Immich
# Phase: 4 (Photo Management)
# Number: 03
# Prerequisites:
#   - Phase 2 complete (Caddy running)
#   - Immich stack deployed (immich-server running)
#   - Configuration loaded (IMMICH_DOMAIN)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   IMMICH_DOMAIN (e.g., photos.home.mydomain.com)
# Environment Variables Optional:
#   IMMICH_PORT (default: 2283)
#
# UFW Note: No additional UFW rules are needed for Immich.
# Immich traffic flows through Caddy on port 443 (HTTPS), which is
# already allowed from Phase 2. Port 2283 is bound by Docker
# (0.0.0.0:2283) but UFW blocks external access since only port 443
# is allowed from LAN. Direct access to 2283 from other LAN devices
# is blocked by UFW — all access goes through Caddy reverse proxy.

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
SERVICES_ENV="/opt/homeserver/configs/services.env"
CADDYFILE="/opt/homeserver/configs/caddy/Caddyfile"

# Source environment files (only if vars not already exported by orchestrator)
if [[ -z "${IMMICH_DOMAIN:-}" ]]; then
    print_info "Loading configuration..."
    if [[ ! -f "$SERVICES_ENV" ]]; then
        print_error "services.env not found at $SERVICES_ENV"
        exit 3
    fi
    source "$SERVICES_ENV"
fi

# Default port if not set
IMMICH_PORT="${IMMICH_PORT:-2283}"

# Validate required environment variables
if [[ -z "${IMMICH_DOMAIN:-}" ]]; then
    print_error "IMMICH_DOMAIN environment variable not set"
    exit 3
fi

# Validate prerequisites
print_info "Validating prerequisites..."

# Check Caddy is running
if ! docker ps --format '{{.Names}}' | grep -q '^caddy$'; then
    print_error "Caddy container is not running (should be deployed in Phase 2)"
    exit 3
fi

# Check Caddyfile exists
if [[ ! -f "$CADDYFILE" ]]; then
    print_error "$CADDYFILE does not exist (should be created in Phase 2)"
    exit 3
fi

# Check immich-server is running
if ! docker ps --format '{{.Names}}' | grep -q '^immich-server$'; then
    print_error "immich-server container is not running (run Task 3.3 first)"
    exit 3
fi

# Check idempotency
if grep -q "^${IMMICH_DOMAIN}" "$CADDYFILE"; then
    print_info "Immich entry already exists in Caddyfile"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would add Immich entry to Caddyfile"
    print_info "[DRY-RUN] Domain: $IMMICH_DOMAIN"
    print_info "[DRY-RUN] Upstream: immich-server:$IMMICH_PORT"
else
    print_info "Adding Immich entry to Caddyfile..."

    # Backup Caddyfile
    BACKUP_FILE="${CADDYFILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CADDYFILE" "$BACKUP_FILE"

    # Add Immich entry (NO redir — Immich doesn't need it)
    cat >> "$CADDYFILE" << EOFCADDY

# Immich Photo Management (Phase 4)
${IMMICH_DOMAIN} {
    reverse_proxy immich-server:${IMMICH_PORT}
    tls internal
    log {
        output file /var/log/caddy/photos-access.log
    }
    handle_errors {
        root * /srv/pages
        rewrite * /starting.html
        file_server
    }
}
EOFCADDY

    print_success "Added Immich entry to Caddyfile"

    # Validate Caddyfile syntax
    print_info "Validating Caddyfile syntax..."
    if docker exec caddy caddy validate --config /etc/caddy/Caddyfile &> /dev/null; then
        print_success "Caddyfile syntax valid"
    else
        print_error "Caddyfile syntax invalid — restoring backup..."
        cp "$BACKUP_FILE" "$CADDYFILE"
        exit 1
    fi

    # Reload Caddy configuration
    print_info "Reloading Caddy configuration..."
    if docker exec caddy caddy reload --config /etc/caddy/Caddyfile; then
        print_success "Caddy configuration reloaded"
    else
        print_error "Failed to reload Caddy configuration — restoring backup..."
        cp "$BACKUP_FILE" "$CADDYFILE"
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile
        exit 1
    fi

    # Full container restart to ensure clean network bindings and trigger
    # TLS certificate generation for the new domain.
    # Lesson from Phase 3 incident (homeserver-reachability-incident.md):
    # After DNS/network changes, a full container restart reapplies Docker
    # iptables/NAT rules and avoids stale network bindings.
    print_info "Restarting Caddy container for clean network bindings and certificate generation..."
    if docker restart caddy; then
        print_success "Caddy container restarted"
    else
        print_error "Caddy container restart failed (reload was successful, service may still work)"
    fi

    print_success "Immich reverse proxy configured"
    print_info "Immich will be accessible at: https://${IMMICH_DOMAIN}"
fi

print_success "Task complete"
exit 0
