#!/bin/bash
# Task: Verify Phase 5 documentation files
# Phase: 5 (Wiki + LLM Platform — Shared Components)
# Number: 13
# Purpose: Validate that all Phase 5 documentation files are present on the server.
#   Documentation files are created in the local Git repo and scp'd to the server
#   alongside all other scripts and configs — no generation step needed.
# Parameters:
#   --dry-run: Report what would be checked without failing
# Exit Codes:
#   0 = All docs present
#   1 = Missing documentation files
# Satisfies: Requirements 21.1-21.6, 22.1-22.6

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utilities
source /opt/homeserver/scripts/operations/utils/output-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

print_header "Task 5.13: Verify Phase 5 Documentation"

# This task is a read-only verification — safe to run multiple times (skipping
# any modification). If all docs already exist, it simply reports success.

# Documentation files that must exist
DOC_FILES=(
    "/opt/homeserver/docs/deployment_manuals/phase5-wiki-llm.md"
    "/opt/homeserver/docs/10-wiki-setup.md"
    "/opt/homeserver/docs/11-llm-setup.md"
)

# Documentation files that must contain Phase 5 content (updated files)
UPDATE_TARGETS=(
    "/opt/homeserver/docs/00-architecture-overview.md:Wiki.js"
    "/opt/homeserver/docs/05-storage.md:wiki/postgres"
    "/opt/homeserver/docs/13-container-restart-procedure.md:wiki-db"
    "/opt/homeserver/README.md:wiki.home"
)

TOTAL=0
PASSED=0

# Check new documentation files exist
print_info "Checking new documentation files..."
for doc in "${DOC_FILES[@]}"; do
    TOTAL=$((TOTAL + 1))
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would check: $doc"
        PASSED=$((PASSED + 1))
    elif [[ -f "$doc" ]]; then
        print_success "Found: $(basename "$doc")"
        PASSED=$((PASSED + 1))
    else
        print_error "Missing: $doc"
    fi
done

# Check updated documentation files contain Phase 5 content
print_info "Checking updated documentation files..."
for entry in "${UPDATE_TARGETS[@]}"; do
    local_file="${entry%%:*}"
    search_term="${entry##*:}"
    TOTAL=$((TOTAL + 1))
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would check: $(basename "$local_file") contains '$search_term'"
        PASSED=$((PASSED + 1))
    elif [[ ! -f "$local_file" ]]; then
        print_error "File not found: $local_file"
    elif grep -q "$search_term" "$local_file"; then
        print_success "Updated: $(basename "$local_file") (contains '$search_term')"
        PASSED=$((PASSED + 1))
    else
        print_error "Not updated: $(basename "$local_file") (missing '$search_term')"
    fi
done

# Summary
echo ""
print_header "Documentation Verification Summary"
echo "$PASSED / $TOTAL documentation checks passed"

if [[ $PASSED -eq $TOTAL ]]; then
    print_success "All Phase 5 documentation present and updated"
    exit 0
else
    print_error "Some documentation files missing or not updated"
    print_info "Ensure all docs are scp'd to the server from the local repo"
    exit 1
fi
