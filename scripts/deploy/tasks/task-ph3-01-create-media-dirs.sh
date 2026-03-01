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

# Check media system user exists, create if missing
if ! getent passwd media &>/dev/null; then
    print_info "media system user does not exist, creating..."
    if [[ "$DRY_RUN" == false ]]; then
        # Use -g to add user to existing media group (created in Phase 2)
        useradd -r -s /usr/sbin/nologin -g media media
        print_success "Created media system user (no login)"
    else
        print_info "[DRY-RUN] Would create media system user (no login)"
    fi
fi

# Fix /mnt/data/media ownership if needed (should be media:media with setgid)
MEDIA_DIR_OWNER=$(stat -c "%U" /mnt/data/media)
MEDIA_DIR_GROUP=$(stat -c "%G" /mnt/data/media)
MEDIA_DIR_PERMS=$(stat -c "%a" /mnt/data/media)
if [[ "$MEDIA_DIR_OWNER" != "media" ]] || [[ "$MEDIA_DIR_GROUP" != "media" ]] || [[ "$MEDIA_DIR_PERMS" != "2775" ]]; then
    print_info "Fixing /mnt/data/media ownership and permissions (currently $MEDIA_DIR_OWNER:$MEDIA_DIR_GROUP, $MEDIA_DIR_PERMS)..."
    if [[ "$DRY_RUN" == false ]]; then
        chown media:media /mnt/data/media
        chmod 2775 /mnt/data/media
        print_success "Fixed /mnt/data/media to media:media with 2775 (setgid)"
    else
        print_info "[DRY-RUN] Would fix /mnt/data/media to media:media with 2775 (setgid)"
    fi
fi

# Check media group exists (created automatically with useradd)
if ! getent group media &>/dev/null; then
    print_error "media group does not exist (should be created with media user)"
    exit 3
fi

# Get media group GID
MEDIA_GID=$(getent group media | cut -d: -f3)
print_info "media group GID: $MEDIA_GID"

# Define subdirectories to create (with setgid bit for group inheritance)
declare -A MEDIA_DIRS=(
    ["/mnt/data/media/Movies"]="2775:media:media"
    ["/mnt/data/media/TV Shows"]="2775:media:media"
    ["/mnt/data/media/Music"]="2775:media:media"
    ["/mnt/data/media/Photos"]="2775:media:media"
    ["/mnt/data/media/HomeVideos"]="2775:media:media"
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
        
        # Also fix any other subdirectories in /mnt/data/media/
        print_info "Checking for additional media subdirectories..."
        for dir in /mnt/data/media/*/; do
            if [[ -d "$dir" ]]; then
                current_perms=$(stat -c "%a" "$dir")
                current_owner=$(stat -c "%U" "$dir")
                current_group=$(stat -c "%G" "$dir")
                
                if [[ "$current_perms" != "2775" ]] || [[ "$current_owner" != "media" ]] || [[ "$current_group" != "media" ]]; then
                    print_info "Fixing permissions for $dir"
                    chmod 2775 "$dir"
                    chown media:media "$dir"
                fi
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
