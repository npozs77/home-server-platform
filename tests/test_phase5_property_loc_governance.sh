#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Script LOC Governance (Property 15)
# Purpose: For each Phase 5 script, count LOC and verify Warning (not failure)
#          when exceeding indicative limit (300/150/200)
# Validates: Requirements 18.2
# Usage: bash tests/test_phase5_property_loc_governance.sh

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

# Property 15: Script LOC Governance
# For any Phase 5 script, LOC exceeding the indicative limit raises Warning, not failure.
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
        # Exceeding is a WARNING, not a failure (per requirement 18.2)
        print_warn "$(basename "$script_path"): $loc LOC exceeds indicative limit $limit ($category)"
    fi
}

echo "========================================"
echo "Property 15: Script LOC Governance"
echo "========================================"
echo ""
echo "Indicative limits (Warning on exceed, not failure):"
echo "  Orchestration scripts: 300 LOC"
echo "  Task modules:          150 LOC"
echo "  Utility libraries:     200 LOC"
echo ""

# Orchestration script (limit: 300)
echo "--- Orchestration Layer ---"
check_loc "scripts/deploy/deploy-phase5-wiki-llm.sh" 300 "orchestration"
echo ""

# Task modules (limit: 150 each)
echo "--- Task Module Layer ---"
TASK_MODULES=(
    "01:create-wiki-directories"
    "02:deploy-wiki-stack"
    "03:configure-wiki-caddy"
    "04:configure-wiki-dns"
    "05:provision-wiki-users"
    "06:create-ollama-directories"
    "07:deploy-llm-stack"
    "08:pull-default-model"
    "09:configure-chat-caddy"
    "10:configure-chat-dns"
    "11:provision-openwebui-users"
    "12:deploy-backup-script"
    "13:create-documentation"
    "14:deploy-wiki-rag-sync"
)
for entry in "${TASK_MODULES[@]}"; do
    num="${entry%%:*}"
    name="${entry#*:}"
    check_loc "scripts/deploy/tasks/task-ph5-${num}-${name}.sh" 150 "task module"
done
echo ""

# Utility libraries (limit: 200 each)
echo "--- Utility Library Layer ---"
check_loc "scripts/operations/utils/validation-wiki-llm-utils.sh" 200 "utility library"
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
    echo -e "${GREEN}✓ Property 15 holds: LOC governance enforced (warnings are acceptable)${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 15 violated: unexpected failures${NC}"
    exit 1
fi
