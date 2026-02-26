#!/bin/bash
# Task: Create backup subdirectories
# Phase: 2 (Infrastructure)
# Number: 03
# Prerequisites: Task 2.1 complete (/mnt/data/backups exists)
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
if [[ ! -d /mnt/data/backups ]]; then
    print_error "/mnt/data/backups does not exist. Run Task 2.1 first."
    exit 2
fi

# Check if already completed (idempotency)
if [[ -d /mnt/data/backups/snapshots ]] && [[ -d /mnt/data/backups/incremental ]] && \
   [[ -d /mnt/data/backups/offsite-sync ]]; then
    print_info "Backup subdirectories already exist - skip"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create /mnt/data/backups/snapshots/ (700, root:root)"
    print_info "[DRY-RUN] Would create /mnt/data/backups/incremental/ (700, root:root)"
    print_info "[DRY-RUN] Would create /mnt/data/backups/offsite-sync/ (700, root:root)"
    exit 0
fi

print_header "Task 2.3: Create Backup Subdirectories"
echo ""

# Create subdirectories
print_info "Creating backup subdirectories..."

if [[ -d /mnt/data/backups/snapshots ]]; then
    print_info "/mnt/data/backups/snapshots/ already exists"
else
    mkdir -p /mnt/data/backups/snapshots
fi
chmod 700 /mnt/data/backups/snapshots
chown root:root /mnt/data/backups/snapshots
print_success "Created /mnt/data/backups/snapshots/ (700, root:root)"

if [[ -d /mnt/data/backups/incremental ]]; then
    print_info "/mnt/data/backups/incremental/ already exists"
else
    mkdir -p /mnt/data/backups/incremental
fi
chmod 700 /mnt/data/backups/incremental
chown root:root /mnt/data/backups/incremental
print_success "Created /mnt/data/backups/incremental/ (700, root:root)"

if [[ -d /mnt/data/backups/offsite-sync ]]; then
    print_info "/mnt/data/backups/offsite-sync/ already exists"
else
    mkdir -p /mnt/data/backups/offsite-sync
fi
chmod 700 /mnt/data/backups/offsite-sync
chown root:root /mnt/data/backups/offsite-sync
print_success "Created /mnt/data/backups/offsite-sync/ (700, root:root)"

print_success "Task 2.3 complete"
exit 0
