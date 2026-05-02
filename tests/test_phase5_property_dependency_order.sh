#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Container Dependency Order (Property 3)
# Purpose: Parse depends_on declarations from wiki.yml and ollama.yml; verify
#          wiki-server depends_on wiki-db with service_healthy;
#          open-webui depends_on ollama with service_healthy
# Validates: Requirements 20.1, 20.2, 20.3
# Usage: bash tests/test_phase5_property_dependency_order.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Resolve compose file (prefer .example for local testing)
resolve_compose() {
    local base="configs/docker-compose/$1"
    local example="${base}.example"
    if [[ -f "$example" ]]; then echo "$example"
    elif [[ -f "$base" ]]; then echo "$base"
    else echo ""; fi
}

echo "========================================"
echo "Property 3: Container Dependency Order (Phase 5)"
echo "========================================"
echo ""

# --- wiki.yml: wiki-server depends_on wiki-db with service_healthy ---

WIKI_FILE=$(resolve_compose "wiki.yml")
if [[ -z "$WIKI_FILE" ]]; then
    echo -e "${RED}✗ FATAL${NC}: wiki.yml not found"
    exit 1
fi
echo "Using: $WIKI_FILE"
WIKI_CONTENT=$(tr -d '\r' < "$WIKI_FILE")

echo ""
echo "--- Sub-phase A: Wiki.js dependency chain ---"

# Check 1: wiki-server has depends_on wiki-db
TESTS_RUN=$((TESTS_RUN + 1))
# Extract wiki-server block
WS_BLOCK=$(sed -n '/^  wiki-server:/,/^  [a-zA-Z]/p' <<< "$WIKI_CONTENT")
if echo "$WS_BLOCK" | grep -q "depends_on:"; then
    print_pass "wiki-server has depends_on declaration"
else
    print_fail "wiki-server MISSING depends_on declaration"
fi

# Check 2: wiki-server depends_on wiki-db specifically
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$WS_BLOCK" | grep -q "wiki-db:"; then
    print_pass "wiki-server depends_on wiki-db"
else
    print_fail "wiki-server does NOT depend_on wiki-db"
fi

# Check 3: wiki-db dependency uses condition: service_healthy
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$WS_BLOCK" | grep -q "condition:.*service_healthy"; then
    print_pass "wiki-db dependency uses condition: service_healthy"
else
    print_fail "wiki-db dependency does NOT use condition: service_healthy"
fi

# Check 4: wiki-db has healthcheck (required for service_healthy condition)
TESTS_RUN=$((TESTS_RUN + 1))
DB_BLOCK=$(sed -n '/^  wiki-db:/,/^  [a-zA-Z]/p' <<< "$WIKI_CONTENT")
if echo "$DB_BLOCK" | grep -q "healthcheck:"; then
    print_pass "wiki-db has healthcheck (required for service_healthy)"
else
    print_fail "wiki-db MISSING healthcheck (service_healthy will fail)"
fi

echo ""

# --- ollama.yml: open-webui depends_on ollama with service_healthy ---

OLLAMA_FILE=$(resolve_compose "ollama.yml")
if [[ -z "$OLLAMA_FILE" ]]; then
    echo -e "${RED}✗ FATAL${NC}: ollama.yml not found"
    exit 1
fi
echo "Using: $OLLAMA_FILE"
OLLAMA_CONTENT=$(tr -d '\r' < "$OLLAMA_FILE")

echo ""
echo "--- Sub-phase B: LLM dependency chain ---"

# Check 5: open-webui has depends_on ollama
TESTS_RUN=$((TESTS_RUN + 1))
OW_BLOCK=$(sed -n '/^  open-webui:/,/^  [a-zA-Z]/p' <<< "$OLLAMA_CONTENT")
if echo "$OW_BLOCK" | grep -q "depends_on:"; then
    print_pass "open-webui has depends_on declaration"
else
    print_fail "open-webui MISSING depends_on declaration"
fi

# Check 6: open-webui depends_on ollama specifically
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OW_BLOCK" | grep -q "ollama:"; then
    print_pass "open-webui depends_on ollama"
else
    print_fail "open-webui does NOT depend_on ollama"
fi

# Check 7: ollama dependency uses condition: service_healthy
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OW_BLOCK" | grep -q "condition:.*service_healthy"; then
    print_pass "ollama dependency uses condition: service_healthy"
else
    print_fail "ollama dependency does NOT use condition: service_healthy"
fi

# Check 8: ollama has healthcheck (required for service_healthy condition)
TESTS_RUN=$((TESTS_RUN + 1))
OL_BLOCK=$(sed -n '/^  ollama:/,/^  [a-zA-Z]/p' <<< "$OLLAMA_CONTENT")
if echo "$OL_BLOCK" | grep -q "healthcheck:"; then
    print_pass "ollama has healthcheck (required for service_healthy)"
else
    print_fail "ollama MISSING healthcheck (service_healthy will fail)"
fi

echo ""
echo "========================================"
echo "Dependency Order Summary (Phase 5)"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 3 holds: All container dependencies use service_healthy condition${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 3 violated: Dependency order issues found${NC}"
    exit 1
fi
