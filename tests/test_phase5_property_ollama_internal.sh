#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Ollama API Internal-Only Access (Property 2)
# Purpose: Parse ollama service definition from ollama.yml; verify no ports:
#          directive publishes 11434 to host. Ollama API must only be accessible
#          via internal Docker network (Open WebUI connects at http://ollama:11434).
# Validates: Requirements 7.3, 12.7
# Usage: bash tests/test_phase5_property_ollama_internal.sh

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
echo "Property 2: Ollama API Internal-Only Access (Phase 5)"
echo "========================================"
echo ""

# --- Locate ollama.yml ---

OLLAMA_FILE=$(resolve_compose "ollama.yml")
if [[ -z "$OLLAMA_FILE" ]]; then
    echo -e "${RED}✗ FATAL${NC}: ollama.yml not found (expected in configs/docker-compose/)"
    exit 1
fi
echo "Using compose file: $OLLAMA_FILE"
CONTENT=$(tr -d '\r' < "$OLLAMA_FILE")
echo ""

# --- Extract ollama service block ---

OLLAMA_BLOCK=$(sed -n '/^  ollama:/,/^  [a-zA-Z]/p' <<< "$CONTENT")
if [[ -z "$OLLAMA_BLOCK" ]]; then
    echo -e "${RED}✗ FATAL${NC}: Could not extract ollama service block"
    exit 1
fi

echo "--- Ollama service checks ---"
echo ""

# Check 1: Ollama service has NO ports: directive at all
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OLLAMA_BLOCK" | grep -q "ports:"; then
    print_fail "ollama service has a 'ports:' directive (should NOT publish any ports)"
else
    print_pass "ollama service has NO 'ports:' directive (API stays internal)"
fi

# Check 2: Port 11434 is NOT in a ports: mapping (host publish)
# We specifically look for port-mapping syntax like "11434:11434" or "- 11434"
# NOT healthcheck URLs which legitimately reference localhost:11434
TESTS_RUN=$((TESTS_RUN + 1))
PORTS_SECTION=""
if echo "$OLLAMA_BLOCK" | grep -q "ports:"; then
    PORTS_SECTION=$(echo "$OLLAMA_BLOCK" | sed -n '/ports:/,/^    [a-z]/p')
fi
if echo "$PORTS_SECTION" | grep -qE '11434'; then
    print_fail "ollama service publishes port 11434 to host via ports: directive"
else
    print_pass "port 11434 is NOT published to host (not in ports: section)"
fi

# Check 3: Open WebUI connects to Ollama via internal Docker network URL
TESTS_RUN=$((TESTS_RUN + 1))
WEBUI_BLOCK=$(sed -n '/^  open-webui:/,/^  [a-zA-Z]/p' <<< "$CONTENT")
if echo "$WEBUI_BLOCK" | grep -q "http://ollama:11434"; then
    print_pass "open-webui connects to ollama via internal Docker URL (http://ollama:11434)"
else
    print_fail "open-webui does NOT use internal Docker URL to connect to ollama"
fi

# Check 4: Open WebUI DOES publish a port (it's the user-facing service)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$WEBUI_BLOCK" | grep -q "ports:"; then
    print_pass "open-webui publishes a port (expected — it's the user-facing service)"
else
    print_fail "open-webui does NOT publish a port (users need access via Caddy)"
fi

# Check 5: Ollama is on the homeserver network (reachable by other containers)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OLLAMA_BLOCK" | grep -q "homeserver"; then
    print_pass "ollama is on the homeserver network (reachable by open-webui internally)"
else
    print_fail "ollama is NOT on the homeserver network"
fi

echo ""
echo "========================================"
echo "Ollama Internal-Only Access Summary (Phase 5)"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 2 holds: Ollama API is internal-only (not published to host)${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 2 violated: Ollama API may be exposed to host${NC}"
    exit 1
fi
