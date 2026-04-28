#!/usr/bin/env bash
# Test Suite: Phase 2 Refactored Scripts
# Purpose: Validate refactored Phase 2 deployment script and task modules
# Requirements: 12.4, 12.5, 12.6, 12.7, 18.1-18.8
# Usage: ./test_phase2_refactored.sh

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

# Test deployment script structure
test_deployment_script_exists() {
    run_test "Deployment script exists and is executable"
    
    if [[ -f "scripts/deploy/deploy-phase2-infrastructure.sh" ]]; then
        print_pass "Deployment script exists"
    else
        print_fail "Deployment script does not exist"
        return 1
    fi
    
    if [[ -x "scripts/deploy/deploy-phase2-infrastructure.sh" ]]; then
        print_pass "Deployment script is executable"
    else
        print_fail "Deployment script is not executable"
        return 1
    fi
}

# Test deployment script size
test_deployment_script_size() {
    run_test "Deployment script is under 300 LOC"
    
    local line_count=$(wc -l < scripts/deploy/deploy-phase2-infrastructure.sh)
    
    if [[ $line_count -le 300 ]]; then
        print_pass "Deployment script is $line_count LOC (limit: 300)"
    else
        print_fail "Deployment script is $line_count LOC (exceeds limit: 300)"
        return 1
    fi
}

# Test deployment script syntax
test_deployment_script_syntax() {
    run_test "Deployment script has valid bash syntax"
    
    if bash -n scripts/deploy/deploy-phase2-infrastructure.sh 2>/dev/null; then
        print_pass "Deployment script syntax is valid"
    else
        print_fail "Deployment script has syntax errors"
        return 1
    fi
}

# Test deployment script has required functions
test_deployment_script_functions() {
    run_test "Deployment script has required functions"
    
    local required_functions=(
        "init_config"
        "load_config"
        "save_config"
        "validate_config"
        "execute_create_data_dirs"
        "execute_create_family_dirs"
        "execute_create_backup_dirs"
        "execute_create_services_yaml"
        "execute_deploy_caddy"
        "execute_export_ca_cert"
        "execute_deploy_pihole"
        "execute_configure_dns"
        "execute_install_msmtp"
        "execute_configure_msmtp"
        "execute_test_email"
        "execute_deploy_netdata"
        "execute_configure_log_rotation"
        "validate_all"
    )
    
    local all_functions_exist=true
    
    for func in "${required_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/deploy/deploy-phase2-infrastructure.sh; then
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

# Test all Phase 2 task modules exist
test_task_modules_exist() {
    run_test "All Phase 2 task modules exist"
    
    local task_modules=(
        "task-ph2-01-create-data-dirs.sh"
        "task-ph2-02-create-family-dirs.sh"
        "task-ph2-03-create-backup-dirs.sh"
        "task-ph2-04-create-services-yaml.sh"
        "task-ph2-05-deploy-caddy.sh"
        "task-ph2-06-export-ca-cert.sh"
        "task-ph2-07-deploy-pihole.sh"
        "task-ph2-08-configure-dns.sh"
        "task-ph2-09-install-msmtp.sh"
        "task-ph2-10-configure-msmtp.sh"
        "task-ph2-11-test-email.sh"
        "task-ph2-12-deploy-netdata.sh"
        "task-ph2-13-configure-log-rotation.sh"
    )
    
    local all_modules_exist=true
    
    for module in "${task_modules[@]}"; do
        if [[ -f "scripts/deploy/tasks/$module" ]]; then
            print_pass "$module exists"
        else
            print_fail "$module does not exist"
            all_modules_exist=false
        fi
    done
    
    if [[ "$all_modules_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all Phase 2 task modules are executable
test_task_modules_executable() {
    run_test "All Phase 2 task modules are executable"
    
    local task_modules=(
        "task-ph2-01-create-data-dirs.sh"
        "task-ph2-02-create-family-dirs.sh"
        "task-ph2-03-create-backup-dirs.sh"
        "task-ph2-04-create-services-yaml.sh"
        "task-ph2-05-deploy-caddy.sh"
        "task-ph2-06-export-ca-cert.sh"
        "task-ph2-07-deploy-pihole.sh"
        "task-ph2-08-configure-dns.sh"
        "task-ph2-09-install-msmtp.sh"
        "task-ph2-10-configure-msmtp.sh"
        "task-ph2-11-test-email.sh"
        "task-ph2-12-deploy-netdata.sh"
        "task-ph2-13-configure-log-rotation.sh"
    )
    
    local all_modules_executable=true
    
    for module in "${task_modules[@]}"; do
        if [[ -x "scripts/deploy/tasks/$module" ]]; then
            print_pass "$module is executable"
        else
            print_fail "$module is not executable"
            all_modules_executable=false
        fi
    done
    
    if [[ "$all_modules_executable" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all Phase 2 task modules have valid syntax
test_task_modules_syntax() {
    run_test "All Phase 2 task modules have valid bash syntax"
    
    local task_modules=(
        "task-ph2-01-create-data-dirs.sh"
        "task-ph2-02-create-family-dirs.sh"
        "task-ph2-03-create-backup-dirs.sh"
        "task-ph2-04-create-services-yaml.sh"
        "task-ph2-05-deploy-caddy.sh"
        "task-ph2-06-export-ca-cert.sh"
        "task-ph2-07-deploy-pihole.sh"
        "task-ph2-08-configure-dns.sh"
        "task-ph2-09-install-msmtp.sh"
        "task-ph2-10-configure-msmtp.sh"
        "task-ph2-11-test-email.sh"
        "task-ph2-12-deploy-netdata.sh"
        "task-ph2-13-configure-log-rotation.sh"
    )
    
    local all_syntax_valid=true
    
    for module in "${task_modules[@]}"; do
        if bash -n "scripts/deploy/tasks/$module" 2>/dev/null; then
            print_pass "$module syntax is valid"
        else
            print_fail "$module has syntax errors"
            all_syntax_valid=false
        fi
    done
    
    if [[ "$all_syntax_valid" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all Phase 2 task modules are under 150 LOC
test_task_modules_size() {
    run_test "All Phase 2 task modules are under 150 LOC"
    
    local task_modules=(
        "task-ph2-01-create-data-dirs.sh"
        "task-ph2-02-create-family-dirs.sh"
        "task-ph2-03-create-backup-dirs.sh"
        "task-ph2-04-create-services-yaml.sh"
        "task-ph2-05-deploy-caddy.sh"
        "task-ph2-06-export-ca-cert.sh"
        "task-ph2-07-deploy-pihole.sh"
        "task-ph2-08-configure-dns.sh"
        "task-ph2-09-install-msmtp.sh"
        "task-ph2-10-configure-msmtp.sh"
        "task-ph2-11-test-email.sh"
        "task-ph2-12-deploy-netdata.sh"
        "task-ph2-13-configure-log-rotation.sh"
    )
    
    local all_within_limit=true
    
    for module in "${task_modules[@]}"; do
        local line_count=$(wc -l < "scripts/deploy/tasks/$module")
        if [[ $line_count -le 150 ]]; then
            print_pass "$module is $line_count LOC (limit: 150)"
        else
            print_fail "$module is $line_count LOC (exceeds limit: 150)"
            all_within_limit=false
        fi
    done
    
    if [[ "$all_within_limit" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all Phase 2 task modules have proper shebang
test_task_modules_shebang() {
    run_test "All Phase 2 task modules have proper shebang"
    
    local task_modules=(
        "task-ph2-01-create-data-dirs.sh"
        "task-ph2-02-create-family-dirs.sh"
        "task-ph2-03-create-backup-dirs.sh"
        "task-ph2-04-create-services-yaml.sh"
        "task-ph2-05-deploy-caddy.sh"
        "task-ph2-06-export-ca-cert.sh"
        "task-ph2-07-deploy-pihole.sh"
        "task-ph2-08-configure-dns.sh"
        "task-ph2-09-install-msmtp.sh"
        "task-ph2-10-configure-msmtp.sh"
        "task-ph2-11-test-email.sh"
        "task-ph2-12-deploy-netdata.sh"
        "task-ph2-13-configure-log-rotation.sh"
    )
    
    local all_have_shebang=true
    
    for module in "${task_modules[@]}"; do
        if head -n1 "scripts/deploy/tasks/$module" | grep -q "#!/usr/bin/env bash\|#!/bin/bash"; then
            print_pass "$module has proper shebang"
        else
            print_fail "$module has incorrect shebang"
            all_have_shebang=false
        fi
    done
    
    if [[ "$all_have_shebang" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all Phase 2 task modules have safety flags
test_task_modules_safety() {
    run_test "All Phase 2 task modules have safety flags"
    
    local task_modules=(
        "task-ph2-01-create-data-dirs.sh"
        "task-ph2-02-create-family-dirs.sh"
        "task-ph2-03-create-backup-dirs.sh"
        "task-ph2-04-create-services-yaml.sh"
        "task-ph2-05-deploy-caddy.sh"
        "task-ph2-06-export-ca-cert.sh"
        "task-ph2-07-deploy-pihole.sh"
        "task-ph2-08-configure-dns.sh"
        "task-ph2-09-install-msmtp.sh"
        "task-ph2-10-configure-msmtp.sh"
        "task-ph2-11-test-email.sh"
        "task-ph2-12-deploy-netdata.sh"
        "task-ph2-13-configure-log-rotation.sh"
    )
    
    local all_have_safety=true
    
    for module in "${task_modules[@]}"; do
        if grep -q "set -euo pipefail" "scripts/deploy/tasks/$module"; then
            print_pass "$module has safety flags"
        else
            print_fail "$module missing safety flags"
            all_have_safety=false
        fi
    done
    
    if [[ "$all_have_safety" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all Phase 2 task modules source utility libraries
test_task_modules_source_utils() {
    run_test "All Phase 2 task modules source utility libraries"
    
    local task_modules=(
        "task-ph2-01-create-data-dirs.sh"
        "task-ph2-02-create-family-dirs.sh"
        "task-ph2-03-create-backup-dirs.sh"
        "task-ph2-04-create-services-yaml.sh"
        "task-ph2-05-deploy-caddy.sh"
        "task-ph2-06-export-ca-cert.sh"
        "task-ph2-07-deploy-pihole.sh"
        "task-ph2-08-configure-dns.sh"
        "task-ph2-09-install-msmtp.sh"
        "task-ph2-10-configure-msmtp.sh"
        "task-ph2-11-test-email.sh"
        "task-ph2-12-deploy-netdata.sh"
        "task-ph2-13-configure-log-rotation.sh"
    )
    
    local all_source_utils=true
    
    for module in "${task_modules[@]}"; do
        if grep -q "source.*output-utils.sh" "scripts/deploy/tasks/$module"; then
            print_pass "$module sources output-utils.sh"
        else
            print_fail "$module does not source output-utils.sh"
            all_source_utils=false
        fi
    done
    
    if [[ "$all_source_utils" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all Phase 2 task modules support dry-run
test_task_modules_dryrun() {
    run_test "All Phase 2 task modules support dry-run"
    
    local task_modules=(
        "task-ph2-01-create-data-dirs.sh"
        "task-ph2-02-create-family-dirs.sh"
        "task-ph2-03-create-backup-dirs.sh"
        "task-ph2-04-create-services-yaml.sh"
        "task-ph2-05-deploy-caddy.sh"
        "task-ph2-06-export-ca-cert.sh"
        "task-ph2-07-deploy-pihole.sh"
        "task-ph2-08-configure-dns.sh"
        "task-ph2-09-install-msmtp.sh"
        "task-ph2-10-configure-msmtp.sh"
        "task-ph2-11-test-email.sh"
        "task-ph2-12-deploy-netdata.sh"
        "task-ph2-13-configure-log-rotation.sh"
    )
    
    local all_support_dryrun=true
    
    for module in "${task_modules[@]}"; do
        if grep -q "DRY_RUN" "scripts/deploy/tasks/$module"; then
            print_pass "$module supports dry-run"
        else
            print_fail "$module does not support dry-run"
            all_support_dryrun=false
        fi
    done
    
    if [[ "$all_support_dryrun" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test validation functions preserved
test_validation_functions_preserved() {
    run_test "Validation functions preserved from original script"
    
    # Phase 2 validation functions (examples - adjust based on actual functions)
    local validation_functions=(
        "validate_data_directories"
        "validate_caddy"
        "validate_pihole"
        "validate_dns"
        "validate_msmtp"
        "validate_netdata"
    )
    
    local all_validations_exist=true
    
    # Check in deployment script or validation-utils.sh
    for validation in "${validation_functions[@]}"; do
        if grep -q "$validation" scripts/deploy/deploy-phase2-infrastructure.sh || \
           grep -q "$validation" scripts/operations/utils/validation-utils.sh 2>/dev/null; then
            print_pass "$validation() function preserved"
        else
            print_fail "$validation() function missing"
            all_validations_exist=false
        fi
    done
    
    if [[ "$all_validations_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Run all tests
main() {
    echo "========================================"
    echo "Phase 2 Refactored Scripts Test Suite"
    echo "========================================"
    
    # Deployment script tests
    test_deployment_script_exists || true
    test_deployment_script_size || true
    test_deployment_script_syntax || true
    test_deployment_script_functions || true
    
    # Task module tests
    test_task_modules_exist || true
    test_task_modules_executable || true
    test_task_modules_syntax || true
    test_task_modules_size || true
    test_task_modules_shebang || true
    test_task_modules_safety || true
    test_task_modules_source_utils || true
    test_task_modules_dryrun || true
    
    # Validation tests
    test_validation_functions_preserved || true
    
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
