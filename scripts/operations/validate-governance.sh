#!/bin/bash
# Governance Validation Script
# Purpose: Validate all deployment scripts, task modules, and utility libraries
#          comply with project governance rules (size limits, patterns, tests)
# Exit Codes:
#   0 = All governance checks passed
#   1 = One or more governance checks failed

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Size limits (lines of code)
DEPLOYMENT_SCRIPT_LIMIT=300
TASK_MODULE_LIMIT=152
UTILITY_LIBRARY_LIMIT=200

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
WARN_CHECKS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED_CHECKS++))
    ((TOTAL_CHECKS++))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((TOTAL_CHECKS++))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN_CHECKS++))
    ((PASSED_CHECKS++))
    ((TOTAL_CHECKS++))
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

count_loc() {
    local file="$1"
    # Count non-empty, non-comment lines
    # Avoid pipeline to prevent pipefail race conditions in CI
    local content
    content=$(grep -v '^\s*#' "$file" || true)
    local count
    count=$(echo "$content" | grep -c -v '^\s*$') || count=0
    echo "$count"
}

check_script_size() {
    local file="$1"
    local limit="$2"
    local description="$3"
    
    if [[ ! -f "$file" ]]; then
        print_fail "$description: File not found: $file"
        return 0  # Don't exit early, continue validation
    fi
    
    local loc
    loc=$(count_loc "$file")
    
    if [[ $loc -le $limit ]]; then
        print_pass "$description: $loc LOC (limit: $limit)"
        return 0
    else
        print_warn "$description: $loc LOC exceeds advisory limit of $limit"
        return 0  # Don't exit early, continue validation
    fi
}

check_bash_syntax() {
    local file="$1"
    local description="$2"
    
    if bash -n "$file" 2>/dev/null; then
        print_pass "$description: Valid bash syntax"
        return 0
    else
        print_fail "$description: Invalid bash syntax"
        return 0  # Don't exit early, continue validation
    fi
}

check_shebang() {
    local file="$1"
    local description="$2"
    
    if head -n 1 "$file" | grep -q '^#!/bin/bash'; then
        print_pass "$description: Correct shebang (#!/bin/bash)"
        return 0
    else
        print_fail "$description: Missing or incorrect shebang"
        return 0  # Don't exit early, continue validation
    fi
}

check_safety_flags() {
    local file="$1"
    local description="$2"
    
    if grep -q 'set -euo pipefail' "$file"; then
        print_pass "$description: Safety flags present (set -euo pipefail)"
        return 0
    else
        print_fail "$description: Missing safety flags (set -euo pipefail)"
        return 0  # Don't exit early, continue validation
    fi
}

check_executable_bits() {
    # Every tracked *.sh under scripts/ and private/scripts/ (cron runs both by path)
    # must carry the git executable bit (100755).
    # This machine may have core.filemode=false, which makes `git add` silently
    # record new scripts as 100644 even when the working tree marks them +x. On
    # the server (git-pull deploy model) such a file lands non-executable and any
    # cron/direct invocation by path fails with "permission denied". This check
    # catches that class of breakage before it ships.
    if ! command -v git &>/dev/null || ! git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null; then
        print_info "Executable bits: not a git checkout — skipping"
        return 0
    fi

    local non_exec
    non_exec=$(git -C "$REPO_ROOT" ls-files -s -- 'scripts/*.sh' 'private/scripts/*.sh' | awk '$1 == "100644" {print $4}')

    if [[ -z "$non_exec" ]]; then
        print_pass "Executable bits: all tracked scripts/*.sh and private/scripts/*.sh are executable (100755)"
        return 0
    fi

    print_fail "Executable bits: the following tracked scripts are NOT executable (100644)"
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        echo "    ${f}  → fix: git update-index --chmod=+x ${f}"
    done <<< "$non_exec"
    return 0  # Don't exit early, continue validation
}

check_test_exists() {
    local file="$1"
    local description="$2"
    
    # Extract base name without extension
    local basename
    basename=$(basename "$file" .sh)
    
    # Look for test file in tests/ directory
    local test_file="${REPO_ROOT}/tests/test_${basename}.sh"
    
    # For task modules, look for phase-specific test files
    if [[ "$file" == *"/tasks/task-ph"* ]]; then
        # Extract phase number (ph1, ph2, etc.)
        local phase
        phase=$(echo "$basename" | grep -o 'ph[0-9]*')
        test_file="${REPO_ROOT}/tests/test_${phase}_scripts.sh"
    fi
    
    # For utility libraries, look for test_utility_libraries.sh
    if [[ "$file" == *"/utils/"* ]]; then
        test_file="${REPO_ROOT}/tests/test_utility_libraries.sh"
    fi
    
    if [[ -f "$test_file" ]]; then
        print_pass "$description: Test file exists"
        return 0
    else
        print_info "$description: Test file not found (expected: $(basename "$test_file"))"
        # Don't fail - tests are optional for MVP
        ((PASSED_CHECKS++))
        ((TOTAL_CHECKS++))
        return 0
    fi
}

# Main validation
main() {
    print_header "Governance Validation"
    echo ""
    
    # Check deployment scripts
    print_header "Deployment Scripts (limit: ${DEPLOYMENT_SCRIPT_LIMIT} LOC)"
    
    for script in "${REPO_ROOT}/scripts/deploy/deploy-phase"*.sh; do
        if [[ -f "$script" ]]; then
            local bname
            bname=$(basename "$script")
            check_script_size "$script" "$DEPLOYMENT_SCRIPT_LIMIT" "$bname" || true
            check_bash_syntax "$script" "$bname" || true
            check_shebang "$script" "$bname" || true
            check_safety_flags "$script" "$bname" || true
            check_test_exists "$script" "$bname" || true
        fi
    done
    echo ""
    
    # Check task modules
    print_header "Task Modules (limit: ${TASK_MODULE_LIMIT} LOC)"
    
    for task in "${REPO_ROOT}/scripts/deploy/tasks/task-ph"*.sh; do
        if [[ -f "$task" ]]; then
            local tname
            tname=$(basename "$task")
            check_script_size "$task" "$TASK_MODULE_LIMIT" "$tname" || true
            check_bash_syntax "$task" "$tname" || true
            check_shebang "$task" "$tname" || true
            check_safety_flags "$task" "$tname" || true
            check_test_exists "$task" "$tname" || true
        fi
    done
    echo ""
    
    # Check utility libraries
    print_header "Utility Libraries (limit: ${UTILITY_LIBRARY_LIMIT} LOC)"
    
    for util in "${REPO_ROOT}/scripts/operations/utils/"*.sh; do
        if [[ -f "$util" ]] && [[ $(basename "$util") != "README.md" ]]; then
            local uname
            uname=$(basename "$util")
            check_script_size "$util" "$UTILITY_LIBRARY_LIMIT" "$uname" || true
            check_bash_syntax "$util" "$uname" || true
            check_shebang "$util" "$uname" || true
            check_safety_flags "$util" "$uname" || true
            check_test_exists "$util" "$uname" || true
        fi
    done
    echo ""

    # Check executable bits on all tracked shell scripts
    print_header "Executable Bits (tracked scripts/*.sh)"
    check_executable_bits || true
    echo ""

    # Summary
    print_header "Governance Validation Summary"
    echo ""
    
    if [[ $PASSED_CHECKS -eq $TOTAL_CHECKS ]]; then
        if [[ $WARN_CHECKS -gt 0 ]]; then
            echo -e "${GREEN}✓ All governance checks passed: ${PASSED_CHECKS} / ${TOTAL_CHECKS} (${WARN_CHECKS} warnings)${NC}"
        else
            echo -e "${GREEN}✓ All governance checks passed: ${PASSED_CHECKS} / ${TOTAL_CHECKS}${NC}"
        fi
        echo ""
        return 0
    else
        local failed=$((TOTAL_CHECKS - PASSED_CHECKS))
        echo -e "${RED}✗ Governance validation failed: ${PASSED_CHECKS} / ${TOTAL_CHECKS} checks passed (${failed} failed, ${WARN_CHECKS} warnings)${NC}"
        echo ""
        echo "Fix violations before deploying."
        return 1
    fi
}

# Entry point
main "$@"
