#!/usr/bin/env bash
# Test Suite: Backward Compatibility
# Purpose: Validate refactored scripts maintain backward compatibility
# Requirements: 4.1-4.8, Property 4: Backward Compatibility
# Usage: ./test_backward_compatibility.sh
# NOTE: This is a DEVELOPMENT WORKSPACE test - does NOT deploy to actual server

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

# Test original Phase 1 script exists
test_original_phase1_exists() {
    run_test "Original Phase 1 script exists"
    
    if [[ -f "scripts/deploy/deploy-phase1-foundation.sh.original" ]]; then
        print_pass "Original Phase 1 script preserved"
        return 0
    else
        print_fail "Original Phase 1 script not preserved"
        return 1
    fi
}

# Test original Phase 2 script exists
test_original_phase2_exists() {
    run_test "Original Phase 2 script exists"
    
    if [[ -f "scripts/deploy/deploy-phase2-infrastructure.sh.original" ]]; then
        print_pass "Original Phase 2 script preserved"
        return 0
    else
        print_fail "Original Phase 2 script not preserved"
        return 1
    fi
}

# Test refactored Phase 1 has all validation functions
test_phase1_validation_functions_preserved() {
    run_test "Phase 1 validation functions preserved"
    
    local validation_functions=(
        "validate_ssh_hardening"
        "validate_ufw_firewall"
        "validate_fail2ban"
        "validate_docker"
        "validate_git_repository"
        "validate_unattended_upgrades"
        "validate_luks_encryption"
    )
    
    local all_preserved=true
    
    for validation in "${validation_functions[@]}"; do
        # Check in refactored deployment script or validation-utils.sh
        if grep -q "$validation" scripts/deploy/deploy-phase1-foundation.sh || \
           grep -q "$validation" scripts/operations/utils/validation-utils.sh 2>/dev/null; then
            print_pass "$validation() preserved"
        else
            print_fail "$validation() missing"
            all_preserved=false
        fi
    done
    
    if [[ "$all_preserved" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test refactored Phase 2 has all validation functions
test_phase2_validation_functions_preserved() {
    run_test "Phase 2 validation functions preserved"
    
    # Phase 2 validation functions (examples - adjust based on actual functions)
    local validation_functions=(
        "validate_data_directories"
        "validate_caddy"
        "validate_pihole"
        "validate_dns"
        "validate_msmtp"
        "validate_netdata"
    )
    
    local all_preserved=true
    
    for validation in "${validation_functions[@]}"; do
        # Check in refactored deployment script or validation-utils.sh
        if grep -q "$validation" scripts/deploy/deploy-phase2-infrastructure.sh || \
           grep -q "$validation" scripts/operations/utils/validation-utils.sh 2>/dev/null; then
            print_pass "$validation() preserved"
        else
            print_fail "$validation() missing"
            all_preserved=false
        fi
    done
    
    if [[ "$all_preserved" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test refactored Phase 1 has dry-run support
test_phase1_dryrun_support() {
    run_test "Phase 1 refactored script supports dry-run"
    
    if grep -q "DRY_RUN\|dry-run" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Phase 1 supports dry-run"
        return 0
    else
        print_fail "Phase 1 does not support dry-run"
        return 1
    fi
}

# Test refactored Phase 2 has dry-run support
test_phase2_dryrun_support() {
    run_test "Phase 2 refactored script supports dry-run"
    
    if grep -q "DRY_RUN\|dry-run" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Phase 2 supports dry-run"
        return 0
    else
        print_fail "Phase 2 does not support dry-run"
        return 1
    fi
}

# Test refactored Phase 1 has interactive menu
test_phase1_interactive_menu() {
    run_test "Phase 1 refactored script has interactive menu"
    
    if grep -q "menu\|select\|read.*choice" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Phase 1 has interactive menu"
        return 0
    else
        print_fail "Phase 1 does not have interactive menu"
        return 1
    fi
}

# Test refactored Phase 2 has interactive menu
test_phase2_interactive_menu() {
    run_test "Phase 2 refactored script has interactive menu"
    
    if grep -q "menu\|select\|read.*choice" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Phase 2 has interactive menu"
        return 0
    else
        print_fail "Phase 2 does not have interactive menu"
        return 1
    fi
}

# Test refactored Phase 1 has configuration management
test_phase1_config_management() {
    run_test "Phase 1 refactored script has configuration management"
    
    local config_functions=(
        "init_config"
        "load_config"
        "save_config"
        "validate_config"
    )
    
    local all_present=true
    
    for func in "${config_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/deploy/deploy-phase1-foundation.sh; then
            print_pass "$func() present"
        else
            print_fail "$func() missing"
            all_present=false
        fi
    done
    
    if [[ "$all_present" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test refactored Phase 2 has configuration management
test_phase2_config_management() {
    run_test "Phase 2 refactored script has configuration management"
    
    local config_functions=(
        "init_config"
        "load_config"
        "save_config"
        "validate_config"
    )
    
    local all_present=true
    
    for func in "${config_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/deploy/deploy-phase2-infrastructure.sh; then
            print_pass "$func() present"
        else
            print_fail "$func() missing"
            all_present=false
        fi
    done
    
    if [[ "$all_present" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test refactored Phase 1 has all task execution functions
test_phase1_task_execution_functions() {
    run_test "Phase 1 refactored script has all task execution functions"
    
    local task_functions=(
        "execute_update_system"
        "execute_setup_luks"
        "execute_harden_ssh"
        "execute_configure_firewall"
        "execute_setup_fail2ban"
        "execute_install_docker"
        "execute_init_git_repo"
        "execute_setup_auto_updates"
    )
    
    local all_present=true
    
    for func in "${task_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/deploy/deploy-phase1-foundation.sh; then
            print_pass "$func() present"
        else
            print_fail "$func() missing"
            all_present=false
        fi
    done
    
    if [[ "$all_present" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test refactored Phase 2 has all task execution functions
test_phase2_task_execution_functions() {
    run_test "Phase 2 refactored script has all task execution functions"
    
    local task_functions=(
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
    )
    
    local all_present=true
    
    for func in "${task_functions[@]}"; do
        if grep -q "^[[:space:]]*function[[:space:]]\+$func\|^[[:space:]]*$func()" scripts/deploy/deploy-phase2-infrastructure.sh; then
            print_pass "$func() present"
        else
            print_fail "$func() missing"
            all_present=false
        fi
    done
    
    if [[ "$all_present" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test refactored Phase 1 has error handling
test_phase1_error_handling() {
    run_test "Phase 1 refactored script has error handling"
    
    if grep -q "set -euo pipefail" scripts/deploy/deploy-phase1-foundation.sh; then
        print_pass "Phase 1 has safety flags (set -euo pipefail)"
    else
        print_fail "Phase 1 missing safety flags"
        return 1
    fi
    
    return 0
}

# Test refactored Phase 2 has error handling
test_phase2_error_handling() {
    run_test "Phase 2 refactored script has error handling"
    
    if grep -q "set -euo pipefail" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Phase 2 has safety flags (set -euo pipefail)"
    else
        print_fail "Phase 2 missing safety flags"
        return 1
    fi
    
    return 0
}

# Test all Phase 1 task modules exist
test_phase1_task_modules_exist() {
    run_test "All Phase 1 task modules exist"
    
    local task_modules=(
        "task-ph1-01-update-system.sh"
        "task-ph1-02-setup-luks.sh"
        "task-ph1-03-harden-ssh.sh"
        "task-ph1-04-configure-firewall.sh"
        "task-ph1-05-setup-fail2ban.sh"
        "task-ph1-06-install-docker.sh"
        "task-ph1-07-init-git-repo.sh"
        "task-ph1-08-setup-auto-updates.sh"
    )
    
    local all_exist=true
    
    for module in "${task_modules[@]}"; do
        if [[ -f "scripts/deploy/tasks/$module" ]]; then
            print_pass "$module exists"
        else
            print_fail "$module missing"
            all_exist=false
        fi
    done
    
    if [[ "$all_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test all Phase 2 task modules exist
test_phase2_task_modules_exist() {
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
    
    local all_exist=true
    
    for module in "${task_modules[@]}"; do
        if [[ -f "scripts/deploy/tasks/$module" ]]; then
            print_pass "$module exists"
        else
            print_fail "$module missing"
            all_exist=false
        fi
    done
    
    if [[ "$all_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test rollback script exists
test_rollback_script_exists() {
    run_test "Rollback script exists for restoring original scripts"
    
    if [[ -f "scripts/operations/rollback-refactoring.sh" ]]; then
        print_pass "Rollback script exists"
        return 0
    else
        print_fail "Rollback script does not exist"
        return 1
    fi
}

# Run all tests
main() {
    echo "========================================"
    echo "Backward Compatibility Test Suite"
    echo "========================================"
    print_info "NOTE: This is a DEVELOPMENT WORKSPACE test"
    print_info "Does NOT deploy to actual server"
    echo ""
    
    # Original scripts preservation
    test_original_phase1_exists || true
    test_original_phase2_exists || true
    
    # Validation functions preservation
    test_phase1_validation_functions_preserved || true
    test_phase2_validation_functions_preserved || true
    
    # Feature preservation
    test_phase1_dryrun_support || true
    test_phase2_dryrun_support || true
    test_phase1_interactive_menu || true
    test_phase2_interactive_menu || true
    test_phase1_config_management || true
    test_phase2_config_management || true
    
    # Task execution functions
    test_phase1_task_execution_functions || true
    test_phase2_task_execution_functions || true
    
    # Error handling
    test_phase1_error_handling || true
    test_phase2_error_handling || true
    
    # Task modules existence
    test_phase1_task_modules_exist || true
    test_phase2_task_modules_exist || true
    
    # Rollback capability
    test_rollback_script_exists || true
    
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
