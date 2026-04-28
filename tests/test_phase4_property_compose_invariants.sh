#!/usr/bin/env bash
# Property Test: Docker Compose Configuration Invariants (Property 1)
# Purpose: Parse all service definitions from immich.yml; for each service verify:
#          restart policy unless-stopped, homeserver network, HEALTHCHECK directive, resource limits
# Validates: Requirements 1.10, 1.12, 14.1-14.6, 21.7-21.9
# Usage: bash tests/test_phase4_property_compose_invariants.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Test against the example template (immich.yml is generated on the server, not in repo)
COMPOSE_FILE="configs/docker-compose/immich.yml.example"
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo -e "${RED}✗ FATAL${NC}: immich.yml.example not found"
    exit 1
fi
echo "Using compose file: $COMPOSE_FILE"
echo ""

# Normalize line endings (strip \r) for reliable parsing
COMPOSE_CONTENT=$(tr -d '\r' < "$COMPOSE_FILE")

# Extract service names: lines matching "^  <name>:" under "services:" section
SERVICES=()
in_services=false
while IFS= read -r line; do
    if [[ "$line" =~ ^services: ]]; then
        in_services=true
        continue
    fi
    # Stop at next top-level key (no leading whitespace)
    if $in_services && [[ -n "$line" ]] && [[ "$line" =~ ^[a-z] ]]; then
        break
    fi
    # Match service name: exactly 2 spaces + word + colon
    if $in_services && [[ "$line" =~ ^\ \ ([a-zA-Z][a-zA-Z0-9_-]+):$ ]]; then
        SERVICES+=("${BASH_REMATCH[1]}")
    fi
done <<< "$COMPOSE_CONTENT"

echo "========================================"
echo "Property 1: Docker Compose Configuration Invariants"
echo "========================================"
echo ""
echo "Services found: ${SERVICES[*]}"
echo ""

# Extract the block for a given service (from "  <service>:" to next service or top-level key)
get_service_block() {
    local svc="$1"
    local capture=false
    while IFS= read -r line; do
        if [[ "$line" == "  ${svc}:" ]]; then
            capture=true
            continue
        fi
        if $capture; then
            # Stop at next service definition or top-level key
            if [[ "$line" =~ ^\ \ [a-zA-Z][a-zA-Z0-9_-]+:$ ]] || { [[ -n "$line" ]] && [[ "$line" =~ ^[a-z] ]]; }; then
                break
            fi
            echo "$line"
        fi
    done <<< "$COMPOSE_CONTENT"
}

for svc in "${SERVICES[@]}"; do
    echo "--- $svc ---"
    BLOCK=$(get_service_block "$svc")

    # Check 1: restart policy is unless-stopped
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$BLOCK" | grep -q "restart:.*unless-stopped"; then
        print_pass "$svc: restart policy is unless-stopped"
    else
        print_fail "$svc: restart policy is NOT unless-stopped"
    fi

    # Check 2: Connected to homeserver network
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$BLOCK" | grep -q "homeserver"; then
        print_pass "$svc: connected to homeserver network"
    else
        print_fail "$svc: NOT connected to homeserver network"
    fi

    # Check 3: Has HEALTHCHECK directive
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$BLOCK" | grep -q "healthcheck:"; then
        print_pass "$svc: has healthcheck directive"
    else
        print_fail "$svc: MISSING healthcheck directive"
    fi

    # Check 4: Has resource limits (deploy.resources.limits)
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$BLOCK" | grep -q "limits:"; then
        print_pass "$svc: has resource limits"
    else
        print_fail "$svc: MISSING resource limits"
    fi

    echo ""
done

echo "========================================"
echo "Compose Invariants Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 1 holds: All services have restart policy, network, healthcheck, and resource limits${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 1 violated: Some services missing required configuration${NC}"
    exit 1
fi
