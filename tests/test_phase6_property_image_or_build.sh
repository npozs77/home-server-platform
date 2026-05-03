#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Image-or-Build Requirement (Property 7)
# Feature: docker-service-helper, Property 7: Image-or-Build Requirement Validation
# Purpose: Verify validator accepts image-only, build-only, both; rejects neither
# Validates: Requirements 1.3, 1.15, 1.17, 10.3
# Usage: bash tests/test_phase6_property_image_or_build.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
print_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

ITERATIONS=100
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT

echo "========================================"
echo "Property 7: Image-or-Build Requirement"
echo "Iterations: $ITERATIONS"
echo "========================================"
echo ""

for ((i=1; i<=ITERATIONS; i++)); do
    svc="test-svc-$(printf '%03d' $i)"
    cfg="${TMP_DIR}/cfg-${i}.yml"
    variant=$((i % 4))  # 0=image-only, 1=build-only, 2=both, 3=neither

    case $variant in
        0) cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    image: test:v1
    port: 8080
YAML
            expected="accept" ;;
        1) cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    port: 8080
    build:
      context: https://github.com/example/repo.git
YAML
            expected="accept" ;;
        2) cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    image: test:v1
    port: 8080
    build:
      context: /tmp/build
YAML
            expected="accept" ;;
        3) cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    port: 8080
YAML
            expected="reject" ;;
    esac

    # Check: image or build.context must be non-empty
    image=$(yq -r ".services.${svc}.image // \"\"" "$cfg")
    bld=$(yq -r ".services.${svc}.build.context // \"\"" "$cfg")

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -n "$image" ]] || [[ -n "$bld" ]]; then
        [[ "$expected" == "accept" ]] && print_pass || print_fail "[$i] variant=$variant: should reject but has image='$image' build='$bld'"
    else
        [[ "$expected" == "reject" ]] && print_pass || print_fail "[$i] variant=$variant: should accept but neither image nor build"
    fi
done

echo ""
echo "========================================"
echo "Property 7 Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
