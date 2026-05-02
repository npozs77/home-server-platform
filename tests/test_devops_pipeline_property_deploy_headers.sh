#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Deploy Scripts Include Non-Blocking Drift Check Header (Property 7)
# Feature: devops-cicd-pipeline, Property 7
# Purpose: For each deploy-phase*.sh: verify drift check with -x guard, --warn-only, || true
# Validates: Requirements 14.1, 14.2, 14.3
# Usage: bash tests/test_devops_pipeline_property_deploy_headers.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "========================================"
echo "Property 7: Deploy Scripts Drift Check Header"
echo "========================================"
echo ""

for script in "${REPO_ROOT}"/scripts/deploy/deploy-phase*.sh; do
    name=$(basename "$script")
    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ ! -f "$script" ]]; then
        print_fail "$name not found"
        continue
    fi

    # Check 1: -x guard (skip if script not found)
    if grep -q '\[\[ -x' "$script"; then
        print_pass "$name has -x guard for drift check"
    else
        print_fail "$name missing -x guard for drift check"
    fi

    # Check 2: --warn-only flag
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q '\-\-warn-only' "$script"; then
        print_pass "$name uses --warn-only flag"
    else
        print_fail "$name missing --warn-only flag"
    fi

    # Check 3: || true (non-blocking)
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q '|| true' "$script"; then
        print_pass "$name uses || true (non-blocking)"
    else
        print_fail "$name missing || true (would block on drift)"
    fi
done

echo ""
echo "========================================"
echo "Property 7 Summary"
echo "========================================"
echo "Checks run:  $TESTS_RUN"
echo -e "Passed:      ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 7 holds: all deploy scripts have non-blocking drift check${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 7 violated: ${TESTS_FAILED} check(s) failed${NC}"
    exit 1
fi
