#!/usr/bin/env bash
# Property Test: Archive Inspection Read-Only Safety (Property 13)
# Purpose: Verify that photo_audit.sh and its modules never modify, create,
#          or delete files in the archive directory.
# Validates: Requirements 43.1, 43.3, 43.5
# Usage: bash tests/test_photo_prep_property_readonly.sh

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

AUDIT_SCRIPT="scripts/operations/utils/immich/photo_audit.sh"
if [[ ! -f "$AUDIT_SCRIPT" ]]; then
    echo -e "${RED}✗ FATAL${NC}: photo_audit.sh not found at $AUDIT_SCRIPT"
    exit 1
fi
echo "Using audit script: $AUDIT_SCRIPT"
echo ""

# ─── Setup: Create temporary archive directory with sample files ─────────────

TEMP_ARCHIVE=$(mktemp -d)
trap 'rm -rf "$TEMP_ARCHIVE"' EXIT

echo "Creating temporary archive at: $TEMP_ARCHIVE"

# Create sample files with various extensions
echo "sample jpeg content"    > "$TEMP_ARCHIVE/photo1.jpg"
echo "sample png content"     > "$TEMP_ARCHIVE/image2.png"
echo "sample text content"    > "$TEMP_ARCHIVE/notes.txt"
echo "sample mp4 content"     > "$TEMP_ARCHIVE/video1.mp4"
echo "sample heic content"    > "$TEMP_ARCHIVE/photo3.heic"
echo "sample raw content"     > "$TEMP_ARCHIVE/photo4.CR2"
echo "sample mov content"     > "$TEMP_ARCHIVE/clip.MOV"

# Create a subdirectory with files to test recursive safety
mkdir -p "$TEMP_ARCHIVE/subdir"
echo "nested jpeg content"    > "$TEMP_ARCHIVE/subdir/nested.jpg"
echo "nested png content"     > "$TEMP_ARCHIVE/subdir/nested.png"

echo "Created $(find "$TEMP_ARCHIVE" -type f | wc -l) sample files"
echo ""

echo "========================================"
echo "Property 13: Archive Inspection Read-Only Safety"
echo "========================================"
echo ""

# ─── Record pre-audit state ──────────────────────────────────────────────────

# Record file list (sorted for deterministic comparison)
PRE_FILE_LIST=$(find "$TEMP_ARCHIVE" -type f | sort)
PRE_FILE_COUNT=$(echo "$PRE_FILE_LIST" | wc -l)

# Record checksums of all files
PRE_CHECKSUMS=""
while IFS= read -r file; do
    if command -v md5sum &>/dev/null; then
        checksum=$(md5sum "$file" | awk '{print $1}')
    elif command -v md5 &>/dev/null; then
        checksum=$(md5 -q "$file")
    else
        checksum=$(cksum "$file" | awk '{print $1}')
    fi
    PRE_CHECKSUMS="${PRE_CHECKSUMS}${checksum}  ${file}"$'\n'
done <<< "$PRE_FILE_LIST"

# Record directory list (to detect new directories too)
PRE_DIR_LIST=$(find "$TEMP_ARCHIVE" -type d | sort)

echo "Pre-audit state recorded:"
echo "  Files: $PRE_FILE_COUNT"
echo "  Directories: $(echo "$PRE_DIR_LIST" | wc -l)"
echo ""

# ─── Run the audit script ────────────────────────────────────────────────────

echo "Running photo_audit.sh against temporary archive..."
echo "---"

# Run the audit script; capture exit code but don't fail the test on non-zero
# (exiftool may not be installed, which causes the script to exit 1 — that's OK,
#  we still verify read-only safety regardless of whether the audit succeeded)
AUDIT_EXIT=0
bash "$AUDIT_SCRIPT" "$TEMP_ARCHIVE" > /dev/null 2>&1 || AUDIT_EXIT=$?

if [[ "$AUDIT_EXIT" -eq 0 ]]; then
    echo "Audit script completed successfully (exit code 0)"
else
    echo -e "${YELLOW}Audit script exited with code $AUDIT_EXIT (expected if exiftool/jdupes not installed)${NC}"
    echo "Read-only safety checks still apply regardless of exit code"
fi
echo ""

# ─── Check 1: No new files created in archive directory ──────────────────────

TESTS_RUN=$((TESTS_RUN + 1))
POST_FILE_LIST=$(find "$TEMP_ARCHIVE" -type f | sort)
POST_FILE_COUNT=$(echo "$POST_FILE_LIST" | wc -l)

if [[ "$PRE_FILE_COUNT" -eq "$POST_FILE_COUNT" ]]; then
    print_pass "File count unchanged after audit ($PRE_FILE_COUNT files)"
else
    print_fail "File count changed: before=$PRE_FILE_COUNT, after=$POST_FILE_COUNT"
fi

# ─── Check 2: No files deleted from archive directory ────────────────────────

TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$PRE_FILE_LIST" == "$POST_FILE_LIST" ]]; then
    print_pass "File list identical before and after audit (no files added or removed)"
else
    print_fail "File list differs after audit"
    diff <(echo "$PRE_FILE_LIST") <(echo "$POST_FILE_LIST") || true
fi

# ─── Check 3: All file checksums unchanged ───────────────────────────────────

TESTS_RUN=$((TESTS_RUN + 1))
POST_CHECKSUMS=""
while IFS= read -r file; do
    if command -v md5sum &>/dev/null; then
        checksum=$(md5sum "$file" | awk '{print $1}')
    elif command -v md5 &>/dev/null; then
        checksum=$(md5 -q "$file")
    else
        checksum=$(cksum "$file" | awk '{print $1}')
    fi
    POST_CHECKSUMS="${POST_CHECKSUMS}${checksum}  ${file}"$'\n'
done <<< "$POST_FILE_LIST"

if [[ "$PRE_CHECKSUMS" == "$POST_CHECKSUMS" ]]; then
    print_pass "All file checksums identical after audit (no content modified)"
else
    print_fail "File checksums differ after audit — content was modified"
    diff <(echo "$PRE_CHECKSUMS") <(echo "$POST_CHECKSUMS") || true
fi

# ─── Check 4: No new directories created in archive ─────────────────────────

TESTS_RUN=$((TESTS_RUN + 1))
POST_DIR_LIST=$(find "$TEMP_ARCHIVE" -type d | sort)

if [[ "$PRE_DIR_LIST" == "$POST_DIR_LIST" ]]; then
    print_pass "Directory structure unchanged after audit"
else
    print_fail "Directory structure changed after audit"
    diff <(echo "$PRE_DIR_LIST") <(echo "$POST_DIR_LIST") || true
fi

# ─── Check 5: Audit script uses read-only commands ──────────────────────────

TESTS_RUN=$((TESTS_RUN + 1))
SCRIPT_CONTENT=$(tr -d '\r' < "$AUDIT_SCRIPT")

# Check that the script does NOT use write commands against the archive
WRITE_CMDS_FOUND=false
if echo "$SCRIPT_CONTENT" | grep -qE "(rm |mv |cp |chmod |chown |touch |truncate |tee )" 2>/dev/null; then
    # Exclude comments and echo/printf lines
    WRITE_LINES=$(echo "$SCRIPT_CONTENT" | grep -vE '^\s*#' | grep -vE '^\s*(echo|printf)' | grep -E "(rm |mv |cp |chmod |chown |touch |truncate |tee )" || true)
    if [[ -n "$WRITE_LINES" ]]; then
        WRITE_CMDS_FOUND=true
    fi
fi

if [[ "$WRITE_CMDS_FOUND" == "false" ]]; then
    print_pass "Audit script does not contain write commands targeting archive"
else
    print_fail "Audit script contains potential write commands"
fi

# ─── Check 6: Audit script documents read-only intent ───────────────────────

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SCRIPT_CONTENT" | grep -qi "read.only\|READ-ONLY\|read only"; then
    print_pass "Audit script documents read-only safety intent"
else
    print_fail "Audit script does not document read-only safety"
fi

echo ""
echo "========================================"
echo "Archive Inspection Read-Only Safety Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 13 holds: Archive inspection is read-only safe${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 13 violated: Archive files were modified during inspection${NC}"
    exit 1
fi
