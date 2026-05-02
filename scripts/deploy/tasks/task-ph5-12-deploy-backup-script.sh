#!/bin/bash
# Task: Deploy Wiki + LLM backup script
# Phase: 5 (Wiki + LLM Platform — Shared Components)
# Number: 12
# Purpose: Install backup-wiki-llm.sh to /opt/homeserver/scripts/backup/
# Prerequisites:
#   - Wiki.js stack deployed (Sub-phase A)
#   - Ollama + Open WebUI stack deployed (Sub-phase B)
#   - msmtp configured for email alerts (Phase 2)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Satisfies: Requirements 15.1-15.11, 22.7

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utilities
source /opt/homeserver/scripts/operations/utils/output-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT_SRC="${SCRIPT_DIR}/../../backup/backup-wiki-llm.sh"
BACKUP_SCRIPT_DEST="/opt/homeserver/scripts/backup/backup-wiki-llm.sh"

print_header "Task 5.12: Deploy Wiki + LLM Backup Script"

# ============================================================
# Validate prerequisites
# ============================================================
print_info "Validating prerequisites..."

if ! docker info &> /dev/null; then
    print_error "Docker is not running"
    exit 3
fi

# Check wiki-db container exists (warning only — backup script handles missing gracefully)
if docker ps --format '{{.Names}}' | grep -q "^wiki-db$"; then
    print_success "wiki-db container is running"
else
    print_info "Warning: wiki-db container not running — pg_dump will be skipped at backup time"
fi

# Verify source backup script exists
if [[ ! -f "$BACKUP_SCRIPT_SRC" ]]; then
    print_error "Backup script source not found: $BACKUP_SCRIPT_SRC"
    exit 3
fi

# Validate source script syntax
if ! bash -n "$BACKUP_SCRIPT_SRC" 2>/dev/null; then
    print_error "Backup script has syntax errors: $BACKUP_SCRIPT_SRC"
    exit 3
fi

# Check msmtp is available (warning only, not blocking)
if ! command -v msmtp &> /dev/null; then
    print_info "Warning: msmtp not found — email alerts will not work"
fi

print_success "Prerequisites validated"

# ============================================================
# Deploy backup script
# ============================================================
print_info "Deploying backup script..."

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create directory: $(dirname "$BACKUP_SCRIPT_DEST")"
    print_info "[DRY-RUN] Would copy: $BACKUP_SCRIPT_SRC → $BACKUP_SCRIPT_DEST"
    print_info "[DRY-RUN] Would set permissions: 755 on $BACKUP_SCRIPT_DEST"
else
    # Create backup scripts directory
    mkdir -p "$(dirname "$BACKUP_SCRIPT_DEST")"

    # Copy backup script to destination (skip if same file)
    if [[ "$(realpath "$BACKUP_SCRIPT_SRC")" != "$(realpath "$BACKUP_SCRIPT_DEST")" ]]; then
        cp "$BACKUP_SCRIPT_SRC" "$BACKUP_SCRIPT_DEST"
    fi
    chmod 755 "$BACKUP_SCRIPT_DEST"
    print_success "Installed $BACKUP_SCRIPT_DEST"
fi

# ============================================================
# Validate deployment
# ============================================================
print_info "Validating deployment..."

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would validate: script exists, executable, syntax"
    print_info "[DRY-RUN] Would validate: pg_dump reference, rsync references"
    print_info "[DRY-RUN] Cron entry NOT added (waiting for DAS HDD)"
else
    # Verify script exists and is executable
    if [[ ! -x "$BACKUP_SCRIPT_DEST" ]]; then
        print_error "Backup script not executable: $BACKUP_SCRIPT_DEST"
        exit 1
    fi
    print_success "Backup script is executable"

    # Validate bash syntax
    if bash -n "$BACKUP_SCRIPT_DEST" 2>/dev/null; then
        print_success "Bash syntax valid"
    else
        print_error "Bash syntax errors in backup script"
        exit 1
    fi

    # Verify script uses pg_dump (NOT filesystem copy of postgres dir)
    if grep -q "pg_dump" "$BACKUP_SCRIPT_DEST"; then
        print_success "Script uses pg_dump for database backup"
    else
        print_error "Script does not use pg_dump — violates backup requirements"
        exit 1
    fi

    # Verify pg_dump exit code is checked
    if grep -qE "PG_EXIT|cleanup_on_failure.*pg_dump" "$BACKUP_SCRIPT_DEST"; then
        print_success "Script checks pg_dump exit code"
    else
        print_error "Script does not check pg_dump exit code"
        exit 1
    fi

    # Verify script uses rsync for content directories
    if grep -q "rsync.*wiki-content" "$BACKUP_SCRIPT_DEST"; then
        print_success "Script rsyncs wiki content"
    else
        print_error "Script does not rsync wiki content"
        exit 1
    fi

    if grep -q "rsync.*openwebui-data" "$BACKUP_SCRIPT_DEST"; then
        print_success "Script rsyncs Open WebUI data"
    else
        print_error "Script does not rsync Open WebUI data"
        exit 1
    fi

    # Verify email alert on failure
    if grep -q "send_alert_email" "$BACKUP_SCRIPT_DEST"; then
        print_success "Script sends email alerts on failure"
    else
        print_error "Script missing email alert on failure"
        exit 1
    fi
fi

# ============================================================
# Summary
# ============================================================
print_header "Deployment Summary"
print_success "Backup script deployed: $BACKUP_SCRIPT_DEST"
print_info ""
print_info "Usage:"
print_info "  sudo $BACKUP_SCRIPT_DEST [--dry-run]"
print_info "  Default destination: /mnt/backup/wiki-llm/"
print_info ""
print_info "Included in backup-all.sh orchestrator (no separate cron entry needed)"

print_success "Task complete"
exit 0
