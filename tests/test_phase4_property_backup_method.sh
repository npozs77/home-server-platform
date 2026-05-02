#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Database Backup Method (Property 8)
# Purpose: Verify backup script calls pg_dump (not cp/rsync on postgres dir);
#          verify pg_dump exit code is checked;
#          verify external photo libraries are backed up (incremental rsync)
# Validates: Requirements 15.1, 15.3, 15.4, 15.6
# Usage: bash tests/test_phase4_property_backup_method.sh

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

BACKUP_SCRIPT="scripts/backup/backup-immich.sh"
if [[ ! -f "$BACKUP_SCRIPT" ]]; then
    echo -e "${RED}✗ FATAL${NC}: backup-immich.sh not found"
    exit 1
fi
echo "Using backup script: $BACKUP_SCRIPT"
echo ""

# Normalize line endings
SCRIPT_CONTENT=$(tr -d '\r' < "$BACKUP_SCRIPT")

echo "========================================"
echo "Property 8: Database Backup Method"
echo "========================================"
echo ""

# -------------------------------------------------------
# Check 1: Script calls pg_dump for database backup
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SCRIPT_CONTENT" | grep -q "pg_dump"; then
    print_pass "Backup script calls pg_dump"
else
    print_fail "Backup script does NOT call pg_dump"
fi

# -------------------------------------------------------
# Check 2: pg_dump runs against the postgres container (docker exec)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SCRIPT_CONTENT" | grep -qE "docker exec.*pg_dump"; then
    print_pass "pg_dump runs via docker exec against postgres container"
else
    print_fail "pg_dump does NOT run via docker exec"
fi

# -------------------------------------------------------
# Check 3: Script does NOT use cp or filesystem copy on postgres data dir
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SCRIPT_CONTENT" | grep -qE "(cp|rsync).*postgres/"; then
    print_fail "Script uses cp/rsync on postgres data directory (unsafe)"
else
    print_pass "Script does NOT use cp/rsync on postgres data directory"
fi

# -------------------------------------------------------
# Check 4: pg_dump exit code is checked (if ! ... or $? or set -e)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
PG_DUMP_EXIT_CHECKED=false
# Pattern 1: if ! docker exec ... pg_dump (explicit check)
if echo "$SCRIPT_CONTENT" | grep -qE "if !.*pg_dump"; then
    PG_DUMP_EXIT_CHECKED=true
fi
# Pattern 2: pg_dump ... || (short-circuit on failure)
if echo "$SCRIPT_CONTENT" | grep -qE "pg_dump.*\|\|"; then
    PG_DUMP_EXIT_CHECKED=true
fi
# Pattern 3: set -e is active (any non-zero exit aborts script)
if echo "$SCRIPT_CONTENT" | grep -qE "set -e(uo pipefail)?"; then
    PG_DUMP_EXIT_CHECKED=true
fi
if [[ "$PG_DUMP_EXIT_CHECKED" == "true" ]]; then
    print_pass "pg_dump exit code is checked (explicit check or set -e)"
else
    print_fail "pg_dump exit code is NOT checked"
fi

# -------------------------------------------------------
# Check 5: Script handles pg_dump failure (cleanup/alert)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SCRIPT_CONTENT" | grep -qE "pg_dump.*fail|cleanup_on_failure.*pg_dump|pg_dump failed"; then
    print_pass "Script handles pg_dump failure with error handling"
else
    print_fail "Script does NOT handle pg_dump failure explicitly"
fi

# -------------------------------------------------------
# Check 6: pg_dump output is saved to a file (not discarded)
# Accepts: redirect to .sql literal OR to a variable defined with .sql suffix
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
PG_DUMP_SAVED=false
# Pattern 1: pg_dump ... > something.sql (literal)
if echo "$SCRIPT_CONTENT" | grep -qE "pg_dump.*>.*\.sql"; then
    PG_DUMP_SAVED=true
fi
# Pattern 2: pg_dump output redirected to a variable, and that variable is defined with .sql
if [[ "$PG_DUMP_SAVED" == "false" ]]; then
    # Get the redirect target after > on the pg_dump line
    REDIRECT_TARGET=$(echo "$SCRIPT_CONTENT" | grep -E 'pg_dump' | grep -oE '> *"?\$[A-Z_{}]+"?' | head -1 || true)
    if [[ -n "$REDIRECT_TARGET" ]]; then
        # Extract variable name from redirect target (e.g., > "$DB_DUMP_FILE" → DB_DUMP_FILE)
        REDIRECT_VAR=$(echo "$REDIRECT_TARGET" | grep -oE '[A-Z_]+' | head -1)
        if [[ -n "$REDIRECT_VAR" ]] && echo "$SCRIPT_CONTENT" | grep -qE "${REDIRECT_VAR}=.*\.sql"; then
            PG_DUMP_SAVED=true
        fi
    fi
fi
if [[ "$PG_DUMP_SAVED" == "true" ]]; then
    print_pass "pg_dump output is saved to a .sql file"
else
    print_fail "pg_dump output is NOT saved to a .sql file"
fi

# -------------------------------------------------------
# Check 7: Script uses set -euo pipefail for strict error handling
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SCRIPT_CONTENT" | grep -q "set -euo pipefail"; then
    print_pass "Script uses set -euo pipefail (strict error handling)"
else
    print_fail "Script does NOT use set -euo pipefail"
fi

# -------------------------------------------------------
# Check 8: Script backs up /mnt/data/media/Photos (external library)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SCRIPT_CONTENT" | grep -qE "media/Photos|MEDIA_PHOTOS_DIR"; then
    print_pass "Script references Media Photos external library"
else
    print_fail "Script does NOT back up Media Photos external library"
fi

# -------------------------------------------------------
# Check 9: Script backs up /mnt/data/family/Photos (external library)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SCRIPT_CONTENT" | grep -qE "family/Photos|FAMILY_PHOTOS_DIR"; then
    print_pass "Script references Family Photos external library"
else
    print_fail "Script does NOT back up Family Photos external library"
fi

# -------------------------------------------------------
# Check 10: External library backup uses rsync (incremental)
# -------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
MEDIA_RSYNC=$(echo "$SCRIPT_CONTENT" | grep -cE "rsync.*media.photos|rsync.*MEDIA_PHOTOS|MEDIA_PHOTOS.*rsync" || true)
FAMILY_RSYNC=$(echo "$SCRIPT_CONTENT" | grep -cE "rsync.*family.photos|rsync.*FAMILY_PHOTOS|FAMILY_PHOTOS.*rsync" || true)
if [[ "$MEDIA_RSYNC" -gt 0 ]] && [[ "$FAMILY_RSYNC" -gt 0 ]]; then
    print_pass "External libraries backed up via rsync (incremental)"
else
    print_fail "External libraries NOT backed up via rsync"
fi

echo ""
echo "========================================"
echo "Database Backup Method Summary"
echo "========================================"
echo "Checks run:    $TESTS_RUN"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 8 holds: Backup uses pg_dump with proper exit code checking, external libraries included${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 8 violated: Database backup method issues found${NC}"
    exit 1
fi
