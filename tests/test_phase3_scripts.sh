#!/usr/bin/env bash
# CI_SAFE=true
# Test Suite: Phase 3 Core Services Scripts
# Purpose: Validate Phase 3 deployment script and task modules
# Requirements: 28.1, 28.2, 28.3, 28.4, 28.5, 28.6
# Usage: ./test_phase3_scripts.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_WARNED=0
TESTS_FAILED=0
FAILED_MESSAGES=()

# Print test result
print_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    TESTS_WARNED=$((TESTS_WARNED + 1))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_MESSAGES+=("$1")
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

# Test deployment script structure
test_deployment_script_exists() {
    run_test "Deployment script exists"
    
    if [[ -f "scripts/deploy/deploy-phase3-core-services.sh" ]]; then
        print_pass "Deployment script exists"
    else
        print_fail "Deployment script does not exist"
        return 1
    fi
}

# Test deployment script has proper shebang
test_deployment_script_shebang() {
    run_test "Deployment script has proper shebang"
    
    local first_line=$(head -n 1 scripts/deploy/deploy-phase3-core-services.sh)
    
    if [[ "$first_line" == "#!/bin/bash" ]]; then
        print_pass "Shebang is correct (#!/bin/bash)"
    else
        print_fail "Shebang is incorrect: $first_line"
        return 1
    fi
}

# Test deployment script has safety flags
test_deployment_script_safety_flags() {
    run_test "Deployment script has safety flags (set -euo pipefail)"
    
    if grep -q "^set -euo pipefail" scripts/deploy/deploy-phase3-core-services.sh; then
        print_pass "Safety flags present"
    else
        print_fail "Safety flags missing"
        return 1
    fi
}

# Test deployment script size (warning on exceed, not failure)
test_deployment_script_size() {
    run_test "Deployment script LOC governance (indicative limit: 300)"
    
    local line_count=$(wc -l < scripts/deploy/deploy-phase3-core-services.sh)
    
    if [[ $line_count -le 300 ]]; then
        print_pass "Deployment script is $line_count LOC (limit: 300)"
    else
        print_warn "Deployment script is $line_count LOC (exceeds indicative limit: 300)"
    fi
}

# Test deployment script syntax
test_deployment_script_syntax() {
    run_test "Deployment script has valid bash syntax"
    
    if bash -n scripts/deploy/deploy-phase3-core-services.sh 2>/dev/null; then
        print_pass "Deployment script syntax is valid"
    else
        print_fail "Deployment script has syntax errors"
        bash -n scripts/deploy/deploy-phase3-core-services.sh
        return 1
    fi
}

# Test deployment script has required config management functions
test_config_management_functions() {
    run_test "Deployment script has config management functions"
    
    local required_functions=(
        "init_config"
        "load_config"
        "save_config"
        "validate_config"
    )
    
    local all_functions_exist=true
    
    for func in "${required_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/deploy/deploy-phase3-core-services.sh; then
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

# Test deployment script has required task execution functions
test_task_execution_functions() {
    run_test "Deployment script has task execution functions"
    
    local required_functions=(
        "execute_task_2_1"
        "execute_task_2_2"
        "execute_task_3_1"
        "execute_task_3_2"
        "execute_task_3_3"
        "execute_task_4_1"
        "execute_task_5_1"
        "execute_task_5_2"
        "execute_task_5_3"
        "execute_task_6_1"
        "execute_task_6_2"
        "execute_task_6_3"
        "execute_task_6_4"
    )
    
    local all_functions_exist=true
    
    for func in "${required_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/deploy/deploy-phase3-core-services.sh; then
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

# Test deployment script has validation function
test_validation_function() {
    run_test "Deployment script has validation function"
    
    if grep -q "^[[:space:]]*function[[:space:]]\+validate_all\|^[[:space:]]*validate_all()" scripts/deploy/deploy-phase3-core-services.sh; then
        print_pass "validate_all() function exists"
    else
        print_fail "validate_all() function missing"
        return 1
    fi
}

# Test deployment script has interactive menu
test_interactive_menu() {
    run_test "Deployment script has interactive menu"
    
    if grep -q "^[[:space:]]*function[[:space:]]\+main_menu\|^[[:space:]]*main_menu()" scripts/deploy/deploy-phase3-core-services.sh; then
        print_pass "main_menu() function exists"
    else
        print_fail "main_menu() function missing"
        return 1
    fi
}

# Test deployment script sources utility libraries
test_utility_library_sourcing() {
    run_test "Deployment script sources utility libraries"
    
    local required_sources=(
        "output-utils.sh"
        "env-utils.sh"
        "validation-core-services-utils.sh"
    )
    
    local all_sources_exist=true
    
    for source_file in "${required_sources[@]}"; do
        if grep -q "source.*$source_file" scripts/deploy/deploy-phase3-core-services.sh; then
            print_pass "Sources $source_file"
        else
            print_fail "Does not source $source_file"
            all_sources_exist=false
        fi
    done
    
    if [[ "$all_sources_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test deployment script has dry-run support
test_dry_run_support() {
    run_test "Deployment script has dry-run support"
    
    if grep -q "DRY_RUN" scripts/deploy/deploy-phase3-core-services.sh; then
        print_pass "Dry-run mode variable exists"
    else
        print_fail "Dry-run mode variable missing"
        return 1
    fi
    
    if grep -q 'DRY_RUN_ARG\|--dry-run' scripts/deploy/deploy-phase3-core-services.sh; then
        print_pass "Dry-run mode checks exist"
    else
        print_fail "Dry-run mode checks missing"
        return 1
    fi
}

# Test deployment script has error handling
test_error_handling() {
    run_test "Deployment script has error handling"
    
    if grep -q "print_error" scripts/deploy/deploy-phase3-core-services.sh; then
        print_pass "Error handling implemented"
    else
        print_fail "Error handling missing"
        return 1
    fi
}

# Test deployment script checks for root
test_root_check() {
    run_test "Deployment script checks for root privileges"
    
    if grep -q "EUID.*-ne.*0" scripts/deploy/deploy-phase3-core-services.sh; then
        print_pass "Root check implemented"
    else
        print_fail "Root check missing"
        return 1
    fi
}

# Test deployment manual exists
test_deployment_manual_exists() {
    run_test "Deployment manual exists"
    
    if [[ -f "docs/deployment_manuals/phase3-core-services.md" ]]; then
        print_pass "Deployment manual exists"
    else
        print_fail "Deployment manual does not exist"
        return 1
    fi
}

# Test deployment manual has required sections
test_deployment_manual_sections() {
    run_test "Deployment manual has required sections"
    
    local required_sections=(
        "Overview"
        "Prerequisites"
        "Quick Start"
        "Pre-Deployment Checklist"
        "Troubleshooting"
    )
    
    local all_sections_exist=true
    
    for section in "${required_sections[@]}"; do
        if grep -q "## $section" docs/deployment_manuals/phase3-core-services.md; then
            print_pass "Section '$section' exists"
        else
            print_fail "Section '$section' missing"
            all_sections_exist=false
        fi
    done
    
    if [[ "$all_sections_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test Phase 3 specific configuration variables
test_phase3_config_variables() {
    run_test "Deployment script has Phase 3 specific config variables"
    
    local required_vars=(
        "ADMIN_USER"
        "POWER_USER"
        "STANDARD_USER"
        "SAMBA_WORKGROUP"
        "SAMBA_SERVER_STRING"
        "JELLYFIN_SERVER_NAME"
    )
    
    local all_vars_exist=true
    
    for var in "${required_vars[@]}"; do
        if grep -q "$var" scripts/deploy/deploy-phase3-core-services.sh; then
            print_pass "Variable $var referenced"
        else
            print_fail "Variable $var missing"
            all_vars_exist=false
        fi
    done
    
    if [[ "$all_vars_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test validation checks are defined
test_validation_checks() {
    run_test "Deployment script defines validation checks"
    
    local required_checks=(
        "Samba Container"
        "Personal Folders"
        "Family Folders"
        "Media Folders"
        "Jellyfin Container"
    )
    
    # Checks now defined in validation-core-services-utils.sh (single source of truth)
    local check_source="scripts/operations/utils/validation-core-services-utils.sh"
    local all_checks_exist=true
    
    for check in "${required_checks[@]}"; do
        if grep -q "$check" "$check_source"; then
            print_pass "Validation check '$check' defined"
        else
            print_fail "Validation check '$check' missing"
            all_checks_exist=false
        fi
    done
    
    if [[ "$all_checks_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test configuration persistence
test_configuration_persistence() {
    run_test "Deployment script saves configuration to services.env"
    
    if grep -q "services.env" scripts/deploy/deploy-phase3-core-services.sh; then
        print_pass "Configuration persistence implemented"
    else
        print_fail "Configuration persistence missing"
        return 1
    fi
}

# Test idempotency checks
test_idempotency() {
    run_test "Deployment script has idempotency checks"
    
    if grep -q "if.*grep.*Phase 3 Configuration" scripts/deploy/deploy-phase3-core-services.sh; then
        print_pass "Idempotency checks implemented"
    else
        print_fail "Idempotency checks missing"
        return 1
    fi
}

# Test task modules exist
test_task_modules_exist() {
    run_test "All task module files exist"
    
    local task_modules=(
        "scripts/deploy/tasks/task-ph3-01-create-media-dirs.sh"
        "scripts/deploy/tasks/task-ph3-02-create-jellyfin-dirs.sh"
        "scripts/deploy/tasks/task-ph3-03-create-samba-config.sh"
        "scripts/deploy/tasks/task-ph3-04-deploy-samba.sh"
        "scripts/deploy/tasks/task-ph3-05-verify-samba.sh"
        "scripts/deploy/tasks/task-ph3-06-create-user-scripts.sh"
        "scripts/deploy/tasks/task-ph3-07-provision-admin.sh"
        "scripts/deploy/tasks/task-ph3-08-provision-power.sh"
        "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"
        "scripts/deploy/tasks/task-ph3-10-create-jellyfin-compose.sh"
        "scripts/deploy/tasks/task-ph3-11-deploy-jellyfin.sh"
        "scripts/deploy/tasks/task-ph3-12-configure-caddy-jellyfin.sh"
        "scripts/deploy/tasks/task-ph3-13-configure-dns-jellyfin.sh"
    )
    
    local all_modules_exist=true
    
    for module in "${task_modules[@]}"; do
        if [[ -f "$module" ]]; then
            print_pass "$(basename $module) exists"
        else
            print_fail "$(basename $module) missing"
            all_modules_exist=false
        fi
    done
    
    if [[ "$all_modules_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test task modules have proper shebang
test_task_modules_shebang() {
    run_test "Task modules have proper shebang"
    
    local task_modules=(
        "scripts/deploy/tasks/task-ph3-01-create-media-dirs.sh"
        "scripts/deploy/tasks/task-ph3-02-create-jellyfin-dirs.sh"
        "scripts/deploy/tasks/task-ph3-03-create-samba-config.sh"
        "scripts/deploy/tasks/task-ph3-04-deploy-samba.sh"
        "scripts/deploy/tasks/task-ph3-05-verify-samba.sh"
        "scripts/deploy/tasks/task-ph3-06-create-user-scripts.sh"
        "scripts/deploy/tasks/task-ph3-07-provision-admin.sh"
        "scripts/deploy/tasks/task-ph3-08-provision-power.sh"
        "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"
        "scripts/deploy/tasks/task-ph3-10-create-jellyfin-compose.sh"
        "scripts/deploy/tasks/task-ph3-11-deploy-jellyfin.sh"
        "scripts/deploy/tasks/task-ph3-12-configure-caddy-jellyfin.sh"
        "scripts/deploy/tasks/task-ph3-13-configure-dns-jellyfin.sh"
    )
    
    local all_shebangs_correct=true
    
    for module in "${task_modules[@]}"; do
        if [[ -f "$module" ]]; then
            local first_line=$(head -n 1 "$module")
            if [[ "$first_line" == "#!/bin/bash" ]]; then
                print_pass "$(basename $module) has correct shebang"
            else
                print_fail "$(basename $module) has incorrect shebang: $first_line"
                all_shebangs_correct=false
            fi
        fi
    done
    
    if [[ "$all_shebangs_correct" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test task modules have safety flags
test_task_modules_safety_flags() {
    run_test "Task modules have safety flags"
    
    local task_modules=(
        "scripts/deploy/tasks/task-ph3-01-create-media-dirs.sh"
        "scripts/deploy/tasks/task-ph3-02-create-jellyfin-dirs.sh"
        "scripts/deploy/tasks/task-ph3-03-create-samba-config.sh"
        "scripts/deploy/tasks/task-ph3-04-deploy-samba.sh"
        "scripts/deploy/tasks/task-ph3-05-verify-samba.sh"
        "scripts/deploy/tasks/task-ph3-06-create-user-scripts.sh"
        "scripts/deploy/tasks/task-ph3-07-provision-admin.sh"
        "scripts/deploy/tasks/task-ph3-08-provision-power.sh"
        "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"
        "scripts/deploy/tasks/task-ph3-10-create-jellyfin-compose.sh"
        "scripts/deploy/tasks/task-ph3-11-deploy-jellyfin.sh"
        "scripts/deploy/tasks/task-ph3-12-configure-caddy-jellyfin.sh"
        "scripts/deploy/tasks/task-ph3-13-configure-dns-jellyfin.sh"
    )
    
    local all_flags_present=true
    
    for module in "${task_modules[@]}"; do
        if [[ -f "$module" ]]; then
            if grep -q "^set -euo pipefail" "$module"; then
                print_pass "$(basename $module) has safety flags"
            else
                print_fail "$(basename $module) missing safety flags"
                all_flags_present=false
            fi
        fi
    done
    
    if [[ "$all_flags_present" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test task modules have valid syntax
test_task_modules_syntax() {
    run_test "Task modules have valid bash syntax"
    
    local task_modules=(
        "scripts/deploy/tasks/task-ph3-01-create-media-dirs.sh"
        "scripts/deploy/tasks/task-ph3-02-create-jellyfin-dirs.sh"
        "scripts/deploy/tasks/task-ph3-03-create-samba-config.sh"
        "scripts/deploy/tasks/task-ph3-04-deploy-samba.sh"
        "scripts/deploy/tasks/task-ph3-05-verify-samba.sh"
        "scripts/deploy/tasks/task-ph3-06-create-user-scripts.sh"
        "scripts/deploy/tasks/task-ph3-07-provision-admin.sh"
        "scripts/deploy/tasks/task-ph3-08-provision-power.sh"
        "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"
        "scripts/deploy/tasks/task-ph3-10-create-jellyfin-compose.sh"
        "scripts/deploy/tasks/task-ph3-11-deploy-jellyfin.sh"
        "scripts/deploy/tasks/task-ph3-12-configure-caddy-jellyfin.sh"
        "scripts/deploy/tasks/task-ph3-13-configure-dns-jellyfin.sh"
    )
    
    local all_syntax_valid=true
    
    for module in "${task_modules[@]}"; do
        if [[ -f "$module" ]]; then
            if bash -n "$module" 2>/dev/null; then
                print_pass "$(basename $module) syntax valid"
            else
                print_fail "$(basename $module) has syntax errors"
                bash -n "$module"
                all_syntax_valid=false
            fi
        fi
    done
    
    if [[ "$all_syntax_valid" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test task modules are under size limit (warning on exceed, not failure)
test_task_modules_size() {
    run_test "Task modules LOC governance (indicative limit: 150)"
    
    local task_modules=(
        "scripts/deploy/tasks/task-ph3-01-create-media-dirs.sh"
        "scripts/deploy/tasks/task-ph3-02-create-jellyfin-dirs.sh"
        "scripts/deploy/tasks/task-ph3-03-create-samba-config.sh"
        "scripts/deploy/tasks/task-ph3-04-deploy-samba.sh"
        "scripts/deploy/tasks/task-ph3-05-verify-samba.sh"
        "scripts/deploy/tasks/task-ph3-06-create-user-scripts.sh"
        "scripts/deploy/tasks/task-ph3-07-provision-admin.sh"
        "scripts/deploy/tasks/task-ph3-08-provision-power.sh"
        "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"
        "scripts/deploy/tasks/task-ph3-10-create-jellyfin-compose.sh"
        "scripts/deploy/tasks/task-ph3-11-deploy-jellyfin.sh"
        "scripts/deploy/tasks/task-ph3-12-configure-caddy-jellyfin.sh"
        "scripts/deploy/tasks/task-ph3-13-configure-dns-jellyfin.sh"
    )
    
    for module in "${task_modules[@]}"; do
        if [[ -f "$module" ]]; then
            local line_count=$(wc -l < "$module")
            if [[ $line_count -le 150 ]]; then
                print_pass "$(basename $module) is $line_count LOC (limit: 150)"
            else
                print_warn "$(basename $module) is $line_count LOC (exceeds indicative limit: 150)"
            fi
        fi
    done
}

# Main test execution
main() {
    echo "========================================"
    echo "Phase 3 Core Services Scripts Test Suite"
    echo "========================================"
    
    # Run all tests
    test_deployment_script_exists || true
    test_deployment_script_shebang || true
    test_deployment_script_safety_flags || true
    test_deployment_script_size || true
    test_deployment_script_syntax || true
    test_config_management_functions || true
    test_task_execution_functions || true
    test_validation_function || true
    test_interactive_menu || true
    test_utility_library_sourcing || true
    test_dry_run_support || true
    test_error_handling || true
    test_root_check || true
    test_deployment_manual_exists || true
    test_deployment_manual_sections || true
    test_phase3_config_variables || true
    test_validation_checks || true
    test_configuration_persistence || true
    test_idempotency || true
    test_task_modules_exist || true
    test_task_modules_shebang || true
    test_task_modules_safety_flags || true
    test_task_modules_syntax || true
    test_task_modules_size || true
    
    # Print summary
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Warnings:      ${YELLOW}$TESTS_WARNED${NC}"
    echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
    echo "$((TESTS_PASSED + TESTS_WARNED)) / $((TESTS_PASSED + TESTS_WARNED + TESTS_FAILED)) assertions passed across $TESTS_RUN test suites (${TESTS_WARNED} warnings)"
    echo "========================================"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed (warnings are acceptable)${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        echo ""
        echo "Failed assertions:"
        for msg in "${FAILED_MESSAGES[@]}"; do
            echo -e "  ${RED}✗${NC} $msg"
        done
        exit 1
    fi
}

# Run main
main
