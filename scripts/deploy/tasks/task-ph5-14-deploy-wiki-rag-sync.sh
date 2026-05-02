#!/bin/bash
# Task: Deploy wiki-to-RAG sync script
# Phase: 5 (Wiki + LLM Platform — Shared Components)
# Number: 14
# Purpose: Install wiki-rag-sync.sh and configure cron job for periodic execution
# Prerequisites:
#   - Wiki.js deployed with Local File System storage configured (Sub-phase A)
#   - Open WebUI deployed and running with API token (Sub-phase B)
#   - OPENWEBUI_API_TOKEN set in secrets.env
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Satisfies: Requirements 13b.1-13b.8

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utilities
source /opt/homeserver/scripts/operations/utils/output-utils.sh
source /opt/homeserver/scripts/operations/utils/env-utils.sh
load_env_files || true

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT_SRC="${SCRIPT_DIR}/../../operations/wiki-rag-sync.sh"
SYNC_SCRIPT_DEST="/opt/homeserver/scripts/operations/wiki-rag-sync.sh"
CRON_FILE="/etc/cron.d/homeserver-wiki-rag-sync"
CRON_SCHEDULE="0 3 * * *"
WIKI_CONTENT_DIR="/mnt/data/services/wiki/content"
CHECKSUM_FILE="/mnt/data/services/openwebui/data/.wiki-rag-checksums"

print_header "Task 5.14: Deploy Wiki-to-RAG Sync Script"

# ============================================================
# Validate prerequisites
# ============================================================
print_info "Validating prerequisites..."

# Verify source sync script exists
if [[ ! -f "$SYNC_SCRIPT_SRC" ]]; then
    print_error "Sync script source not found: $SYNC_SCRIPT_SRC"
    exit 3
fi

# Validate source script syntax
if ! bash -n "$SYNC_SCRIPT_SRC" 2>/dev/null; then
    print_error "Sync script has syntax errors: $SYNC_SCRIPT_SRC"
    exit 3
fi

# Check wiki content directory exists (warning only)
if [[ -d "$WIKI_CONTENT_DIR" ]]; then
    print_success "Wiki content directory exists: $WIKI_CONTENT_DIR"
else
    print_info "Warning: Wiki content directory not found — sync will skip until available"
fi

# Check Open WebUI container is running (warning only)
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^open-webui$"; then
    print_success "open-webui container is running"
else
    print_info "Warning: open-webui container not running — sync will fail until available"
fi

# Check OPENWEBUI_API_TOKEN is set (warning only — may not be set until manual step)
if [[ -n "${OPENWEBUI_API_TOKEN:-}" ]]; then
    print_success "OPENWEBUI_API_TOKEN is set"
else
    print_info "Warning: OPENWEBUI_API_TOKEN not set — sync requires this token"
fi

# Check OPENWEBUI_DOMAIN is set
if [[ -n "${OPENWEBUI_DOMAIN:-}" ]]; then
    print_success "OPENWEBUI_DOMAIN is set: ${OPENWEBUI_DOMAIN}"
else
    print_info "Warning: OPENWEBUI_DOMAIN not set in services.env"
fi

print_success "Prerequisites validated"

# ============================================================
# Deploy sync script
# ============================================================
print_info "Deploying wiki-to-RAG sync script..."

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create directory: $(dirname "$SYNC_SCRIPT_DEST")"
    print_info "[DRY-RUN] Would copy: $SYNC_SCRIPT_SRC → $SYNC_SCRIPT_DEST"
    print_info "[DRY-RUN] Would set permissions: 755 on $SYNC_SCRIPT_DEST"
    print_info "[DRY-RUN] Would initialize checksum file: $CHECKSUM_FILE"
else
    # Create operations directory
    mkdir -p "$(dirname "$SYNC_SCRIPT_DEST")"

    # Copy sync script to destination
    cp "$SYNC_SCRIPT_SRC" "$SYNC_SCRIPT_DEST"
    chmod 755 "$SYNC_SCRIPT_DEST"
    print_success "Installed $SYNC_SCRIPT_DEST"

    # Initialize checksum file if it doesn't exist
    if [[ ! -f "$CHECKSUM_FILE" ]]; then
        CHECKSUM_DIR=$(dirname "$CHECKSUM_FILE")
        if [[ -d "$CHECKSUM_DIR" ]]; then
            touch "$CHECKSUM_FILE"
            chmod 644 "$CHECKSUM_FILE"
            print_success "Created checksum file: $CHECKSUM_FILE"
        else
            print_info "Checksum directory not yet available — will be created on first sync"
        fi
    else
        print_info "Checksum file already exists: $CHECKSUM_FILE"
    fi
fi

# ============================================================
# Configure cron job
# ============================================================
print_info "Configuring cron job..."

CRON_ENTRY="${CRON_SCHEDULE} root ${SYNC_SCRIPT_DEST} >> /var/log/homeserver/wiki-rag-sync.log 2>&1"

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create cron file: $CRON_FILE"
    print_info "[DRY-RUN] Cron schedule: $CRON_ENTRY"
else
    # Create cron file (idempotent — overwrites if exists)
    cat > "$CRON_FILE" <<EOF
# Wiki-to-RAG sync — sync Wiki.js content to Open WebUI RAG
# Installed by: task-ph5-14-deploy-wiki-rag-sync.sh
# Schedule: nightly at 03:00
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

${CRON_ENTRY}
EOF
    chmod 644 "$CRON_FILE"
    print_success "Cron job configured: $CRON_FILE"

    # Create log directory
    mkdir -p /var/log/homeserver
fi

# ============================================================
# Validate deployment
# ============================================================
print_info "Validating deployment..."

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would validate: script exists, executable, syntax"
    print_info "[DRY-RUN] Would validate: checksum logic, API references, cron file"
else
    # Verify script exists and is executable
    if [[ ! -x "$SYNC_SCRIPT_DEST" ]]; then
        print_error "Sync script not executable: $SYNC_SCRIPT_DEST"
        exit 1
    fi
    print_success "Sync script is executable"

    # Validate bash syntax
    if bash -n "$SYNC_SCRIPT_DEST" 2>/dev/null; then
        print_success "Bash syntax valid"
    else
        print_error "Bash syntax errors in sync script"
        exit 1
    fi

    # Verify script uses checksum comparison
    if grep -q "md5sum\|checksum" "$SYNC_SCRIPT_DEST"; then
        print_success "Script uses checksum comparison"
    else
        print_error "Script missing checksum comparison"
        exit 1
    fi

    # Verify script references Open WebUI document API
    if grep -qE "api/v1/files|api/v1/documents" "$SYNC_SCRIPT_DEST"; then
        print_success "Script references Open WebUI document API"
    else
        print_error "Script missing Open WebUI document API reference"
        exit 1
    fi

    # Verify cron file exists
    if [[ -f "$CRON_FILE" ]]; then
        print_success "Cron file exists: $CRON_FILE"
    else
        print_error "Cron file not created: $CRON_FILE"
        exit 1
    fi
fi

# ============================================================
# Summary
# ============================================================
print_header "Deployment Summary"
print_success "Sync script deployed: $SYNC_SCRIPT_DEST"
print_success "Cron job configured: $CRON_FILE"
print_info ""
print_info "Usage:"
print_info "  sudo $SYNC_SCRIPT_DEST [--dry-run]"
print_info ""
print_info "Cron schedule: nightly at 03:00"
print_info "Log: /var/log/homeserver/wiki-rag-sync.log"

print_success "Task complete"
exit 0
