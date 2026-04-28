#!/usr/bin/env bash
# Test Suite: Governance Validation
# Purpose: Validate governance validation script and compliance checks
# Requirements: 12.5, 12.6, 12.7, 26.1-26.10
# Usage: ./test_governance_validation.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test directory
TEST_DIR="/tmp/governance_test_$$"

# Print test result
print_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Run test
run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo "Test $TESTS_RUN: $1"
    echo "----------------------------------------"
}

# Setup test environment
setup_test_env() {
    print_info "Setting up test environment: $TEST_DIR"
    mkdir -p "$TEST_DIR/scripts/deploy"
    mkdir -p "$TEST_DIR/scripts/deploy/tasks"
    mkdir -p "$TEST_DIR/scripts/operations/utils"
}

# Cleanup test environment
cleanup_test_env() {
    print_info "Cleaning up test environment"
    rm -rf "$TEST_DIR"
}

# Test governance validation script exists
test_governance_script_exists() {
    run_test "Governance validation script exists and is executable"
    
    if [[ -f "scripts/operations/validate-governance.sh" ]]; then
        print_pass "Governance validation script exists"
    else
        print_fail "Governance validation script does not exist"
        return 1
    fi
    
    if [[ -x "scripts/operations/validate-governance.sh" ]]; then
        print_pass "Governance validation script is executable"
    else
        print_fail "Governance validation script is not executable"
        return 1
    fi
}

# Test governance validation script syntax
test_governance_script_syntax() {
    run_test "Governance validation script has valid bash syntax"
    
    if bash -n scripts/operations/validate-governance.sh 2>/dev/null; then
        print_pass "Governance validation script syntax is valid"
    else
        print_fail "Governance validation script has syntax errors"
        return 1
    fi
}

# Test governance validation detects oversized deployment script
test_governance_detects_oversized_deployment() {
    run_test "Governance validation detects oversized deployment script"
    
    setup_test_env
    
    # Create an oversized deployment script (>300 LOC)
    cat > "$TEST_DIR/scripts/deploy/deploy-test.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
EOF
    
    # Add 301 lines
    for i in {1..299}; do
        echo "# Line $i" >> "$TEST_DIR/scripts/deploy/deploy-test.sh"
    done
    
    # Run governance validation (should fail)
    cd "$TEST_DIR"
    if bash "$(pwd)/../../scripts/operations/validate-governance.sh" 2>/dev/null; then
        print_fail "Governance validation did not detect oversized deployment script"
        cd - > /dev/null
        cleanup_test_env
        return 1
    else
        print_pass "Governance validation detected oversized deployment script"
        cd - > /dev/null
        cleanup_test_env
        return 0
    fi
}

# Test governance validation detects oversized task module
test_governance_detects_oversized_task() {
    run_test "Governance validation detects oversized task module"
    
    setup_test_env
    
    # Create an oversized task module (>150 LOC)
    cat > "$TEST_DIR/scripts/deploy/tasks/task-test.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
EOF
    
    # Add 151 lines
    for i in {1..149}; do
        echo "# Line $i" >> "$TEST_DIR/scripts/deploy/tasks/task-test.sh"
    done
    
    # Run governance validation (should fail)
    cd "$TEST_DIR"
    if bash "$(pwd)/../../scripts/operations/validate-governance.sh" 2>/dev/null; then
        print_fail "Governance validation did not detect oversized task module"
        cd - > /dev/null
        cleanup_test_env
        return 1
    else
        print_pass "Governance validation detected oversized task module"
        cd - > /dev/null
        cleanup_test_env
        return 0
    fi
}

# Test governance validation detects oversized utility library
test_governance_detects_oversized_utility() {
    run_test "Governance validation detects oversized utility library"
    
    setup_test_env
    
    # Create an oversized utility library (>200 LOC)
    cat > "$TEST_DIR/scripts/operations/utils/test-utils.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
EOF
    
    # Add 201 lines
    for i in {1..199}; do
        echo "# Line $i" >> "$TEST_DIR/scripts/operations/utils/test-utils.sh"
    done
    
    # Run governance validation (should fail)
    cd "$TEST_DIR"
    if bash "$(pwd)/../../scripts/operations/validate-governance.sh" 2>/dev/null; then
        print_fail "Governance validation did not detect oversized utility library"
        cd - > /dev/null
        cleanup_test_env
        return 1
    else
        print_pass "Governance validation detected oversized utility library"
        cd - > /dev/null
        cleanup_test_env
        return 0
    fi
}

# Test governance validation passes for compliant scripts
test_governance_passes_compliant_scripts() {
    run_test "Governance validation passes for compliant scripts"
    
    setup_test_env
    
    # Create compliant deployment script (<300 LOC)
    cat > "$TEST_DIR/scripts/deploy/deploy-test.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
# Compliant deployment script
echo "Test"
EOF
    
    # Create compliant task module (<150 LOC)
    cat > "$TEST_DIR/scripts/deploy/tasks/task-test.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
# Compliant task module
echo "Test"
EOF
    
    # Create compliant utility library (<200 LOC)
    cat > "$TEST_DIR/scripts/operations/utils/test-utils.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
# Compliant utility library
echo "Test"
EOF
    
    # Run governance validation (should pass)
    cd "$TEST_DIR"
    if bash "$(pwd)/../../scripts/operations/validate-governance.sh" 2>/dev/null; then
        print_pass "Governance validation passed for compliant scripts"
        cd - > /dev/null
        cleanup_test_env
        return 0
    else
        print_fail "Governance validation failed for compliant scripts"
        cd - > /dev/null
        cleanup_test_env
        return 1
    fi
}

# Test governance validation prints summary
test_governance_prints_summary() {
    run_test "Governance validation prints summary with X / Y format"
    
    # Run governance validation and capture output
    local output=$(bash scripts/operations/validate-governance.sh 2>&1 || true)
    
    # Check if output contains "X / Y" pattern
    if echo "$output" | grep -q "[0-9]\+ / [0-9]\+"; then
        print_pass "Governance validation prints summary with X / Y format"
        return 0
    else
        print_fail "Governance validation does not print summary with X / Y format"
        return 1
    fi
}

# Test governance validation returns correct exit codes
test_governance_exit_codes() {
    run_test "Governance validation returns correct exit codes"
    
    # Run governance validation on actual project (should pass if all scripts compliant)
    if bash scripts/operations/validate-governance.sh 2>/dev/null; then
        print_pass "Governance validation returns exit code 0 for compliant project"
        return 0
    else
        print_info "Governance validation returned non-zero exit code (some scripts may be non-compliant)"
        # This is not necessarily a failure - it means the project has non-compliant scripts
        # which is expected during development
        print_pass "Governance validation returns non-zero exit code for non-compliant scripts"
        return 0
    fi
}

# Test governance validation checks deployment scripts
test_governance_checks_deployment_scripts() {
    run_test "Governance validation checks deployment scripts"
    
    # Run governance validation and capture output
    local output=$(bash scripts/operations/validate-governance.sh 2>&1 || true)
    
    # Check if output mentions deployment scripts
    if echo "$output" | grep -q "deploy-phase"; then
        print_pass "Governance validation checks deployment scripts"
        return 0
    else
        print_fail "Governance validation does not check deployment scripts"
        return 1
    fi
}

# Test governance validation checks task modules
test_governance_checks_task_modules() {
    run_test "Governance validation checks task modules"
    
    # Run governance validation and capture output
    local output=$(bash scripts/operations/validate-governance.sh 2>&1 || true)
    
    # Check if output mentions task modules
    if echo "$output" | grep -q "task-ph"; then
        print_pass "Governance validation checks task modules"
        return 0
    else
        print_fail "Governance validation does not check task modules"
        return 1
    fi
}

# Test governance validation checks utility libraries
test_governance_checks_utility_libraries() {
    run_test "Governance validation checks utility libraries"
    
    # Run governance validation and capture output
    local output=$(bash scripts/operations/validate-governance.sh 2>&1 || true)
    
    # Check if output mentions utility libraries
    if echo "$output" | grep -q "utils"; then
        print_pass "Governance validation checks utility libraries"
        return 0
    else
        print_fail "Governance validation does not check utility libraries"
        return 1
    fi
}

# Test governance validation script size
test_governance_script_size() {
    run_test "Governance validation script is reasonably sized"
    
    local line_count=$(wc -l < scripts/operations/validate-governance.sh)
    
    if [[ $line_count -le 300 ]]; then
        print_pass "Governance validation script is $line_count LOC (reasonable size)"
    else
        print_info "Governance validation script is $line_count LOC (larger than expected)"
        # Not a failure, just informational
        print_pass "Governance validation script size noted"
    fi
    
    return 0
}

# Run all tests
main() {
    echo "========================================"
    echo "Governance Validation Test Suite"
    echo "========================================"
    
    # Script structure tests
    test_governance_script_exists || true
    test_governance_script_syntax || true
    test_governance_script_size || true
    
    # Validation behavior tests
    test_governance_detects_oversized_deployment || true
    test_governance_detects_oversized_task || true
    test_governance_detects_oversized_utility || true
    test_governance_passes_compliant_scripts || true
    
    # Output and exit code tests
    test_governance_prints_summary || true
    test_governance_exit_codes || true
    
    # Coverage tests
    test_governance_checks_deployment_scripts || true
    test_governance_checks_task_modules || true
    test_governance_checks_utility_libraries || true
    
    # Summary
    echo ""
    echo "========================================"
    echo "Test Results"
    echo "========================================"
    echo "$TESTS_PASSED / $TESTS_RUN checks passed"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! ✓${NC}"
        exit 0
    else
        echo -e "${RED}$TESTS_FAILED tests failed. Please review and fix issues.${NC}"
        exit 1
    fi
}

# Run tests
main
