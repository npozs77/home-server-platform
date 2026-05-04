#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Helper_Services_Config Read-Only Round-Trip (Property 11)
# Feature: docker-service-helper, Property 11: Helper_Services_Config Read-Only Round-Trip
# Purpose: Verify reading service definitions does not modify the config file
# Validates: Requirements 11.1, 11.2, 11.4, 23.1
# Usage: bash tests/test_phase6_property_roundtrip.sh

set -euo pipefail

if ! command -v yq &>/dev/null; then echo "SKIP: yq not installed"; exit 0; fi

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
print_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

ITERATIONS=100
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT
EXAMPLE="configs/helper-services/services.yml.example"

[[ -f "$EXAMPLE" ]] || { echo "FATAL: $EXAMPLE not found"; exit 1; }

echo "========================================"
echo "Property 11: Config Read-Only Round-Trip"
echo "Iterations: $ITERATIONS"
echo "========================================"
echo ""

# Get all service names from example
SERVICES=$(yq -r '.services | keys | .[]' "$EXAMPLE")

for ((i=1; i<=ITERATIONS; i++)); do
    # Copy example to temp
    cfg="${TMP_DIR}/services-${i}.yml"
    cp "$EXAMPLE" "$cfg"
    hash_before=$(shasum -a 256 "$cfg" | awk '{print $1}')

    # Read a random service (cycle through available services)
    svc=$(echo "$SERVICES" | shuf -n 1 2>/dev/null || echo "$SERVICES" | head -1)

    # Perform read operations (same as service-ops.sh does)
    yq -r ".services.${svc}.image // \"\"" "$cfg" >/dev/null
    yq -r ".services.${svc}.port // \"\"" "$cfg" >/dev/null
    yq -r ".services.${svc}.no_proxy // false" "$cfg" >/dev/null
    yq -r ".services.${svc}.build.context // \"\"" "$cfg" >/dev/null
    yq -r ".services.${svc}.volumes[]? // empty" "$cfg" >/dev/null 2>&1 || true
    yq -r ".services.${svc}.environment | keys | .[]" "$cfg" >/dev/null 2>&1 || true
    yq -r '.services | keys | .[]' "$cfg" >/dev/null

    hash_after=$(shasum -a 256 "$cfg" | awk '{print $1}')

    TESTS_RUN=$((TESTS_RUN + 1))
    [[ "$hash_before" == "$hash_after" ]] && print_pass || print_fail "[$i] File hash changed after reading service '${svc}'"
done

echo ""
echo "========================================"
echo "Property 11 Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
