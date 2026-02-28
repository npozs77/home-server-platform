#!/bin/bash
# Task: Create media library subdirectories
# Phase: 3 (Core Services)
# Number: 01
# Prerequisites:
#   - Phase 2 complete
#   - /mnt/data/media/ exists
#   - media group exists (GID 1002)
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

# Check /mnt/data/media/ exists
if [[ ! -d /mnt/data/media ]]; then
    print_error "/mnt/data/media/ does not exist (should be created in Phase 2)"
    exit 3
fi

# Check media group exists, create if missing
if ! getent group media &>/dev/null; then
    print_info "media group does not exist, creating with GID 1002..."
    if [[ "$DRY_RUN" == false ]]; then
        groupadd -g 1002 media
        print_success "Created media group (GID 1002)"
    else
        print_info "[DRY-RUN] Would create media group (GID 1002)"
    fi
fi

# Get media group GID
MEDIA_GID=$(getent group media | cut -d: -f3)
print_info "media group GID: $MEDIA_GID"

# Validate GID is 1002
if [[ "$MEDIA_GID" != "1002" ]]; then
    print_error "media group GID is $MEDIA_GID, expected 1002"
    exit 3
fi

# Define subdirectories to create
declare -A MEDIA_DIRS=(
    ["/mnt/data/media/Movies"]="755:root:media"
    ["/mnt/data/media/TV Shows"]="755:root:media"
    ["/mnt/data/media/Music"]="755:root:media"
)

# Check idempotency
all_exist=true
for dir in "${!MEDIA_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        all_exist=false
        break
    fi
done

if [[ "$all_exist" == true ]]; then
    print_info "All media subdirectories already exist"
    if [[ "$DRY_RUN" == false ]]; then
        print_info "Verifying permissions and ownership..."
        for dir in "${!MEDIA_DIRS[@]}"; do
            IFS=':' read -r perms owner group <<< "${MEDIA_DIRS[$dir]}"
            current_perms=$(stat -c "%a" "$dir")
            current_owner=$(stat -c "%U" "$dir")
            current_group=$(stat -c "%G" "$dir")
            
            if [[ "$current_perms" != "$perms" ]] || [[ "$current_owner" != "$owner" ]] || [[ "$current_group" != "$group" ]]; then
                print_info "Fixing permissions for $dir"
                chmod "$perms" "$dir"
                chown "$owner:$group" "$dir"
            fi
        done
        print_success "All media subdirectories verified"
    fi
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create media subdirectories:"
    for dir in "${!MEDIA_DIRS[@]}"; do
        IFS=':' read -r perms owner group <<< "${MEDIA_DIRS[$dir]}"
        print_info "  - $dir ($perms, $owner:$group)"
    done
else
    print_info "Creating media subdirectories..."
    
    for dir in "${!MEDIA_DIRS[@]}"; do
        IFS=':' read -r perms owner group <<< "${MEDIA_DIRS[$dir]}"
        
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
    
    print_success "All media subdirectories created"
fi

print_success "Task complete"
exit 0
