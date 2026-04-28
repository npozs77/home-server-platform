#!/bin/bash
# Task: Configure Caddy reverse proxy for Wiki.js
# Phase: 5 (Wiki + LLM Platform — Sub-phase A)
# Number: 03
# Prerequisites:
#   - Phase 2 complete (Caddy running)
#   - Wiki.js stack deployed (wiki-server running)
#   - Configuration loaded (WIKI_DOMAIN)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   WIKI_DOMAIN (e.g., wiki.home.mydomain.com)
# Environment Variables Optional:
#   WIKI_PORT (default: 3000)
#
# UFW Note: No additional UFW rules are needed for Wiki.js.
# Wiki.js traffic flows through Caddy on port 443 (HTTPS), which is
# already allowed from Phase 2. Port 3000 is bound by Docker but UFW
# blocks external access since only port 443 is allowed from LAN.
# All access goes through Caddy reverse proxy.
# Satisfies: Requirements 6.2, 6.3, 6.4, 6.5

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
if [[ -z "${WIKI_DOMAIN:-}" ]]; then
    print_info "Loading configuration..."
    if [[ ! -f "$SERVICES_ENV" ]]; then
        print_error "services.env not found at $SERVICES_ENV"
        exit 3
    fi
    source "$SERVICES_ENV"
fi

# Default port if not set
WIKI_PORT="${WIKI_PORT:-3000}"

# Validate required environment variables
if [[ -z "${WIKI_DOMAIN:-}" ]]; then
    print_error "WIKI_DOMAIN environment variable not set"
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

# Check wiki-server is running
if ! docker ps --format '{{.Names}}' | grep -q '^wiki-server$'; then
    print_error "wiki-server container is not running (run Task 3.3 first)"
    exit 3
fi

# Check idempotency
if grep -q "^${WIKI_DOMAIN}" "$CADDYFILE"; then
    print_success "Wiki.js entry already exists in Caddyfile — skipping"
    # Still reload Caddy in case previous run added entry but didn't reload
    print_info "Reloading Caddy..."
    docker exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null && \
        print_success "Caddy reloaded" || \
        print_info "Caddy reload failed — check Caddy logs"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would add Wiki.js entry to Caddyfile"
    print_info "[DRY-RUN] Domain: $WIKI_DOMAIN"
    print_info "[DRY-RUN] Upstream: wiki-server:$WIKI_PORT"
else
    print_info "Adding Wiki.js entry to Caddyfile..."

    # Backup Caddyfile
    BACKUP_FILE="${CADDYFILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CADDYFILE" "$BACKUP_FILE"

    # Add Wiki.js entry
    cat >> "$CADDYFILE" << EOFCADDY

# Wiki.js Family Wiki (Phase 5 — Sub-phase A)
${WIKI_DOMAIN} {
    reverse_proxy wiki-server:${WIKI_PORT}
    tls internal
    log {
        output file /var/log/caddy/wiki-access.log
    }
    handle_errors {
        root * /srv/pages
        rewrite * /starting.html
        file_server
    }
}
EOFCADDY

    print_success "Added Wiki.js entry to Caddyfile"

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

    print_success "Wiki.js reverse proxy configured"
    print_info "Wiki.js will be accessible at: https://${WIKI_DOMAIN}"
fi

print_success "Task complete"
exit 0
