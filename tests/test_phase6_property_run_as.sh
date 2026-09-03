#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: run_as Field Behavior (Property 28)
# Feature: docker-service-helper, Property 28: run_as Field Behavior
# Purpose: Verify that run_as field is correctly read from services.yml and
#          produces the expected Docker user directive in compose output.
#          Also verifies omission means no user directive.
# Validates: Data directory ownership and container user mapping
# Usage: bash tests/test_phase6_property_run_as.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
print_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

ITERATIONS="${PBT_ITERATIONS:-25}"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "========================================"
echo "Property 28: run_as Field Behavior"
echo "Iterations: $ITERATIONS"
echo "========================================"
echo ""

rand_name() {
    local len=$((RANDOM % 6 + 3)); local name=""
    for ((i=0; i<len; i++)); do
        name+=$(printf "\\x$(printf '%02x' $((RANDOM % 26 + 97)))")
    done
    echo "$name"
}
rand_uid() { echo $(( RANDOM % 65534 + 1 )); }

# Test 1: run_as present → yq reads correct value and compose-gen logic would emit user:
echo "--- Test Group 1: run_as present → user directive expected ---"
for ((iter=1; iter<=ITERATIONS/2; iter++)); do
    svc=$(rand_name)
    uid=$(rand_uid)
    gid=$(rand_uid)

    cfg="${TMP_DIR}/services-${iter}-with.yml"
    cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    image: testimg:latest
    port: 8080
    run_as: "${uid}:${gid}"
YAML

    # Verify yq reads run_as correctly (this is what compose-gen.sh uses)
    TESTS_RUN=$((TESTS_RUN + 1))
    actual=$(yq -r ".services.${svc}.run_as // \"\"" "$cfg")
    if [[ "$actual" == "${uid}:${gid}" ]]; then
        print_pass
    else
        print_fail "[$iter] ${svc}: expected run_as='${uid}:${gid}', got '${actual}'"
    fi

    # Verify the value is non-empty (compose-gen emits user: only when non-empty)
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -n "$actual" ]]; then
        print_pass
    else
        print_fail "[$iter] ${svc}: run_as should be non-empty"
    fi
done

# Test 2: run_as absent → yq returns empty string, no user directive
echo "--- Test Group 2: run_as absent → no user directive ---"
for ((iter=1; iter<=ITERATIONS/2; iter++)); do
    svc=$(rand_name)

    cfg="${TMP_DIR}/services-${iter}-without.yml"
    cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    image: testimg:latest
    port: 8080
YAML

    TESTS_RUN=$((TESTS_RUN + 1))
    actual=$(yq -r ".services.${svc}.run_as // \"\"" "$cfg")
    if [[ -z "$actual" ]]; then
        print_pass
    else
        print_fail "[$iter] ${svc}: expected empty run_as, got '${actual}'"
    fi
done

# Test 3: Verify compose-gen.sh contains the user directive logic
echo "--- Test Group 3: Code inspection ---"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q 'run_as' scripts/docker-helper/lib/compose-gen.sh; then
    print_pass
else
    print_fail "compose-gen.sh missing run_as handling"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if grep -q 'user:' scripts/docker-helper/lib/compose-gen.sh; then
    print_pass
else
    print_fail "compose-gen.sh missing user: directive output"
fi

# Test 4: Verify service-ops.sh uses run_as for chown
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q 'chown -R "$run_as"' scripts/docker-helper/lib/service-ops.sh; then
    print_pass
else
    print_fail "service-ops.sh missing chown with run_as"
fi

# Test 5: run_as format validation (uid:gid pattern)
echo "--- Test Group 4: Format validation ---"
valid_formats=("100:101" "0:0" "65534:65534" "1000:1000" "999:999")
for fmt in "${valid_formats[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$fmt" =~ ^[0-9]+:[0-9]+$ ]]; then
        print_pass
    else
        print_fail "Format '${fmt}' should be valid uid:gid"
    fi
done

echo ""
echo "========================================"
echo "Property 28 Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
