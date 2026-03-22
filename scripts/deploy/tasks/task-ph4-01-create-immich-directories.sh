#!/bin/bash
# Task: Create Immich data directories
# Phase: 4 (Photo Management)
# Number: 01
# Prerequisites:
#   - Phase 1 complete (LUKS encrypted /mnt/data/ mounted)
#   - /mnt/data/services/ exists (created in Phase 2)
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

# Check /mnt/data/services/ exists (created in Phase 2)
if [[ ! -d /mnt/data/services ]]; then
    print_error "/mnt/data/services/ does not exist (should be created in Phase 2)"
    exit 3
fi

# Define Immich base directory
IMMICH_BASE="/mnt/data/services/immich"

# Define subdirectories with permissions and ownership
# Format: "permissions:owner:group"
# - postgres/: Owned by postgres process inside container; set initial ownership
#   to root:root with 700 — Docker/postgres will manage internally
# - upload/: Writable by immich-server container process; set to root:root with
#   755 initially — container manages internal ownership
# - model-cache: Uses a named Docker volume (created automatically by Docker
#   Compose) — NO host directory needed
declare -A IMMICH_DIRS=(
    ["${IMMICH_BASE}/postgres"]="700:root:root"
    ["${IMMICH_BASE}/upload"]="755:root:root"
)

# Check idempotency — if all dirs already exist, verify permissions and exit
all_exist=true
for dir in "${!IMMICH_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        all_exist=false
        break
    fi
done

if [[ "$all_exist" == true ]]; then
    print_info "All Immich directories already exist"
    if [[ "$DRY_RUN" == false ]]; then
        print_info "Verifying permissions and ownership..."
        for dir in "${!IMMICH_DIRS[@]}"; do
            IFS=':' read -r perms owner group <<< "${IMMICH_DIRS[$dir]}"
            current_perms=$(stat -c "%a" "$dir")
            current_owner=$(stat -c "%U" "$dir")
            current_group=$(stat -c "%G" "$dir")

            if [[ "$current_perms" != "$perms" ]] || [[ "$current_owner" != "$owner" ]] || [[ "$current_group" != "$group" ]]; then
                print_info "Fixing permissions for $dir (currently $current_owner:$current_group, $current_perms)"
                chmod "$perms" "$dir"
                chown "$owner:$group" "$dir"
                print_success "Fixed $dir to $owner:$group with $perms"
            else
                print_info "$dir OK ($owner:$group, $perms)"
            fi
        done
        print_success "All Immich directories verified"
    else
        print_info "[DRY-RUN] Would verify permissions on existing directories"
    fi
    exit 0
fi

# Execute task — create directories
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create Immich directories:"

    # Base directory
    if [[ ! -d "$IMMICH_BASE" ]]; then
        print_info "  - $IMMICH_BASE (root:root, 755)"
    else
        print_info "  - $IMMICH_BASE (already exists)"
    fi

    # Subdirectories
    for dir in "${!IMMICH_DIRS[@]}"; do
        IFS=':' read -r perms owner group <<< "${IMMICH_DIRS[$dir]}"
        if [[ ! -d "$dir" ]]; then
            print_info "  - $dir ($perms, $owner:$group)"
        else
            print_info "  - $dir (already exists, would verify permissions)"
        fi
    done

    print_info "[DRY-RUN] Note: model-cache uses a named Docker volume (no host directory needed)"
else
    print_info "Creating Immich directories..."

    # Create base directory if needed
    if [[ ! -d "$IMMICH_BASE" ]]; then
        mkdir -p "$IMMICH_BASE"
        chown root:root "$IMMICH_BASE"
        chmod 755 "$IMMICH_BASE"
        print_success "Created $IMMICH_BASE (root:root, 755)"
    else
        print_info "$IMMICH_BASE already exists"
    fi

    # Create subdirectories
    for dir in "${!IMMICH_DIRS[@]}"; do
        IFS=':' read -r perms owner group <<< "${IMMICH_DIRS[$dir]}"

        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod "$perms" "$dir"
            chown "$owner:$group" "$dir"
            print_success "Created $dir ($perms, $owner:$group)"
        else
            print_info "$dir already exists, verifying permissions..."
            current_perms=$(stat -c "%a" "$dir")
            current_owner=$(stat -c "%U" "$dir")
            current_group=$(stat -c "%G" "$dir")

            if [[ "$current_perms" != "$perms" ]] || [[ "$current_owner" != "$owner" ]] || [[ "$current_group" != "$group" ]]; then
                chmod "$perms" "$dir"
                chown "$owner:$group" "$dir"
                print_success "Fixed $dir to $owner:$group with $perms"
            else
                print_success "Verified $dir ($perms, $owner:$group)"
            fi
        fi
    done

    print_info "Note: model-cache uses a named Docker volume (created automatically by Docker Compose)"
    print_success "All Immich directories created"
fi

print_success "Task complete"
exit 0
