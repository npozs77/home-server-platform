#!/bin/bash
# Task: Create Ollama + Open WebUI data directories
# Phase: 5 (Wiki + LLM Platform — Sub-phase B)
# Number: 06
# Prerequisites:
#   - Phase 1 complete (LUKS encrypted /mnt/data/ mounted)
#   - /mnt/data/services/ exists (created in Phase 2)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Satisfies: Requirements 7.2, 9.2

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

# Define base directories
OLLAMA_BASE="/mnt/data/services/ollama"
OPENWEBUI_BASE="/mnt/data/services/openwebui"

# Define subdirectories with permissions and ownership
# Format: "permissions:owner:group"
# - ollama/models/: Ollama stores models at /root/.ollama inside container;
#   mapped to host. Container runs as root, so root:root with 755.
# - openwebui/data/: Open WebUI stores SQLite DB, chat history, RAG embeddings;
#   container runs as internal user. root:root with 755 initially.
declare -A LLM_DIRS=(
    ["${OLLAMA_BASE}/models"]="755:root:root"
    ["${OPENWEBUI_BASE}/data"]="755:root:root"
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
for dir in "${!LLM_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        all_exist=false
        break
    fi
done

if [[ "$all_exist" == true ]]; then
    print_info "All Ollama/Open WebUI directories already exist"
    if [[ "$DRY_RUN" == false ]]; then
        print_info "Verifying permissions and ownership..."
        for dir in "${!LLM_DIRS[@]}"; do
            IFS=':' read -r perms owner group <<< "${LLM_DIRS[$dir]}"
            verify_permissions "$dir" "$perms" "$owner" "$group"
        done
        print_success "All Ollama/Open WebUI directories verified"
    else
        print_info "[DRY-RUN] Would verify permissions on existing directories"
    fi
    exit 0
fi

# Execute task — create directories
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create Ollama/Open WebUI directories:"

    for base in "$OLLAMA_BASE" "$OPENWEBUI_BASE"; do
        if [[ ! -d "$base" ]]; then
            print_info "  - $base (root:root, 755)"
        else
            print_info "  - $base (already exists)"
        fi
    done

    for dir in "${!LLM_DIRS[@]}"; do
        IFS=':' read -r perms owner group <<< "${LLM_DIRS[$dir]}"
        if [[ ! -d "$dir" ]]; then
            print_info "  - $dir ($perms, $owner:$group)"
        else
            print_info "  - $dir (already exists, would verify permissions)"
        fi
    done
else
    print_info "Creating Ollama/Open WebUI directories..."

    # Create base directories if needed
    for base in "$OLLAMA_BASE" "$OPENWEBUI_BASE"; do
        if [[ ! -d "$base" ]]; then
            mkdir -p "$base"
            chown root:root "$base"
            chmod 755 "$base"
            print_success "Created $base (root:root, 755)"
        else
            print_info "$base already exists"
        fi
    done

    # Create subdirectories
    for dir in "${!LLM_DIRS[@]}"; do
        IFS=':' read -r perms owner group <<< "${LLM_DIRS[$dir]}"

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

    print_success "All Ollama/Open WebUI directories created"
fi

print_success "Task complete"
exit 0
