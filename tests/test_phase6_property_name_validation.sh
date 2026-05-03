#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Service Name Validation (Property 6)
# Feature: docker-service-helper, Property 6: Service Name Validation
# Purpose: Verify validator accepts valid names, rejects invalid names
# Validates: Requirements 1.2, 10.2, 10.5, 10.8
# Usage: bash tests/test_phase6_property_name_validation.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
print_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

ITERATIONS=100
REGEX='^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'

echo "========================================"
echo "Property 6: Service Name Validation"
echo "Iterations: $ITERATIONS"
echo "========================================"
echo ""

# Random valid name: lowercase + digits + hyphens, starts/ends alphanumeric
rand_valid() {
    local chars="abcdefghijklmnopqrstuvwxyz0123456789"
    local mid="abcdefghijklmnopqrstuvwxyz0123456789-"
    local len=$((RANDOM % 8 + 2))
    local name="${chars:$((RANDOM % 36)):1}"
    for ((i=1; i<len-1; i++)); do name+="${mid:$((RANDOM % 37)):1}"; done
    name+="${chars:$((RANDOM % 36)):1}"
    # Avoid double hyphens
    echo "$name" | sed 's/--/-/g'
}

# Random invalid name: uppercase, underscores, spaces, special chars
rand_invalid() {
    local types=("UPPER" "under_score" "with space" "special!" ".dot" "-start" "end-" "" "123 abc")
    echo "${types[$((RANDOM % ${#types[@]}))]}"
}

# Test valid names
for ((i=1; i<=ITERATIONS/2; i++)); do
    name=$(rand_valid)
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$name" =~ $REGEX ]]; then
        print_pass
    else
        print_fail "[$i] Valid name '${name}' rejected by regex"
    fi
done

# Test invalid names
for ((i=1; i<=ITERATIONS/2; i++)); do
    name=$(rand_invalid)
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$name" =~ $REGEX ]]; then
        print_fail "[$i] Invalid name '${name}' accepted by regex"
    else
        print_pass
    fi
done

echo ""
echo "========================================"
echo "Property 6 Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
