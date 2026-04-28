#!/usr/bin/env bash
# Test Suite: Phase 5 Wiki + LLM Platform Scripts
# Purpose: Validate Phase 5 deployment script structure and conventions
# Requirements: 17.1-17.10, 18.2, 18.3
# Usage: bash tests/test_phase5_scripts.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0; FAILED_MESSAGES=()

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_MESSAGES+=("$1"); }
print_warn() { echo -e "${YELLOW}⚠ WARN${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
run_test() { TESTS_RUN=$((TESTS_RUN + 1)); echo ""; echo "Test $TESTS_RUN: $1"; echo "----------------------------------------"; }

DEPLOY_SCRIPT="scripts/deploy/deploy-phase5-wiki-llm.sh"
UTILS_FILE="scripts/operations/utils/validation-wiki-llm-utils.sh"

# --- Deployment Script Tests ---

test_deployment_script_exists() {
    run_test "Deployment script exists"
    [[ -f "$DEPLOY_SCRIPT" ]] && print_pass "Deployment script exists" || print_fail "Deployment script does not exist"
}

test_deployment_script_shebang() {
    run_test "Deployment script has proper shebang"
    local first_line; first_line=$(head -n 1 "$DEPLOY_SCRIPT")
    [[ "$first_line" == "#!/bin/bash" ]] && print_pass "Shebang is correct" || print_fail "Shebang incorrect: $first_line"
}

test_deployment_script_safety_flags() {
    run_test "Deployment script has safety flags (set -euo pipefail)"
    grep -q "^set -euo pipefail" "$DEPLOY_SCRIPT" && print_pass "Safety flags present" || print_fail "Safety flags missing"
}

test_deployment_script_syntax() {
    run_test "Deployment script has valid bash syntax"
    bash -n "$DEPLOY_SCRIPT" 2>/dev/null && print_pass "Syntax valid" || print_fail "Syntax errors found"
}

test_deployment_script_size() {
    run_test "Deployment script LOC (target ~300)"
    local line_count; line_count=$(wc -l < "$DEPLOY_SCRIPT")
    if [[ $line_count -le 300 ]]; then
        print_pass "Deployment script is $line_count LOC (limit: 300)"
    else
        print_warn "Deployment script is $line_count LOC (exceeds indicative limit: 300)"
    fi
}

test_config_management_functions() {
    run_test "Deployment script has config management functions"
    for func in init_config load_config save_config validate_config; do
        grep -qE "^[[:space:]]*(function[[:space:]]+)?${func}\(\)" "$DEPLOY_SCRIPT" && print_pass "$func() exists" || print_fail "$func() missing"
    done
}

test_task_execution_functions() {
    run_test "Deployment script has task delegation functions"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
        grep -qE "^[[:space:]]*(function[[:space:]]+)?execute_task_5_${i}\(\)" "$DEPLOY_SCRIPT" && print_pass "execute_task_5_${i}() exists" || print_fail "execute_task_5_${i}() missing"
    done
}

test_validation_function() {
    run_test "Deployment script has validate_all with checks array"
    grep -qE "^[[:space:]]*(function[[:space:]]+)?validate_all\(\)" "$DEPLOY_SCRIPT" && print_pass "validate_all() exists" || print_fail "validate_all() missing"
    grep -q "PHASE5_CHECKS" "$DEPLOY_SCRIPT" && print_pass "Uses PHASE5_CHECKS array" || print_fail "Missing PHASE5_CHECKS reference"
    [[ -f "$UTILS_FILE" ]] && print_pass "validation-wiki-llm-utils.sh exists" || print_fail "validation-wiki-llm-utils.sh missing"
    grep -q "validate_wiki_server_container" "$UTILS_FILE" && print_pass "Has wiki container validation" || print_fail "Missing wiki container validation"
    grep -q "validate_ollama_internal_only" "$UTILS_FILE" && print_pass "Has Ollama internal-only check" || print_fail "Missing Ollama internal-only check"
    grep -q "validate_secrets_not_tracked" "$UTILS_FILE" && print_pass "Has secrets tracking check" || print_fail "Missing secrets tracking check"
}

test_interactive_menu() {
    run_test "Deployment script has interactive menu"
    grep -qE "^[[:space:]]*(function[[:space:]]+)?main_menu\(\)" "$DEPLOY_SCRIPT" && print_pass "main_menu() exists" || print_fail "main_menu() missing"
    grep -q "Sub-phase A" "$DEPLOY_SCRIPT" && print_pass "Menu has Sub-phase A section" || print_fail "Menu missing Sub-phase A"
    grep -q "Sub-phase B" "$DEPLOY_SCRIPT" && print_pass "Menu has Sub-phase B section" || print_fail "Menu missing Sub-phase B"
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
    for source_file in output-utils.sh env-utils.sh validation-wiki-llm-utils.sh; do
        grep -q "source.*$source_file" "$DEPLOY_SCRIPT" && print_pass "Sources $source_file" || print_fail "Does not source $source_file"
    done
}

test_config_file_references() {
    run_test "Deployment script references config files"
    grep -q "foundation.env" "$DEPLOY_SCRIPT" && print_pass "References foundation.env" || print_fail "Missing foundation.env"
    grep -q "services.env" "$DEPLOY_SCRIPT" && print_pass "References services.env" || print_fail "Missing services.env"
    grep -q "secrets.env" "$DEPLOY_SCRIPT" && print_pass "References secrets.env" || print_fail "Missing secrets.env"
}

test_phase5_config_variables() {
    run_test "Deployment script references Phase 5 config variables"
    for var in WIKI_DOMAIN WIKI_PORT WIKI_DB_USER WIKI_DB_NAME OLLAMA_DEFAULT_MODEL OPENWEBUI_DOMAIN OPENWEBUI_PORT; do
        grep -q "$var" "$DEPLOY_SCRIPT" && print_pass "Variable $var referenced" || print_fail "Variable $var missing"
    done
}

test_task_module_delegation() {
    run_test "Task functions delegate to task-ph5-*.sh modules"
    for module in task-ph5-01 task-ph5-02 task-ph5-03 task-ph5-04 task-ph5-05 task-ph5-06 task-ph5-07 task-ph5-08 task-ph5-09 task-ph5-10 task-ph5-11 task-ph5-12 task-ph5-13 task-ph5-14; do
        grep -q "$module" "$DEPLOY_SCRIPT" && print_pass "Delegates to $module" || print_fail "Missing delegation to $module"
    done
}

test_governance_validation() {
    run_test "Deployment script runs governance validation"
    grep -q "validate-governance.sh" "$DEPLOY_SCRIPT" && print_pass "Governance validation present" || print_fail "Governance validation missing"
}

# --- services.env.example Tests ---

test_services_env_wiki_vars() {
    run_test "services.env.example has Wiki.js configuration variables"
    local config_file="configs/services.env.example"
    [[ -f "$config_file" ]] || { print_fail "services.env.example not found"; return; }
    for var in WIKI_DOMAIN WIKI_PORT WIKI_DB_USER WIKI_DB_NAME WIKI_MEM_LIMIT WIKI_CPU_LIMIT WIKI_DB_MEM_LIMIT WIKI_DB_CPU_LIMIT; do
        grep -q "$var" "$config_file" && print_pass "$var in services.env.example" || print_fail "$var missing"
    done
}

test_services_env_ollama_vars() {
    run_test "services.env.example has Ollama configuration variables"
    local config_file="configs/services.env.example"
    for var in OLLAMA_DEFAULT_MODEL OLLAMA_VERSION OLLAMA_MEM_LIMIT OLLAMA_CPU_LIMIT; do
        grep -q "$var" "$config_file" && print_pass "$var in services.env.example" || print_fail "$var missing"
    done
}

test_services_env_openwebui_vars() {
    run_test "services.env.example has Open WebUI configuration variables"
    local config_file="configs/services.env.example"
    for var in OPENWEBUI_VERSION OPENWEBUI_DOMAIN OPENWEBUI_PORT OPENWEBUI_MEM_LIMIT OPENWEBUI_CPU_LIMIT ENABLE_WEB_SEARCH WEB_SEARCH_ENGINE; do
        grep -q "$var" "$config_file" && print_pass "$var in services.env.example" || print_fail "$var missing"
    done
}

test_services_env_external_llm_commented() {
    run_test "services.env.example has commented-out external LLM provider variables"
    local config_file="configs/services.env.example"
    grep -q "# OPENAI_API_KEY\|# ANTHROPIC_API_KEY\|# AWS_BEDROCK" "$config_file" && print_pass "External LLM vars commented out" || print_fail "External LLM vars missing"
}

test_secrets_env_phase5_vars() {
    run_test "secrets.env.example has Phase 5 secrets"
    local config_file="configs/secrets.env.example"
    [[ -f "$config_file" ]] || { print_fail "secrets.env.example not found"; return; }
    grep -q "WIKI_DB_PASSWORD" "$config_file" && print_pass "WIKI_DB_PASSWORD present" || print_fail "WIKI_DB_PASSWORD missing"
    grep -q "WIKI_API_TOKEN" "$config_file" && print_pass "WIKI_API_TOKEN present" || print_fail "WIKI_API_TOKEN missing"
    grep -q "OPENWEBUI_API_TOKEN" "$config_file" && print_pass "OPENWEBUI_API_TOKEN present" || print_fail "OPENWEBUI_API_TOKEN missing"
}

test_secrets_env_not_in_git() {
    run_test "secrets.env is excluded from Git"
    (grep -q "secrets.env" .gitignore || grep -q "\*.env" .gitignore) && print_pass "secrets.env in .gitignore" || print_fail "secrets.env not in .gitignore"
}

# --- Docker Compose Example Tests ---

test_wiki_compose_example() {
    run_test "wiki.yml.example exists with correct patterns"
    local compose_file="configs/docker-compose/wiki.yml.example"
    [[ -f "$compose_file" ]] || { print_fail "wiki.yml.example not found"; return; }
    print_pass "wiki.yml.example exists"
    grep -q "ghcr.io/requarks/wiki:2" "$compose_file" && print_pass "Wiki.js v2 image pinned" || print_fail "Wiki.js image not pinned to v2"
    grep -q "postgres:15-alpine" "$compose_file" && print_pass "PostgreSQL 15 alpine" || print_fail "PostgreSQL image incorrect"
    grep -q "unless-stopped" "$compose_file" && print_pass "Restart policy set" || print_fail "Restart policy missing"
    grep -q "homeserver" "$compose_file" && print_pass "Homeserver network" || print_fail "Homeserver network missing"
    grep -q "healthcheck" "$compose_file" && print_pass "Healthcheck present" || print_fail "Healthcheck missing"
    grep -q "shm_size" "$compose_file" && print_pass "shm_size for postgres" || print_fail "shm_size missing"
    grep -q "WIKI_DB_PASSWORD" "$compose_file" && print_pass "Uses WIKI_DB_PASSWORD" || print_fail "WIKI_DB_PASSWORD not referenced"
}

test_ollama_compose_example() {
    run_test "ollama.yml.example exists with correct patterns"
    local compose_file="configs/docker-compose/ollama.yml.example"
    [[ -f "$compose_file" ]] || { print_fail "ollama.yml.example not found"; return; }
    print_pass "ollama.yml.example exists"
    grep -q "ollama/ollama" "$compose_file" && print_pass "Ollama image" || print_fail "Ollama image missing"
    grep -q "open-webui/open-webui" "$compose_file" && print_pass "Open WebUI image" || print_fail "Open WebUI image missing"
    grep -q "ENABLE_SIGNUP.*false" "$compose_file" && print_pass "Self-registration disabled" || print_fail "Self-registration not disabled"
    grep -q "OLLAMA_BASE_URL.*ollama:11434" "$compose_file" && print_pass "Internal Ollama URL" || print_fail "Internal Ollama URL missing"
    grep -q "unless-stopped" "$compose_file" && print_pass "Restart policy set" || print_fail "Restart policy missing"
    grep -q "homeserver" "$compose_file" && print_pass "Homeserver network" || print_fail "Homeserver network missing"
    grep -q "healthcheck" "$compose_file" && print_pass "Healthcheck present" || print_fail "Healthcheck missing"
    # Verify Ollama port NOT published to host
    ! grep -q "11434:11434" "$compose_file" && print_pass "Ollama port NOT published to host" || print_fail "Ollama port published to host (should be internal only)"
}

# --- Validation Utils Tests ---

test_validation_utils_syntax() {
    run_test "Validation utils has valid bash syntax"
    bash -n "$UTILS_FILE" 2>/dev/null && print_pass "Syntax valid" || print_fail "Syntax errors found"
}

test_validation_utils_size() {
    run_test "Validation utils LOC (target ~200)"
    local line_count; line_count=$(wc -l < "$UTILS_FILE")
    if [[ $line_count -le 200 ]]; then
        print_pass "Validation utils is $line_count LOC (limit: 200)"
    else
        print_warn "Validation utils is $line_count LOC (exceeds indicative limit: 200)"
    fi
}

test_validation_utils_checks_array() {
    run_test "Validation utils defines PHASE5_CHECKS array"
    grep -q "PHASE5_CHECKS=" "$UTILS_FILE" && print_pass "PHASE5_CHECKS array defined" || print_fail "PHASE5_CHECKS array missing"
}

# --- Main ---

main() {
    echo "========================================"
    echo "Phase 5 Wiki + LLM Platform Scripts Test Suite"
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
    test_phase5_config_variables || true
    test_task_module_delegation || true
    test_governance_validation || true
    test_services_env_wiki_vars || true
    test_services_env_ollama_vars || true
    test_services_env_openwebui_vars || true
    test_services_env_external_llm_commented || true
    test_secrets_env_phase5_vars || true
    test_secrets_env_not_in_git || true
    test_wiki_compose_example || true
    test_ollama_compose_example || true
    test_validation_utils_syntax || true
    test_validation_utils_size || true
    test_validation_utils_checks_array || true

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
        echo ""; echo "Failed assertions:"
        for msg in "${FAILED_MESSAGES[@]}"; do echo -e "  ${RED}✗${NC} $msg"; done
        exit 1
    fi
}

main
