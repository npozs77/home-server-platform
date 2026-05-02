#!/usr/bin/env bash
# Property Test: Backup Method — pg_dump Only (Property 11)
# Purpose: Verify backup script calls pg_dump (not cp/rsync on postgres dir);
#          verify pg_dump exit code is checked; verify rsync of wiki/content,
#          openwebui/data, and ollama/models directories
# Validates: Requirements 15.1, 15.4
# Usage: bash tests/test_phase5_property_backup_pgdump.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Resolve backup script (prefer the actual script, fall back to source)
BACKUP_SCRIPT=""
if [[ -f "scripts/backup/backup-wiki-llm.sh" ]]; then
    BACKUP_SCRIPT="scripts/backup/backup-wiki-llm.sh"
else
    echo -e "${RED}✗ FATAL${NC}: backup-wiki-llm.sh not found"
    exit 1
fi

echo "========================================"
echo "Property 11: Backup Method — pg_dump Only (Phase 5)"
echo "========================================"
echo ""
echo "Using backup script: $BACKUP_SCRIPT"
echo ""

CONTENT=$(cat "$BACKUP_SCRIPT")

# --- Property 11a: pg_dump is used for database backup ---

echo "--- 11a: pg_dump usage ---"

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONTENT" | grep -q "pg_dump"; then
    print_pass "Backup script calls pg_dump"
else
    print_fail "Backup script does NOT call pg_dump"
fi

# Verify pg_dump targets wiki-db container
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONTENT" | grep -q "wiki-db\|WIKI_DB_CONTAINER"; then
    print_pass "pg_dump targets wiki-db container"
else
    print_fail "pg_dump does not target wiki-db container"
fi

# --- Property 11b: No filesystem copy of postgres directory ---

echo ""
echo "--- 11b: No filesystem copy of postgres dir ---"

TESTS_RUN=$((TESTS_RUN + 1))
if ! echo "$CONTENT" | grep -qE "rsync.*postgres/|cp.*postgres/|rsync.*wiki/postgres"; then
    print_pass "No rsync/cp of postgres data directory (correct — uses pg_dump)"
else
    print_fail "Script copies postgres data directory directly (should use pg_dump only)"
fi

# --- Property 11c: pg_dump exit code is checked ---

echo ""
echo "--- 11c: pg_dump exit code verification ---"

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONTENT" | grep -qE "PG_EXIT|cleanup_on_failure.*pg_dump|if.*!.*pg_dump"; then
    print_pass "pg_dump exit code is checked"
else
    print_fail "pg_dump exit code is NOT checked"
fi

# Verify failed dump file is cleaned up
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONTENT" | grep -qE "rm -f.*DB_DUMP_FILE|rm.*DUMP_FILE"; then
    print_pass "Failed dump file is cleaned up on error"
else
    print_fail "Failed dump file is NOT cleaned up on error"
fi

# --- Property 11d: rsync of required data directories ---

echo ""
echo "--- 11d: rsync of required data directories ---"

# Wiki content directory (markdown page exports)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONTENT" | grep -qE "rsync.*wiki/content|WIKI_CONTENT_DIR"; then
    print_pass "Backup includes wiki content directory (markdown exports)"
else
    print_fail "Backup MISSING wiki content directory"
fi

# Open WebUI data directory (chat history, RAG embeddings)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONTENT" | grep -qE "rsync.*openwebui/data|OPENWEBUI_DATA_DIR"; then
    print_pass "Backup includes Open WebUI data directory"
else
    print_fail "Backup MISSING Open WebUI data directory"
fi

# Ollama models — NOT backed up (multi-GB, re-pullable via 'ollama pull')
TESTS_RUN=$((TESTS_RUN + 1))
if ! echo "$CONTENT" | grep -qE "rsync.*ollama|OLLAMA_MODELS_DIR"; then
    print_pass "Backup correctly excludes Ollama models (re-pullable)"
else
    print_fail "Backup should NOT rsync Ollama models (they are re-pullable)"
fi

# --- Property 11e: Email alert on failure ---

echo ""
echo "--- 11e: Email alert on failure ---"

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONTENT" | grep -q "send_alert_email"; then
    print_pass "Backup script sends email alert on failure"
else
    print_fail "Backup script MISSING email alert on failure"
fi

# --- Property 11f: Script is cron-ready ---

echo ""
echo "--- 11f: Cron readiness ---"

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONTENT" | grep -q "set -euo pipefail"; then
    print_pass "Script has strict error handling (set -euo pipefail)"
else
    print_fail "Script MISSING strict error handling"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONTENT" | grep -q "exit 0"; then
    print_pass "Script exits with code 0 on success"
else
    print_fail "Script MISSING exit 0 on success"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONTENT" | grep -qE "exit [1-9]"; then
    print_pass "Script exits with non-zero on failure"
else
    print_fail "Script MISSING non-zero exit on failure"
fi

# --- Summary ---

echo ""
echo "========================================"
echo "Backup Method Property Summary (Phase 5)"
echo "========================================"
echo "Checks run:  $TESTS_RUN"
echo -e "Passed:      ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:    ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 11 holds: Backup uses pg_dump (not filesystem copy), checks exit code, rsyncs all required directories${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 11 violated: Backup method requirements not fully met${NC}"
    exit 1
fi
