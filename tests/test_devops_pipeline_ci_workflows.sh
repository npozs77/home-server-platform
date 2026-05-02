#!/usr/bin/env bash
# CI_SAFE=true
# Property Tests: CI Workflow Properties (Properties 5 & 6)
# Feature: devops-cicd-pipeline
# Property 5: GitHub Actions steps are SHA-pinned
# Property 6: Mirror workflow strips all private-only files
# Validates: Requirements 8.7, 9.5, 9.8
# Usage: bash tests/test_devops_pipeline_ci_workflows.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CI_YML="${REPO_ROOT}/.github/workflows/ci.yml"
MIRROR_YML="${REPO_ROOT}/.github/workflows/mirror-public.yml"

echo "========================================"
echo "Properties 5 & 6: CI Workflow Checks"
echo "========================================"

# ============================================================
# Property 5: GitHub Actions steps are SHA-pinned
# ============================================================
echo ""
echo "--- Property 5: SHA-pinned actions ---"

WORKFLOW_FILES=("$CI_YML" "$MIRROR_YML")

for wf in "${WORKFLOW_FILES[@]}"; do
    wf_name=$(basename "$wf")
    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ ! -f "$wf" ]]; then
        print_fail "$wf_name not found"
        continue
    fi
    print_pass "$wf_name exists"

    # Extract all uses: directives and check each is SHA-pinned
    while IFS= read -r line; do
        # Extract the action reference (after 'uses:')
        action_ref=$(echo "$line" | sed 's/.*uses:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')
        TESTS_RUN=$((TESTS_RUN + 1))

        # Check version part (after @) is a 40-char hex SHA
        if echo "$action_ref" | grep -qE '@[0-9a-f]{40}'; then
            print_pass "$wf_name: $action_ref is SHA-pinned"
        else
            print_fail "$wf_name: $action_ref is NOT SHA-pinned (must use 40-char commit SHA)"
        fi
    done < <(grep 'uses:' "$wf")
done

# ============================================================
# Property 6: Mirror workflow strips all private-only files
# ============================================================
echo ""
echo "--- Property 6: Mirror strip list ---"

PRIVATE_ONLY_PATHS=(".kiro/" "input/" ".gitleaks.toml")

TESTS_RUN=$((TESTS_RUN + 1))
if [[ ! -f "$MIRROR_YML" ]]; then
    print_fail "mirror-public.yml not found — cannot verify strip list"
else
    print_pass "mirror-public.yml exists for strip list check"

    for path in "${PRIVATE_ONLY_PATHS[@]}"; do
        TESTS_RUN=$((TESTS_RUN + 1))
        if grep -q "git rm.*${path}" "$MIRROR_YML"; then
            print_pass "Mirror strips $path via git rm"
        else
            print_fail "Mirror does NOT strip $path — missing git rm command"
        fi
    done
fi

echo ""
echo "========================================"
echo "Properties 5 & 6 Summary"
echo "========================================"
echo "Checks run:  $TESTS_RUN"
echo -e "Passed:      ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Properties 5 & 6 hold${NC}"
    exit 0
else
    echo -e "${RED}✗ Property violation: ${TESTS_FAILED} check(s) failed${NC}"
    exit 1
fi
