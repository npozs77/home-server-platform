#!/usr/bin/env bash
# CI_SAFE=true
# Test Suite: Photo Prep (Archive Inspection) Scripts
# Purpose: Validate photo audit orchestrator and module scripts
# Requirements: 43.1, 43.3, 52.1, 53.1-53.8
# Usage: bash tests/test_photo_prep_scripts.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
print_warn() { echo -e "${YELLOW}⚠ WARN${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }

run_test() { TESTS_RUN=$((TESTS_RUN + 1)); echo ""; echo "Test $TESTS_RUN: $1"; echo "----------------------------------------"; }

# Script paths
SCRIPT_DIR="scripts/operations/utils/immich"
ORCHESTRATOR="$SCRIPT_DIR/photo_audit.sh"
METADATA="$SCRIPT_DIR/metadata_report.sh"
DUPLICATE="$SCRIPT_DIR/duplicate_scan.sh"
YEAR_DIST="$SCRIPT_DIR/year_distribution.sh"
META_FIX="$SCRIPT_DIR/metadata_fix.sh"
META_AUTOFILL="$SCRIPT_DIR/metadata_autofill.sh"
ALL_SCRIPTS=("$ORCHESTRATOR" "$METADATA" "$DUPLICATE" "$YEAR_DIST" "$META_FIX" "$META_AUTOFILL")
ALL_NAMES=("photo_audit.sh" "metadata_report.sh" "duplicate_scan.sh" "year_distribution.sh" "metadata_fix.sh" "metadata_autofill.sh")

# LOC limit for orchestrator and modules
LOC_LIMIT=250

# --- Script Existence Tests ---

test_scripts_exist() {
    run_test "All four scripts exist"
    for i in "${!ALL_SCRIPTS[@]}"; do
        [[ -f "${ALL_SCRIPTS[$i]}" ]] && print_pass "${ALL_NAMES[$i]} exists" || print_fail "${ALL_NAMES[$i]} does not exist"
    done
}

# --- Shebang Tests ---

test_shebang() {
    run_test "All scripts have proper shebang (#!/bin/bash)"
    for i in "${!ALL_SCRIPTS[@]}"; do
        local script="${ALL_SCRIPTS[$i]}"
        [[ -f "$script" ]] || { print_fail "${ALL_NAMES[$i]} not found (skipping shebang check)"; continue; }
        local first_line
        first_line=$(head -n 1 "$script")
        [[ "$first_line" == "#!/bin/bash" ]] && print_pass "${ALL_NAMES[$i]} shebang correct" || print_fail "${ALL_NAMES[$i]} shebang incorrect: $first_line"
    done
}

# --- Safety Flags Tests ---

test_safety_flags() {
    run_test "All scripts have set -euo pipefail"
    for i in "${!ALL_SCRIPTS[@]}"; do
        local script="${ALL_SCRIPTS[$i]}"
        [[ -f "$script" ]] || { print_fail "${ALL_NAMES[$i]} not found (skipping safety flags check)"; continue; }
        grep -q "^set -euo pipefail" "$script" && print_pass "${ALL_NAMES[$i]} safety flags present" || print_fail "${ALL_NAMES[$i]} safety flags missing"
    done
}

# --- Syntax Check Tests ---

test_syntax() {
    run_test "All scripts pass bash -n syntax check"
    for i in "${!ALL_SCRIPTS[@]}"; do
        local script="${ALL_SCRIPTS[$i]}"
        [[ -f "$script" ]] || { print_fail "${ALL_NAMES[$i]} not found (skipping syntax check)"; continue; }
        if bash -n "$script" 2>/dev/null; then
            print_pass "${ALL_NAMES[$i]} syntax valid"
        else
            print_fail "${ALL_NAMES[$i]} has syntax errors"
        fi
    done
}

# Audit-only scripts (archive directory based)
AUDIT_SCRIPTS=("$ORCHESTRATOR" "$METADATA" "$DUPLICATE" "$YEAR_DIST")
AUDIT_NAMES=("photo_audit.sh" "metadata_report.sh" "duplicate_scan.sh" "year_distribution.sh")

# CSV-based scripts (metadata fix/autofill)
CSV_SCRIPTS=("$META_FIX" "$META_AUTOFILL")
CSV_NAMES=("metadata_fix.sh" "metadata_autofill.sh")

# --- Archive Directory Argument Tests ---

test_archive_dir_argument() {
    run_test "Audit scripts accept archive directory as first argument"
    for i in "${!AUDIT_SCRIPTS[@]}"; do
        local script="${AUDIT_SCRIPTS[$i]}"
        [[ -f "$script" ]] || { print_fail "${AUDIT_NAMES[$i]} not found (skipping argument check)"; continue; }
        # Check for $1 or ${1 usage (first positional argument)
        if grep -qE '\$\{?1[:\}]' "$script"; then
            print_pass "${AUDIT_NAMES[$i]} accepts first argument"
        else
            print_fail "${AUDIT_NAMES[$i]} does not reference first argument (\$1)"
        fi
    done
}

# --- Archive Directory Validation Tests ---

test_archive_dir_validation() {
    run_test "Audit scripts validate archive directory exists and is readable"
    for i in "${!AUDIT_SCRIPTS[@]}"; do
        local script="${AUDIT_SCRIPTS[$i]}"
        [[ -f "$script" ]] || { print_fail "${AUDIT_NAMES[$i]} not found (skipping validation check)"; continue; }
        grep -q '! -d' "$script" && print_pass "${AUDIT_NAMES[$i]} checks directory exists" || print_fail "${AUDIT_NAMES[$i]} missing directory existence check"
        grep -q '! -r' "$script" && print_pass "${AUDIT_NAMES[$i]} checks directory is readable" || print_fail "${AUDIT_NAMES[$i]} missing readability check"
    done
}

# --- Read-Only Safety Tests ---

test_read_only_safety() {
    run_test "Audit scripts use read-only commands only (no write ops on archive)"
    # Dangerous patterns: rm, mv, chmod, chown operating on ARCHIVE_DIR
    local dangerous_patterns=('rm\s' 'mv\s' 'chmod\s' 'chown\s')
    for i in "${!AUDIT_SCRIPTS[@]}"; do
        local script="${AUDIT_SCRIPTS[$i]}"
        [[ -f "$script" ]] || { print_fail "${AUDIT_NAMES[$i]} not found (skipping read-only check)"; continue; }
        local safe=true
        for pattern in "${dangerous_patterns[@]}"; do
            # Check if dangerous command is used with ARCHIVE_DIR or $1
            if grep -E "$pattern" "$script" | grep -qE '\$ARCHIVE_DIR|\$1|\$\{1'; then
                print_fail "${AUDIT_NAMES[$i]} uses write command '$pattern' on archive directory"
                safe=false
            fi
        done
        if $safe; then
            print_pass "${AUDIT_NAMES[$i]} uses read-only commands on archive"
        fi
    done
}

# --- Orchestrator Invokes All Modules ---

test_orchestrator_invokes_modules() {
    run_test "photo_audit.sh invokes all three modules"
    [[ -f "$ORCHESTRATOR" ]] || { print_fail "photo_audit.sh not found (skipping module invocation check)"; return; }
    grep -q "metadata_report.sh" "$ORCHESTRATOR" && print_pass "Invokes metadata_report.sh" || print_fail "Does not invoke metadata_report.sh"
    grep -q "year_distribution.sh" "$ORCHESTRATOR" && print_pass "Invokes year_distribution.sh" || print_fail "Does not invoke year_distribution.sh"
    grep -q "duplicate_scan.sh" "$ORCHESTRATOR" && print_pass "Invokes duplicate_scan.sh" || print_fail "Does not invoke duplicate_scan.sh"
}

# --- metadata_report.sh References exiftool -fast ---

test_metadata_exiftool_fast() {
    run_test "metadata_report.sh references exiftool -fast"
    [[ -f "$METADATA" ]] || { print_fail "metadata_report.sh not found"; return; }
    grep -q "exiftool -fast" "$METADATA" && print_pass "metadata_report.sh uses exiftool -fast" || print_fail "metadata_report.sh missing exiftool -fast"
}

# --- duplicate_scan.sh Handles Missing jdupes Gracefully ---

test_duplicate_jdupes_graceful() {
    run_test "duplicate_scan.sh handles missing jdupes gracefully"
    [[ -f "$DUPLICATE" ]] || { print_fail "duplicate_scan.sh not found"; return; }
    grep -q "command -v jdupes" "$DUPLICATE" && print_pass "duplicate_scan.sh checks for jdupes with 'command -v'" || print_fail "duplicate_scan.sh missing 'command -v jdupes' check"
}

# --- --report Flag Support ---

test_report_flag() {
    run_test "--report flag support present in audit scripts"
    for i in "${!AUDIT_SCRIPTS[@]}"; do
        local script="${AUDIT_SCRIPTS[$i]}"
        [[ -f "$script" ]] || { print_fail "${AUDIT_NAMES[$i]} not found (skipping --report check)"; continue; }
        grep -q "\-\-report" "$script" && print_pass "${AUDIT_NAMES[$i]} supports --report flag" || print_fail "${AUDIT_NAMES[$i]} missing --report flag support"
    done
}

# --- LOC Limits ---

test_loc_limits() {
    run_test "LOC limits (warning on exceed — ${LOC_LIMIT} LOC for orchestrator/modules)"
    for i in "${!ALL_SCRIPTS[@]}"; do
        local script="${ALL_SCRIPTS[$i]}"
        [[ -f "$script" ]] || { print_fail "${ALL_NAMES[$i]} not found (skipping LOC check)"; continue; }
        local line_count
        line_count=$(wc -l < "$script")
        if [[ $line_count -le $LOC_LIMIT ]]; then
            print_pass "${ALL_NAMES[$i]} is $line_count LOC (limit: $LOC_LIMIT)"
        else
            print_warn "${ALL_NAMES[$i]} is $line_count LOC (exceeds indicative limit: $LOC_LIMIT)"
        fi
    done
}

# --- Dependency Validation ---

test_dependency_validation() {
    run_test "Dependency validation present in scripts"
    # exiftool check in photo_audit.sh
    if [[ -f "$ORCHESTRATOR" ]]; then
        grep -q "command -v exiftool\|which exiftool" "$ORCHESTRATOR" && print_pass "photo_audit.sh checks for exiftool" || print_fail "photo_audit.sh missing exiftool dependency check"
    else
        print_fail "photo_audit.sh not found"
    fi

    # exiftool check in metadata_report.sh
    if [[ -f "$METADATA" ]]; then
        grep -q "command -v exiftool\|which exiftool" "$METADATA" && print_pass "metadata_report.sh checks for exiftool" || print_fail "metadata_report.sh missing exiftool dependency check"
    else
        print_fail "metadata_report.sh not found"
    fi

    # jdupes check in duplicate_scan.sh
    if [[ -f "$DUPLICATE" ]]; then
        grep -q "command -v jdupes\|which jdupes" "$DUPLICATE" && print_pass "duplicate_scan.sh checks for jdupes" || print_fail "duplicate_scan.sh missing jdupes dependency check"
    else
        print_fail "duplicate_scan.sh not found"
    fi

    # exiftool check in metadata_fix.sh
    if [[ -f "$META_FIX" ]]; then
        grep -q "command -v exiftool\|which exiftool" "$META_FIX" && print_pass "metadata_fix.sh checks for exiftool" || print_fail "metadata_fix.sh missing exiftool dependency check"
    else
        print_fail "metadata_fix.sh not found"
    fi
}

# --- metadata_fix.sh Specific Tests ---

test_metadata_fix() {
    run_test "metadata_fix.sh validates CSV input and supports --dry-run"
    [[ -f "$META_FIX" ]] || { print_fail "metadata_fix.sh not found"; return; }
    local content
    content=$(cat "$META_FIX")

    # Accepts CSV file as first argument
    echo "$content" | grep -qE '\$\{?1[:\}]' && print_pass "metadata_fix.sh accepts CSV file as first argument" || print_fail "metadata_fix.sh missing first argument"

    # Validates CSV file exists
    echo "$content" | grep -q '! -f' && print_pass "metadata_fix.sh validates CSV file exists" || print_fail "metadata_fix.sh missing file existence check"

    # Checks for FixDateTimeOriginal column
    echo "$content" | grep -q 'FixDateTimeOriginal' && print_pass "metadata_fix.sh checks for FixDateTimeOriginal column" || print_fail "metadata_fix.sh missing FixDateTimeOriginal check"

    # Supports --dry-run
    echo "$content" | grep -q '\-\-dry-run' && print_pass "metadata_fix.sh supports --dry-run flag" || print_fail "metadata_fix.sh missing --dry-run support"

    # Validates date format YYYY:MM:DD HH:MM:SS
    echo "$content" | grep -qE '\[0-9\]\{4\}:\[0-9\]\{2\}' && print_pass "metadata_fix.sh validates date format" || print_fail "metadata_fix.sh missing date format validation"

    # Uses exiftool to write DateTimeOriginal
    echo "$content" | grep -q 'exiftool.*-DateTimeOriginal' && print_pass "metadata_fix.sh writes DateTimeOriginal via exiftool" || print_fail "metadata_fix.sh missing exiftool DateTimeOriginal write"

    # Also writes CreateDate
    echo "$content" | grep -q 'exiftool.*-CreateDate' && print_pass "metadata_fix.sh writes CreateDate via exiftool" || print_fail "metadata_fix.sh missing exiftool CreateDate write"
}

# --- metadata_autofill.sh Specific Tests ---

test_metadata_autofill() {
    run_test "metadata_autofill.sh interactive autofill validation"
    [[ -f "$META_AUTOFILL" ]] || { print_fail "metadata_autofill.sh not found"; return; }
    local content
    content=$(cat "$META_AUTOFILL")

    # Accepts CSV file as first argument
    echo "$content" | grep -qE '\$\{?1[:\}]' && print_pass "metadata_autofill.sh accepts CSV file as first argument" || print_fail "metadata_autofill.sh missing first argument"

    # Validates CSV file exists
    echo "$content" | grep -q '! -f' && print_pass "metadata_autofill.sh validates CSV file exists" || print_fail "metadata_autofill.sh missing file existence check"

    # Checks for FixDateTimeOriginal column
    echo "$content" | grep -q 'FixDateTimeOriginal' && print_pass "metadata_autofill.sh checks for FixDateTimeOriginal column" || print_fail "metadata_autofill.sh missing FixDateTimeOriginal check"

    # Has guess functions (CreateDate, filename, folder)
    echo "$content" | grep -q 'guess_date\|guess_from' && print_pass "metadata_autofill.sh has date guess logic" || print_fail "metadata_autofill.sh missing date guess logic"

    # Reads from /dev/tty for interactive input
    echo "$content" | grep -q '/dev/tty' && print_pass "metadata_autofill.sh reads interactive input from /dev/tty" || print_fail "metadata_autofill.sh missing /dev/tty read"

    # Supports quit (q) to save progress
    echo "$content" | grep -qE '"q"' && print_pass "metadata_autofill.sh supports quit (q) with progress save" || print_fail "metadata_autofill.sh missing quit support"

    # Does NOT modify photo files (only CSV)
    local safe=true
    if echo "$content" | grep -vE '^\s*#' | grep -q 'exiftool'; then
        print_fail "metadata_autofill.sh should NOT call exiftool (CSV-only script)"
        safe=false
    fi
    if $safe; then
        print_pass "metadata_autofill.sh does not modify photo files (CSV-only)"
    fi

    # Plausible date validation
    echo "$content" | grep -q 'is_plausible_date\|plausible' && print_pass "metadata_autofill.sh validates plausible date range" || print_fail "metadata_autofill.sh missing plausible date validation"
}

# --- Main ---

main() {
    echo "========================================"
    echo "Photo Prep Scripts Test Suite"
    echo "========================================"

    test_scripts_exist || true
    test_shebang || true
    test_safety_flags || true
    test_syntax || true
    test_archive_dir_argument || true
    test_archive_dir_validation || true
    test_read_only_safety || true
    test_orchestrator_invokes_modules || true
    test_metadata_exiftool_fast || true
    test_duplicate_jdupes_graceful || true
    test_report_flag || true
    test_loc_limits || true
    test_dependency_validation || true
    test_metadata_fix || true
    test_metadata_autofill || true

    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo "$TESTS_PASSED / $TESTS_RUN checks passed"
    echo "========================================"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        exit 1
    fi
}

main
