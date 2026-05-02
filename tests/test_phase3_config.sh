#!/bin/bash
# Unit Tests: Phase 3 Configuration Initialization
# Tests deployment script configuration management

set -euo pipefail

# Test configuration
DEPLOYMENT_SCRIPT="scripts/deploy/deploy-phase3-core-services.sh"
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
print_section "Phase 3 Configuration - Unit Tests"

# Test 1: Deployment script exists
echo "Test 1: Deployment script exists..."
if [[ -f "$DEPLOYMENT_SCRIPT" ]]; then
    print_pass "deploy-phase3-core-services.sh exists"
else
    print_fail "deploy-phase3-core-services.sh not found"
fi

# Test 2: Config management functions exist
echo ""
echo "Test 2: Config management functions..."
if grep -q 'function init_config\|^init_config()' "$DEPLOYMENT_SCRIPT"; then
    print_pass "init_config() function exists"
else
    print_fail "init_config() function missing"
fi

if grep -q 'function load_config\|^load_config()' "$DEPLOYMENT_SCRIPT"; then
    print_pass "load_config() function exists"
else
    print_fail "load_config() function missing"
fi

if grep -q 'function save_config\|^save_config()' "$DEPLOYMENT_SCRIPT"; then
    print_pass "save_config() function exists"
else
    print_fail "save_config() function missing"
fi

if grep -q 'function validate_config\|^validate_config()' "$DEPLOYMENT_SCRIPT"; then
    print_pass "validate_config() function exists"
else
    print_fail "validate_config() function missing"
fi

# Test 3: Phase 3 variables defined
echo ""
echo "Test 3: Phase 3 configuration variables..."
for var in "POWER_USER" "STANDARD_USER" "SAMBA_WORKGROUP" "SAMBA_SERVER_STRING" "JELLYFIN_SERVER_NAME"; do
    if grep -q "$var" "$DEPLOYMENT_SCRIPT"; then
        print_pass "$var referenced in script"
    else
        print_fail "$var not found in script"
    fi
done

# Test 4: Config file paths defined
echo ""
echo "Test 4: Config file paths..."
if grep -q 'foundation.env' "$DEPLOYMENT_SCRIPT"; then
    print_pass "foundation.env referenced"
else
    print_fail "foundation.env not referenced"
fi

if grep -q 'services.env' "$DEPLOYMENT_SCRIPT"; then
    print_pass "services.env referenced"
else
    print_fail "services.env not referenced"
fi

# Test 5: Config persistence
echo ""
echo "Test 5: Config persistence logic..."
if grep -q 'save_config' "$DEPLOYMENT_SCRIPT"; then
    print_pass "Config save logic present"
else
    print_fail "Config save logic missing"
fi

# Test 6: Config validation
echo ""
echo "Test 6: Config validation logic..."
if grep -q 'validate_config' "$DEPLOYMENT_SCRIPT"; then
    print_pass "Config validation logic present"
else
    print_fail "Config validation logic missing"
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
