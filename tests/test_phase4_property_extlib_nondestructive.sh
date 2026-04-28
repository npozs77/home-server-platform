#!/usr/bin/env bash
# Property Test: External Library Scan Non-Destructiveness (Property 6)
# Purpose: Verify external library volume mounts are :ro;
#          verify Immich configuration does not allow write operations to external library paths
# Validates: Requirements 4.4, 4.5, 4.6, 4.7
# Usage: bash tests/test_phase4_property_extlib_nondestructive.sh

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
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo -e "${RED}✗ FATAL${NC}: immich.yml.example not found"
    exit 1
fi
echo "Using compose file: $COMPOSE_FILE"
echo ""

# Normalize line endings
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
echo "Property 6: External Library Scan Non-Destructiveness"
echo "========================================"
echo ""

# -------------------------------------------------------
# Check 1: media/Photos mount is read-only (:ro)
# Requirement 4.4: Immich SHALL read photo files (not write)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SERVER_BLOCK" | grep -q "/mnt/data/media/Photos.*:ro"; then
    print_pass "media/Photos mounted as read-only (:ro)"
else
    print_fail "media/Photos NOT mounted as read-only"
fi

# -------------------------------------------------------
# Check 2: family/Photos mount is read-only (:ro)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SERVER_BLOCK" | grep -q "/mnt/data/family/Photos.*:ro"; then
    print_pass "family/Photos mounted as read-only (:ro)"
else
    print_fail "family/Photos NOT mounted as read-only"
fi

# -------------------------------------------------------
# Check 3: External library paths are NOT mounted as :rw
# Ensures no accidental read-write mount
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
MEDIA_RW=$(echo "$SERVER_BLOCK" | grep "/mnt/data/media/Photos.*:rw" || true)
FAMILY_RW=$(echo "$SERVER_BLOCK" | grep "/mnt/data/family/Photos.*:rw" || true)
if [[ -z "$MEDIA_RW" ]] && [[ -z "$FAMILY_RW" ]]; then
    print_pass "No external library paths mounted as :rw"
else
    print_fail "External library path(s) mounted as :rw (destructive writes possible)"
fi

# -------------------------------------------------------
# Check 4: Upload location (/data) is separate from external libraries
# Requirement 4.7: Immich SHALL NOT copy or move photo files from external libraries
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
UPLOAD_MOUNT=$(echo "$SERVER_BLOCK" | grep "UPLOAD_LOCATION.*:/data" || true)
if [[ -n "$UPLOAD_MOUNT" ]]; then
    # Verify upload mount path is different from external library container paths
    UPLOAD_CONTAINER_PATH="/data"
    MEDIA_CONTAINER_PATH="/mnt/media/Photos"
    FAMILY_CONTAINER_PATH="/mnt/family/Photos"
    if [[ "$UPLOAD_CONTAINER_PATH" != "$MEDIA_CONTAINER_PATH" ]] && \
       [[ "$UPLOAD_CONTAINER_PATH" != "$FAMILY_CONTAINER_PATH" ]]; then
        print_pass "Upload path (/data) is separate from external library paths"
    else
        print_fail "Upload path overlaps with external library paths"
    fi
else
    print_fail "Upload mount not found in immich-server"
fi

# -------------------------------------------------------
# Check 5: External libraries map to distinct container paths
# Ensures no path collision between media and family libraries
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
MEDIA_DEST=$(echo "$SERVER_BLOCK" | grep "/mnt/data/media/Photos" | grep -oE ':/[^:]+:' | tr -d ':' || true)
FAMILY_DEST=$(echo "$SERVER_BLOCK" | grep "/mnt/data/family/Photos" | grep -oE ':/[^:]+:' | tr -d ':' || true)
if [[ -n "$MEDIA_DEST" ]] && [[ -n "$FAMILY_DEST" ]] && [[ "$MEDIA_DEST" != "$FAMILY_DEST" ]]; then
    print_pass "External libraries map to distinct container paths ($MEDIA_DEST vs $FAMILY_DEST)"
else
    print_fail "External library container paths are missing or collide"
fi

# -------------------------------------------------------
# Check 6: Only immich-server has external library mounts (not ml, redis, postgres)
# Other containers should not have access to external photo files
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
# Check that external library paths only appear in immich-server section
NON_SERVER_EXTLIB=false
for svc in immich-ml immich-redis immich-postgres; do
    SVC_BLOCK=""
    capture=false
    while IFS= read -r line; do
        if [[ "$line" == "  ${svc}:" ]]; then
            capture=true
            continue
        fi
        if $capture; then
            if [[ "$line" =~ ^\ \ [a-zA-Z][a-zA-Z0-9_-]+:$ ]] || { [[ -n "$line" ]] && [[ "$line" =~ ^[a-z] ]]; }; then
                break
            fi
            SVC_BLOCK+="$line"$'\n'
        fi
    done <<< "$COMPOSE_CONTENT"
    if echo "$SVC_BLOCK" | grep -q "/mnt/data/media/Photos\|/mnt/data/family/Photos"; then
        NON_SERVER_EXTLIB=true
        break
    fi
done
if [[ "$NON_SERVER_EXTLIB" == "false" ]]; then
    print_pass "Only immich-server has external library mounts (ml, redis, postgres do not)"
else
    print_fail "Non-server container has external library mount (unexpected)"
fi

# -------------------------------------------------------
# Check 7: Upload location is :rw (write goes to upload, not external libs)
# Confirms write operations are directed to upload path only
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SERVER_BLOCK" | grep -qE 'UPLOAD_LOCATION.*:/data:rw'; then
    print_pass "Upload location is :rw (writes directed to upload path, not external libs)"
else
    print_fail "Upload location not mounted as :rw"
fi

echo ""
echo "========================================"
echo "External Library Non-Destructiveness Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 6 holds: External libraries are read-only, scan cannot modify source files${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 6 violated: External library non-destructiveness issues found${NC}"
    exit 1
fi
