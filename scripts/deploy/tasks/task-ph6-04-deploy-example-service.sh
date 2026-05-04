#!/bin/bash
# Task: Deploy example service using the helper
# Phase: 6 (Docker Service Helper)
# Number: 04
# Prerequisites: task-ph6-03 (services.yml created), helper scripts deployed
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes: 0 = Success, 1 = Failure
# Requirements: 15.3–15.6, 17.5–17.7

set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Error: Must run as root (use sudo)" >&2; exit 1; }

source /opt/homeserver/scripts/operations/utils/output-utils.sh

DRY_RUN=false
DRY_RUN_ARG=""
[[ "${1:-}" == "--dry-run" ]] && { DRY_RUN=true; DRY_RUN_ARG="--dry-run"; }

HELPER="/opt/homeserver/scripts/docker-helper/docker-service-helper.sh"
SERVICE="${2:-vocabgen}"

print_header "Task ph6-04: Deploy example service (${SERVICE})"

if [[ ! -x "$HELPER" ]]; then
    print_error "Helper script not found or not executable: ${HELPER}"
    exit 1
fi

# Deploy via helper
if ! bash "$HELPER" add "$SERVICE" ${DRY_RUN_ARG}; then
    print_error "Failed to deploy ${SERVICE}"
    exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would deploy and validate ${SERVICE}"
    exit 0
fi

# Validate deployment
if ! bash "$HELPER" validate "$SERVICE"; then
    print_error "Validation failed for ${SERVICE}"
    exit 1
fi

print_success "Example service '${SERVICE}' deployed and validated"
exit 0
