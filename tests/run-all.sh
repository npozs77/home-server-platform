#!/bin/bash
# Run all test suites and report summary
# Usage: bash tests/run-all.sh [--ci]
#   --ci  Run only CI-safe tests (those with '# CI_SAFE=true' in first 5 lines)
#   No flag: run all tests (backward compatible)
set -uo pipefail

CI_MODE=false
[[ "${1:-}" == "--ci" ]] && CI_MODE=true

PASS=0; FAIL=0; SKIP=0; FAILED=()
for f in "$(dirname "$0")"/test_*.sh; do
    name=$(basename "$f")

    # In CI mode, only run tests with CI_SAFE=true marker in first 5 lines
    if $CI_MODE; then
        if ! head -n 5 "$f" | grep -q '# CI_SAFE=true'; then
            SKIP=$((SKIP+1))
            continue
        fi
    fi

    if bash "$f" >/dev/null 2>&1; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED+=("$name")
    fi
done

echo "========================================"
if $CI_MODE; then
    echo "Test Summary (CI mode): $PASS/$((PASS+FAIL)) suites passing ($SKIP skipped)"
else
    echo "Test Summary: $PASS/$((PASS+FAIL)) suites passing"
fi
echo "========================================"
for name in "${FAILED[@]+"${FAILED[@]}"}"; do
    echo "  ✗ $name"
done
[[ $FAIL -eq 0 ]] && echo "✓ All test suites passed" && exit 0 || exit 1
