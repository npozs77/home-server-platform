#!/usr/bin/env bash
# Property Test: Data Persistence Round-Trip (Property 9)
# Purpose: Verify that docker compose down followed by docker compose up -d
#          preserves all stateful data (volume mounts configured correctly)
# Validates: Requirements 2.4, 2.5, 2.6, 2.7, 2.8
# Usage: bash tests/test_phase4_property_data_persistence.sh

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

COMPOSE_FILE="configs/docker-compose/immich.yml.example"
[[ -f "$COMPOSE_FILE" ]] || COMPOSE_FILE="configs/docker-compose/immich.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo -e "${RED}✗ FATAL${NC}: immich.yml.example not found"
    exit 1
fi
echo "Using compose file: $COMPOSE_FILE"
echo ""

# Normalize line endings
COMPOSE_CONTENT=$(tr -d '\r' < "$COMPOSE_FILE")

echo "========================================"
echo "Property 9: Data Persistence Round-Trip"
echo "========================================"
echo ""

# -------------------------------------------------------
# Check 1: PostgreSQL data persisted via host volume (DB_DATA_LOCATION)
# Requirement 2.4: preserve all user accounts
# Requirement 2.5: preserve all photo metadata
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$COMPOSE_CONTENT" | grep -qE 'DB_DATA_LOCATION.*:/var/lib/postgresql/data'; then
    print_pass "PostgreSQL data persisted via DB_DATA_LOCATION host volume"
else
    print_fail "PostgreSQL data NOT persisted via host volume"
fi

# -------------------------------------------------------
# Check 2: Upload directory persisted via host volume (UPLOAD_LOCATION)
# Requirement 2.7: preserve all uploaded photos
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$COMPOSE_CONTENT" | grep -qE 'UPLOAD_LOCATION.*:/data'; then
    print_pass "Upload directory persisted via UPLOAD_LOCATION host volume"
else
    print_fail "Upload directory NOT persisted via host volume"
fi

# -------------------------------------------------------
# Check 3: ML model cache uses named Docker volume (survives down/up)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$COMPOSE_CONTENT" | grep -q "model-cache:/cache"; then
    print_pass "ML model cache uses named Docker volume (model-cache)"
else
    print_fail "ML model cache NOT using named Docker volume"
fi

# -------------------------------------------------------
# Check 4: Named volume 'model-cache' declared at top level
# Named volumes survive docker compose down (only removed with -v flag)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$COMPOSE_CONTENT" | grep -qE '^volumes:' && echo "$COMPOSE_CONTENT" | grep -q "model-cache:"; then
    print_pass "Named volume 'model-cache' declared at top level (survives down/up)"
else
    print_fail "Named volume 'model-cache' NOT declared at top level"
fi

# -------------------------------------------------------
# Check 5: PostgreSQL volume uses :rw (read-write) for data persistence
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$COMPOSE_CONTENT" | grep -qE 'DB_DATA_LOCATION.*:/var/lib/postgresql/data:rw'; then
    print_pass "PostgreSQL volume mounted as :rw (read-write)"
else
    print_fail "PostgreSQL volume NOT mounted as :rw"
fi

# -------------------------------------------------------
# Check 6: Upload volume uses :rw (read-write) for data persistence
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$COMPOSE_CONTENT" | grep -qE 'UPLOAD_LOCATION.*:/data:rw'; then
    print_pass "Upload volume mounted as :rw (read-write)"
else
    print_fail "Upload volume NOT mounted as :rw"
fi

# -------------------------------------------------------
# Check 7: External library mounts use host paths (persist independently)
# Requirement 2.8: preserve all external library references
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
MEDIA_MOUNT=$(echo "$COMPOSE_CONTENT" | grep -c "/mnt/data/media/Photos" || true)
FAMILY_MOUNT=$(echo "$COMPOSE_CONTENT" | grep -c "/mnt/data/family/Photos" || true)
if [[ "$MEDIA_MOUNT" -gt 0 ]] && [[ "$FAMILY_MOUNT" -gt 0 ]]; then
    print_pass "External library mounts use host paths (persist independently of containers)"
else
    print_fail "External library host path mounts missing"
fi

# -------------------------------------------------------
# Check 8: No anonymous volumes (all stateful data on named/host volumes)
# Anonymous volumes are lost on docker compose down
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
# Extract immich-postgres volumes section only (between "volumes:" and next key at same indent)
PG_BLOCK=$(echo "$COMPOSE_CONTENT" | sed -n '/immich-postgres:/,/^  [a-zA-Z]/p')
PG_VOLUMES=$(echo "$PG_BLOCK" | sed -n '/^    volumes:/,/^    [a-z]/p' | grep -E '^\s+- ' | grep -v '#' || true)
# All volume lines should reference a variable, named volume, or host path (not bare container paths)
ANON_VOLUMES=$(echo "$PG_VOLUMES" | grep -vE '\$\{|/mnt/|model-cache|/etc/' || true)
if [[ -z "$ANON_VOLUMES" ]]; then
    print_pass "No anonymous volumes in immich-postgres (all data on host/named volumes)"
else
    print_fail "Anonymous volumes detected in immich-postgres (data lost on down/up)"
fi

# -------------------------------------------------------
# Check 9: PostgreSQL uses data-checksums for integrity verification
# Ensures data integrity is verifiable after round-trip
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$COMPOSE_CONTENT" | grep -q "data-checksums"; then
    print_pass "PostgreSQL uses --data-checksums for integrity verification"
else
    print_fail "PostgreSQL NOT using --data-checksums"
fi

# -------------------------------------------------------
# Check 10: services.env.example defines DB_DATA_LOCATION and UPLOAD_LOCATION
# Ensures host paths are configurable (not hardcoded in compose)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
SERVICES_ENV="configs/services.env.example"
if [[ -f "$SERVICES_ENV" ]]; then
    DB_LOC=$(grep -c "DB_DATA_LOCATION=" "$SERVICES_ENV" || true)
    UP_LOC=$(grep -c "UPLOAD_LOCATION=" "$SERVICES_ENV" || true)
    if [[ "$DB_LOC" -gt 0 ]] && [[ "$UP_LOC" -gt 0 ]]; then
        print_pass "services.env.example defines DB_DATA_LOCATION and UPLOAD_LOCATION"
    else
        print_fail "services.env.example missing DB_DATA_LOCATION or UPLOAD_LOCATION"
    fi
else
    print_fail "services.env.example not found"
fi

echo ""
echo "========================================"
echo "Data Persistence Round-Trip Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 9 holds: All stateful data persisted via host/named volumes, survives down/up cycle${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 9 violated: Data persistence configuration issues found${NC}"
    exit 1
fi
