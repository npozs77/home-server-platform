#!/usr/bin/env bash
# CI_SAFE=true
# Test Suite: Core Service Updater
# Purpose: Structural + behavioural checks for the core-service update path —
#   scripts/operations/update-core-service.sh + utils/core-service-utils.sh.
#   Docker- and root-free: verifies conventions, the known-service map, arg
#   rejection, and the backup-before-recreate wiring without touching containers.
# Usage: bash tests/test_core_service_update.sh

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASSED=0; FAILED=0
pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}✗ FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="${REPO_ROOT}/scripts/operations/update-core-service.sh"
UTILS="${REPO_ROOT}/scripts/operations/utils/core-service-utils.sh"

echo "========================================"
echo "Core Service Updater Test Suite"
echo "========================================"

# --- existence, shebang, safety, syntax, LOC ---
for f in "$WRAPPER" "$UTILS"; do
    name=$(basename "$f")
    [[ -f "$f" ]] && pass "${name} exists" || { fail "${name} exists"; continue; }
    [[ -x "$f" ]] && pass "${name} is executable" || fail "${name} is executable"
    [[ "$(head -n1 "$f")" == "#!/bin/bash" || "$(head -n1 "$f")" == "#!/usr/bin/env bash" ]] \
        && pass "${name} has bash shebang" || fail "${name} shebang"
    head -n 5 "$f" | grep -q 'set -euo pipefail' && pass "${name} set -euo pipefail" || fail "${name} safety flags"
    bash -n "$f" 2>/dev/null && pass "${name} valid syntax" || fail "${name} syntax"
    loc=$(wc -l < "$f")
    [[ "$loc" -le 200 ]] && pass "${name} ${loc} LOC (≤200)" || fail "${name} ${loc} LOC exceeds 200"
done

# --- utils: source guard + expected functions ---
grep -q 'CORE_SERVICE_UTILS_LOADED' "$UTILS" && pass "utils has idempotent source guard" || fail "utils missing source guard"
for fn in csu_compose_cmd csu_compose_file csu_run_backup csu_pull csu_recreate csu_wait_healthy; do
    grep -qE "^${fn}\(\)" "$UTILS" && pass "utils defines ${fn}()" || fail "utils missing ${fn}()"
done

# --- wrapper: known-service map covers exactly the compose-based core services ---
for svc in wiki immich ollama jellyfin; do
    grep -qE "^[[:space:]]*${svc}\)" "$WRAPPER" && pass "wrapper handles '${svc}'" || fail "wrapper missing '${svc}'"
done

# --- wrapper: docker-run infra is explicitly rejected, not silently mishandled ---
grep -qE 'caddy\|pihole\|netdata' "$WRAPPER" && pass "wrapper rejects docker-run infra (caddy/pihole/netdata)" \
    || fail "wrapper does not explicitly reject docker-run infra"

# --- wrapper: backup-before-recreate ordering (backup call precedes recreate) ---
backup_line=$(grep -n 'csu_run_backup' "$WRAPPER" | head -1 | cut -d: -f1)
recreate_line=$(grep -n 'csu_recreate' "$WRAPPER" | head -1 | cut -d: -f1)
if [[ -n "$backup_line" && -n "$recreate_line" && "$backup_line" -lt "$recreate_line" ]]; then
    pass "backup runs before recreate (line ${backup_line} < ${recreate_line})"
else
    fail "backup does not precede recreate"
fi

# --- wrapper: correct backup scripts wired per service ---
grep -q 'backup-wiki-llm.sh' "$WRAPPER" && pass "wiki/ollama wired to backup-wiki-llm.sh" || fail "missing backup-wiki-llm.sh wiring"
grep -q 'backup-immich.sh' "$WRAPPER" && pass "immich wired to backup-immich.sh" || fail "missing backup-immich.sh wiring"

# --- behavioural: arg handling (no docker/root needed) ---
# no service → usage, exit 2
out=$(bash "$WRAPPER" 2>&1); rc=$?
[[ $rc -eq 2 ]] && echo "$out" | grep -q "Usage:" && pass "no-arg → usage + exit 2" || fail "no-arg handling (rc=$rc)"

# docker-run infra name → rejected, exit 2
out=$(bash "$WRAPPER" caddy 2>&1); rc=$?
[[ $rc -eq 2 ]] && echo "$out" | grep -qi "docker-run infra" && pass "'caddy' → rejected (docker-run infra), exit 2" || fail "caddy rejection (rc=$rc)"

# unknown service → rejected, exit 2
out=$(bash "$WRAPPER" bogus 2>&1); rc=$?
[[ $rc -eq 2 ]] && echo "$out" | grep -qi "Unknown core service" && pass "unknown service → rejected, exit 2" || fail "unknown service handling (rc=$rc)"

echo ""
echo "========================================"
echo "$((PASSED + FAILED)) checks — ${PASSED} passed, ${FAILED} failed"
echo "========================================"
[[ $FAILED -eq 0 ]] && exit 0 || exit 1
