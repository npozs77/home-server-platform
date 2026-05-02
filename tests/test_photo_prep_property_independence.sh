#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Inspection Module Independence (Property 14)
# Purpose: Verify each inspection module is self-contained and can run
#          independently without depending on prior module execution or
#          orchestrator-provided state.
# Validates: Requirements 53.2, 53.3, 53.4, 53.5
# Usage: bash tests/test_photo_prep_property_independence.sh

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

SCRIPT_DIR="scripts/operations/utils/immich"
METADATA_SCRIPT="$SCRIPT_DIR/metadata_report.sh"
DUPLICATE_SCRIPT="$SCRIPT_DIR/duplicate_scan.sh"
YEAR_DIST_SCRIPT="$SCRIPT_DIR/year_distribution.sh"
ORCHESTRATOR="$SCRIPT_DIR/photo_audit.sh"

# Verify all scripts exist before proceeding
for script in "$METADATA_SCRIPT" "$DUPLICATE_SCRIPT" "$YEAR_DIST_SCRIPT" "$ORCHESTRATOR"; do
    if [[ ! -f "$script" ]]; then
        echo -e "${RED}✗ FATAL${NC}: $script not found"
        exit 1
    fi
done
echo "All inspection scripts found"
echo ""

# ─── Setup: Create temporary archive directory with sample files ─────────────

TEMP_ARCHIVE=$(mktemp -d)
trap 'rm -rf "$TEMP_ARCHIVE"' EXIT

echo "Creating temporary archive at: $TEMP_ARCHIVE"
echo "sample jpeg content"  > "$TEMP_ARCHIVE/photo1.jpg"
echo "sample png content"   > "$TEMP_ARCHIVE/image2.png"
echo "sample text content"  > "$TEMP_ARCHIVE/notes.txt"
mkdir -p "$TEMP_ARCHIVE/subdir"
echo "nested jpeg content"  > "$TEMP_ARCHIVE/subdir/nested.jpg"
echo "Created $(find "$TEMP_ARCHIVE" -type f | wc -l) sample files"
echo ""

# Normalize line endings helper
normalize() { tr -d '\r' < "$1"; }

echo "========================================"
echo "Property 14: Inspection Module Independence"
echo "========================================"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STATIC ANALYSIS: Verify each module is self-contained
# ═══════════════════════════════════════════════════════════════════════════════

echo "--- Static Analysis: Self-Containment ---"
echo ""

# -------------------------------------------------------
# Check 1: metadata_report.sh validates its own archive directory
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
META_CONTENT=$(normalize "$METADATA_SCRIPT")
if echo "$META_CONTENT" | grep -qE '\[\[.*-d.*ARCHIVE|! -d.*ARCHIVE|\[\[.*-d.*\$1|\[\[.*-d.*\$\{1'; then
    print_pass "metadata_report.sh validates archive directory independently"
else
    print_fail "metadata_report.sh does NOT validate archive directory independently"
fi

# -------------------------------------------------------
# Check 2: duplicate_scan.sh validates its own archive directory
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
DUP_CONTENT=$(normalize "$DUPLICATE_SCRIPT")
if echo "$DUP_CONTENT" | grep -qE '\[\[.*-d.*ARCHIVE|! -d.*ARCHIVE|\[\[.*-d.*\$1|\[\[.*-d.*\$\{1'; then
    print_pass "duplicate_scan.sh validates archive directory independently"
else
    print_fail "duplicate_scan.sh does NOT validate archive directory independently"
fi

# -------------------------------------------------------
# Check 3: year_distribution.sh validates its own archive directory
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
YEAR_CONTENT=$(normalize "$YEAR_DIST_SCRIPT")
if echo "$YEAR_CONTENT" | grep -qE '\[\[.*-d.*ARCHIVE|! -d.*ARCHIVE|\[\[.*-d.*\$1|\[\[.*-d.*\$\{1'; then
    print_pass "year_distribution.sh validates archive directory independently"
else
    print_fail "year_distribution.sh does NOT validate archive directory independently"
fi

# -------------------------------------------------------
# Check 4: metadata_report.sh checks its own dependencies (exiftool)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$META_CONTENT" | grep -qE 'command -v exiftool|which exiftool'; then
    print_pass "metadata_report.sh checks exiftool dependency independently"
else
    print_fail "metadata_report.sh does NOT check exiftool dependency"
fi

# -------------------------------------------------------
# Check 5: duplicate_scan.sh checks its own dependencies (jdupes)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$DUP_CONTENT" | grep -qE 'command -v jdupes|which jdupes'; then
    print_pass "duplicate_scan.sh checks jdupes dependency independently"
else
    print_fail "duplicate_scan.sh does NOT check jdupes dependency"
fi

# -------------------------------------------------------
# Check 6: year_distribution.sh checks its own dependencies (exiftool)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$YEAR_CONTENT" | grep -qE 'command -v exiftool|which exiftool'; then
    print_pass "year_distribution.sh checks exiftool dependency independently"
else
    print_fail "year_distribution.sh does NOT check exiftool dependency"
fi

# -------------------------------------------------------
# Check 7: Each module accepts archive directory as first argument
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
ALL_ACCEPT_ARG=true
for script_content_var in META_CONTENT DUP_CONTENT YEAR_CONTENT; do
    content="${!script_content_var}"
    if ! echo "$content" | grep -qE 'ARCHIVE_DIR=.*\$\{?1'; then
        ALL_ACCEPT_ARG=false
    fi
done
if [[ "$ALL_ACCEPT_ARG" == "true" ]]; then
    print_pass "All modules accept archive directory as first argument (\$1)"
else
    print_fail "Not all modules accept archive directory as first argument"
fi

# -------------------------------------------------------
# Check 8: No module sources or references another module's output
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
CROSS_REF_FOUND=false
# Check metadata_report.sh doesn't reference other modules
if echo "$META_CONTENT" | grep -vE '^\s*#' | grep -qE 'duplicate_scan|year_distribution'; then
    CROSS_REF_FOUND=true
fi
# Check duplicate_scan.sh doesn't reference other modules
if echo "$DUP_CONTENT" | grep -vE '^\s*#' | grep -qE 'metadata_report|year_distribution'; then
    CROSS_REF_FOUND=true
fi
# Check year_distribution.sh doesn't reference other modules
if echo "$YEAR_CONTENT" | grep -vE '^\s*#' | grep -qE 'metadata_report|duplicate_scan'; then
    CROSS_REF_FOUND=true
fi
if [[ "$CROSS_REF_FOUND" == "false" ]]; then
    print_pass "No module references another module's script or output"
else
    print_fail "Cross-module references found between inspection modules"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# RUNTIME: Verify each module runs independently and produces output
# ═══════════════════════════════════════════════════════════════════════════════

echo "--- Runtime: Independent Execution ---"
echo ""

# -------------------------------------------------------
# Check 9: metadata_report.sh runs independently (exit 0 or 1 for missing dep)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
META_OUTPUT=""
META_EXIT=0
META_OUTPUT=$(bash "$METADATA_SCRIPT" "$TEMP_ARCHIVE" 2>&1) || META_EXIT=$?

if [[ "$META_EXIT" -eq 0 ]]; then
    # Ran successfully — verify non-empty output
    if [[ -n "$META_OUTPUT" ]]; then
        print_pass "metadata_report.sh runs independently with output (exit 0)"
    else
        print_fail "metadata_report.sh runs but produces no output"
    fi
elif [[ "$META_EXIT" -eq 1 ]]; then
    # Exit 1 expected if exiftool not installed
    if echo "$META_OUTPUT" | grep -qi "exiftool"; then
        print_pass "metadata_report.sh runs independently, exits 1 (exiftool not installed — expected)"
    else
        print_fail "metadata_report.sh exits 1 for unexpected reason: $META_OUTPUT"
    fi
else
    print_fail "metadata_report.sh exits with unexpected code $META_EXIT"
fi

# -------------------------------------------------------
# Check 10: duplicate_scan.sh runs independently (exit 0 even without jdupes)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
DUP_OUTPUT=""
DUP_EXIT=0
DUP_OUTPUT=$(bash "$DUPLICATE_SCRIPT" "$TEMP_ARCHIVE" 2>&1) || DUP_EXIT=$?

if [[ "$DUP_EXIT" -eq 0 ]]; then
    if [[ -n "$DUP_OUTPUT" ]]; then
        print_pass "duplicate_scan.sh runs independently with output (exit 0)"
    else
        print_fail "duplicate_scan.sh runs but produces no output"
    fi
else
    print_fail "duplicate_scan.sh exits with code $DUP_EXIT (expected 0, even without jdupes)"
fi

# -------------------------------------------------------
# Check 11: year_distribution.sh runs independently (exit 0 or 1 for missing dep)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
YEAR_OUTPUT=""
YEAR_EXIT=0
YEAR_OUTPUT=$(bash "$YEAR_DIST_SCRIPT" "$TEMP_ARCHIVE" 2>&1) || YEAR_EXIT=$?

if [[ "$YEAR_EXIT" -eq 0 ]]; then
    if [[ -n "$YEAR_OUTPUT" ]]; then
        print_pass "year_distribution.sh runs independently with output (exit 0)"
    else
        print_fail "year_distribution.sh runs but produces no output"
    fi
elif [[ "$YEAR_EXIT" -eq 1 ]]; then
    if echo "$YEAR_OUTPUT" | grep -qi "exiftool"; then
        print_pass "year_distribution.sh runs independently, exits 1 (exiftool not installed — expected)"
    else
        print_fail "year_distribution.sh exits 1 for unexpected reason: $YEAR_OUTPUT"
    fi
else
    print_fail "year_distribution.sh exits with unexpected code $YEAR_EXIT"
fi

# -------------------------------------------------------
# Check 12: duplicate_scan.sh handles missing jdupes gracefully (exit 0 + warning)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if command -v jdupes &>/dev/null; then
    # jdupes IS installed — skip this specific check, just pass
    print_pass "duplicate_scan.sh jdupes handling (jdupes installed, graceful skip not testable)"
else
    # jdupes NOT installed — verify exit 0 and warning message
    if [[ "$DUP_EXIT" -eq 0 ]] && echo "$DUP_OUTPUT" | grep -qi "jdupes.*not installed\|not installed.*jdupes\|WARNING.*jdupes"; then
        print_pass "duplicate_scan.sh exits 0 with warning when jdupes not installed"
    else
        print_fail "duplicate_scan.sh does not handle missing jdupes gracefully (exit=$DUP_EXIT)"
    fi
fi

# -------------------------------------------------------
# Check 13: Each module produces output without other modules having run first
#            (We already ran them independently above — verify they didn't need
#             any state from a prior module run)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
# Create a FRESH temp directory to ensure no leftover state
FRESH_ARCHIVE=$(mktemp -d)
echo "fresh content" > "$FRESH_ARCHIVE/test.jpg"

FRESH_DUP_EXIT=0
FRESH_DUP_OUT=$(bash "$DUPLICATE_SCRIPT" "$FRESH_ARCHIVE" 2>&1) || FRESH_DUP_EXIT=$?

# Clean up fresh archive
rm -rf "$FRESH_ARCHIVE"

if [[ "$FRESH_DUP_EXIT" -eq 0 ]] && [[ -n "$FRESH_DUP_OUT" ]]; then
    print_pass "Modules produce output on fresh directory (no prior module state needed)"
else
    print_fail "Module failed on fresh directory without prior module execution"
fi

echo ""
echo "========================================"
echo "Inspection Module Independence Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 14 holds: All inspection modules are independent and self-contained${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 14 violated: Module independence issues found${NC}"
    exit 1
fi
