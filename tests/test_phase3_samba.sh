#!/bin/bash
# Unit Tests: Phase 3 Samba Tasks
# Tests task modules for Samba configuration, deployment, and verification

set -euo pipefail

# Test configuration
TASK_MODULES=(
    "scripts/deploy/tasks/task-ph3-03-create-samba-config.sh"
    "scripts/deploy/tasks/task-ph3-04-deploy-samba.sh"
    "scripts/deploy/tasks/task-ph3-05-verify-samba.sh"
)
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Functions
function print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

function print_fail() {
    echo -e "${RED}✗${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

function print_section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

# Test Suite
print_section "Phase 3 Samba Tasks - Unit Tests"

# Test 1: Task modules exist
echo "Test 1: Task modules exist..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        print_pass "$(basename "$module") exists"
    else
        print_fail "$(basename "$module") not found"
    fi
done

# Test 2: Proper shebang
echo ""
echo "Test 2: Proper shebang..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && head -1 "$module" | grep -q '^#!/bin/bash'; then
        print_pass "$(basename "$module") has proper shebang"
    else
        print_fail "$(basename "$module") missing proper shebang"
    fi
done

# Test 3: Safety flags
echo ""
echo "Test 3: Safety flags (set -euo pipefail)..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q '^set -euo pipefail' "$module"; then
        print_pass "$(basename "$module") has safety flags"
    else
        print_fail "$(basename "$module") missing safety flags"
    fi
done

# Test 4: Valid syntax
echo ""
echo "Test 4: Valid bash syntax..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && bash -n "$module" 2>/dev/null; then
        print_pass "$(basename "$module") syntax valid"
    else
        print_fail "$(basename "$module") has syntax errors"
    fi
done

# Test 5: Samba config generation
echo ""
echo "Test 5: Samba configuration generation..."
if grep -q 'smb.conf' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-03 generates smb.conf"
else
    print_fail "task-ph3-03 doesn't generate smb.conf"
fi

if grep -q 'Family\|Media' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-03 defines shares"
else
    print_fail "task-ph3-03 missing share definitions"
fi

# Test 6: Docker compose creation
echo ""
echo "Test 6: Docker compose creation..."
if grep -q 'docker-compose\|docker compose' "${TASK_MODULES[1]}"; then
    print_pass "task-ph3-04 uses docker compose"
else
    print_fail "task-ph3-04 missing docker compose"
fi

if grep -q 'samba' "${TASK_MODULES[1]}"; then
    print_pass "task-ph3-04 references Samba"
else
    print_fail "task-ph3-04 doesn't reference Samba"
fi

# Test 7: Share verification
echo ""
echo "Test 7: Share verification logic..."
if grep -q 'smbclient' "${TASK_MODULES[2]}"; then
    print_pass "task-ph3-05 uses smbclient"
else
    print_fail "task-ph3-05 doesn't use smbclient"
fi

if grep -q 'Family\|Media' "${TASK_MODULES[2]}"; then
    print_pass "task-ph3-05 verifies shares"
else
    print_fail "task-ph3-05 doesn't verify shares"
fi

# Test 8: Dry-run support
echo ""
echo "Test 8: Dry-run support..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q 'DRY_RUN' "$module"; then
        print_pass "$(basename "$module") supports dry-run"
    else
        print_fail "$(basename "$module") missing dry-run support"
    fi
done

# Test 9: Root check
echo ""
echo "Test 9: Root privilege check..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q 'EUID.*-ne.*0' "$module"; then
        print_pass "$(basename "$module") checks for root"
    else
        print_fail "$(basename "$module") missing root check"
    fi
done

# Test 10: Environment variables
echo ""
echo "Test 10: Environment variable usage..."
if grep -q 'SAMBA_WORKGROUP\|SAMBA_SERVER_STRING' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-03 uses Samba variables"
else
    print_fail "task-ph3-03 missing Samba variables"
fi

if grep -q 'TIMEZONE' "${TASK_MODULES[1]}"; then
    print_pass "task-ph3-04 uses TIMEZONE variable"
else
    print_fail "task-ph3-04 missing TIMEZONE variable"
fi

# Summary
print_section "Test Summary"
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
echo "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
