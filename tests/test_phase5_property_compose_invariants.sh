#!/usr/bin/env bash
# Property Test: Docker Compose Configuration Invariants (Property 1)
# Purpose: Parse all service definitions from wiki.yml and ollama.yml; for each
#          service verify: restart policy unless-stopped, homeserver network,
#          HEALTHCHECK directive, TZ env var, resource limits
# Validates: Requirements 1.4, 1.5, 1.6, 1.7, 1.8, 7.4, 7.5, 7.8, 9.4, 9.6
# Usage: bash tests/test_phase5_property_compose_invariants.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Resolve compose files (prefer .example for local testing)
resolve_compose() {
    local base="configs/docker-compose/$1"
    local example="${base}.example"
    if [[ -f "$example" ]]; then echo "$example"
    elif [[ -f "$base" ]]; then echo "$base"
    else echo ""; fi
}

# Extract service names from a compose file
extract_services() {
    local content="$1"
    local in_services=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^services: ]]; then in_services=true; continue; fi
        if $in_services && [[ -n "$line" ]] && [[ "$line" =~ ^[a-z] ]]; then break; fi
        if $in_services && [[ "$line" =~ ^\ \ ([a-zA-Z][a-zA-Z0-9_-]+):$ ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done <<< "$content"
}

# Extract the block for a given service
get_service_block() {
    local svc="$1" content="$2"
    local capture=false
    while IFS= read -r line; do
        if [[ "$line" == "  ${svc}:" ]]; then capture=true; continue; fi
        if $capture; then
            if [[ "$line" =~ ^\ \ [a-zA-Z][a-zA-Z0-9_-]+:$ ]] || { [[ -n "$line" ]] && [[ "$line" =~ ^[a-z] ]]; }; then
                break
            fi
            echo "$line"
        fi
    done <<< "$content"
}

# Check invariants for a single service
check_service_invariants() {
    local svc="$1" block="$2" file="$3"

    echo "--- $svc ($file) ---"

    # Check 1: restart policy is unless-stopped
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$block" | grep -q "restart:.*unless-stopped"; then
        print_pass "$svc: restart policy is unless-stopped"
    else
        print_fail "$svc: restart policy is NOT unless-stopped"
    fi

    # Check 2: Connected to homeserver network
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$block" | grep -q "homeserver"; then
        print_pass "$svc: connected to homeserver network"
    else
        print_fail "$svc: NOT connected to homeserver network"
    fi

    # Check 3: Has HEALTHCHECK directive
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$block" | grep -q "healthcheck:"; then
        print_pass "$svc: has healthcheck directive"
    else
        print_fail "$svc: MISSING healthcheck directive"
    fi

    # Check 4: Has TZ environment variable
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$block" | grep -qE "TZ:"; then
        print_pass "$svc: has TZ environment variable"
    else
        print_fail "$svc: MISSING TZ environment variable"
    fi

    # Check 5: Has resource limits (deploy.resources.limits)
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$block" | grep -q "limits:"; then
        print_pass "$svc: has resource limits"
    else
        print_fail "$svc: MISSING resource limits"
    fi

    echo ""
}

# --- Main ---

echo "========================================"
echo "Property 1: Docker Compose Configuration Invariants (Phase 5)"
echo "========================================"
echo ""

COMPOSE_FILES=("wiki.yml" "ollama.yml")
TOTAL_SERVICES=0

for fname in "${COMPOSE_FILES[@]}"; do
    FPATH=$(resolve_compose "$fname")
    if [[ -z "$FPATH" ]]; then
        echo -e "${RED}✗ SKIP${NC}: $fname not found (expected in configs/docker-compose/)"
        echo ""
        continue
    fi
    echo "Using compose file: $FPATH"
    CONTENT=$(tr -d '\r' < "$FPATH")
    SERVICES=($(extract_services "$CONTENT"))
    echo "Services found: ${SERVICES[*]}"
    echo ""

    for svc in "${SERVICES[@]}"; do
        BLOCK=$(get_service_block "$svc" "$CONTENT")
        check_service_invariants "$svc" "$BLOCK" "$fname"
        TOTAL_SERVICES=$((TOTAL_SERVICES + 1))
    done
done

if [[ $TOTAL_SERVICES -eq 0 ]]; then
    echo -e "${RED}✗ FATAL${NC}: No compose files found to test"
    exit 1
fi

echo "========================================"
echo "Compose Invariants Summary (Phase 5)"
echo "========================================"
echo "Services checked: $TOTAL_SERVICES"
echo "Checks run:       $TESTS_RUN"
echo -e "Passed:           ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:         ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 1 holds: All Phase 5 services have restart policy, network, healthcheck, TZ, and resource limits${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 1 violated: Some services missing required configuration${NC}"
    exit 1
fi
