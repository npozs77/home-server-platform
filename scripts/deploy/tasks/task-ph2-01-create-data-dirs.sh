#!/bin/bash
# Task: Create top-level data directories
# Phase: 2 (Infrastructure)
# Number: 01
# Prerequisites: Phase 1 complete (/mnt/data mounted)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   2 = Prerequisites not met
# Environment Variables Required:
#   None
# Environment Variables Optional:
#   None

set -euo pipefail
# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utility libraries
source /opt/homeserver/scripts/operations/utils/output-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Check prerequisites
if [[ ! -d /mnt/data ]]; then
    print_error "/mnt/data does not exist. Phase 1 incomplete?"
    exit 2
fi

# Create family group if not exists (always check, even if dirs exist)
if ! getent group family &>/dev/null; then
    print_info "Creating family group..."
    groupadd family
fi

# Check if already completed (idempotency) - but still fix permissions if needed
DIRS_EXIST=true
for dir in media family users backups services; do
    [[ ! -d "/mnt/data/$dir" ]] && DIRS_EXIST=false
done

if [[ "$DIRS_EXIST" == true ]]; then
    print_info "Top-level data directories already exist - fixing permissions if needed"
    # Fix permissions even if dirs exist
    chmod 755 /mnt/data/media && chown root:root /mnt/data/media
    chmod 755 /mnt/data/family && chown root:family /mnt/data/family
    chmod 755 /mnt/data/users && chown root:root /mnt/data/users
    chmod 700 /mnt/data/backups && chown root:root /mnt/data/backups
    chmod 755 /mnt/data/services && chown root:root /mnt/data/services
    print_success "Permissions verified/fixed"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create /mnt/data/media/ (755, root:root)"
    print_info "[DRY-RUN] Would create /mnt/data/family/ (755, root:family)"
    print_info "[DRY-RUN] Would create /mnt/data/users/ (755, root:root)"
    print_info "[DRY-RUN] Would create /mnt/data/backups/ (700, root:root)"
    print_info "[DRY-RUN] Would create /mnt/data/services/ (755, root:root)"
    exit 0
fi

print_header "Task 2.1: Create Top-Level Data Directories"
echo ""

# Create family group if not exists
if ! getent group family &>/dev/null; then
    print_info "Creating family group..."
    groupadd family
fi

# Create directories
print_info "Creating top-level directories..."

if [[ -d /mnt/data/media ]]; then
    print_info "/mnt/data/media/ already exists"
else
    mkdir -p /mnt/data/media
fi
chmod 755 /mnt/data/media
chown root:root /mnt/data/media
print_success "Created /mnt/data/media/ (755, root:root)"

if [[ -d /mnt/data/family ]]; then
    print_info "/mnt/data/family/ already exists"
else
    mkdir -p /mnt/data/family
fi
chmod 755 /mnt/data/family
chown root:family /mnt/data/family
print_success "Created /mnt/data/family/ (755, root:family)"

if [[ -d /mnt/data/users ]]; then
    print_info "/mnt/data/users/ already exists"
else
    mkdir -p /mnt/data/users
fi
chmod 755 /mnt/data/users
chown root:root /mnt/data/users
print_success "Created /mnt/data/users/ (755, root:root)"

if [[ -d /mnt/data/backups ]]; then
    print_info "/mnt/data/backups/ already exists"
else
    mkdir -p /mnt/data/backups
fi
chmod 700 /mnt/data/backups
chown root:root /mnt/data/backups
print_success "Created /mnt/data/backups/ (700, root:root)"

if [[ -d /mnt/data/services ]]; then
    print_info "/mnt/data/services/ already exists"
else
    mkdir -p /mnt/data/services
fi
chmod 755 /mnt/data/services
chown root:root /mnt/data/services
print_success "Created /mnt/data/services/ (755, root:root)"

print_success "Task 2.1 complete"
exit 0
