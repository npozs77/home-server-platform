#!/usr/bin/env bash
# Test Suite: Phase 4 Photo Management Scripts
# Purpose: Validate Phase 4 deployment script structure and conventions
# Requirements: 31.1, 31.2, 31.3, 31.4, 31.5, 31.6, 31.7
# Usage: bash tests/test_phase4_scripts.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_MESSAGES=()

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_MESSAGES+=("$1"); }
print_warn() { echo -e "${YELLOW}⚠ WARN${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }

run_test() { TESTS_RUN=$((TESTS_RUN + 1)); echo ""; echo "Test $TESTS_RUN: $1"; echo "----------------------------------------"; }

DEPLOY_SCRIPT="scripts/deploy/deploy-phase4-photo-management.sh"

# --- Deployment Script Tests ---

test_deployment_script_exists() {
    run_test "Deployment script exists"
    [[ -f "$DEPLOY_SCRIPT" ]] && print_pass "Deployment script exists" || print_fail "Deployment script does not exist"
}

test_deployment_script_shebang() {
    run_test "Deployment script has proper shebang"
    local first_line
    first_line=$(head -n 1 "$DEPLOY_SCRIPT")
    [[ "$first_line" == "#!/bin/bash" ]] && print_pass "Shebang is correct (#!/bin/bash)" || print_fail "Shebang is incorrect: $first_line"
}

test_deployment_script_safety_flags() {
    run_test "Deployment script has safety flags (set -euo pipefail)"
    grep -q "^set -euo pipefail" "$DEPLOY_SCRIPT" && print_pass "Safety flags present" || print_fail "Safety flags missing"
}

test_deployment_script_syntax() {
    run_test "Deployment script has valid bash syntax"
    if bash -n "$DEPLOY_SCRIPT" 2>/dev/null; then
        print_pass "Deployment script syntax is valid"
    else
        print_fail "Deployment script has syntax errors"
        bash -n "$DEPLOY_SCRIPT"
    fi
}

test_deployment_script_size() {
    run_test "Deployment script LOC (target ~300)"
    local line_count
    line_count=$(wc -l < "$DEPLOY_SCRIPT")
    if [[ $line_count -le 300 ]]; then
        print_pass "Deployment script is $line_count LOC (limit: 300)"
    else
        print_warn "Deployment script is $line_count LOC (exceeds indicative limit: 300)"
    fi
}

test_config_management_functions() {
    run_test "Deployment script has config management functions"
    local required_functions=("init_config" "load_config" "save_config" "validate_config")
    local all_exist=true
    for func in "${required_functions[@]}"; do
        if grep -qE "^[[:space:]]*(function[[:space:]]+)?${func}\(\)" "$DEPLOY_SCRIPT"; then
            print_pass "$func() function exists"
        else
            print_fail "$func() function missing"
            all_exist=false
        fi
    done
}

test_task_execution_functions() {
    run_test "Deployment script has task delegation functions"
    local required_functions=(
        "execute_task_4_1" "execute_task_4_2" "execute_task_4_3" "execute_task_4_4"
        "execute_task_4_5" "execute_task_4_6" "execute_task_4_7"
    )
    local all_exist=true
    for func in "${required_functions[@]}"; do
        if grep -qE "^[[:space:]]*(function[[:space:]]+)?${func}\(\)" "$DEPLOY_SCRIPT"; then
            print_pass "$func() function exists"
        else
            print_fail "$func() function missing"
            all_exist=false
        fi
    done
}

test_validation_function() {
    run_test "Deployment script has inline validate_all with checks array"
    grep -qE "^[[:space:]]*(function[[:space:]]+)?validate_all\(\)" "$DEPLOY_SCRIPT" && print_pass "validate_all() exists" || print_fail "validate_all() missing"
    grep -q "local checks=" "$DEPLOY_SCRIPT" && print_pass "validate_all uses checks array pattern" || print_fail "validate_all missing checks array"
    # Validation helper functions in sourced utils file
    local UTILS_FILE="scripts/operations/utils/validation-photo-management-utils.sh"
    [[ -f "$UTILS_FILE" ]] && print_pass "validation-photo-management-utils.sh exists" || print_fail "validation-photo-management-utils.sh missing"
    grep -q "validate_immich_containers" "$UTILS_FILE" && print_pass "Has container validation" || print_fail "Missing container validation"
    grep -q "validate_version_pinned" "$UTILS_FILE" && print_pass "Has version pinning check" || print_fail "Missing version pinning check"
    grep -q "validate_secrets_not_tracked" "$UTILS_FILE" && print_pass "Has secrets tracking check" || print_fail "Missing secrets tracking check"
}

test_interactive_menu() {
    run_test "Deployment script has interactive menu"
    grep -qE "^[[:space:]]*(function[[:space:]]+)?main_menu\(\)" "$DEPLOY_SCRIPT" && print_pass "main_menu() exists" || print_fail "main_menu() missing"
}

test_dry_run_support() {
    run_test "Deployment script has dry-run support"
    grep -q "DRY_RUN" "$DEPLOY_SCRIPT" && print_pass "Dry-run support implemented" || print_fail "Dry-run support missing"
    grep -q "\-\-dry-run" "$DEPLOY_SCRIPT" && print_pass "--dry-run flag handled" || print_fail "--dry-run flag not handled"
}

test_root_check() {
    run_test "Deployment script checks for root privileges"
    grep -q "EUID.*-ne.*0" "$DEPLOY_SCRIPT" && print_pass "Root check implemented" || print_fail "Root check missing"
}

test_utility_library_sourcing() {
    run_test "Deployment script sources utility libraries"
    local required_sources=("output-utils.sh" "env-utils.sh" "validation-photo-management-utils.sh")
    for source_file in "${required_sources[@]}"; do
        grep -q "source.*$source_file" "$DEPLOY_SCRIPT" && print_pass "Sources $source_file" || print_fail "Does not source $source_file"
    done
}

test_config_file_references() {
    run_test "Deployment script references foundation.env and services.env"
    grep -q "foundation.env" "$DEPLOY_SCRIPT" && print_pass "References foundation.env" || print_fail "Missing foundation.env reference"
    grep -q "services.env" "$DEPLOY_SCRIPT" && print_pass "References services.env" || print_fail "Missing services.env reference"
}

test_immich_config_variables() {
    run_test "Deployment script references Immich config variables"
    local required_vars=("IMMICH_VERSION" "IMMICH_DOMAIN" "IMMICH_PORT" "MEDIA_GROUP_GID" "UPLOAD_LOCATION" "DB_DATA_LOCATION" "DB_USERNAME" "DB_DATABASE_NAME")
    for var in "${required_vars[@]}"; do
        grep -q "$var" "$DEPLOY_SCRIPT" && print_pass "Variable $var referenced" || print_fail "Variable $var missing"
    done
}

test_task_module_delegation() {
    run_test "Task functions delegate to task-ph4-*.sh modules"
    local task_modules=(
        "task-ph4-01" "task-ph4-02" "task-ph4-03" "task-ph4-04"
        "task-ph4-05" "task-ph4-06" "task-ph4-07"
    )
    for module in "${task_modules[@]}"; do
        grep -q "$module" "$DEPLOY_SCRIPT" && print_pass "Delegates to $module" || print_fail "Missing delegation to $module"
    done
}

# --- services.env.example Tests ---

test_services_env_immich_vars() {
    run_test "services.env.example has Immich configuration variables"
    local config_file="configs/services.env.example"
    [[ -f "$config_file" ]] || { print_fail "services.env.example not found"; return; }
    local required_vars=("IMMICH_VERSION" "IMMICH_DOMAIN" "IMMICH_PORT" "MEDIA_GROUP_GID" "UPLOAD_LOCATION" "DB_DATA_LOCATION" "DB_USERNAME" "DB_DATABASE_NAME")
    for var in "${required_vars[@]}"; do
        grep -q "$var" "$config_file" && print_pass "$var in services.env.example" || print_fail "$var missing from services.env.example"
    done
}

test_services_env_uuid_placeholders() {
    run_test "services.env.example has UUID mapping placeholders"
    local config_file="configs/services.env.example"
    grep -q "IMMICH_UUID_" "$config_file" && print_pass "UUID mapping placeholders present" || print_fail "UUID mapping placeholders missing"
}

test_secrets_env_immich_vars() {
    run_test "secrets.env.example has Immich secrets"
    local config_file="configs/secrets.env.example"
    [[ -f "$config_file" ]] || { print_fail "secrets.env.example not found"; return; }
    grep -q "IMMICH_DB_PASSWORD\|DB_PASSWORD" "$config_file" && print_pass "DB_PASSWORD in secrets.env.example" || print_fail "DB_PASSWORD missing"
    grep -q "IMMICH_API_KEY" "$config_file" && print_pass "IMMICH_API_KEY in secrets.env.example" || print_fail "IMMICH_API_KEY missing"
}

test_secrets_env_not_in_git() {
    run_test "secrets.env is excluded from Git"
    (grep -q "secrets.env" .gitignore || grep -q "\*.env" .gitignore) && print_pass "secrets.env in .gitignore" || print_fail "secrets.env not in .gitignore"
}

# --- Task Module Pattern Tests ---

test_dns_script_json_building() {
    run_test "DNS script builds valid JSON array (not naive sed append)"
    local dns_script="scripts/deploy/tasks/task-ph4-04-configure-dns.sh"
    [[ -f "$dns_script" ]] || { print_fail "task-ph4-04-configure-dns.sh not found"; return; }
    # Must NOT use the old fragile sed pattern that mixes quoted/unquoted entries
    if grep -q 'sed.*s/\].*DNS_RECORD.*\]' "$dns_script"; then
        print_fail "DNS script uses fragile sed append (should rebuild full JSON array)"
    else
        print_pass "DNS script does not use fragile sed append"
    fi
    # Must rebuild array with proper quoting (ENTRIES array pattern)
    grep -q 'ENTRIES=()' "$dns_script" && print_pass "DNS script rebuilds array from scratch (ENTRIES pattern)" || print_fail "DNS script missing ENTRIES array rebuild"
    grep -q 'NEW_HOSTS_JSON' "$dns_script" && print_pass "DNS script builds NEW_HOSTS_JSON" || print_fail "DNS script missing NEW_HOSTS_JSON build"
}

# --- Docker Compose Example Tests ---

test_docker_compose_example_exists() {
    run_test "immich.yml.example exists with key Immich v2 patterns"
    local compose_file="configs/docker-compose/immich.yml.example"
    [[ -f "$compose_file" ]] || compose_file="configs/docker-compose/immich.yml"
    [[ -f "$compose_file" ]] || { print_fail "immich.yml.example not found"; return; }
    print_pass "immich.yml exists"
    grep -q "immich-healthcheck" "$compose_file" && print_pass "Uses immich-healthcheck (v2 pattern)" || print_fail "Missing immich-healthcheck"
    grep -q "valkey" "$compose_file" && print_pass "Uses Valkey (v2 Redis replacement)" || print_fail "Missing Valkey reference"
    grep -q "UPLOAD_LOCATION.*:/data" "$compose_file" && print_pass "Volume mount uses :/data (v2 path)" || print_fail "Missing :/data volume mount"
    grep -q "POSTGRES_INITDB_ARGS" "$compose_file" && print_pass "Has POSTGRES_INITDB_ARGS" || print_fail "Missing POSTGRES_INITDB_ARGS"
    grep -q "shm_size" "$compose_file" && print_pass "Has shm_size for postgres" || print_fail "Missing shm_size"
    grep -q "model-cache" "$compose_file" && print_pass "Uses named model-cache volume" || print_fail "Missing model-cache volume"
}

# --- Main ---

main() {
    echo "========================================"
    echo "Phase 4 Photo Management Scripts Test Suite"
    echo "========================================"

    test_deployment_script_exists || true
    test_deployment_script_shebang || true
    test_deployment_script_safety_flags || true
    test_deployment_script_syntax || true
    test_deployment_script_size || true
    test_config_management_functions || true
    test_task_execution_functions || true
    test_validation_function || true
    test_interactive_menu || true
    test_dry_run_support || true
    test_root_check || true
    test_utility_library_sourcing || true
    test_config_file_references || true
    test_immich_config_variables || true
    test_task_module_delegation || true
    test_dns_script_json_building || true
    test_services_env_immich_vars || true
    test_services_env_uuid_placeholders || true
    test_secrets_env_immich_vars || true
    test_secrets_env_not_in_git || true
    test_docker_compose_example_exists || true

    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo "$TESTS_PASSED / $((TESTS_PASSED + TESTS_FAILED)) assertions passed across $TESTS_RUN test suites"
    echo "========================================"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
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

main
