#!/usr/bin/env bash
# CI_SAFE=true
# Property-Based Tests for Phase 02 Scripts
# Purpose: Validate infrastructure deployment scripts
# Test framework: Bash-based property testing
# Usage: ./test_phase2_scripts.sh

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

# Test deployment script exists and is executable
test_deployment_exists() {
    run_test "Deployment script exists"
    
    if [[ -f "scripts/deploy/deploy-phase2-infrastructure.sh" ]]; then
        print_pass "Deployment script exists"
    else
        print_fail "Deployment script does not exist"
        return 1
    fi
}

# Test deployment script has proper shebang
test_deployment_shebang() {
    run_test "Deployment script has proper shebang"
    
    if head -n1 scripts/deploy/deploy-phase2-infrastructure.sh | grep -q "^#!/bin/bash"; then
        print_pass "Deployment script has correct shebang"
    else
        print_fail "Deployment script has incorrect shebang"
        return 1
    fi
}

# Test deployment script has set -euo pipefail
test_deployment_safety() {
    run_test "Deployment script has safety flags"
    
    if grep -q "set -euo pipefail" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Deployment script has safety flags"
    else
        print_fail "Deployment script missing safety flags"
        return 1
    fi
}

# Test deployment script syntax
test_deployment_syntax() {
    run_test "Deployment script syntax is valid"
    
    if bash -n scripts/deploy/deploy-phase2-infrastructure.sh 2>/dev/null; then
        print_pass "Deployment script syntax is valid"
    else
        print_fail "Deployment script has syntax errors"
        return 1
    fi
}

# Test deployment script has configuration management functions
test_deployment_config_functions() {
    run_test "Deployment script has configuration management functions"
    
    if grep -q "load_config()" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "load_config() function exists"
    else
        print_fail "load_config() function missing"
        return 1
    fi
    
    if grep -q "save_config()" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "save_config() function exists"
    else
        print_fail "save_config() function missing"
        return 1
    fi
    
    if grep -q "init_config()" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "init_config() function exists"
    else
        print_fail "init_config() function missing"
        return 1
    fi
    
    if grep -q "validate_config()" scripts/deploy/deploy-phase2-infrastructure.sh; then
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
    
    # Check orchestration functions exist in deployment script (actual function names)
    for task in deploy_pihole deploy_caddy configure_msmtp deploy_netdata create_data_dirs configure_log_rotation; do
        if grep -q "execute_${task}()" scripts/deploy/deploy-phase2-infrastructure.sh; then
            print_pass "execute_${task}() orchestration function exists"
        else
            print_fail "execute_${task}() orchestration function missing"
            all_tasks_exist=false
        fi
    done
    
    # Check task modules exist
    if ls scripts/deploy/tasks/task-ph2-*.sh 2>/dev/null | grep -q .; then
        print_pass "Phase 2 task modules exist"
    else
        print_fail "Phase 2 task modules missing"
        all_tasks_exist=false
    fi
    
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
        "validate_dns_service"
        "validate_caddy_service"
        "validate_smtp_service"
        "validate_netdata_service"
        "validate_data_structure"
    )
    
    local all_validations_exist=true
    
    # Check deployment script sources validation utility
    if grep -q "source.*validation-infrastructure-utils.sh" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Deployment script sources validation utility"
    else
        print_fail "Deployment script does not source validation utility"
        all_validations_exist=false
    fi
    
    # Check validation utility has functions
    for validation in "${validations[@]}"; do
        if grep -q "$validation()" scripts/operations/utils/validation-infrastructure-utils.sh 2>/dev/null; then
            print_pass "$validation() function exists in utility"
        else
            print_fail "$validation() function missing from utility"
            all_validations_exist=false
        fi
    done
    
    # Check deployment script has validate_all orchestration
    if grep -q "validate_all()" scripts/deploy/deploy-phase2-infrastructure.sh; then
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
    
    if grep -q "DRY_RUN" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Dry-run mode variable exists"
    else
        print_fail "Dry-run mode variable missing"
        return 1
    fi
    
    if grep -q 'DRY_RUN_ARG\|DRY_RUN.*true' scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Dry-run mode checks exist"
        return 0
    else
        print_fail "Dry-run mode checks missing"
        return 1
    fi
}

# Test deployment script has interactive menu
test_deployment_menu() {
    run_test "Deployment script has interactive menu"
    
    if grep -qE "(show_menu|main_menu)\(\)" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Menu function exists"
    else
        print_fail "Menu function missing"
        return 1
    fi
    
    if grep -q "Select option" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Interactive menu exists"
        return 0
    else
        print_fail "Interactive menu missing"
        return 1
    fi
}

# Test deployment manual exists
test_deployment_manual_exists() {
    run_test "Deployment manual exists"
    
    if [[ -f "docs/deployment_manuals/phase2-infrastructure.md" ]]; then
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
        "## Overview"
        "## Prerequisites"
        "## Quick Start"
        "## Pre-Deployment Checklist"
        "## Post-Deployment Tasks"
        "## Validation"
        "## Troubleshooting"
    )
    
    local all_sections_exist=true
    
    for section in "${required_sections[@]}"; do
        if grep -q "$section" docs/deployment_manuals/phase2-infrastructure.md; then
            print_pass "Section exists: $section"
        else
            print_fail "Section missing: $section"
            all_sections_exist=false
        fi
    done
    
    if [[ "$all_sections_exist" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Property: Idempotency - Scripts should be safe to run multiple times
test_property_idempotency() {
    run_test "Property: Scripts implement idempotency checks"
    
    # Check task modules have idempotency checks
    if grep -qE "(already|exists|running)" scripts/deploy/tasks/task-ph2-*.sh 2>/dev/null; then
        print_pass "Task modules have idempotency checks"
        return 0
    else
        print_fail "Task modules missing idempotency checks"
        return 1
    fi
}

# Property: Error handling - Scripts should handle errors gracefully
test_property_error_handling() {
    run_test "Property: Scripts implement error handling"
    
    # Check for set -euo pipefail (fail fast)
    if grep -q "set -euo pipefail" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Script has fail-fast error handling"
    else
        print_fail "Script missing fail-fast error handling"
        return 1
    fi
    
    # Check for error messages
    if grep -q "print_error" scripts/deploy/deploy-phase2-infrastructure.sh; then
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
    if grep -qE "cat >|echo.*>" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "save_config() writes to file"
    else
        print_fail "save_config() does not write to file"
        return 1
    fi
    
    # Check load_config sources file
    if grep -qE "source.*CONFIG" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "load_config() sources file"
        return 0
    else
        print_fail "load_config() does not source file"
        return 1
    fi
}

# Property: Validation checks actual state - Not just config files
test_property_validation_state() {
    run_test "Property: Validation checks actual system state"
    
    # Check validation utility uses system commands
    if grep -q "docker ps\|docker inspect" scripts/operations/utils/validation-infrastructure-utils.sh 2>/dev/null; then
        print_pass "Validation checks container status"
    else
        print_fail "Validation does not check container status"
        return 1
    fi
    
    if grep -qE "nslookup|curl|wget" scripts/operations/utils/validation-infrastructure-utils.sh 2>/dev/null; then
        print_pass "Validation checks service accessibility"
        return 0
    else
        print_fail "Validation does not check service accessibility"
        return 1
    fi
}

# Property: Phase 2 specific - Domain and SMTP configuration
test_property_phase2_config() {
    run_test "Property: Phase 2 configuration includes domain and SMTP"
    
    # Check for domain configuration
    if grep -q "DOMAIN=" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "Domain configuration exists"
    else
        print_fail "Domain configuration missing"
        return 1
    fi
    
    # Check for SMTP configuration
    if grep -qE "SMTP|smtp" scripts/deploy/deploy-phase2-infrastructure.sh; then
        print_pass "SMTP configuration exists"
        return 0
    else
        print_fail "SMTP configuration missing"
        return 1
    fi
}

# Property: Phase 2 specific - validation checks exist
test_property_phase2_validations() {
    run_test "Property: Phase 2 has validation checks"
    
    # Count validation functions in utility
    local count=$(grep -c "^validate_.*() {" scripts/operations/utils/validation-infrastructure-utils.sh 2>/dev/null || echo 0)
    
    if [[ $count -ge 5 ]]; then
        print_pass "Phase 2 has $count validation functions"
        return 0
    else
        print_fail "Phase 2 has only $count validation functions (expected 5+)"
        return 1
    fi
}

# LOC Governance: Deployment script (warning on exceed, not failure)
test_deployment_script_loc() {
    run_test "Deployment script LOC governance (indicative limit: 300)"
    
    local line_count=$(wc -l < scripts/deploy/deploy-phase2-infrastructure.sh)
    
    if [[ $line_count -le 300 ]]; then
        print_pass "deploy-phase2-infrastructure.sh: $line_count LOC (limit: 300)"
    else
        print_warn "deploy-phase2-infrastructure.sh: $line_count LOC (exceeds indicative limit: 300)"
    fi
}

# LOC Governance: Task modules (warning on exceed, not failure)
test_task_modules_loc() {
    run_test "Task modules LOC governance (indicative limit: 150)"
    
    for module in scripts/deploy/tasks/task-ph2-*.sh; do
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
    
    if [[ -f "scripts/operations/utils/validation-infrastructure-utils.sh" ]]; then
        local line_count=$(wc -l < scripts/operations/utils/validation-infrastructure-utils.sh)
        if [[ $line_count -le 200 ]]; then
            print_pass "validation-infrastructure-utils.sh: $line_count LOC (limit: 200)"
        else
            print_warn "validation-infrastructure-utils.sh: $line_count LOC (exceeds indicative limit: 200)"
        fi
    fi
}

# Run all tests
main() {
    echo "========================================"
    echo "Phase 02 Scripts Property-Based Tests"
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
    test_deployment_menu || true
    
    # Documentation tests
    test_deployment_manual_exists || true
    test_deployment_manual_sections || true
    
    # Property tests
    test_property_idempotency || true
    test_property_error_handling || true
    test_property_config_persistence || true
    test_property_validation_state || true
    test_property_phase2_config || true
    test_property_phase2_validations || true
    
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
