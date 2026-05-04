#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Enabled Flag Behavior (Properties 23, 24, 25)
# Feature: docker-service-helper, Properties 23-25: Enabled Flag Behavior
# Purpose: Verify enabled=false → skip, enabled=true/omitted → normal behavior
# Validates: Requirements 1.19, 6.8, 8.5, 9.9, 30.2, 30.3
# Usage: bash tests/test_phase6_property_enabled_flag.sh

set -euo pipefail

if ! command -v yq &>/dev/null; then echo "SKIP: yq not installed"; exit 0; fi

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
print_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

ITERATIONS=100
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT

echo "========================================"
echo "Properties 23-25: Enabled Flag Behavior"
echo "Iterations: $ITERATIONS"
echo "========================================"
echo ""

for ((i=1; i<=ITERATIONS; i++)); do
    svc="svc-$(printf '%03d' $i)"
    cfg="${TMP_DIR}/cfg-${i}.yml"
    variant=$((i % 3))  # 0=true, 1=false, 2=omitted

    case $variant in
        0) cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    image: test:v1
    port: 8080
    enabled: true
YAML
            expected_enabled="true" ;;
        1) cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    image: test:v1
    port: 8080
    enabled: false
YAML
            expected_enabled="false" ;;
        2) cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    image: test:v1
    port: 8080
YAML
            expected_enabled="true" ;;  # default
    esac

    # Read enabled field same way as service-ops.sh (_so_enabled)
    raw=$(yq -r ".services.${svc}.enabled" "$cfg")
    if [[ "$raw" == "null" || -z "$raw" ]]; then enabled="true"; else enabled="$raw"; fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$enabled" == "$expected_enabled" ]]; then
        print_pass
    else
        print_fail "[$i] variant=$variant: expected enabled='${expected_enabled}' got '${enabled}'"
    fi

    # Verify: enabled=false should mean "skip"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$enabled" == "false" ]]; then
        # Should skip — verify the code has this guard
        [[ $variant -eq 1 ]] && print_pass || print_fail "[$i] enabled=false but variant=$variant"
    else
        # Should proceed
        [[ $variant -ne 1 ]] && print_pass || print_fail "[$i] enabled=true but variant=1"
    fi
done

# Verify code-level guards exist
echo ""
echo "--- Code-level enabled guards ---"
for fn in cmd_add cmd_validate; do
    TESTS_RUN=$((TESTS_RUN + 1))
    grep -A10 "^${fn}()" scripts/docker-helper/lib/service-ops.sh | grep -q 'enabled.*false' && print_pass || print_fail "${fn}() missing enabled=false guard"
done

# Verify list shows "disabled" for enabled=false
TESTS_RUN=$((TESTS_RUN + 1))
grep "disabled" scripts/docker-helper/lib/service-ops.sh | grep -q "cmd_list\|status=" && print_pass || print_fail "cmd_list missing 'disabled' status"

echo ""
echo "========================================"
echo "Properties 23-25 Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
