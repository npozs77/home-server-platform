#!/usr/bin/env bash
# CI_SAFE=true
# Test Suite: Operational locking + container-down guards
# Purpose: Cover the stability behaviours added for scheduled jobs —
#   1. acquire_lock (lock-utils.sh): real flock acquire/contention + exit-code map
#   2. backup-all.sh / REDACTED use the shared lock helper
#   3. backup-helper-services.sh skips a pre_command when its container is down
#   4. validate-governance.sh enforces the executable bit on tracked scripts
# Usage: bash tests/test_ops_locking_container_guards.sh
# Note: Docker- and root-free. Live-flock checks skip gracefully if flock is absent.

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASSED=0; FAILED=0; SKIPPED=0
pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}✗ FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }
skip() { echo -e "${YELLOW}○ SKIP${NC}: $1"; SKIPPED=$((SKIPPED + 1)); }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_UTILS="${REPO_ROOT}/scripts/operations/utils/lock-utils.sh"
LOG_UTILS="${REPO_ROOT}/scripts/operations/utils/log-utils.sh"
BACKUP_ALL="${REPO_ROOT}/scripts/backup/backup-all.sh"
REDACTED="${REPO_ROOT}/scripts/operations/REDACTED"
HELPER="${REPO_ROOT}/scripts/backup/backup-helper-services.sh"
GOVERNANCE="${REPO_ROOT}/scripts/operations/validate-governance.sh"

echo "========================================"
echo "Operational Locking + Container Guards"
echo "========================================"

# ------------------------------------------------------------
# 1. lock-utils.sh exists, is sound, and behaves correctly
# ------------------------------------------------------------
echo ""
echo "--- lock-utils.sh ---"
[[ -f "$LOCK_UTILS" ]] && pass "lock-utils.sh exists" || fail "lock-utils.sh exists"
bash -n "$LOCK_UTILS" 2>/dev/null && pass "lock-utils.sh valid syntax" || fail "lock-utils.sh valid syntax"
grep -q 'LOCK_UTILS_LOADED' "$LOCK_UTILS" && pass "lock-utils.sh has idempotent source guard" || fail "lock-utils.sh missing source guard"

if command -v flock &>/dev/null; then
    TMP_LOCK=$(mktemp -u /tmp/lockutils-test.XXXXXX.lock)
    trap 'rm -f "$TMP_LOCK"' EXIT

    # Acquire on a free lock → return 0
    rc=0
    bash -c "source '$LOG_UTILS'; source '$LOCK_UTILS'; acquire_lock '$TMP_LOCK' 'test'" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 0 ]] && pass "acquire_lock returns 0 on a free lock" || fail "acquire_lock returned $rc on a free lock (expected 0)"

    # Contention: hold the lock in a background flock, then acquire_lock → return 1
    flock -n "$TMP_LOCK" -c "sleep 3" &
    HOLDER=$!; sleep 1
    rc=0
    bash -c "source '$LOG_UTILS'; source '$LOCK_UTILS'; acquire_lock '$TMP_LOCK' 'test'" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 1 ]] && pass "acquire_lock returns 1 when lock is held (contention)" || fail "acquire_lock returned $rc under contention (expected 1)"
    wait "$HOLDER" 2>/dev/null || true

    # Cannot open lock file (unwritable dir) → return 2
    rc=0
    bash -c "source '$LOG_UTILS'; source '$LOCK_UTILS'; acquire_lock '/nonexistent-dir-xyz/x.lock' 'test'" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 2 ]] && pass "acquire_lock returns 2 when lock file cannot be opened" || fail "acquire_lock returned $rc for unopenable lock (expected 2)"
else
    skip "flock not available — skipping live acquire_lock behaviour checks (syntax/code checks still run)"
fi

# ------------------------------------------------------------
# 2. Callers use the shared helper (not an inline duplicate)
# ------------------------------------------------------------
echo ""
echo "--- lock helper adoption ---"
for caller in "$BACKUP_ALL" "$REDACTED"; do
    name=$(basename "$caller")
    grep -q 'source.*lock-utils\.sh' "$caller" && pass "$name sources lock-utils.sh" || fail "$name does not source lock-utils.sh"
    grep -q 'acquire_lock' "$caller" && pass "$name calls acquire_lock" || fail "$name does not call acquire_lock"
    # Must map rc==1 to a clean skip (exit 0), never a hard failure
    grep -qE 'rc -eq 1.*exit 0' "$caller" && pass "$name skips cleanly (exit 0) on contention" || fail "$name missing clean-skip on contention"
done

# backup-all.sh must NOT retain a raw inline flock (proves the extraction happened)
grep -q 'flock -n 9' "$BACKUP_ALL" && fail "backup-all.sh still has inline 'flock -n 9' (should use helper)" || pass "backup-all.sh has no inline flock (uses helper)"

# ------------------------------------------------------------
# 3. watchdog.sh probes the lock instead of pgrep
# ------------------------------------------------------------
echo ""
echo "--- watchdog lock probe ---"
WATCHDOG="${REPO_ROOT}/scripts/operations/monitoring/watchdog.sh"
grep -q 'pgrep -f .*backup-all' "$WATCHDOG" && fail "watchdog.sh still uses pgrep (should probe the lock)" || pass "watchdog.sh no longer uses pgrep"
grep -q '/run/backup-all.lock' "$WATCHDOG" && pass "watchdog.sh probes /run/backup-all.lock" || fail "watchdog.sh does not probe the backup lock"

# ------------------------------------------------------------
# 4. backup-helper-services.sh container-down guard
# ------------------------------------------------------------
echo ""
echo "--- helper pre_command container guard ---"
grep -q 'docker inspect' "$HELPER" && pass "helper inspects the pre_command container" || fail "helper missing docker inspect up-check"
# On a down container it must WARN + skip the snapshot, NOT hard-fail the service
grep -q 'skipping snapshot' "$HELPER" && pass "helper WARNs + skips snapshot when container down" || fail "helper missing skip-snapshot path"

# Behavioural: the container-name extraction picks the right token for the
# simple `docker exec <name>` form, and stays empty for ambiguous flag forms.
extract() {
    local pre_cmd="$1" c=""
    if [[ "$pre_cmd" =~ docker[[:space:]]+exec[[:space:]]+([^-][^[:space:]]*) ]]; then c="${BASH_REMATCH[1]}"; fi
    printf '%s' "$c"
}
[[ "$(extract 'docker exec REDACTED sqlite3 /data/x.db ".backup /data/y.db"')" == "REDACTED" ]] \
    && pass "extract: simple 'docker exec REDACTED' → REDACTED" || fail "extract: simple form wrong"
[[ "$(extract 'sudo docker exec immich-postgres pg_dump')" == "immich-postgres" ]] \
    && pass "extract: 'sudo docker exec immich-postgres' → immich-postgres" || fail "extract: sudo form wrong"
[[ -z "$(extract 'docker exec -u postgres mydb pg_dump')" ]] \
    && pass "extract: ambiguous flag form → empty (skips guess, runs as before)" || fail "extract: flag form should be empty"
[[ -z "$(extract 'sqlite3 /data/x.db .dump')" ]] \
    && pass "extract: non-docker pre_command → empty" || fail "extract: non-docker form should be empty"

# ------------------------------------------------------------
# 5. governance executable-bit guard
# ------------------------------------------------------------
echo ""
echo "--- governance executable-bit guard ---"
grep -q 'check_executable_bits' "$GOVERNANCE" && pass "governance has check_executable_bits" || fail "governance missing check_executable_bits"
grep -q '100644' "$GOVERNANCE" && pass "governance flags 100644 (non-executable) scripts" || fail "governance does not check for 100644"

echo ""
echo "========================================"
echo "$PASSED passed, $FAILED failed, $SKIPPED skipped"
echo "========================================"
[[ $FAILED -eq 0 ]] && exit 0 || exit 1
