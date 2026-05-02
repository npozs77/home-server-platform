#!/bin/bash
# Task: Create Wiki.js data directories
# Phase: 5 (Wiki + LLM Platform — Sub-phase A)
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
# Satisfies: Requirements 2.1, 5.1, 5.2

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

if [[ ! -d /mnt/data/services ]]; then
    print_error "/mnt/data/services/ does not exist (should be created in Phase 2)"
    exit 3
fi

# Define Wiki.js base directory
WIKI_BASE="/mnt/data/services/wiki"

# Define subdirectories with permissions and ownership
# Format: "permissions:owner:group"
# - postgres/: Owned by postgres process inside container; set initial ownership
#   to root:root with 700 — Docker/postgres will manage internally
# - content/: Wiki.js Local File System storage module output; writable by
#   wiki-server container process (runs as uid 1000 / node); 755 initially
declare -A WIKI_DIRS=(
    ["${WIKI_BASE}/postgres"]="700:root:root"
    ["${WIKI_BASE}/content"]="755:1000:1000"
)

# Verify and fix permissions on a directory
verify_permissions() {
    local dir="$1" perms="$2" owner="$3" group="$4"
    local cur_p; cur_p=$(stat -c "%a" "$dir")
    local cur_o; cur_o=$(stat -c "%U" "$dir")
    local cur_g; cur_g=$(stat -c "%G" "$dir")
    if [[ "$cur_p" != "$perms" ]] || [[ "$cur_o" != "$owner" ]] || [[ "$cur_g" != "$group" ]]; then
        chmod "$perms" "$dir"; chown "$owner:$group" "$dir"
        print_success "Fixed $dir to $owner:$group with $perms"
    else
        print_info "$dir OK ($owner:$group, $perms)"
    fi
}

# Check idempotency — if all dirs already exist, verify permissions and exit
all_exist=true
for dir in "${!WIKI_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        all_exist=false
        break
    fi
done

if [[ "$all_exist" == true ]]; then
    print_info "All Wiki.js directories already exist"
    if [[ "$DRY_RUN" == false ]]; then
        print_info "Verifying permissions and ownership..."
        for dir in "${!WIKI_DIRS[@]}"; do
            IFS=':' read -r perms owner group <<< "${WIKI_DIRS[$dir]}"
            verify_permissions "$dir" "$perms" "$owner" "$group"
        done
        print_success "All Wiki.js directories verified"
    else
        print_info "[DRY-RUN] Would verify permissions on existing directories"
    fi
    exit 0
fi

# Execute task — create directories
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create Wiki.js directories:"

    # Base directory
    if [[ ! -d "$WIKI_BASE" ]]; then
        print_info "  - $WIKI_BASE (root:root, 755)"
    else
        print_info "  - $WIKI_BASE (already exists)"
    fi

    # Subdirectories
    for dir in "${!WIKI_DIRS[@]}"; do
        IFS=':' read -r perms owner group <<< "${WIKI_DIRS[$dir]}"
        if [[ ! -d "$dir" ]]; then
            print_info "  - $dir ($perms, $owner:$group)"
        else
            print_info "  - $dir (already exists, would verify permissions)"
        fi
    done
else
    print_info "Creating Wiki.js directories..."

    # Create base directory if needed
    if [[ ! -d "$WIKI_BASE" ]]; then
        mkdir -p "$WIKI_BASE"
        chown root:root "$WIKI_BASE"
        chmod 755 "$WIKI_BASE"
        print_success "Created $WIKI_BASE (root:root, 755)"
    else
        print_info "$WIKI_BASE already exists"
    fi

    # Create subdirectories
    for dir in "${!WIKI_DIRS[@]}"; do
        IFS=':' read -r perms owner group <<< "${WIKI_DIRS[$dir]}"

        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod "$perms" "$dir"
            chown "$owner:$group" "$dir"
            print_success "Created $dir ($perms, $owner:$group)"
        else
            print_info "$dir already exists, verifying permissions..."
            verify_permissions "$dir" "$perms" "$owner" "$group"
        fi
    done

    print_success "All Wiki.js directories created"
fi

print_success "Task complete"
exit 0
