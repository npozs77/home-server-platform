#!/bin/bash
# Task: Deploy helper scripts to server
# Phase: 6 (Docker Service Helper)
# Number: 02
# Prerequisites: task-ph6-01 (yq installed)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes: 0 = Success, 1 = Failure
# Requirements: 12.2, 12.3

set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Error: Must run as root (use sudo)" >&2; exit 1; }

source /opt/homeserver/scripts/operations/utils/output-utils.sh

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

REPO_ROOT="/opt/homeserver"
HELPER_DIR="${REPO_ROOT}/scripts/docker-helper"

print_header "Task ph6-02: Deploy helper scripts"

# Verify source files exist (they come from git pull)
REQUIRED_FILES=(
    "${HELPER_DIR}/docker-service-helper.sh"
    "${HELPER_DIR}/lib/compose-gen.sh"
    "${HELPER_DIR}/lib/service-ops.sh"
    "${HELPER_DIR}/templates/caddy-block.template"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        print_error "Missing: $f — run 'git pull' first"
        exit 1
    fi
done
print_success "All helper source files present"

# Ensure executable permissions
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would set executable permissions on helper scripts"
else
    chmod +x "${HELPER_DIR}/docker-service-helper.sh"
    chmod +x "${HELPER_DIR}/lib/compose-gen.sh"
    chmod +x "${HELPER_DIR}/lib/service-ops.sh"
    print_success "Executable permissions set"
fi

# Create helper-services config directory
CONF_DIR="${REPO_ROOT}/configs/helper-services"
if [[ -d "$CONF_DIR" ]]; then
    print_info "Config directory already exists: ${CONF_DIR}"
else
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create ${CONF_DIR}"
    else
        mkdir -p "$CONF_DIR"
        print_success "Created ${CONF_DIR}"
    fi
fi

# Verify bash syntax
for f in "${REQUIRED_FILES[@]}"; do
    [[ "$f" == *.sh ]] || continue
    if ! bash -n "$f" 2>/dev/null; then
        print_error "Syntax error in $f"
        exit 1
    fi
done
print_success "All scripts pass bash syntax check"

print_success "Helper scripts deployed"
exit 0
