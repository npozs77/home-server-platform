#!/bin/bash
# CI_SAFE=true
# Unit Tests: Phase 4 Immich User Provisioning Task Module
# Purpose: Validate provisioning script structure, conventions, and logic
# Requirements: 42.1-42.11
# Usage: bash tests/test_phase4_provisioning.sh

# Note: Not using set -e to allow all tests to run even if some fail

# Test framework
TESTS_PASSED=0
TESTS_FAILED=0

print_pass() { echo "✓ PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo "✗ FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
print_warn() { echo "⚠ WARN: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }

SCRIPT="scripts/deploy/tasks/task-ph4-05-provision-immich-users.sh"

echo ""
echo "========================================"
echo "Phase 4: Immich Provisioning Unit Tests"
echo "========================================"

# --- Test 1: Script exists ---
echo ""
echo "--- Test 1: Script exists ---"
if [[ -f "$SCRIPT" ]]; then
    print_pass "Provisioning script exists: $SCRIPT"
else
    print_fail "Provisioning script missing: $SCRIPT"
fi

# --- Test 2: Proper shebang ---
echo ""
echo "--- Test 2: Proper shebang ---"
if [[ -f "$SCRIPT" ]]; then
    first_line=$(head -n 1 "$SCRIPT")
    if [[ "$first_line" == "#!/bin/bash" ]]; then
        print_pass "Shebang is correct (#!/bin/bash)"
    else
        print_fail "Shebang incorrect: $first_line"
    fi
fi

# --- Test 3: Safety flags ---
echo ""
echo "--- Test 3: Safety flags (set -euo pipefail) ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q "^set -euo pipefail" "$SCRIPT"; then
        print_pass "Safety flags present"
    else
        print_fail "Safety flags missing"
    fi
fi

# --- Test 4: Valid bash syntax ---
echo ""
echo "--- Test 4: Valid bash syntax ---"
if [[ -f "$SCRIPT" ]]; then
    if bash -n "$SCRIPT" 2>/dev/null; then
        print_pass "Bash syntax is valid"
    else
        print_fail "Bash syntax errors detected"
    fi
fi

# --- Test 5: Sources foundation.env (ADMIN_USER, ADMIN_EMAIL) ---
echo ""
echo "--- Test 5: Sources foundation.env ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q "foundation.env" "$SCRIPT"; then
        print_pass "References foundation.env"
    else
        print_fail "Does not reference foundation.env"
    fi
    if grep -q "ADMIN_USER" "$SCRIPT" && grep -q "ADMIN_EMAIL" "$SCRIPT"; then
        print_pass "References ADMIN_USER and ADMIN_EMAIL"
    else
        print_fail "Missing ADMIN_USER or ADMIN_EMAIL reference"
    fi
fi

# --- Test 6: Sources services.env and secrets.env ---
echo ""
echo "--- Test 6: Sources services.env and secrets.env ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q "services.env" "$SCRIPT" && grep -q "secrets.env" "$SCRIPT"; then
        print_pass "References services.env and secrets.env"
    else
        print_fail "Missing services.env or secrets.env reference"
    fi
fi

# --- Test 7: References IMMICH_API_KEY ---
echo ""
echo "--- Test 7: References IMMICH_API_KEY ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q "IMMICH_API_KEY" "$SCRIPT"; then
        print_pass "References IMMICH_API_KEY"
    else
        print_fail "Missing IMMICH_API_KEY reference"
    fi
fi

# --- Test 8: References /api/users endpoint ---
echo ""
echo "--- Test 8: References /api/users endpoint ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q "/users" "$SCRIPT"; then
        print_pass "References /api/users endpoint"
    else
        print_fail "Missing /api/users endpoint reference"
    fi
fi

# --- Test 9: References /api/server/ping ---
echo ""
echo "--- Test 9: References /api/server/ping ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q "server/ping" "$SCRIPT"; then
        print_pass "References /api/server/ping endpoint"
    else
        print_fail "Missing /api/server/ping endpoint reference"
    fi
fi

# --- Test 10: Handles --dry-run flag ---
echo ""
echo "--- Test 10: Handles --dry-run flag ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q "\-\-dry-run" "$SCRIPT" && grep -q "DRY_RUN" "$SCRIPT"; then
        print_pass "Handles --dry-run flag"
    else
        print_fail "Missing --dry-run support"
    fi
fi

# --- Test 11: Idempotency logic (GET before POST) ---
echo ""
echo "--- Test 11: Idempotency logic (GET existing users before POST) ---"
if [[ -f "$SCRIPT" ]]; then
    # Script should GET existing users and check before POSTing
    if grep -q "EXISTING_USERS" "$SCRIPT" && grep -q "already exists" "$SCRIPT"; then
        print_pass "Idempotency logic present (checks existing users)"
    else
        print_fail "Missing idempotency logic"
    fi
fi

# --- Test 12: Admin user gets isAdmin=true ---
echo ""
echo "--- Test 12: Admin user gets isAdmin=true ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q 'isAdmin.*true' "$SCRIPT" || grep -q '"true"' "$SCRIPT"; then
        print_pass "Admin user isAdmin=true logic present"
    else
        print_fail "Missing isAdmin=true for admin user"
    fi
fi

# --- Test 13: Non-admin users get isAdmin=false ---
echo ""
echo "--- Test 13: Non-admin users get isAdmin=false ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q 'isAdmin.*false' "$SCRIPT" || grep -q '"false"' "$SCRIPT"; then
        print_pass "Non-admin users isAdmin=false logic present"
    else
        print_fail "Missing isAdmin=false for non-admin users"
    fi
fi

# --- Test 14: Writes IMMICH_UUID_{username} to services.env ---
echo ""
echo "--- Test 14: Writes IMMICH_UUID_{username} to services.env ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q "IMMICH_UUID_" "$SCRIPT" && grep -q "write_uuid_to_services_env\|SERVICES_ENV" "$SCRIPT"; then
        print_pass "Writes IMMICH_UUID_{username} to services.env"
    else
        print_fail "Missing IMMICH_UUID write logic"
    fi
fi

# --- Test 15: LOC check (indicative ~150) ---
echo ""
echo "--- Test 15: LOC check (target ~150) ---"
if [[ -f "$SCRIPT" ]]; then
    line_count=$(wc -l < "$SCRIPT")
    if [[ $line_count -le 150 ]]; then
        print_pass "Script is $line_count LOC (within 150 limit)"
    else
        print_warn "Script is $line_count LOC (exceeds indicative 150 limit — Warning only)"
    fi
fi

# --- Test 16: Root check present ---
echo ""
echo "--- Test 16: Root check present ---"
if [[ -f "$SCRIPT" ]]; then
    if grep -q "EUID" "$SCRIPT"; then
        print_pass "Root check present"
    else
        print_fail "Missing root check"
    fi
fi

# --- Summary ---
echo ""
echo "========================================"
TOTAL=$((TESTS_PASSED + TESTS_FAILED))
echo "$TESTS_PASSED / $TOTAL checks passed"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "$TESTS_FAILED check(s) FAILED"
    exit 1
fi
echo "All checks passed"
exit 0
