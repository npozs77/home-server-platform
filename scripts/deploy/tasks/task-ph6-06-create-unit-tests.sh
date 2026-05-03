#!/bin/bash
# Task: Deploy unit test file to server
# Phase: 6 (Docker Service Helper)
# Number: 06
# Prerequisites: Helper scripts deployed
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes: 0 = Success, 1 = Failure
# Requirements: 12.3, 17.1

set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Error: Must run as root (use sudo)" >&2; exit 1; }

source /opt/homeserver/scripts/operations/utils/output-utils.sh

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

TEST_FILE="/opt/homeserver/tests/test_phase6_scripts.sh"

print_header "Task ph6-06: Deploy unit tests"

if [[ -f "$TEST_FILE" ]]; then
    print_info "Test file already exists: ${TEST_FILE} — skip"
    exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would verify test file exists at ${TEST_FILE}"
    exit 0
fi

# Test file comes from git pull — verify it arrived
if [[ ! -f "$TEST_FILE" ]]; then
    print_error "Test file not found: ${TEST_FILE} — run 'git pull' first"
    exit 1
fi

chmod +x "$TEST_FILE"
print_success "Unit test file deployed: ${TEST_FILE}"
exit 0
