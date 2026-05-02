#!/usr/bin/env bash
# Property Test: Version Pinning - No :latest (Property 3)
# Purpose: Parse all image references from immich.yml; verify no image uses :latest tag;
#          verify Immich images use ${IMMICH_VERSION}; verify non-Immich images have specific version tags
# Validates: Requirements 29.7
# Usage: bash tests/test_phase4_property_version_pinning.sh

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

# Normalize line endings and extract all image: lines (strip leading whitespace)
IMAGE_LINES=$(tr -d '\r' < "$COMPOSE_FILE" | grep -E '^\s+image:' | sed 's/^[[:space:]]*image:[[:space:]]*//')

echo "========================================"
echo "Property 3: Version Pinning (No :latest)"
echo "========================================"
echo ""
echo "Images found:"
echo "$IMAGE_LINES" | while read -r img; do echo "  - $img"; done
echo ""

# Check each image line
while IFS= read -r image_ref; do
    [[ -z "$image_ref" ]] && continue

    # Check 1: No image uses :latest
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$image_ref" | grep -q ":latest"; then
        print_fail "$image_ref uses :latest tag"
    else
        print_pass "$image_ref does not use :latest"
    fi

    # Check 2: Immich images (ghcr.io/immich-app/immich-*) use ${IMMICH_VERSION}
    if echo "$image_ref" | grep -q "ghcr.io/immich-app/immich-"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        if echo "$image_ref" | grep -qF '${IMMICH_VERSION}'; then
            print_pass "$image_ref uses \${IMMICH_VERSION} variable"
        else
            print_fail "$image_ref does NOT use \${IMMICH_VERSION} variable"
        fi
    fi

    # Check 3: Non-Immich images have a specific version tag (contains ":" with something after it)
    if ! echo "$image_ref" | grep -q "ghcr.io/immich-app/immich-"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        if echo "$image_ref" | grep -qE ':[a-zA-Z0-9]'; then
            print_pass "$image_ref has a specific version tag"
        else
            print_fail "$image_ref MISSING specific version tag"
        fi
    fi

done <<< "$IMAGE_LINES"

echo ""
echo "========================================"
echo "Version Pinning Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 3 holds: All images version-pinned, no :latest tags${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 3 violated: Version pinning issues found${NC}"
    exit 1
fi
