#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Data Persistence Round-Trip (Property 4)
# Purpose: Verify all Phase 5 volume mounts configured correctly in Docker
#          Compose files. Bind-mount host paths under /mnt/data/ ensure that
#          docker compose down followed by docker compose up -d preserves all
#          stateful data (database, wiki content, models, chat history).
# Validates: Requirements 2.2, 2.3, 2.4, 2.5, 13.5
# Usage: bash tests/test_phase5_property_data_persistence.sh

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

# Extract the block for a given service (from top-level services: key)
get_service_block() {
    local svc="$1" content="$2"
    sed -n "/^  ${svc}:/,/^  [a-zA-Z]/p" <<< "$content"
}

# Extract volume mount lines from a service block
get_volume_mounts() {
    local block="$1"
    local in_volumes=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+volumes: ]]; then
            in_volumes=true; continue
        fi
        if $in_volumes; then
            if [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
                echo "$line"
            else
                break
            fi
        fi
    done <<< "$block"
}

echo "========================================"
echo "Property 4: Data Persistence Round-Trip (Phase 5)"
echo "========================================"
echo ""

# ============================================================
# Part A: wiki.yml — Wiki.js volume mounts
# ============================================================

WIKI_FILE=$(resolve_compose "wiki.yml")
if [[ -z "$WIKI_FILE" ]]; then
    echo -e "${RED}✗ FATAL${NC}: wiki.yml not found (expected in configs/docker-compose/)"
    exit 1
fi
echo "Using compose file: $WIKI_FILE"
WIKI_CONTENT=$(tr -d '\r' < "$WIKI_FILE")
echo ""

# --- wiki-db: PostgreSQL data persistence ---

echo "--- wiki-db: PostgreSQL data persistence ---"

DB_BLOCK=$(get_service_block "wiki-db" "$WIKI_CONTENT")
DB_VOLUMES=$(get_volume_mounts "$DB_BLOCK")

# Check 1: wiki-db has a volumes: section
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -n "$DB_VOLUMES" ]]; then
    print_pass "wiki-db has volume mounts"
else
    print_fail "wiki-db has NO volume mounts (data lost on recreate)"
fi

# Check 2: wiki-db mounts host path /mnt/data/services/wiki/postgres
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$DB_VOLUMES" | grep -q "/mnt/data/services/wiki/postgres"; then
    print_pass "wiki-db mounts /mnt/data/services/wiki/postgres (host bind mount)"
else
    print_fail "wiki-db does NOT mount /mnt/data/services/wiki/postgres"
fi

# Check 3: wiki-db maps to correct container path /var/lib/postgresql/data
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$DB_VOLUMES" | grep -q "/var/lib/postgresql/data"; then
    print_pass "wiki-db maps to /var/lib/postgresql/data (PostgreSQL data dir)"
else
    print_fail "wiki-db does NOT map to /var/lib/postgresql/data"
fi

# Check 4: wiki-db volume is read-write (:rw)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$DB_VOLUMES" | grep -q ":rw"; then
    print_pass "wiki-db volume is read-write (:rw)"
else
    print_fail "wiki-db volume is NOT explicitly :rw (may default to rw, but should be explicit)"
fi

# Check 5: wiki-db uses bind mount (absolute host path), not named volume
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$DB_VOLUMES" | grep -qE "^\s*-\s+/"; then
    print_pass "wiki-db uses bind mount (absolute host path, not named volume)"
else
    print_fail "wiki-db may use named volume (data lost if volume pruned)"
fi

echo ""

# --- wiki-server: Wiki.js content persistence ---

echo "--- wiki-server: Wiki.js content persistence ---"

WS_BLOCK=$(get_service_block "wiki-server" "$WIKI_CONTENT")
WS_VOLUMES=$(get_volume_mounts "$WS_BLOCK")

# Check 6: wiki-server has a volumes: section
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -n "$WS_VOLUMES" ]]; then
    print_pass "wiki-server has volume mounts"
else
    print_fail "wiki-server has NO volume mounts (content lost on recreate)"
fi

# Check 7: wiki-server mounts host path /mnt/data/services/wiki/content
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$WS_VOLUMES" | grep -q "/mnt/data/services/wiki/content"; then
    print_pass "wiki-server mounts /mnt/data/services/wiki/content (host bind mount)"
else
    print_fail "wiki-server does NOT mount /mnt/data/services/wiki/content"
fi

# Check 8: wiki-server maps to correct container path /wiki/data/content
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$WS_VOLUMES" | grep -q "/wiki/data/content"; then
    print_pass "wiki-server maps to /wiki/data/content (Wiki.js disk storage)"
else
    print_fail "wiki-server does NOT map to /wiki/data/content"
fi

# Check 9: wiki-server volume is read-write (:rw)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$WS_VOLUMES" | grep -q ":rw"; then
    print_pass "wiki-server volume is read-write (:rw)"
else
    print_fail "wiki-server volume is NOT explicitly :rw"
fi

# Check 10: wiki-server uses bind mount (absolute host path)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$WS_VOLUMES" | grep -qE "^\s*-\s+/"; then
    print_pass "wiki-server uses bind mount (absolute host path, not named volume)"
else
    print_fail "wiki-server may use named volume (data lost if volume pruned)"
fi

echo ""

# ============================================================
# Part B: ollama.yml — LLM stack volume mounts
# ============================================================

OLLAMA_FILE=$(resolve_compose "ollama.yml")
if [[ -z "$OLLAMA_FILE" ]]; then
    echo -e "${RED}✗ FATAL${NC}: ollama.yml not found (expected in configs/docker-compose/)"
    exit 1
fi
echo "Using compose file: $OLLAMA_FILE"
OLLAMA_CONTENT=$(tr -d '\r' < "$OLLAMA_FILE")
echo ""

# --- ollama: LLM model persistence ---

echo "--- ollama: LLM model persistence ---"

OL_BLOCK=$(get_service_block "ollama" "$OLLAMA_CONTENT")
OL_VOLUMES=$(get_volume_mounts "$OL_BLOCK")

# Check 11: ollama has a volumes: section
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -n "$OL_VOLUMES" ]]; then
    print_pass "ollama has volume mounts"
else
    print_fail "ollama has NO volume mounts (models lost on recreate)"
fi

# Check 12: ollama mounts host path /mnt/data/services/ollama/models
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OL_VOLUMES" | grep -q "/mnt/data/services/ollama/models"; then
    print_pass "ollama mounts /mnt/data/services/ollama/models (host bind mount)"
else
    print_fail "ollama does NOT mount /mnt/data/services/ollama/models"
fi

# Check 13: ollama maps to correct container path /root/.ollama
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OL_VOLUMES" | grep -q "/root/.ollama"; then
    print_pass "ollama maps to /root/.ollama (Ollama model storage)"
else
    print_fail "ollama does NOT map to /root/.ollama"
fi

# Check 14: ollama volume is read-write (:rw)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OL_VOLUMES" | grep -q ":rw"; then
    print_pass "ollama volume is read-write (:rw)"
else
    print_fail "ollama volume is NOT explicitly :rw"
fi

# Check 15: ollama uses bind mount (absolute host path)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OL_VOLUMES" | grep -qE "^\s*-\s+/"; then
    print_pass "ollama uses bind mount (absolute host path, not named volume)"
else
    print_fail "ollama may use named volume (data lost if volume pruned)"
fi

echo ""

# --- open-webui: Chat history and RAG persistence ---

echo "--- open-webui: Chat history and RAG persistence ---"

OW_BLOCK=$(get_service_block "open-webui" "$OLLAMA_CONTENT")
OW_VOLUMES=$(get_volume_mounts "$OW_BLOCK")

# Check 16: open-webui has a volumes: section
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -n "$OW_VOLUMES" ]]; then
    print_pass "open-webui has volume mounts"
else
    print_fail "open-webui has NO volume mounts (chat history lost on recreate)"
fi

# Check 17: open-webui mounts host path /mnt/data/services/openwebui/data
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OW_VOLUMES" | grep -q "/mnt/data/services/openwebui/data"; then
    print_pass "open-webui mounts /mnt/data/services/openwebui/data (host bind mount)"
else
    print_fail "open-webui does NOT mount /mnt/data/services/openwebui/data"
fi

# Check 18: open-webui maps to correct container path /app/backend/data
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OW_VOLUMES" | grep -q "/app/backend/data"; then
    print_pass "open-webui maps to /app/backend/data (Open WebUI data dir)"
else
    print_fail "open-webui does NOT map to /app/backend/data"
fi

# Check 19: open-webui volume is read-write (:rw)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OW_VOLUMES" | grep -q ":rw"; then
    print_pass "open-webui volume is read-write (:rw)"
else
    print_fail "open-webui volume is NOT explicitly :rw"
fi

# Check 20: open-webui uses bind mount (absolute host path)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OW_VOLUMES" | grep -qE "^\s*-\s+/"; then
    print_pass "open-webui uses bind mount (absolute host path, not named volume)"
else
    print_fail "open-webui may use named volume (data lost if volume pruned)"
fi

echo ""

# ============================================================
# Part C: Cross-cutting persistence guarantees
# ============================================================

echo "--- Cross-cutting: Persistence guarantees ---"

# Check 21: All host paths are under /mnt/data/ (LUKS-encrypted)
TESTS_RUN=$((TESTS_RUN + 1))
ALL_VOLUMES="${DB_VOLUMES}
${WS_VOLUMES}
${OL_VOLUMES}
${OW_VOLUMES}"
NON_LUKS=$(echo "$ALL_VOLUMES" | grep -vE "/mnt/data/" | grep -E "^\s*-\s+/" || true)
if [[ -z "$NON_LUKS" ]]; then
    print_pass "All host volume paths are under /mnt/data/ (LUKS-encrypted)"
else
    print_fail "Some host paths are NOT under /mnt/data/: $NON_LUKS"
fi

# Check 22: No named volumes in wiki.yml (all bind mounts)
TESTS_RUN=$((TESTS_RUN + 1))
# Named volumes would appear as a top-level 'volumes:' key with sub-keys (not just the network external one)
# Check if there's a volumes: section at root level that defines named volumes
WIKI_NAMED=$(echo "$WIKI_CONTENT" | grep -E "^volumes:" || true)
if [[ -z "$WIKI_NAMED" ]]; then
    print_pass "wiki.yml has no named volumes (all bind mounts — safe for down/up)"
else
    print_fail "wiki.yml defines named volumes (risk of data loss on docker volume prune)"
fi

# Check 23: No named volumes in ollama.yml (all bind mounts)
TESTS_RUN=$((TESTS_RUN + 1))
OLLAMA_NAMED=$(echo "$OLLAMA_CONTENT" | grep -E "^volumes:" || true)
if [[ -z "$OLLAMA_NAMED" ]]; then
    print_pass "ollama.yml has no named volumes (all bind mounts — safe for down/up)"
else
    print_fail "ollama.yml defines named volumes (risk of data loss on docker volume prune)"
fi

# Check 24: All 4 stateful services have volume mounts (completeness check)
TESTS_RUN=$((TESTS_RUN + 1))
EXPECTED_SERVICES=("wiki-db" "wiki-server" "ollama" "open-webui")
MISSING_VOLUMES=()
for svc in "${EXPECTED_SERVICES[@]}"; do
    if [[ "$svc" == "wiki-db" || "$svc" == "wiki-server" ]]; then
        block=$(get_service_block "$svc" "$WIKI_CONTENT")
    else
        block=$(get_service_block "$svc" "$OLLAMA_CONTENT")
    fi
    vols=$(get_volume_mounts "$block")
    if [[ -z "$vols" ]]; then
        MISSING_VOLUMES+=("$svc")
    fi
done
if [[ ${#MISSING_VOLUMES[@]} -eq 0 ]]; then
    print_pass "All 4 stateful services (wiki-db, wiki-server, ollama, open-webui) have volume mounts"
else
    print_fail "Services missing volume mounts: ${MISSING_VOLUMES[*]}"
fi

# Check 25: Volume mounts use unique host paths (no two services share same path)
TESTS_RUN=$((TESTS_RUN + 1))
HOST_PATHS=()
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(/[^:]+): ]]; then
        HOST_PATHS+=("${BASH_REMATCH[1]}")
    fi
done <<< "$ALL_VOLUMES"
TOTAL_PATHS=${#HOST_PATHS[@]}
if [[ "$TOTAL_PATHS" -eq 0 ]]; then
    print_fail "No host volume paths found to check for uniqueness"
else
    UNIQUE_PATHS=$(printf '%s\n' "${HOST_PATHS[@]}" | sort -u | wc -l)
    if [[ "$UNIQUE_PATHS" -eq "$TOTAL_PATHS" ]]; then
        print_pass "All volume host paths are unique (no shared mounts between services)"
    else
        print_fail "Duplicate host paths detected — services may overwrite each other's data"
    fi
fi

echo ""

# ============================================================
# Summary
# ============================================================

echo "========================================"
echo "Data Persistence Round-Trip Summary (Phase 5)"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 4 holds: All Phase 5 services use bind-mount volumes under /mnt/data/ — data survives down/up cycle${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 4 violated: Some services may lose data on container recreation${NC}"
    exit 1
fi
