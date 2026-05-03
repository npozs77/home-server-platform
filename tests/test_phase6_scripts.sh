#!/usr/bin/env bash
# CI_SAFE=true
# Test Suite: Phase 6 Docker Service Helper Scripts
# Purpose: Validate Phase 6 script structure, conventions, and function existence
# Requirements: 17.1–17.8
# Usage: bash tests/test_phase6_scripts.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0; FAILED_MESSAGES=()

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_MESSAGES+=("$1"); }
run_test() { TESTS_RUN=$((TESTS_RUN + 1)); echo ""; echo "Test $TESTS_RUN: $1"; echo "----------------------------------------"; }

HELPER="scripts/docker-helper/docker-service-helper.sh"
COMPOSE_GEN="scripts/docker-helper/lib/compose-gen.sh"
SERVICE_OPS="scripts/docker-helper/lib/service-ops.sh"
DEPLOY_SCRIPT="scripts/deploy/deploy-phase6-docker-helper.sh"
VALIDATION_UTILS="scripts/operations/utils/validation-docker-helper-utils.sh"
EXAMPLE_YML="configs/helper-services/services.yml.example"
CADDY_TPL="scripts/docker-helper/templates/caddy-block.template"

# --- Script existence ---

test_scripts_exist() {
    run_test "All Phase 6 scripts exist"
    for f in "$HELPER" "$COMPOSE_GEN" "$SERVICE_OPS" "$DEPLOY_SCRIPT" "$VALIDATION_UTILS" "$CADDY_TPL"; do
        [[ -f "$f" ]] && print_pass "Exists: $f" || print_fail "Missing: $f"
    done
}

# --- Executable checks ---

test_scripts_executable() {
    run_test "Helper scripts are executable"
    for f in "$HELPER" "$COMPOSE_GEN" "$SERVICE_OPS" "$DEPLOY_SCRIPT" "$VALIDATION_UTILS"; do
        [[ -x "$f" ]] && print_pass "Executable: $f" || print_fail "Not executable: $f"
    done
}

# --- Shebang ---

test_shebangs() {
    run_test "All scripts have proper shebang"
    for f in "$HELPER" "$COMPOSE_GEN" "$SERVICE_OPS" "$DEPLOY_SCRIPT" "$VALIDATION_UTILS"; do
        local first; first=$(head -n 1 "$f")
        [[ "$first" == "#!/bin/bash" ]] && print_pass "Shebang OK: $(basename "$f")" || print_fail "Bad shebang in $(basename "$f"): $first"
    done
}

# --- Safety flags ---

test_safety_flags() {
    run_test "All scripts have set -euo pipefail"
    for f in "$HELPER" "$COMPOSE_GEN" "$SERVICE_OPS" "$DEPLOY_SCRIPT" "$VALIDATION_UTILS"; do
        grep -q "set -euo pipefail" "$f" && print_pass "Safety flags: $(basename "$f")" || print_fail "Missing safety flags: $(basename "$f")"
    done
}

# --- Bash syntax ---

test_bash_syntax() {
    run_test "All scripts pass bash -n syntax check"
    for f in "$HELPER" "$COMPOSE_GEN" "$SERVICE_OPS" "$DEPLOY_SCRIPT" "$VALIDATION_UTILS"; do
        bash -n "$f" 2>/dev/null && print_pass "Syntax OK: $(basename "$f")" || print_fail "Syntax error: $(basename "$f")"
    done
}

# --- LOC limits ---

test_loc_limits() {
    run_test "Scripts within LOC limits"
    local loc
    loc=$(wc -l < "$HELPER"); (( loc <= 200 )) && print_pass "Helper: $loc LOC (limit 200)" || print_fail "Helper: $loc LOC exceeds 200"
    loc=$(wc -l < "$COMPOSE_GEN"); (( loc <= 210 )) && print_pass "compose-gen: $loc LOC (advisory limit 200)" || print_fail "compose-gen: $loc LOC exceeds 200"
    loc=$(wc -l < "$DEPLOY_SCRIPT"); (( loc <= 300 )) && print_pass "Deploy script: $loc LOC (limit 300)" || print_fail "Deploy script: $loc LOC exceeds 300"
    loc=$(wc -l < "$VALIDATION_UTILS"); (( loc <= 200 )) && print_pass "Validation utils: $loc LOC (limit 200)" || print_fail "Validation utils: $loc LOC exceeds 200"
}

# --- Function existence: compose-gen.sh ---

test_compose_gen_functions() {
    run_test "compose-gen.sh has generate_compose_file()"
    grep -q "generate_compose_file()" "$COMPOSE_GEN" && print_pass "generate_compose_file() exists" || print_fail "generate_compose_file() missing"
}

# --- Function existence: service-ops.sh ---

test_service_ops_functions() {
    run_test "service-ops.sh has all cmd_* functions"
    for fn in cmd_add cmd_remove cmd_update cmd_list cmd_validate cmd_logs cmd_stop cmd_start cmd_lint cmd_backup show_usage; do
        grep -q "${fn}()" "$SERVICE_OPS" && print_pass "${fn}() exists" || print_fail "${fn}() missing"
    done
}

# --- Function existence: deployment script ---

test_deploy_functions() {
    run_test "Deployment script has required functions"
    for fn in load_config validate_all validate_prerequisites main_menu; do
        grep -q "${fn}()" "$DEPLOY_SCRIPT" && print_pass "${fn}() exists" || print_fail "${fn}() missing"
    done
    for task in execute_task_6_1 execute_task_6_2 execute_task_6_3 execute_task_6_4 execute_task_6_7; do
        grep -q "${task}()" "$DEPLOY_SCRIPT" && print_pass "${task}() exists" || print_fail "${task}() missing"
    done
}

# --- Validation utils: PHASE6_CHECKS array ---

test_validation_checks_array() {
    run_test "Validation utils defines PHASE6_CHECKS array"
    grep -q "PHASE6_CHECKS=" "$VALIDATION_UTILS" && print_pass "PHASE6_CHECKS defined" || print_fail "PHASE6_CHECKS missing"
}

# --- validate-all.sh includes Phase 6 ---

test_validate_all_includes_phase6() {
    run_test "validate-all.sh sources Phase 6 validation"
    local va="scripts/operations/validate-all.sh"
    grep -q "validation-docker-helper-utils.sh" "$va" && print_pass "validate-all.sh sources Phase 6 utils" || print_fail "validate-all.sh missing Phase 6 source"
    grep -q 'run_phase 6' "$va" && print_pass "validate-all.sh runs Phase 6" || print_fail "validate-all.sh missing Phase 6 run_phase"
}

# --- Example services.yml.example ---

test_example_services() {
    run_test "services.yml.example has example service definitions"
    [[ -f "$EXAMPLE_YML" ]] || { print_fail "services.yml.example missing"; return; }
    grep -q "vocabgen" "$EXAMPLE_YML" && print_pass "VocabGen definition present" || print_fail "VocabGen missing"
    grep -q "musivault" "$EXAMPLE_YML" && print_pass "MusiVault definition present" || print_fail "MusiVault missing"
    grep -q "my-worker" "$EXAMPLE_YML" && print_pass "my-worker (no_proxy) definition present" || print_fail "my-worker missing"
}

# --- Dispatcher: no args shows usage ---

test_dispatcher_default_usage() {
    run_test "Dispatcher default case calls show_usage"
    grep -q 'show_usage' "$HELPER" && print_pass "Default case calls show_usage" || print_fail "Default case missing show_usage"
}

# --- Task modules exist ---

test_task_modules_exist() {
    run_test "Phase 6 task modules exist"
    for t in 01 02 03 04 06 07; do
        local f="scripts/deploy/tasks/task-ph6-${t}-*.sh"
        # shellcheck disable=SC2086
        ls $f >/dev/null 2>&1 && print_pass "task-ph6-${t} exists" || print_fail "task-ph6-${t} missing"
    done
}

# --- Run all tests ---

echo "========================================"
echo "Phase 6: Docker Service Helper — Unit Tests"
echo "========================================"

test_scripts_exist
test_scripts_executable
test_shebangs
test_safety_flags
test_bash_syntax
test_loc_limits
test_compose_gen_functions
test_service_ops_functions
test_deploy_functions
test_validation_checks_array
test_validate_all_includes_phase6
test_example_services
test_dispatcher_default_usage
test_task_modules_exist

echo ""
echo "========================================"
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for msg in "${FAILED_MESSAGES[@]}"; do echo "  - $msg"; done
    exit 1
fi

exit 0
