#!/bin/bash
# Task: Deploy Immich backup script
# Phase: 4 (Photo Management)
# Number: 07
# Purpose: Install backup-immich.sh to /opt/homeserver/scripts/backup/
# Prerequisites:
#   - Immich stack deployed and running (Task 3.3)
#   - msmtp configured for email alerts (Phase 2)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error

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
BACKUP_SCRIPT_SRC="${SCRIPT_DIR}/../../backup/backup-immich.sh"
BACKUP_SCRIPT_DEST="/opt/homeserver/scripts/backup/backup-immich.sh"
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/immich-backup.log"
FOUNDATION_ENV="/opt/homeserver/configs/foundation.env"

print_header "Task 4.7: Deploy Immich Backup Script"

# ============================================================
# Validate prerequisites
# ============================================================
print_info "Validating prerequisites..."

if ! docker info &> /dev/null; then
    print_error "Docker is not running"
    exit 3
fi

# Check immich-postgres container exists
if ! docker ps --format '{{.Names}}' | grep -q "^immich-postgres$"; then
    print_error "immich-postgres container is not running"
    print_info "Deploy Immich stack first (Task 3.3)"
    exit 3
fi

# Verify source backup script exists
if [[ ! -f "$BACKUP_SCRIPT_SRC" ]]; then
    print_error "Backup script source not found: $BACKUP_SCRIPT_SRC"
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
    print_info "[DRY-RUN] Would create log file: $LOG_FILE"
else
    # Create backup scripts directory
    mkdir -p "$(dirname "$BACKUP_SCRIPT_DEST")"

    # Copy backup script to destination
    cp "$BACKUP_SCRIPT_SRC" "$BACKUP_SCRIPT_DEST"
    chmod 755 "$BACKUP_SCRIPT_DEST"
    print_success "Installed $BACKUP_SCRIPT_DEST"

    # Create log file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
        print_success "Created log file: $LOG_FILE"
    else
        print_info "Log file already exists: $LOG_FILE"
    fi
fi

# ============================================================
# Validate deployment
# ============================================================
print_info "Validating deployment..."

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would validate: script exists, executable, syntax"
    print_info "[DRY-RUN] Would validate: pg_dump reference, rsync reference"
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

    # Verify script uses pg_dump (not filesystem copy)
    if grep -q "pg_dump" "$BACKUP_SCRIPT_DEST"; then
        print_success "Script uses pg_dump for database backup"
    else
        print_error "Script does not use pg_dump — violates backup requirements"
        exit 1
    fi

    # Verify script uses rsync for upload directory
    if grep -q "rsync" "$BACKUP_SCRIPT_DEST"; then
        print_success "Script uses rsync for upload backup"
    else
        print_error "Script does not use rsync for upload backup"
        exit 1
    fi
fi

# ============================================================
# Summary
# ============================================================
print_header "Deployment Summary"
print_success "Backup script deployed: $BACKUP_SCRIPT_DEST"
print_info "Log file: $LOG_FILE"
print_info ""
print_info "Usage:"
print_info "  sudo $BACKUP_SCRIPT_DEST [backup_destination]"
print_info "  Default destination: /mnt/backup/immich/"
print_info ""
print_info "Cron entry (add when DAS HDD is available):"
print_info "  0 2 * * * root $BACKUP_SCRIPT_DEST /mnt/backup/immich >> $LOG_FILE 2>&1"

print_success "Task complete"
exit 0
