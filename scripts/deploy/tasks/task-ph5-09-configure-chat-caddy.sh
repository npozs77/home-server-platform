#!/bin/bash
# Task: Configure Caddy reverse proxy for Open WebUI
# Phase: 5 (Wiki + LLM Platform — Sub-phase B)
# Number: 09
# Prerequisites:
#   - Phase 2 complete (Caddy running)
#   - Open WebUI stack deployed (open-webui running)
#   - Configuration loaded (OPENWEBUI_DOMAIN)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   OPENWEBUI_DOMAIN (e.g., chat.home.mydomain.com)
# Environment Variables Optional:
#   OPENWEBUI_PORT (default: 8080)
#
# UFW Note: No additional UFW rules needed. Open WebUI traffic flows
# through Caddy on port 443 (HTTPS), already allowed from Phase 2.
# Satisfies: Requirements 12.2, 12.3, 12.4, 12.5

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
if [[ -z "${OPENWEBUI_DOMAIN:-}" ]]; then
    print_info "Loading configuration..."
    if [[ ! -f "$SERVICES_ENV" ]]; then
        print_error "services.env not found at $SERVICES_ENV"
        exit 3
    fi
    source "$SERVICES_ENV"
fi

# Default port if not set
OPENWEBUI_PORT="${OPENWEBUI_PORT:-8080}"

# Validate required environment variables
if [[ -z "${OPENWEBUI_DOMAIN:-}" ]]; then
    print_error "OPENWEBUI_DOMAIN environment variable not set"
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

# Check open-webui is running
if ! docker ps --format '{{.Names}}' | grep -q '^open-webui$'; then
    print_error "open-webui container is not running (run Task 9.3 first)"
    exit 3
fi

# Check idempotency
if grep -q "^${OPENWEBUI_DOMAIN}" "$CADDYFILE"; then
    print_success "Open WebUI entry already exists in Caddyfile — skipping"
    print_info "Reloading Caddy..."
    docker exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null && \
        print_success "Caddy reloaded" || \
        print_info "Caddy reload failed — check Caddy logs"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would add Open WebUI entry to Caddyfile"
    print_info "[DRY-RUN] Domain: $OPENWEBUI_DOMAIN"
    print_info "[DRY-RUN] Upstream: open-webui:$OPENWEBUI_PORT"
else
    print_info "Adding Open WebUI entry to Caddyfile..."

    # Backup Caddyfile
    BACKUP_FILE="${CADDYFILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CADDYFILE" "$BACKUP_FILE"

    # Add Open WebUI entry
    cat >> "$CADDYFILE" << EOFCADDY

# Open WebUI AI Chat (Phase 5 — Sub-phase B)
${OPENWEBUI_DOMAIN} {
    reverse_proxy open-webui:${OPENWEBUI_PORT}
    tls internal
    log {
        output file /var/log/caddy/chat-access.log
    }
    handle_errors {
        root * /srv/pages
        rewrite * /starting.html
        file_server
    }
}
EOFCADDY

    print_success "Added Open WebUI entry to Caddyfile"

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

    # Full container restart for clean network bindings and TLS cert generation
    print_info "Restarting Caddy container for clean network bindings and certificate generation..."
    if docker restart caddy; then
        print_success "Caddy container restarted"
    else
        print_error "Caddy container restart failed (reload was successful, service may still work)"
    fi

    print_success "Open WebUI reverse proxy configured"
    print_info "HTTPS routing ready. Run the DNS task (task-ph5-10) next to enable https://${OPENWEBUI_DOMAIN}"
fi

print_success "Task complete"
exit 0
