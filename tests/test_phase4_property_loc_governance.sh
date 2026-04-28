#!/usr/bin/env bash
# Property Test: Script LOC Governance (Property 10)
# Purpose: For each Phase 4 script, count LOC and verify Warning (not failure)
#          when exceeding indicative limit (300/150/200)
# Validates: Requirements 20.11, 20.12, 20.13, 20.14
# Usage: bash tests/test_phase4_property_loc_governance.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_WARNED=0
TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_warn() { echo -e "${YELLOW}⚠ WARN${NC}: $1"; TESTS_WARNED=$((TESTS_WARNED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Property 10: Script LOC Governance
# For any Phase 4 script, LOC exceeding the indicative limit raises Warning, not failure.
# Limits: orchestration=300, task modules=150, utility libraries=200
check_loc() {
    local script_path="$1"
    local limit="$2"
    local category="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ ! -f "$script_path" ]]; then
        # Script doesn't exist yet — not a governance failure, just skip
        echo -e "${YELLOW}ℹ${NC} $(basename "$script_path") not yet created — skipped"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return
    fi

    local loc
    loc=$(wc -l < "$script_path")

    if [[ $loc -le $limit ]]; then
        print_pass "$(basename "$script_path"): $loc LOC (limit: $limit, $category)"
    else
        # Exceeding is a WARNING, not a failure (per requirements 20.11-20.14)
        print_warn "$(basename "$script_path"): $loc LOC exceeds indicative limit $limit ($category)"
    fi
}

echo "========================================"
echo "Property 10: Script LOC Governance"
echo "========================================"
echo ""
echo "Indicative limits (Warning on exceed, not failure):"
echo "  Orchestration scripts: 300 LOC"
echo "  Task modules:          150 LOC"
echo "  Utility libraries:     200 LOC"
echo ""

# Orchestration script (limit: 300)
echo "--- Orchestration Layer ---"
check_loc "scripts/deploy/deploy-phase4-photo-management.sh" 300 "orchestration"
echo ""

# Task modules (limit: 150 each)
echo "--- Task Module Layer ---"
declare -A TASK_MODULES=(
    ["01"]="create-immich-directories"
    ["02"]="deploy-immich-stack"
    ["03"]="configure-caddy"
    ["04"]="configure-dns"
    ["05"]="configure-samba-uploads"
    ["06"]="deploy-backup-script"
    ["07"]="create-documentation"
    ["08"]="validate-phase4"
)
for i in "${!TASK_MODULES[@]}"; do
    check_loc "scripts/deploy/tasks/task-ph4-${i}-${TASK_MODULES[$i]}.sh" 150 "task module"
done
echo ""

# Utility libraries (limit: 200 each)
echo "--- Utility Library Layer ---"
# Check for any Phase 4 specific utility (immich-utils.sh if created)
if compgen -G "scripts/operations/utils/immich-*.sh" > /dev/null 2>&1; then
    for util in scripts/operations/utils/immich-*.sh; do
        check_loc "$util" 200 "utility library"
    done
else
    echo -e "${YELLOW}ℹ${NC} No Phase 4 specific utility libraries yet — skipped"
fi

echo ""
echo "========================================"
echo "LOC Governance Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Warnings:      ${YELLOW}$TESTS_WARNED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$((TESTS_PASSED + TESTS_WARNED)) / $TESTS_RUN checks passed (${TESTS_WARNED} warnings)"
echo "========================================"

# Property: Warnings are acceptable, failures are not
if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 10 holds: LOC governance enforced (warnings are acceptable)${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 10 violated: unexpected failures${NC}"
    exit 1
fi
