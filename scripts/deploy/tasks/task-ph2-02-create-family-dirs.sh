#!/bin/bash
# Task: Create family subdirectories
# Phase: 2 (Infrastructure)
# Number: 02
# Prerequisites: Task 2.1 complete (/mnt/data/family exists)
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
if [[ ! -d /mnt/data/family ]]; then
    print_error "/mnt/data/family does not exist. Run Task 2.1 first."
    exit 2
fi

# Create family group if not exists
if ! getent group family &>/dev/null; then
    print_info "Creating family group..."
    groupadd family
fi

# Check if already completed (idempotency) - but still fix permissions if needed
DIRS_EXIST=true
for dir in Documents Photos Videos Projects; do
    [[ ! -d "/mnt/data/family/$dir" ]] && DIRS_EXIST=false
done

if [[ "$DIRS_EXIST" == true ]]; then
    print_info "Family subdirectories already exist - fixing permissions for ALL folders..."
    # Fix permissions for all folders in /mnt/data/family/ (including manually created ones)
    for dir in /mnt/data/family/*/; do
        if [[ -d "$dir" ]]; then
            dirname=$(basename "$dir")
            # Determine correct permissions based on folder name
            if [[ "$dirname" == "Photos" ]] || [[ "$dirname" == "Music" ]]; then
                chmod 2770 "$dir" && chown root:family "$dir"
                print_success "Fixed $dirname/ (2770, root:family, setgid)"
            else
                chmod 2775 "$dir" && chown root:family "$dir"
                print_success "Fixed $dirname/ (2775, root:family, setgid)"
            fi
        fi
    done
    print_success "All family folders verified/fixed (setgid bit applied)"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create /mnt/data/family/Documents/ (2775, root:family, setgid)"
    print_info "[DRY-RUN] Would create /mnt/data/family/Photos/ (2770, root:family, setgid)"
    print_info "[DRY-RUN] Would create /mnt/data/family/Videos/ (2770, root:family, setgid)"
    print_info "[DRY-RUN] Would create /mnt/data/family/Projects/ (2775, root:family, setgid)"
    exit 0
fi

print_header "Task 2.2: Create Family Subdirectories"
echo ""

# Create subdirectories
print_info "Creating family subdirectories..."

if [[ -d /mnt/data/family/Documents ]]; then
    print_info "/mnt/data/family/Documents/ already exists"
else
    mkdir -p /mnt/data/family/Documents
fi
chmod 2775 /mnt/data/family/Documents
chown root:family /mnt/data/family/Documents
print_success "Created /mnt/data/family/Documents/ (2775, root:family, setgid)"

if [[ -d /mnt/data/family/Photos ]]; then
    print_info "/mnt/data/family/Photos/ already exists"
else
    mkdir -p /mnt/data/family/Photos
fi
chmod 2770 /mnt/data/family/Photos
chown root:family /mnt/data/family/Photos
print_success "Created /mnt/data/family/Photos/ (2770, root:family, setgid)"

if [[ -d /mnt/data/family/Videos ]]; then
    print_info "/mnt/data/family/Videos/ already exists"
else
    mkdir -p /mnt/data/family/Videos
fi
chmod 2770 /mnt/data/family/Videos
chown root:family /mnt/data/family/Videos
print_success "Created /mnt/data/family/Videos/ (2770, root:family, setgid)"

if [[ -d /mnt/data/family/Projects ]]; then
    print_info "/mnt/data/family/Projects/ already exists"
else
    mkdir -p /mnt/data/family/Projects
fi
chmod 2775 /mnt/data/family/Projects
chown root:family /mnt/data/family/Projects
print_success "Created /mnt/data/family/Projects/ (2775, root:family, setgid)"

print_success "Task 2.2 complete"
exit 0
