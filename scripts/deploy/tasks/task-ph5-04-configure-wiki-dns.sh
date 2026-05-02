#!/bin/bash
# Task: Configure DNS record for Wiki.js
# Phase: 5 (Wiki + LLM Platform — Sub-phase A)
# Number: 04
# Prerequisites:
#   - Phase 2 complete (Pi-hole running)
#   - Configuration loaded (SERVER_IP, WIKI_DOMAIN)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   SERVER_IP, WIKI_DOMAIN
# Environment Variables Optional:
#   None
#
# Pi-hole v6 Note:
#   Pi-hole v6 no longer uses custom.list for local DNS records.
#   Records are managed via pihole-FTL --config dns.hosts (pihole.toml).
#   Phase 2 (task-ph2-08) established this pattern. This script appends
#   the Wiki.js record to the existing dns.hosts array.
# Satisfies: Requirements 6.1, 6.6

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
if [[ -z "${WIKI_DOMAIN:-}" ]]; then
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

if [[ -z "${WIKI_DOMAIN:-}" ]]; then
    print_error "WIKI_DOMAIN environment variable not set"
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
DNS_RECORD="${SERVER_IP} ${WIKI_DOMAIN}"

# Read current dns.hosts JSON array from Pi-hole
CURRENT_JSON=$(docker exec pihole pihole-FTL --config dns.hosts 2>/dev/null || echo "[]")

# Check idempotency
if echo "$CURRENT_JSON" | grep -q "${WIKI_DOMAIN}"; then
    print_success "Wiki.js DNS record already exists in Pi-hole dns.hosts — skipping"
    # Still verify DNS actually resolves (previous run may have failed after adding record)
    if nslookup "${WIKI_DOMAIN}" 127.0.0.1 &> /dev/null; then
        print_success "DNS resolution verified: ${WIKI_DOMAIN} -> ${SERVER_IP}"
    else
        print_info "DNS record exists but not resolving — restarting Pi-hole..."
        docker restart pihole
        sleep 8
        if nslookup "${WIKI_DOMAIN}" 127.0.0.1 &> /dev/null; then
            print_success "DNS resolution verified after restart: ${WIKI_DOMAIN} -> ${SERVER_IP}"
        else
            print_error "DNS still not resolving after Pi-hole restart"
            exit 1
        fi
    fi
    # Reload Caddy to ensure certs are generated for this domain
    if docker ps --format '{{.Names}}' | grep -q '^caddy$'; then
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null && \
            print_success "Caddy reloaded" || true
    fi
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would add Wiki.js DNS record to Pi-hole dns.hosts"
    print_info "[DRY-RUN] Record: ${DNS_RECORD}"
else
    print_info "Adding Wiki.js DNS record to Pi-hole dns.hosts..."

    # Append new entry to the existing JSON array
    # pihole-FTL --config dns.hosts returns entries without JSON quotes, e.g.:
    #   [ 192.168.1.2 foo.com, 192.168.1.2 bar.com ]
    # But setting requires valid JSON: ["192.168.1.2 foo.com", "192.168.1.2 bar.com"]
    # Rebuild the full array from scratch to ensure valid JSON.

    # Extract existing entries (strip brackets, split on comma, trim whitespace)
    ENTRIES=()
    RAW=$(echo "$CURRENT_JSON" | sed 's/^\[//;s/\]$//')
    if [[ -n "$RAW" && "$RAW" != " " ]]; then
        while IFS= read -r entry; do
            entry=$(echo "$entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            # Strip any existing quotes
            entry=$(echo "$entry" | sed 's/^"//;s/"$//')
            [[ -n "$entry" ]] && ENTRIES+=("$entry")
        done < <(echo "$RAW" | tr ',' '\n')
    fi
    # Add the new record
    ENTRIES+=("${DNS_RECORD}")

    # Build valid JSON array
    NEW_HOSTS_JSON="["
    for i in "${!ENTRIES[@]}"; do
        [[ $i -gt 0 ]] && NEW_HOSTS_JSON+=", "
        NEW_HOSTS_JSON+="\"${ENTRIES[$i]}\""
    done
    NEW_HOSTS_JSON+="]"

    # Apply the updated dns.hosts array
    print_info "Setting dns.hosts: ${NEW_HOSTS_JSON}"
    if docker exec pihole pihole-FTL --config dns.hosts "${NEW_HOSTS_JSON}"; then
        print_success "Wiki.js DNS record added to Pi-hole"
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

    if nslookup "${WIKI_DOMAIN}" 127.0.0.1 &> /dev/null; then
        RESOLVED_IP=$(nslookup "${WIKI_DOMAIN}" 127.0.0.1 | grep -A1 "Name:" | grep "Address:" | awk '{print $2}')
        if [[ "$RESOLVED_IP" == "$SERVER_IP" ]]; then
            print_success "DNS resolution verified: ${WIKI_DOMAIN} -> ${SERVER_IP}"
        else
            print_info "DNS resolution returned unexpected IP: ${RESOLVED_IP} (expected: ${SERVER_IP})"
        fi
    else
        print_info "DNS resolution not yet working (FTL may need more time)"
    fi

    print_success "Wiki.js DNS record configured"

    # Reload Caddy to trigger certificate generation for the new DNS name
    if docker ps --format '{{.Names}}' | grep -q '^caddy$'; then
        print_info "Reloading Caddy to trigger certificate generation..."
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null && \
            print_success "Caddy reloaded" || \
            print_info "Caddy reload skipped (Caddy route may not be configured yet)"
    fi

    print_info "Wiki.js accessible at: https://${WIKI_DOMAIN}"
fi

print_success "Task complete"
exit 0
