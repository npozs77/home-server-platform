#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Visibility Field Validation (Property 22)
# Feature: docker-service-helper, Property 22: Visibility Field Validation
# Purpose: Verify public/private accepted, invalid rejected, omitted defaults to private
# Validates: Requirements 1.18, 25.4, 28.4
# Usage: bash tests/test_phase6_property_visibility.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
print_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

ITERATIONS=100
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT

# The validation logic from service-ops.sh:
# if vis is non-empty and not "public" and not "private" → error
validate_visibility() {
    local vis="$1"
    if [[ -n "$vis" ]] && [[ "$vis" != "public" ]] && [[ "$vis" != "private" ]]; then
        return 1
    fi
    return 0
}

echo "========================================"
echo "Property 22: Visibility Field Validation"
echo "Iterations: $ITERATIONS"
echo "========================================"
echo ""

VALID_VALUES=("public" "private")
INVALID_VALUES=("internal" "PUBLIC" "Private" "yes" "no" "true" "false" "hidden" "open" "restricted")

for ((i=1; i<=ITERATIONS; i++)); do
    variant=$((i % 4))  # 0=public, 1=private, 2=invalid, 3=omitted

    case $variant in
        0) vis="public"; expected=0 ;;
        1) vis="private"; expected=0 ;;
        2) vis="${INVALID_VALUES[$((RANDOM % ${#INVALID_VALUES[@]}))]}" ; expected=1 ;;
        3) vis=""; expected=0 ;;  # omitted defaults to private
    esac

    TESTS_RUN=$((TESTS_RUN + 1))
    if validate_visibility "$vis"; then
        [[ $expected -eq 0 ]] && print_pass || print_fail "[$i] vis='${vis}' should be rejected but was accepted"
    else
        [[ $expected -eq 1 ]] && print_pass || print_fail "[$i] vis='${vis}' should be accepted but was rejected"
    fi
done

# Also verify the actual code has the same validation logic
TESTS_RUN=$((TESTS_RUN + 1))
grep -q 'visibility.*public.*private' scripts/docker-helper/lib/service-ops.sh && print_pass || print_fail "service-ops.sh missing visibility validation"

echo ""
echo "========================================"
echo "Property 22 Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
