#!/bin/bash
# Unit Tests: Phase 3 Data Storage Tasks
# Tests task modules for media and Jellyfin directory creation

set -euo pipefail

# Test configuration
TASK_MODULES=(
    "scripts/deploy/tasks/task-ph3-01-create-media-dirs.sh"
    "scripts/deploy/tasks/task-ph3-02-create-jellyfin-dirs.sh"
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
print_section "Phase 3 Storage Tasks - Unit Tests"

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

# Test 5: Directory creation logic
echo ""
echo "Test 5: Directory creation logic..."
if grep -q 'mkdir -p' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-01 creates media directories"
else
    print_fail "task-ph3-01 missing directory creation"
fi

if grep -q 'mkdir -p' "${TASK_MODULES[1]}"; then
    print_pass "task-ph3-02 creates Jellyfin directories"
else
    print_fail "task-ph3-02 missing directory creation"
fi

# Test 6: Permission setting logic
echo ""
echo "Test 6: Permission setting logic..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q 'chmod' "$module"; then
        print_pass "$(basename "$module") sets permissions"
    else
        print_fail "$(basename "$module") doesn't set permissions"
    fi
done

# Test 7: Ownership setting logic
echo ""
echo "Test 7: Ownership setting logic..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q 'chown' "$module"; then
        print_pass "$(basename "$module") sets ownership"
    else
        print_fail "$(basename "$module") doesn't set ownership"
    fi
done

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
