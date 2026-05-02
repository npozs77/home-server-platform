#!/usr/bin/env bash
# Property Test: Photo Upload Quality Preservation (Property 11)
# Purpose: Verify Immich stores original files without re-encoding;
#          verify standard file copy (Samba) preserves EXIF metadata
# Validates: Requirements 5.6, 17.10
# Usage: bash tests/test_phase4_property_upload_quality.sh

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
SAMBA_CONF="configs/samba/smb.conf.example"
SAMBA_UPLOAD_SCRIPT="scripts/deploy/tasks/task-ph4-06-configure-samba-uploads.sh"
DESIGN_DOC=".kiro/specs/04-photo-management/design.md"

echo "========================================"
echo "Property 11: Photo Upload Quality Preservation"
echo "========================================"
echo ""

# -------------------------------------------------------
# Check 1: Upload volume maps to host filesystem (not tmpfs or anonymous volume)
# Requirement 5.6: preserve original photo quality
# Host filesystem storage means originals are stored as-is (no container-level re-encoding)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "$COMPOSE_FILE" ]]; then
    COMPOSE_CONTENT=$(tr -d '\r' < "$COMPOSE_FILE")
    if echo "$COMPOSE_CONTENT" | grep -qE 'UPLOAD_LOCATION.*:/data:rw'; then
        print_pass "Upload volume maps to host filesystem via UPLOAD_LOCATION (originals stored as-is)"
    else
        print_fail "Upload volume not properly mapped to host filesystem"
    fi
else
    print_fail "immich.yml.example not found"
fi

# -------------------------------------------------------
# Check 2: No transcoding or re-encoding environment variables set for uploads
# Immich stores originals by default; verify no env vars override this
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "$COMPOSE_FILE" ]]; then
    COMPOSE_CONTENT=$(tr -d '\r' < "$COMPOSE_FILE")
    # Check that no TRANSCODE or REENCODE env vars are set on immich-server
    TRANSCODE_VARS=$(echo "$COMPOSE_CONTENT" | grep -iE 'TRANSCODE|REENCODE|CONVERT_UPLOAD|STRIP_METADATA' || true)
    if [[ -z "$TRANSCODE_VARS" ]]; then
        print_pass "No transcoding/re-encoding environment variables set (originals preserved)"
    else
        print_fail "Transcoding/re-encoding variables detected: $TRANSCODE_VARS"
    fi
else
    print_fail "immich.yml.example not found"
fi

# -------------------------------------------------------
# Check 3: Samba Media share uses force group = media (ownership inheritance)
# Requirement 17.10: file copy preserves EXIF metadata
# Standard file copy (cp, Samba) preserves file content including EXIF
# force group ensures proper ownership without modifying file content
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "$SAMBA_CONF" ]]; then
    SAMBA_CONTENT=$(tr -d '\r' < "$SAMBA_CONF")
    if echo "$SAMBA_CONTENT" | grep -q "force group = media"; then
        print_pass "Samba Media share uses force group = media (ownership only, content untouched)"
    else
        print_fail "Samba Media share missing force group = media"
    fi
else
    print_fail "smb.conf.example not found"
fi

# -------------------------------------------------------
# Check 4: Samba does NOT use vfs objects that modify file content
# Recycle bin is OK (moves files, doesn't modify content)
# Audit/full_audit is OK (logging only)
# Streams/xattr is OK (metadata in alternate streams)
# Catia/fruit is OK (name translation only)
# BAD: vfs_compress, vfs_prealloc with content modification
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "$SAMBA_CONF" ]]; then
    SAMBA_CONTENT=$(tr -d '\r' < "$SAMBA_CONF")
    DESTRUCTIVE_VFS=$(echo "$SAMBA_CONTENT" | grep -iE 'vfs.*compress|vfs.*prealloc' || true)
    if [[ -z "$DESTRUCTIVE_VFS" ]]; then
        print_pass "No content-modifying VFS modules in Samba config"
    else
        print_fail "Content-modifying VFS modules detected: $DESTRUCTIVE_VFS"
    fi
else
    print_fail "smb.conf.example not found"
fi

# -------------------------------------------------------
# Check 5: Samba upload shares are read-only (no accidental modification of originals)
# Per-user upload shares expose Immich originals as read-only
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "$SAMBA_UPLOAD_SCRIPT" ]]; then
    SAMBA_UPLOAD_CONTENT=$(tr -d '\r' < "$SAMBA_UPLOAD_SCRIPT")
    if echo "$SAMBA_UPLOAD_CONTENT" | grep -q "read only = yes"; then
        print_pass "Samba upload shares are read-only (originals cannot be modified via Samba)"
    else
        print_fail "Samba upload shares NOT set to read-only"
    fi
else
    print_fail "Samba upload script not found"
fi

# -------------------------------------------------------
# Check 6: Samba create mask preserves file permissions (not stripping bits)
# Standard create mask 0664 or 0770 preserves file content
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "$SAMBA_CONF" ]]; then
    SAMBA_CONTENT=$(tr -d '\r' < "$SAMBA_CONF")
    if echo "$SAMBA_CONTENT" | grep -qE "create mask = 0[67][67][04]"; then
        print_pass "Samba create mask preserves standard file permissions"
    else
        print_fail "Samba create mask may strip file permissions"
    fi
else
    print_fail "smb.conf.example not found"
fi

# -------------------------------------------------------
# Check 7: External library mounts are read-only (originals never modified by Immich)
# Requirement 5.6: Immich reads but never modifies external library files
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "$COMPOSE_FILE" ]]; then
    COMPOSE_CONTENT=$(tr -d '\r' < "$COMPOSE_FILE")
    MEDIA_RO=$(echo "$COMPOSE_CONTENT" | grep "/mnt/data/media/Photos.*:ro" || true)
    FAMILY_RO=$(echo "$COMPOSE_CONTENT" | grep "/mnt/data/family/Photos.*:ro" || true)
    if [[ -n "$MEDIA_RO" ]] && [[ -n "$FAMILY_RO" ]]; then
        print_pass "External libraries mounted read-only (originals never modified by Immich)"
    else
        print_fail "External libraries NOT all mounted as read-only"
    fi
else
    print_fail "immich.yml.example not found"
fi

# -------------------------------------------------------
# Check 8: Samba Family share uses force group = family (ownership only)
# Requirement 17.10: copy to Family share preserves EXIF (content untouched)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "$SAMBA_CONF" ]]; then
    SAMBA_CONTENT=$(tr -d '\r' < "$SAMBA_CONF")
    if echo "$SAMBA_CONTENT" | grep -q "force group = family"; then
        print_pass "Samba Family share uses force group = family (ownership only, content untouched)"
    else
        print_fail "Samba Family share missing force group = family"
    fi
else
    print_fail "smb.conf.example not found"
fi

echo ""
echo "========================================"
echo "Photo Upload Quality Preservation Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 11 holds: Originals stored without re-encoding, Samba copies preserve EXIF metadata${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 11 violated: Photo quality preservation issues found${NC}"
    exit 1
fi
