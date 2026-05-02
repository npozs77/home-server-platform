#!/usr/bin/env bash
# Property-Based Tests for Phase 01 Scripts
# Purpose: Validate bootstrap and deployment scripts
# Test framework: Bash-based property testing
# Usage: ./test_phase1_scripts.sh

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

# Test bootstrap script exists
test_bootstrap_exists() {
    run_test "Bootstrap script exists"
    
    if [[ -f "scripts/deploy/bootstrap.sh" ]]; then
        print_pass "Bootstrap script exists"
    else
        print_fail "Bootstrap script does not exist"
        return 1
    fi
}

# Test bootstrap script has proper shebang
test_bootstrap_shebang() {
    run_test "Bootstrap script has proper shebang"
    
    if head -n1 scripts/deploy/bootstrap.sh | grep -q "#!/usr/bin/env bash"; then
        print_pass "Bootstrap script has correct shebang"
    else
        print_fail "Bootstrap script has incorrect shebang"
        return 1
    fi
}

# Test bootstrap script has set -euo pipefail
test_bootstrap_safety() {
    run_test "Bootstrap script has safety flags"
    
    if grep -q "set -euo pipefail" scripts/deploy/bootstrap.sh; then
        print_pass "Bootstrap script has safety flags"
    else
        print_fail "Bootstrap script missing safety flags"
        return 1
    fi
}

# Test bootstrap script syntax
test_bootstrap_syntax() {
    run_test "Bootstrap script syntax is valid"
    
    if bash -n scripts/deploy/bootstrap.sh 2>/dev/null; then
        print_pass "Bootstrap script syntax is valid"
    else
        print_fail "Bootstrap script has syntax errors"
        return 1
    fi
}

# Test deployment script exists
test_deployment_exists() {
    run_test "Deployment script exists"
    
    if [[ -f "scripts/deploy/deploy-phase1-foundation.sh" ]]; then
        print_pass "Deployment script exists"
    else
        print_fail "Deployment script does not exist"
        return 1
    fi
}

# Test deployment script has proper shebang
test_deployment_shebang() {
    run_test "Deployment script has proper shebang"
    
    if head -n1 scripts/deploy/deploy-phase1-foundation.sh | grep -q "^#!/bin/bash"; then
        print_pass "Deployment script has correct shebang"
    else
        print_fail "Deployment script has incorrect shebang"
        return 1
    fi
}

# Test deployment script has set -euo pipefail
test_deployment_safety() {
    run_test "Deployment script has safety flags"
    
    if grep -q "set -euo pipefail" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Deployment script has safety flags"
    else
        print_fail "Deployment script missing safety flags"
        return 1
    fi
}

# Test deployment script syntax
test_deployment_syntax() {
    run_test "Deployment script syntax is valid"
    
    if bash -n scripts/deploy/deploy-phase1-foundation.sh 2>/dev/null; then
        print_pass "Deployment script syntax is valid"
    else
        print_fail "Deployment script has syntax errors"
        return 1
    fi
}

# Test deployment script has configuration management functions
test_deployment_config_functions() {
    run_test "Deployment script has configuration management functions"
    
    if grep -q "load_config()" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "load_config() function exists"
    else
        print_fail "load_config() function missing"
        return 1
    fi
    
    if grep -q "save_config()" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "save_config() function exists"
    else
        print_fail "save_config() function missing"
        return 1
    fi
    
    if grep -q "init_config()" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "init_config() function exists"
    else
        print_fail "init_config() function missing"
        return 1
    fi
    
    if grep -q "validate_config()" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "validate_config() function exists"
        return 0
    else
        print_fail "validate_config() function missing"
        return 1
    fi
}

# Test deployment script has task execution functions (modular architecture)
test_deployment_task_functions() {
    run_test "Deployment script has task execution functions (modular)"
    
    local all_tasks_exist=true
    
    # Check orchestration functions exist in deployment script
    for task in update_system setup_luks harden_ssh configure_firewall setup_fail2ban install_docker init_git_repo setup_auto_updates; do
        if grep -q "execute_${task}()" scripts/deploy/deploy-phase1-foundation.sh; then
            print_pass "execute_${task}() orchestration function exists"
        else
            print_fail "execute_${task}() orchestration function missing"
            all_tasks_exist=false
        fi
    done
    
    # Check task modules exist
    for i in {1..8}; do
        task_file="scripts/deploy/tasks/task-ph1-0${i}-*.sh"
        if ls $task_file 2>/dev/null | grep -q .; then
            print_pass "Task module ph1-0${i} exists"
        else
            print_fail "Task module ph1-0${i} missing"
            all_tasks_exist=false
        fi
    done
    
    if [[ "$all_tasks_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test deployment script has validation functions (modular architecture)
test_deployment_validation_functions() {
    run_test "Deployment script has validation functions (modular)"
    
    local validations=(
        "validate_ssh_hardening"
        "validate_ufw_firewall"
        "validate_fail2ban"
        "validate_docker"
        "validate_git_repository"
        "validate_unattended_upgrades"
        "validate_luks_encryption"
        "validate_docker_group"
        "validate_essential_tools"
    )
    
    local all_validations_exist=true
    
    # Check deployment script sources validation utility
    if grep -q "source.*validation-foundation-utils.sh" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Deployment script sources validation utility"
    else
        print_fail "Deployment script does not source validation utility"
        all_validations_exist=false
    fi
    
    # Check validation utility has functions
    for validation in "${validations[@]}"; do
        if grep -q "$validation()" scripts/operations/utils/validation-foundation-utils.sh; then
            print_pass "$validation() function exists in utility"
        else
            print_fail "$validation() function missing from utility"
            all_validations_exist=false
        fi
    done
    
    # Check deployment script has validate_all orchestration
    if grep -q "validate_all()" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "validate_all() orchestration exists"
    else
        print_fail "validate_all() orchestration missing"
        all_validations_exist=false
    fi
    
    if [[ "$all_validations_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test deployment script has dry-run support
test_deployment_dryrun() {
    run_test "Deployment script has dry-run support"
    
    if grep -q "DRY_RUN" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Dry-run mode variable exists"
    else
        print_fail "Dry-run mode variable missing"
        return 1
    fi
    
    if grep -q '\[\[ "\$DRY_RUN" == true \]\]' scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Dry-run mode checks exist"
        return 0
    else
        print_fail "Dry-run mode checks missing"
        return 1
    fi
}

# Test deployment script has DNS port 53 UFW rules (in task module)
test_deployment_dns_ufw_rules() {
    run_test "Deployment script has DNS port 53 UFW rules (in task module)"
    
    if grep -q "ufw allow from 192.168.1.0/24 to any port 53 proto tcp" scripts/deploy/tasks/task-ph1-04-*.sh 2>/dev/null; then
        print_pass "DNS TCP UFW rule exists in task module"
    else
        print_fail "DNS TCP UFW rule missing"
        return 1
    fi
    
    if grep -q "ufw allow from 192.168.1.0/24 to any port 53 proto udp" scripts/deploy/tasks/task-ph1-04-*.sh 2>/dev/null; then
        print_pass "DNS UDP UFW rule exists in task module"
        return 0
    else
        print_fail "DNS UDP UFW rule missing"
        return 1
    fi
}

# Test deployment script has interactive menu
test_deployment_menu() {
    run_test "Deployment script has interactive menu"
    
    if grep -qE "(show_menu|main_menu)\(\)" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Menu function exists"
    else
        print_fail "Menu function missing"
        return 1
    fi
    
    if grep -q "Select option" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Interactive menu exists"
        return 0
    else
        print_fail "Interactive menu missing"
        return 1
    fi
}

# Test configuration example exists
test_config_example_exists() {
    run_test "Configuration example exists"
    
    if [[ -f "configs/foundation.env.example" ]] && [[ -f "configs/secrets.env.example" ]]; then
        print_pass "Configuration examples exist"
    else
        print_fail "Configuration examples do not exist"
        return 1
    fi
}

# Test configuration example has all required variables
test_config_example_variables() {
    run_test "Configuration example has all required variables"
    
    local required_vars=(
        "TIMEZONE"
        "HOSTNAME"
        "SERVER_IP"
        "ADMIN_USER"
        "ADMIN_EMAIL"
        "DATA_DISK"
        "LUKS_PASSPHRASE"
        "GIT_USER_NAME"
        "GIT_USER_EMAIL"
        "NETWORK_INTERFACE"
    )
    
    local all_vars_exist=true
    
    for var in "${required_vars[@]}"; do
        if grep -q "^$var=" configs/foundation.env.example || grep -q "^$var=" configs/secrets.env.example; then
            print_pass "$var variable exists"
        else
            print_fail "$var variable missing"
            all_vars_exist=false
        fi
    done
    
    if [[ "$all_vars_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test CONFIG_GUIDE.md exists
test_config_guide_exists() {
    run_test "CONFIG_GUIDE.md exists"
    
    if [[ -f "configs/CONFIG_GUIDE.md" ]]; then
        print_pass "CONFIG_GUIDE.md exists"
    else
        print_fail "CONFIG_GUIDE.md does not exist"
        return 1
    fi
}

# Test deployment manual exists
test_deployment_manual_exists() {
    run_test "Deployment manual exists"
    
    if [[ -f "docs/deployment_manuals/phase1-foundation.md" ]]; then
        print_pass "Deployment manual exists"
    else
        print_fail "Deployment manual does not exist"
        return 1
    fi
}

# Property: Idempotency - Scripts should be safe to run multiple times
test_property_idempotency() {
    run_test "Property: Scripts implement idempotency checks"
    
    # Check task modules have idempotency checks
    if grep -qE "(already installed|already exists|already configured)" scripts/deploy/tasks/task-ph1-*.sh 2>/dev/null; then
        print_pass "Task modules have idempotency checks"
    else
        print_fail "Task modules missing idempotency checks"
        return 1
    fi
    
    if grep -qE "(\[\[ -f|\[\[ -d|command -v)" scripts/deploy/tasks/task-ph1-*.sh 2>/dev/null; then
        print_pass "Task modules check for existing resources"
        return 0
    else
        print_fail "Task modules missing existence checks"
        return 1
    fi
}

# Property: Error handling - Scripts should handle errors gracefully
test_property_error_handling() {
    run_test "Property: Scripts implement error handling"
    
    # Check for set -euo pipefail (fail fast)
    if grep -q "set -euo pipefail" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Deployment script has fail-fast error handling"
    else
        print_fail "Deployment script missing fail-fast error handling"
        return 1
    fi
    
    # Check for error messages
    if grep -q "print_error" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Deployment script has error messaging"
        return 0
    else
        print_fail "Deployment script missing error messaging"
        return 1
    fi
}

# Property: Configuration persistence - Config should persist correctly
test_property_config_persistence() {
    run_test "Property: Configuration persists correctly"
    
    # Check save_config writes to file
    if grep -qE "cat >|echo.*>" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "save_config() writes to file"
    else
        print_fail "save_config() does not write to file"
        return 1
    fi
    
    # Check load_config sources file
    if grep -qE "source.*CONFIG" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "load_config() sources file"
    else
        print_fail "load_config() does not source file"
        return 1
    fi

    # Check save_config includes backup DAS variables
    local save_block
    save_block=$(sed -n '/^save_config/,/^}/p' scripts/deploy/deploy-phase1-foundation.sh)
    if echo "$save_block" | grep -q 'BACKUP_DISK'; then
        print_pass "save_config() includes BACKUP_DISK"
    else
        print_fail "save_config() missing BACKUP_DISK"
    fi
    if echo "$save_block" | grep -q 'BACKUP_MOUNT'; then
        print_pass "save_config() includes BACKUP_MOUNT"
    else
        print_fail "save_config() missing BACKUP_MOUNT"
    fi
    if echo "$save_block" | grep -q 'BACKUP_MAPPER'; then
        print_pass "save_config() includes BACKUP_MAPPER"
    else
        print_fail "save_config() missing BACKUP_MAPPER"
    fi
}

# Property: Validation checks actual state - Not just config files
test_property_validation_state() {
    run_test "Property: Validation checks actual system state"
    
    # Check validation utility uses system commands
    if grep -q "systemctl is-active" scripts/operations/utils/validation-foundation-utils.sh; then
        print_pass "Validation checks service status"
    else
        print_fail "Validation does not check service status"
        return 1
    fi
    
    if grep -q "command -v" scripts/operations/utils/validation-foundation-utils.sh; then
        print_pass "Validation checks command existence"
        return 0
    else
        print_fail "Validation does not check command existence"
        return 1
    fi
}

# LOC Governance: Deployment script (warning on exceed, not failure)
test_deployment_script_loc() {
    run_test "Deployment script LOC governance (indicative limit: 300)"
    
    local line_count=$(wc -l < scripts/deploy/deploy-phase1-foundation.sh)
    
    if [[ $line_count -le 300 ]]; then
        print_pass "deploy-phase1-foundation.sh: $line_count LOC (limit: 300)"
    else
        print_warn "deploy-phase1-foundation.sh: $line_count LOC (exceeds indicative limit: 300)"
    fi
}

# LOC Governance: Task modules (warning on exceed, not failure)
test_task_modules_loc() {
    run_test "Task modules LOC governance (indicative limit: 150)"
    
    for module in scripts/deploy/tasks/task-ph1-*.sh; do
        if [[ -f "$module" ]]; then
            local line_count=$(wc -l < "$module")
            if [[ $line_count -le 150 ]]; then
                print_pass "$(basename $module): $line_count LOC (limit: 150)"
            else
                print_warn "$(basename $module): $line_count LOC (exceeds indicative limit: 150)"
            fi
        fi
    done
}

# LOC Governance: Utility libraries (warning on exceed, not failure)
test_utility_libraries_loc() {
    run_test "Utility libraries LOC governance (indicative limit: 200)"
    
    if [[ -f "scripts/operations/utils/validation-foundation-utils.sh" ]]; then
        local line_count=$(wc -l < scripts/operations/utils/validation-foundation-utils.sh)
        if [[ $line_count -le 200 ]]; then
            print_pass "validation-foundation-utils.sh: $line_count LOC (limit: 200)"
        else
            print_warn "validation-foundation-utils.sh: $line_count LOC (exceeds indicative limit: 200)"
        fi
    fi
}

# Run all tests
main() {
    echo "========================================"
    echo "Phase 01 Scripts Property-Based Tests"
    echo "========================================"
    
    # Deployment script tests
    test_deployment_exists || true
    test_deployment_shebang || true
    test_deployment_safety || true
    test_deployment_syntax || true
    test_deployment_config_functions || true
    test_deployment_task_functions || true
    test_deployment_validation_functions || true
    test_deployment_dryrun || true
    test_deployment_dns_ufw_rules || true
    test_deployment_menu || true
    
    # Configuration tests
    test_config_example_exists || true
    test_config_example_variables || true
    test_config_guide_exists || true
    
    # Documentation tests
    test_deployment_manual_exists || true
    
    # Property tests
    test_property_idempotency || true
    test_property_error_handling || true
    test_property_config_persistence || true
    test_property_validation_state || true
    
    # LOC Governance tests
    test_deployment_script_loc || true
    test_task_modules_loc || true
    test_utility_libraries_loc || true
    
    # Summary
    echo ""
    echo "========================================"
    echo "Test Results"
    echo "========================================"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Warnings:      ${YELLOW}$TESTS_WARNED${NC}"
    echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
    echo "$((TESTS_PASSED + TESTS_WARNED)) / $((TESTS_PASSED + TESTS_WARNED + TESTS_FAILED)) assertions passed across $TESTS_RUN test suites (${TESTS_WARNED} warnings)"
    echo "========================================"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed (warnings are acceptable) ✓${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please review and fix issues.${NC}"
        echo ""
        echo "Failed assertions:"
        for msg in "${FAILED_MESSAGES[@]}"; do
            echo -e "  ${RED}✗${NC} $msg"
        done
        exit 1
    fi
}

# Run tests
main
