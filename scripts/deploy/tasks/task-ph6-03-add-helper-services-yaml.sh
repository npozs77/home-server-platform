#!/bin/bash
# Task: Create live services.yml from example
# Phase: 6 (Docker Service Helper)
# Number: 03
# Prerequisites: task-ph6-02 (helper scripts deployed), yq installed
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes: 0 = Success, 1 = Failure
# Requirements: 24.3, 15.1, 15.2

set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Error: Must run as root (use sudo)" >&2; exit 1; }

source /opt/homeserver/scripts/operations/utils/output-utils.sh

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

CONF_DIR="/opt/homeserver/configs/helper-services"
EXAMPLE="${CONF_DIR}/services.yml.example"
LIVE="${CONF_DIR}/services.yml"

print_header "Task ph6-03: Create helper services YAML"

# Verify example exists
if [[ ! -f "$EXAMPLE" ]]; then
    print_error "Example file missing: ${EXAMPLE}"
    exit 1
fi

# Idempotent: skip if live file exists
if [[ -f "$LIVE" ]]; then
    print_info "Live config already exists: ${LIVE} — skip"
    exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would copy ${EXAMPLE} → ${LIVE}"
    exit 0
fi

cp "$EXAMPLE" "$LIVE"
chmod 644 "$LIVE"

# Validate with yq
if ! yq '.' "$LIVE" >/dev/null 2>&1; then
    print_error "Generated services.yml has YAML syntax errors"
    rm -f "$LIVE"
    exit 1
fi

local_count=$(yq '.services | length' "$LIVE")
print_success "Created ${LIVE} with ${local_count} service definition(s)"
exit 0
