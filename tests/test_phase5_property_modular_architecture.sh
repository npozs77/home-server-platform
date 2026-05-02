#!/usr/bin/env bash
# Property Test: Deployment Script Modular Architecture (Property 13)
# Purpose: Verify orchestration script delegates to task-ph5-*.sh modules;
#          verify each task is a separate file in scripts/deploy/tasks/
# Validates: Requirements 18.2, 18.3
# Usage: bash tests/test_phase5_property_modular_architecture.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

ORCH_SCRIPT="scripts/deploy/deploy-phase5-wiki-llm.sh"
TASK_DIR="scripts/deploy/tasks"

echo "========================================"
echo "Property 13: Deployment Script Modular Architecture (Phase 5)"
echo "========================================"
echo ""

# --- Pre-check: orchestration script exists ---

if [[ ! -f "$ORCH_SCRIPT" ]]; then
    echo -e "${RED}✗ FATAL${NC}: Orchestration script not found: $ORCH_SCRIPT"
    exit 1
fi
echo "Using orchestration script: $ORCH_SCRIPT"
echo ""

ORCH_CONTENT=$(cat "$ORCH_SCRIPT")

# ============================================================
# 13a: Orchestration script follows three-layer architecture
# ============================================================

echo "--- 13a: Three-layer modular architecture ---"
echo ""

# Check 1: Orchestration script sources utility libraries
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$ORCH_CONTENT" | grep -q "source.*utils/output-utils.sh"; then
    print_pass "Orchestration sources output-utils.sh (utility library layer)"
else
    print_fail "Orchestration does NOT source output-utils.sh"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$ORCH_CONTENT" | grep -q "source.*utils/env-utils.sh"; then
    print_pass "Orchestration sources env-utils.sh (utility library layer)"
else
    print_fail "Orchestration does NOT source env-utils.sh"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$ORCH_CONTENT" | grep -q "source.*utils/validation-wiki-llm-utils.sh"; then
    print_pass "Orchestration sources validation-wiki-llm-utils.sh (Phase 5 validation)"
else
    print_fail "Orchestration does NOT source validation-wiki-llm-utils.sh"
fi

# Check 2: Orchestration has config management functions
TESTS_RUN=$((TESTS_RUN + 1))
CONFIG_FUNCS=0
for func in load_config save_config init_config validate_config; do
    echo "$ORCH_CONTENT" | grep -q "${func}()" && CONFIG_FUNCS=$((CONFIG_FUNCS + 1))
done
if [[ $CONFIG_FUNCS -eq 4 ]]; then
    print_pass "Orchestration has all 4 config management functions (load, save, init, validate)"
else
    print_fail "Orchestration missing config management functions (found $CONFIG_FUNCS/4)"
fi

# Check 3: Orchestration has interactive menu
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$ORCH_CONTENT" | grep -q "main_menu"; then
    print_pass "Orchestration has interactive menu (main_menu)"
else
    print_fail "Orchestration MISSING interactive menu"
fi

# ============================================================
# 13b: Task delegation — orchestration delegates to task modules
# ============================================================

echo ""
echo "--- 13b: Task delegation to task-ph5-*.sh modules ---"
echo ""

# Expected task modules that the orchestration script should delegate to
# (task-ph5-13 is documentation generation, handled directly — not in orchestration menu)
EXPECTED_TASKS=(
    "task-ph5-01-create-wiki-directories.sh"
    "task-ph5-02-deploy-wiki-stack.sh"
    "task-ph5-03-configure-wiki-caddy.sh"
    "task-ph5-04-configure-wiki-dns.sh"
    "task-ph5-05-provision-wiki-users.sh"
    "task-ph5-06-create-ollama-directories.sh"
    "task-ph5-07-deploy-llm-stack.sh"
    "task-ph5-08-pull-default-model.sh"
    "task-ph5-09-configure-chat-caddy.sh"
    "task-ph5-10-configure-chat-dns.sh"
    "task-ph5-11-provision-openwebui-users.sh"
    "task-ph5-12-deploy-backup-script.sh"
    "task-ph5-14-deploy-wiki-rag-sync.sh"
)

# Check each expected task is delegated via bash call in orchestration
DELEGATED=0
MISSING_DELEGATIONS=()
for task in "${EXPECTED_TASKS[@]}"; do
    if echo "$ORCH_CONTENT" | grep -q "$task"; then
        DELEGATED=$((DELEGATED + 1))
    else
        MISSING_DELEGATIONS+=("$task")
    fi
done

TESTS_RUN=$((TESTS_RUN + 1))
if [[ $DELEGATED -eq ${#EXPECTED_TASKS[@]} ]]; then
    print_pass "Orchestration delegates to all ${#EXPECTED_TASKS[@]} expected task modules"
else
    print_fail "Orchestration delegates to $DELEGATED/${#EXPECTED_TASKS[@]} task modules"
    for missing in "${MISSING_DELEGATIONS[@]}"; do
        echo "         Missing delegation: $missing"
    done
fi

# Check delegation uses bash command (not source/inline)
TESTS_RUN=$((TESTS_RUN + 1))
BASH_DELEGATIONS=$(echo "$ORCH_CONTENT" | grep -c "bash.*task-ph5-" || true)
if [[ $BASH_DELEGATIONS -ge ${#EXPECTED_TASKS[@]} ]]; then
    print_pass "All task delegations use 'bash' command (separate process, not sourced)"
else
    print_fail "Only $BASH_DELEGATIONS/${#EXPECTED_TASKS[@]} delegations use 'bash' command"
fi

# Check each delegation has an execute_task function wrapper
TESTS_RUN=$((TESTS_RUN + 1))
EXEC_FUNCS=$(echo "$ORCH_CONTENT" | grep -c "^execute_task_5_" || true)
if [[ $EXEC_FUNCS -ge ${#EXPECTED_TASKS[@]} ]]; then
    print_pass "Orchestration has $EXEC_FUNCS execute_task_5_* wrapper functions (>= ${#EXPECTED_TASKS[@]} tasks)"
else
    print_fail "Only $EXEC_FUNCS execute_task_5_* functions (expected >= ${#EXPECTED_TASKS[@]})"
fi

# ============================================================
# 13c: Each task is a separate file
# ============================================================

echo ""
echo "--- 13c: Each task is a separate file in $TASK_DIR ---"
echo ""

FOUND_FILES=0
MISSING_FILES=()
for task in "${EXPECTED_TASKS[@]}"; do
    if [[ -f "$TASK_DIR/$task" ]]; then
        FOUND_FILES=$((FOUND_FILES + 1))
    else
        MISSING_FILES+=("$task")
    fi
done

TESTS_RUN=$((TESTS_RUN + 1))
if [[ $FOUND_FILES -eq ${#EXPECTED_TASKS[@]} ]]; then
    print_pass "All ${#EXPECTED_TASKS[@]} task module files exist in $TASK_DIR"
else
    print_fail "Only $FOUND_FILES/${#EXPECTED_TASKS[@]} task module files found"
    for missing in "${MISSING_FILES[@]}"; do
        echo "         Missing file: $TASK_DIR/$missing"
    done
fi

# Check each task module has proper shebang and safety flags
echo ""
echo "--- 13d: Task module script standards ---"
echo ""

SHEBANG_OK=0
SAFETY_OK=0
TOTAL_MODULES=0
for task in "${EXPECTED_TASKS[@]}"; do
    local_path="$TASK_DIR/$task"
    [[ ! -f "$local_path" ]] && continue
    TOTAL_MODULES=$((TOTAL_MODULES + 1))
    head -1 "$local_path" | grep -q "#!/bin/bash\|#!/usr/bin/env bash" && SHEBANG_OK=$((SHEBANG_OK + 1))
    grep -q "set -euo pipefail" "$local_path" && SAFETY_OK=$((SAFETY_OK + 1))
done

TESTS_RUN=$((TESTS_RUN + 1))
if [[ $SHEBANG_OK -eq $TOTAL_MODULES ]]; then
    print_pass "All $TOTAL_MODULES task modules have proper bash shebang"
else
    print_fail "Only $SHEBANG_OK/$TOTAL_MODULES task modules have proper shebang"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if [[ $SAFETY_OK -eq $TOTAL_MODULES ]]; then
    print_pass "All $TOTAL_MODULES task modules have 'set -euo pipefail'"
else
    print_fail "Only $SAFETY_OK/$TOTAL_MODULES task modules have 'set -euo pipefail'"
fi

# Check each task module supports --dry-run
DRYRUN_OK=0
for task in "${EXPECTED_TASKS[@]}"; do
    local_path="$TASK_DIR/$task"
    [[ ! -f "$local_path" ]] && continue
    grep -q "dry.run\|DRY_RUN\|dry_run" "$local_path" && DRYRUN_OK=$((DRYRUN_OK + 1))
done

TESTS_RUN=$((TESTS_RUN + 1))
if [[ $DRYRUN_OK -eq $TOTAL_MODULES ]]; then
    print_pass "All $TOTAL_MODULES task modules support dry-run mode"
else
    print_fail "Only $DRYRUN_OK/$TOTAL_MODULES task modules support dry-run mode"
fi

# ============================================================
# 13e: No inline task implementation in orchestration
# ============================================================

echo ""
echo "--- 13e: No inline task implementation in orchestration ---"
echo ""

# Verify execute_task functions are thin wrappers (delegate, don't implement)
# Each execute_task function should be short — just load_config + bash call
TESTS_RUN=$((TESTS_RUN + 1))
INLINE_DOCKER=$(echo "$ORCH_CONTENT" | grep -c "docker compose\|docker exec\|docker run" || true)
# Allow docker references in validate_all or comments, but not in execute_task functions
TASK_FUNC_DOCKER=0
in_task_func=false
while IFS= read -r line; do
    if [[ "$line" =~ ^execute_task_5_ ]]; then
        in_task_func=true
    elif [[ "$in_task_func" == true && "$line" =~ ^\} ]]; then
        in_task_func=false
    elif [[ "$in_task_func" == true ]]; then
        if echo "$line" | grep -qE "docker compose|docker exec|docker run"; then
            TASK_FUNC_DOCKER=$((TASK_FUNC_DOCKER + 1))
        fi
    fi
done <<< "$ORCH_CONTENT"

if [[ $TASK_FUNC_DOCKER -eq 0 ]]; then
    print_pass "No docker commands in execute_task functions (properly delegated to modules)"
else
    print_fail "Found $TASK_FUNC_DOCKER docker commands inside execute_task functions (should be in task modules)"
fi

# ============================================================
# 13f: Orchestration passes dry-run flag to task modules
# ============================================================

echo ""
echo "--- 13f: Dry-run flag propagation ---"
echo ""

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$ORCH_CONTENT" | grep -q 'DRY_RUN=false'; then
    print_pass "Orchestration initializes DRY_RUN flag"
else
    print_fail "Orchestration MISSING DRY_RUN flag initialization"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$ORCH_CONTENT" | grep -q '\-\-dry-run'; then
    print_pass "Orchestration supports --dry-run CLI flag"
else
    print_fail "Orchestration MISSING --dry-run CLI support"
fi

TESTS_RUN=$((TESTS_RUN + 1))
DRYRUN_PROPAGATIONS=$(echo "$ORCH_CONTENT" | grep -c 'DRY_RUN.*--dry-run\|dry-run.*DRY_RUN' || true)
if [[ $DRYRUN_PROPAGATIONS -ge 1 ]]; then
    print_pass "Orchestration propagates --dry-run flag to task modules"
else
    print_fail "Orchestration does NOT propagate --dry-run to task modules"
fi

# ============================================================
# 13g: Governance validation before task execution
# ============================================================

echo ""
echo "--- 13g: Governance validation ---"
echo ""

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$ORCH_CONTENT" | grep -q "validate-governance.sh"; then
    print_pass "Orchestration runs governance validation before executing tasks"
else
    print_fail "Orchestration MISSING governance validation (validate-governance.sh)"
fi

# --- Summary ---

echo ""
echo "========================================"
echo "Modular Architecture Property Summary (Phase 5)"
echo "========================================"
echo "Checks run:  $TESTS_RUN"
echo -e "Passed:      ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:    ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 13 holds: Deployment follows three-layer modular architecture with task delegation${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 13 violated: Modular architecture requirements not fully met${NC}"
    exit 1
fi
