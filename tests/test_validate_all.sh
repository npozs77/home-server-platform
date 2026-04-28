#!/bin/bash
set -euo pipefail

# Unit Tests: validate-all.sh (E2E Validation Script)
# Run: bash tests/test_validate_all.sh

SCRIPT="scripts/operations/validate-all.sh"
UTILS_DIR="scripts/operations/utils"
PASS=0
FAIL=0
TOTAL=0

check() {
    local desc="$1" result="$2"
    TOTAL=$((TOTAL + 1))
    if [[ "$result" == "0" ]]; then
        echo -e "  \033[0;32m✓\033[0m $desc"
        PASS=$((PASS + 1))
    else
        echo -e "  \033[0;31m✗\033[0m $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "Testing: $SCRIPT"
echo ""

# ── Script basics ──
[[ -f "$SCRIPT" ]]; check "Script exists" "$?"
head -1 "$SCRIPT" | grep -q "#!/bin/bash"; check "Proper shebang" "$?"
grep -q "set -euo pipefail" "$SCRIPT"; check "Safety flags" "$?"
bash -n "$SCRIPT" 2>/dev/null; check "Valid bash syntax" "$?"

# ── Sources utilities (no duplication) ──
grep -q "output-utils.sh" "$SCRIPT"; check "Sources output-utils.sh" "$?"
grep -q "env-utils.sh" "$SCRIPT"; check "Sources env-utils.sh" "$?"
grep -q "validation-foundation-utils.sh" "$SCRIPT"; check "Sources validation-foundation-utils.sh" "$?"
grep -q "validation-infrastructure-utils.sh" "$SCRIPT"; check "Sources validation-infrastructure-utils.sh" "$?"
grep -q "validation-core-services-utils.sh" "$SCRIPT"; check "Sources validation-core-services-utils.sh" "$?"
grep -q "validation-photo-management-utils.sh" "$SCRIPT"; check "Sources validation-photo-management-utils.sh" "$?"

# ── Uses registry arrays from utils (NOT local duplicates) ──
grep -q 'PHASE1_CHECKS\[@\]' "$SCRIPT"; check "Uses PHASE1_CHECKS from registry" "$?"
grep -q 'PHASE2_CHECKS\[@\]' "$SCRIPT"; check "Uses PHASE2_CHECKS from registry" "$?"
grep -q 'PHASE3_CHECKS\[@\]' "$SCRIPT"; check "Uses PHASE3_CHECKS from registry" "$?"
grep -q 'PHASE4_CHECKS\[@\]' "$SCRIPT"; check "Uses PHASE4_CHECKS from registry" "$?"
! grep -q '^phase1_checks=' "$SCRIPT"; check "No local phase1_checks duplicate" "$?"
! grep -q '^phase2_checks=' "$SCRIPT"; check "No local phase2_checks duplicate" "$?"
! grep -q '^phase3_checks=' "$SCRIPT"; check "No local phase3_checks duplicate" "$?"
! grep -q '^phase4_checks=' "$SCRIPT"; check "No local phase4_checks duplicate" "$?"

# ── Registries exist in validation utils ──
grep -q "^PHASE1_CHECKS=" "$UTILS_DIR/validation-foundation-utils.sh"; check "PHASE1_CHECKS defined in foundation utils" "$?"
grep -q "^PHASE2_CHECKS=" "$UTILS_DIR/validation-infrastructure-utils.sh"; check "PHASE2_CHECKS defined in infrastructure utils" "$?"
grep -q "^PHASE3_CHECKS=" "$UTILS_DIR/validation-core-services-utils.sh"; check "PHASE3_CHECKS defined in core-services utils" "$?"
grep -q "^PHASE4_CHECKS=" "$UTILS_DIR/validation-photo-management-utils.sh"; check "PHASE4_CHECKS defined in photo-management utils" "$?"

# ── Validation utils syntax ──
bash -n "$UTILS_DIR/validation-foundation-utils.sh" 2>/dev/null; check "validation-foundation-utils.sh syntax valid" "$?"
bash -n "$UTILS_DIR/validation-infrastructure-utils.sh" 2>/dev/null; check "validation-infrastructure-utils.sh syntax valid" "$?"
bash -n "$UTILS_DIR/validation-core-services-utils.sh" 2>/dev/null; check "validation-core-services-utils.sh syntax valid" "$?"
bash -n "$UTILS_DIR/validation-photo-management-utils.sh" 2>/dev/null; check "validation-photo-management-utils.sh syntax valid" "$?"

# ── CLI flags ──
grep -q "\-\-phase" "$SCRIPT"; check "--phase filter support" "$?"
grep -q "\-\-json" "$SCRIPT"; check "--json output support" "$?"
grep -q "\-\-quiet" "$SCRIPT"; check "--quiet mode support" "$?"

# ── Output and exit codes ──
grep -q "E2E VALIDATION SUMMARY" "$SCRIPT"; check "Summary output" "$?"
grep -q "GRAND_TOTAL" "$SCRIPT"; check "Grand total counter" "$?"
grep -q "exit 0" "$SCRIPT"; check "Exit 0 on success" "$?"
grep -q "exit 1" "$SCRIPT"; check "Exit 1 on failure" "$?"
grep -q "exit 2" "$SCRIPT"; check "Exit 2 on config error" "$?"
grep -q "TIMESTAMP" "$SCRIPT"; check "Timestamp for alerting" "$?"
grep -q "PHASE_RESULTS" "$SCRIPT"; check "Per-phase results" "$?"
grep -q "rm -f /tmp/validate_all_output" "$SCRIPT"; check "Temp file cleanup" "$?"
grep -q "EUID" "$SCRIPT"; check "Root privilege check" "$?"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL checks passed"
echo "========================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
