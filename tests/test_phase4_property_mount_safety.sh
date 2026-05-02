#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: External Library Mount Safety (Property 2)
# Purpose: Parse volume mounts from immich.yml for external library paths;
#          verify :ro flag present; verify group_add contains media GID
# Validates: Requirements 25.1, 25.2, 25.5
# Usage: bash tests/test_phase4_property_mount_safety.sh

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
[[ -f "$COMPOSE_FILE" ]] || COMPOSE_FILE="configs/docker-compose/immich.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo -e "${RED}✗ FATAL${NC}: immich.yml.example not found"
    exit 1
fi
echo "Using compose file: $COMPOSE_FILE"
echo ""

# Normalize line endings (strip \r) for reliable parsing
COMPOSE_CONTENT=$(tr -d '\r' < "$COMPOSE_FILE")

# Extract immich-server block
get_server_block() {
    local capture=false
    while IFS= read -r line; do
        if [[ "$line" == "  immich-server:" ]]; then
            capture=true
            continue
        fi
        if $capture; then
            if [[ "$line" =~ ^\ \ [a-zA-Z][a-zA-Z0-9_-]+:$ ]] || { [[ -n "$line" ]] && [[ "$line" =~ ^[a-z] ]]; }; then
                break
            fi
            echo "$line"
        fi
    done <<< "$COMPOSE_CONTENT"
}

SERVER_BLOCK=$(get_server_block)

echo "========================================"
echo "Property 2: External Library Mount Safety"
echo "========================================"
echo ""

# Check 1: /mnt/data/media/Photos mount has :ro flag
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SERVER_BLOCK" | grep -q "/mnt/data/media/Photos.*:ro"; then
    print_pass "media/Photos mount has :ro flag"
else
    print_fail "media/Photos mount MISSING :ro flag"
fi

# Check 2: /mnt/data/family/Photos mount has :ro flag
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SERVER_BLOCK" | grep -q "/mnt/data/family/Photos.*:ro"; then
    print_pass "family/Photos mount has :ro flag"
else
    print_fail "family/Photos mount MISSING :ro flag"
fi

# Check 3: group_add section exists in immich-server
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SERVER_BLOCK" | grep -q "group_add:"; then
    print_pass "immich-server has group_add section"
else
    print_fail "immich-server MISSING group_add section"
fi

# Check 4: group_add contains a GID value (numeric or variable reference)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SERVER_BLOCK" | grep -qE 'MEDIA_GROUP_GID|"[0-9]+"'; then
    print_pass "group_add contains media GID value"
else
    print_fail "group_add MISSING media GID value"
fi

echo ""
echo "========================================"
echo "Mount Safety Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 2 holds: External library mounts are read-only with group_add for media GID${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 2 violated: Mount safety checks failed${NC}"
    exit 1
fi
