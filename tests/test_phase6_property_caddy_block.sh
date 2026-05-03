#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Caddy Block Generation Invariants (Property 9)
# Feature: docker-service-helper, Property 9: Caddy Block Generation Invariants
# Purpose: Verify generated Caddy blocks contain FQDN, reverse_proxy, tls internal,
#          log, handle_errors, and marker comments for random proxied services
# Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5
# Usage: bash tests/test_phase6_property_caddy_block.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
print_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

TEMPLATE="scripts/docker-helper/templates/caddy-block.template"
ITERATIONS=100
INTERNAL_SUBDOMAIN="home.example.com"

[[ -f "$TEMPLATE" ]] || { echo "FATAL: $TEMPLATE not found"; exit 1; }

echo "========================================"
echo "Property 9: Caddy Block Generation Invariants"
echo "Iterations: $ITERATIONS"
echo "========================================"
echo ""

rand_name() {
    local chars="abcdefghijklmnopqrstuvwxyz"
    local len=$((RANDOM % 8 + 3))
    local name=""
    for ((i=0; i<len; i++)); do name+="${chars:$((RANDOM % 26)):1}"; done
    echo "$name"
}

for ((i=1; i<=ITERATIONS; i++)); do
    svc=$(rand_name)
    subdomain=$(rand_name)
    port=$((RANDOM % 64000 + 1024))

    # Generate Caddy block using sed substitution (same as add_caddy_entry in service-ops.sh)
    block=$(sed -e "s|{{SERVICE_NAME}}|${svc}|g" \
                -e "s|{{SUBDOMAIN}}|${subdomain}|g" \
                -e "s|{{INTERNAL_SUBDOMAIN}}|${INTERNAL_SUBDOMAIN}|g" \
                -e "s|{{CONTAINER_NAME}}|${svc}|g" \
                -e "s|{{PORT}}|${port}|g" \
                "$TEMPLATE")

    fqdn="${subdomain}.${INTERNAL_SUBDOMAIN}"

    # Check: FQDN present
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "$block" | grep -q "$fqdn" && print_pass || print_fail "[$i] Missing FQDN ${fqdn}"

    # Check: reverse_proxy with container:port
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "$block" | grep -q "reverse_proxy ${svc}:${port}" && print_pass || print_fail "[$i] Missing reverse_proxy ${svc}:${port}"

    # Check: tls internal
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "$block" | grep -q "tls internal" && print_pass || print_fail "[$i] Missing tls internal"

    # Check: log block
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "$block" | grep -q "log {" && print_pass || print_fail "[$i] Missing log block"

    # Check: handle_errors block
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "$block" | grep -q "handle_errors" && print_pass || print_fail "[$i] Missing handle_errors"

    # Check: BEGIN marker
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "$block" | grep -q "# BEGIN helper:${svc}" && print_pass || print_fail "[$i] Missing BEGIN marker"

    # Check: END marker
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "$block" | grep -q "# END helper:${svc}" && print_pass || print_fail "[$i] Missing END marker"
done

echo ""
echo "========================================"
echo "Property 9 Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
