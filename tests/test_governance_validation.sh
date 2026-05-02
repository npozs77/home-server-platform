#!/usr/bin/env bash
# CI_SAFE=true
# Test Suite: Governance Validation
# Purpose: Validate governance validation script and compliance checks
# Requirements: 12.5, 12.6, 12.7, 26.1-26.10

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/operations/validate-governance.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}✗ FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

echo "========================================"
echo "Governance Validation Test Suite"
echo "========================================"

# Script exists and has valid syntax
[[ -f "$SCRIPT" ]] && pass "Script exists" || fail "Script exists"
bash -n "$SCRIPT" 2>/dev/null && pass "Valid syntax" || fail "Valid syntax"
[[ $(wc -l < "$SCRIPT") -le 300 ]] && pass "≤300 LOC" || fail "≤300 LOC"

# Runs and produces expected output
OUTPUT=$(bash "$SCRIPT" 2>&1 || true)
CLEAN=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')

echo "$CLEAN" | grep -q "Governance Validation Summary" && pass "Produces summary header" || fail "Produces summary header"
echo "$CLEAN" | grep -q "[0-9]* / [0-9]*" && pass "Reports X / Y format" || fail "Reports X / Y format"
echo "$CLEAN" | grep -q "deploy-phase" && pass "Checks deployment scripts" || fail "Checks deployment scripts"
echo "$CLEAN" | grep -q "task-ph" && pass "Checks task modules" || fail "Checks task modules"
echo "$CLEAN" | grep -q "utils" && pass "Checks utility libraries" || fail "Checks utility libraries"
bash "$SCRIPT" >/dev/null 2>&1 && pass "Exit code 0" || fail "Exit code 0"

TOTAL=$((PASSED + FAILED))
echo ""
echo "========================================"
echo "${PASSED} / ${TOTAL} checks passed"
echo "========================================"

[[ $FAILED -eq 0 ]] && exit 0 || exit 1
