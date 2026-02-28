#!/bin/bash
# Task: Create services/jellyfin subdirectories
# Phase: 3 (Core Services)
# Number: 02
# Prerequisites:
#   - Phase 2 complete
#   - /mnt/data/services/ exists
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   None (uses hardcoded paths)
# Environment Variables Optional:
#   None

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

# Validate prerequisites
print_info "Validating prerequisites..."

# Check /mnt/data/services/ exists
if [[ ! -d /mnt/data/services ]]; then
    print_error "/mnt/data/services/ does not exist (should be created in Phase 2)"
    exit 3
fi

# Define subdirectories to create
declare -A JELLYFIN_DIRS=(
    ["/mnt/data/services/jellyfin"]="755:root:root"
    ["/mnt/data/services/jellyfin/config"]="755:root:root"
    ["/mnt/data/services/jellyfin/cache"]="755:root:root"
)

# Check idempotency
all_exist=true
for dir in "${!JELLYFIN_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        all_exist=false
        break
    fi
done

if [[ "$all_exist" == true ]]; then
    print_info "All Jellyfin service subdirectories already exist"
    if [[ "$DRY_RUN" == false ]]; then
        print_info "Verifying permissions and ownership..."
        for dir in "${!JELLYFIN_DIRS[@]}"; do
            IFS=':' read -r perms owner group <<< "${JELLYFIN_DIRS[$dir]}"
            current_perms=$(stat -c "%a" "$dir")
            current_owner=$(stat -c "%U" "$dir")
            current_group=$(stat -c "%G" "$dir")
            
            if [[ "$current_perms" != "$perms" ]] || [[ "$current_owner" != "$owner" ]] || [[ "$current_group" != "$group" ]]; then
                print_info "Fixing permissions for $dir"
                chmod "$perms" "$dir"
                chown "$owner:$group" "$dir"
            fi
        done
        print_success "All Jellyfin service subdirectories verified"
    fi
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create Jellyfin service subdirectories:"
    for dir in "${!JELLYFIN_DIRS[@]}"; do
        IFS=':' read -r perms owner group <<< "${JELLYFIN_DIRS[$dir]}"
        print_info "  - $dir ($perms, $owner:$group)"
    done
else
    print_info "Creating Jellyfin service subdirectories..."
    
    for dir in "${!JELLYFIN_DIRS[@]}"; do
        IFS=':' read -r perms owner group <<< "${JELLYFIN_DIRS[$dir]}"
        
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod "$perms" "$dir"
            chown "$owner:$group" "$dir"
            print_success "Created $dir ($perms, $owner:$group)"
        else
            print_info "$dir already exists, verifying permissions..."
            chmod "$perms" "$dir"
            chown "$owner:$group" "$dir"
            print_success "Verified $dir ($perms, $owner:$group)"
        fi
    done
    
    print_success "All Jellyfin service subdirectories created"
fi

print_success "Task complete"
exit 0
