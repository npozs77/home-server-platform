#!/usr/bin/env bash
# Test Suite: Utility Libraries
# Purpose: Validate utility library structure and functions
# Requirements: 12.5, 12.6, 12.7
# Usage: ./test_utility_libraries.sh

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

# Test all utility libraries exist
test_utility_libraries_exist() {
    run_test "All utility libraries exist"
    
    local utilities=(
        "output-utils.sh"
        "env-utils.sh"
        "password-utils.sh"
        "service-utils.sh"
        "validation-utils.sh"
    )
    
    local all_exist=true
    
    for util in "${utilities[@]}"; do
        if [[ -f "scripts/operations/utils/$util" ]]; then
            print_pass "$util exists"
        else
            print_fail "$util does not exist"
            all_exist=false
        fi
    done
    
    if [[ "$all_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all utility libraries have valid syntax
test_utility_libraries_syntax() {
    run_test "All utility libraries have valid bash syntax"
    
    local utilities=(
        "output-utils.sh"
        "env-utils.sh"
        "password-utils.sh"
        "service-utils.sh"
        "validation-utils.sh"
    )
    
    local all_valid=true
    
    for util in "${utilities[@]}"; do
        if bash -n "scripts/operations/utils/$util" 2>/dev/null; then
            print_pass "$util syntax is valid"
        else
            print_fail "$util has syntax errors"
            all_valid=false
        fi
    done
    
    if [[ "$all_valid" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all utility libraries are under 200 LOC
test_utility_libraries_size() {
    run_test "All utility libraries are under 200 LOC"
    
    local utilities=(
        "output-utils.sh"
        "env-utils.sh"
        "password-utils.sh"
        "service-utils.sh"
        "validation-utils.sh"
    )
    
    local all_within_limit=true
    
    for util in "${utilities[@]}"; do
        local line_count=$(wc -l < "scripts/operations/utils/$util")
        if [[ $line_count -le 200 ]]; then
            print_pass "$util is $line_count LOC (limit: 200)"
        else
            print_fail "$util is $line_count LOC (exceeds limit: 200)"
            all_within_limit=false
        fi
    done
    
    if [[ "$all_within_limit" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all utility libraries have proper shebang
test_utility_libraries_shebang() {
    run_test "All utility libraries have proper shebang"
    
    local utilities=(
        "output-utils.sh"
        "env-utils.sh"
        "password-utils.sh"
        "service-utils.sh"
        "validation-utils.sh"
    )
    
    local all_have_shebang=true
    
    for util in "${utilities[@]}"; do
        if head -n1 "scripts/operations/utils/$util" | grep -q "#!/usr/bin/env bash\|#!/bin/bash"; then
            print_pass "$util has proper shebang"
        else
            print_fail "$util has incorrect shebang"
            all_have_shebang=false
        fi
    done
    
    if [[ "$all_have_shebang" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test output-utils.sh has required functions
test_output_utils_functions() {
    run_test "output-utils.sh has required functions"
    
    local required_functions=(
        "print_success"
        "print_error"
        "print_info"
        "print_header"
    )
    
    local all_functions_exist=true
    
    for func in "${required_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/operations/utils/output-utils.sh; then
            print_pass "$func() function exists"
        else
            print_fail "$func() function missing"
            all_functions_exist=false
        fi
    done
    
    if [[ "$all_functions_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test env-utils.sh has required functions
test_env_utils_functions() {
    run_test "env-utils.sh has required functions"
    
    local required_functions=(
        "validate_required_vars"
        "validate_ip_address"
        "validate_email"
        "validate_domain"
    )
    
    local all_functions_exist=true
    
    for func in "${required_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/operations/utils/env-utils.sh; then
            print_pass "$func() function exists"
        else
            print_fail "$func() function missing"
            all_functions_exist=false
        fi
    done
    
    if [[ "$all_functions_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test password-utils.sh has required functions
test_password_utils_functions() {
    run_test "password-utils.sh has required functions"
    
    local required_functions=(
        "fetch_secret"
    )
    
    local all_functions_exist=true
    
    for func in "${required_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/operations/utils/password-utils.sh; then
            print_pass "$func() function exists"
        else
            print_fail "$func() function missing"
            all_functions_exist=false
        fi
    done
    
    if [[ "$all_functions_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test service-utils.sh has required functions
test_service_utils_functions() {
    run_test "service-utils.sh has required functions"
    
    local required_functions=(
        "check_docker_container"
        "check_systemd_service"
        "check_port_listening"
    )
    
    local all_functions_exist=true
    
    for func in "${required_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/operations/utils/service-utils.sh; then
            print_pass "$func() function exists"
        else
            print_fail "$func() function missing"
            all_functions_exist=false
        fi
    done
    
    if [[ "$all_functions_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test validation-utils.sh has Phase 1 validation functions
test_validation_utils_phase1_functions() {
    run_test "validation-utils.sh has Phase 1 validation functions"
    
    local required_functions=(
        "validate_ssh_hardening"
        "validate_ufw_firewall"
        "validate_fail2ban"
        "validate_docker"
        "validate_git_repository"
        "validate_unattended_upgrades"
        "validate_luks_encryption"
    )
    
    local all_functions_exist=true
    
    for func in "${required_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/operations/utils/validation-utils.sh; then
            print_pass "$func() function exists"
        else
            print_fail "$func() function missing"
            all_functions_exist=false
        fi
    done
    
    if [[ "$all_functions_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test validation-utils.sh has Phase 2 validation functions
test_validation_utils_phase2_functions() {
    run_test "validation-utils.sh has Phase 2 validation functions"
    
    # Phase 2 validation functions (examples - adjust based on actual functions)
    local required_functions=(
        "validate_data_directories"
        "validate_caddy"
        "validate_pihole"
        "validate_dns"
        "validate_msmtp"
        "validate_netdata"
    )
    
    local all_functions_exist=true
    
    for func in "${required_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/operations/utils/validation-utils.sh; then
            print_pass "$func() function exists"
        else
            print_fail "$func() function missing"
            all_functions_exist=false
        fi
    done
    
    if [[ "$all_functions_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test utility libraries can be sourced
test_utility_libraries_sourceable() {
    run_test "All utility libraries can be sourced without errors"
    
    local utilities=(
        "output-utils.sh"
        "env-utils.sh"
        "password-utils.sh"
        "service-utils.sh"
        "validation-utils.sh"
    )
    
    local all_sourceable=true
    
    for util in "${utilities[@]}"; do
        # Try to source in a subshell to avoid polluting current environment
        if (source "scripts/operations/utils/$util" 2>/dev/null); then
            print_pass "$util can be sourced"
        else
            print_fail "$util cannot be sourced (has errors)"
            all_sourceable=false
        fi
    done
    
    if [[ "$all_sourceable" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test utility libraries have safety flags
test_utility_libraries_safety() {
    run_test "All utility libraries have safety flags"
    
    local utilities=(
        "output-utils.sh"
        "env-utils.sh"
        "password-utils.sh"
        "service-utils.sh"
        "validation-utils.sh"
    )
    
    local all_have_safety=true
    
    for util in "${utilities[@]}"; do
        if grep -q "set -euo pipefail" "scripts/operations/utils/$util"; then
            print_pass "$util has safety flags"
        else
            print_fail "$util missing safety flags"
            all_have_safety=false
        fi
    done
    
    if [[ "$all_have_safety" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test README exists
test_utils_readme_exists() {
    run_test "Utility libraries README exists"
    
    if [[ -f "scripts/operations/utils/README.md" ]]; then
        print_pass "README.md exists"
        return 0
    else
        print_fail "README.md does not exist"
        return 1
    fi
}

# Run all tests
main() {
    echo "========================================"
    echo "Utility Libraries Test Suite"
    echo "========================================"
    
    # Structure tests
    test_utility_libraries_exist || true
    test_utility_libraries_syntax || true
    test_utility_libraries_size || true
    test_utility_libraries_shebang || true
    test_utility_libraries_safety || true
    test_utility_libraries_sourceable || true
    
    # Function tests
    test_output_utils_functions || true
    test_env_utils_functions || true
    test_password_utils_functions || true
    test_service_utils_functions || true
    test_validation_utils_phase1_functions || true
    test_validation_utils_phase2_functions || true
    
    # Documentation tests
    test_utils_readme_exists || true
    
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
