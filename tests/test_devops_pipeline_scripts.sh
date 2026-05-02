#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: New Scripts Follow Bash Standards (Property 2)
# Feature: devops-cicd-pipeline, Property 2: New scripts follow bash standards
# Purpose: For deploy-update.sh and check-drift.sh: verify #!/bin/bash first line,
#          set -euo pipefail in first 5 lines, passes bash -n
# Validates: Requirements 5.4, 5.5, 12.12
# Usage: bash tests/test_devops_pipeline_scripts.sh

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

# Scripts created by the devops-cicd-pipeline spec
SCRIPTS=(
    "scripts/operations/utils/deploy-update.sh"
    "scripts/operations/monitoring/check-drift.sh"
)

echo "========================================"
echo "Property 2: New Scripts Follow Bash Standards"
echo "========================================"
echo ""

for script_rel in "${SCRIPTS[@]}"; do
    script_path="${REPO_ROOT}/${script_rel}"
    script_name="$(basename "$script_rel")"

    echo "--- ${script_name} ---"

    # Check if script exists (check-drift.sh may not exist yet)
    if [[ ! -f "$script_path" ]]; then
        echo -e "${YELLOW}ℹ${NC} ${script_name} not yet created — skipped"
        echo ""
        continue
    fi

    # Check 1: First line is #!/bin/bash
    TESTS_RUN=$((TESTS_RUN + 1))
    first_line="$(head -n 1 "$script_path")"
    if [[ "$first_line" == "#!/bin/bash" ]]; then
        print_pass "${script_name}: shebang is #!/bin/bash"
    else
        print_fail "${script_name}: first line is '${first_line}', expected '#!/bin/bash'"
    fi

    # Check 2: set -euo pipefail in first 5 lines
    TESTS_RUN=$((TESTS_RUN + 1))
    if head -n 5 "$script_path" | grep -q 'set -euo pipefail'; then
        print_pass "${script_name}: set -euo pipefail found in first 5 lines"
    else
        print_fail "${script_name}: set -euo pipefail NOT found in first 5 lines"
    fi

    # Check 3: Valid bash syntax (bash -n)
    TESTS_RUN=$((TESTS_RUN + 1))
    if bash -n "$script_path" 2>/dev/null; then
        print_pass "${script_name}: passes bash -n syntax check"
    else
        print_fail "${script_name}: fails bash -n syntax check"
    fi

    echo ""
done

echo "========================================"
echo "Property 2 Summary"
echo "========================================"
echo "Checks run:  $TESTS_RUN"
echo -e "Passed:      ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_RUN -eq 0 ]]; then
    echo -e "${YELLOW}ℹ No scripts created yet — property holds vacuously${NC}"
    exit 0
elif [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 2 holds: all new scripts follow bash standards${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 2 violated: ${TESTS_FAILED} check(s) failed${NC}"
    exit 1
fi
