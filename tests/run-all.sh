#!/bin/bash
# Run all test suites and report summary
set -uo pipefail

PASS=0; FAIL=0; FAILED=()
for f in "$(dirname "$0")"/test_*.sh; do
    name=$(basename "$f")
    if bash "$f" >/dev/null 2>&1; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED+=("$name")
    fi
done

echo "========================================"
echo "Test Summary: $PASS/$((PASS+FAIL)) suites passing"
echo "========================================"
for name in "${FAILED[@]+"${FAILED[@]}"}"; do
    echo "  ✗ $name"
done
[[ $FAIL -eq 0 ]] && echo "✓ All test suites passed" && exit 0 || exit 1
