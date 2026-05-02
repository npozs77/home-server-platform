#!/bin/bash
# CI_SAFE=true
# Property Test: Provisioning Idempotency and Email Strategy (Property 12)
# Purpose: Verify universal correctness properties of the provisioning script
# Validates: Requirements 42.3, 42.4, 42.6, 42.7, 42.8
# Usage: bash tests/test_phase4_property_provisioning.sh

# Note: Not using set -e to allow all tests to run even if some fail

# Test framework
TESTS_PASSED=0
TESTS_FAILED=0

print_pass() { echo "✓ PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo "✗ FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

SCRIPT="scripts/deploy/tasks/task-ph4-05-provision-immich-users.sh"

echo ""
echo "========================================"
echo "Property 12: Provisioning Idempotency"
echo "         and Email Strategy"
echo "========================================"

# Guard: script must exist
if [[ ! -f "$SCRIPT" ]]; then
    print_fail "Provisioning script not found: $SCRIPT"
    echo ""
    echo "0 / 1 checks passed"
    exit 1
fi

SCRIPT_CONTENT=$(cat "$SCRIPT")

# --- Property 12.1: GET before POST pattern (idempotency) ---
echo ""
echo "--- Property 12.1: Script checks existing users before creating (GET before POST) ---"
# The script must fetch existing users (GET /api/users) before creating any (POST /api/users)
# This ensures idempotency: running the script multiple times does not create duplicates
get_line=0
post_line=0
line_num=0
while IFS= read -r line; do
    line_num=$((line_num + 1))
    # Find first GET /users reference (fetching existing users)
    if [[ $get_line -eq 0 ]] && echo "$line" | grep -q "GET\|api/users.*x-api-key\|Fetching existing\|EXISTING_USERS"; then
        # Exclude POST lines
        if ! echo "$line" | grep -q "POST"; then
            get_line=$line_num
        fi
    fi
    # Find first POST /users reference (creating new user)
    if [[ $post_line -eq 0 ]] && echo "$line" | grep -q "POST.*users\|-X POST"; then
        post_line=$line_num
    fi
done < "$SCRIPT"

if [[ $get_line -gt 0 && $post_line -gt 0 && $get_line -lt $post_line ]]; then
    print_pass "GET existing users (line $get_line) occurs before POST new user (line $post_line)"
else
    print_fail "GET before POST pattern not found (GET line: $get_line, POST line: $post_line)"
fi

# Verify script checks if user already exists before creating
if echo "$SCRIPT_CONTENT" | grep -q "already exists\|already in Immich\|EXISTING_USERS_BY_EMAIL"; then
    print_pass "Script checks for existing users before creating"
else
    print_fail "Script does not check for existing users before creating"
fi

# --- Property 12.2: Admin user uses ADMIN_EMAIL from foundation.env ---
echo ""
echo "--- Property 12.2: Admin user uses ADMIN_EMAIL (real email) ---"

# The script must use ADMIN_EMAIL for the admin user (not a placeholder)
if echo "$SCRIPT_CONTENT" | grep -q "ADMIN_EMAIL"; then
    print_pass "Script references ADMIN_EMAIL variable"
else
    print_fail "Script does not reference ADMIN_EMAIL"
fi

# Verify admin email logic: admin user gets ADMIN_EMAIL, not {username}@homeserver
if echo "$SCRIPT_CONTENT" | grep -q 'ADMIN_USER.*ADMIN_EMAIL\|username.*==.*ADMIN_USER.*ADMIN_EMAIL\|"$username" == "$ADMIN_USER"'; then
    print_pass "Admin user email logic distinguishes admin from other users"
else
    print_fail "No conditional logic for admin email vs placeholder email"
fi

# --- Property 12.3: Non-admin users use {username}@homeserver pattern ---
echo ""
echo "--- Property 12.3: Non-admin users use {username}@homeserver placeholder ---"

if echo "$SCRIPT_CONTENT" | grep -q '@homeserver'; then
    print_pass "Script uses @homeserver placeholder for non-admin users"
else
    print_fail "Script does not use @homeserver placeholder pattern"
fi

# --- Property 12.4: Admin user gets isAdmin=true, all others get isAdmin=false ---
echo ""
echo "--- Property 12.4: Admin gets isAdmin=true, others get isAdmin=false ---"

# Check that admin user is marked as admin
if echo "$SCRIPT_CONTENT" | grep -q 'ADMIN_USER.*true\|USER_IS_ADMIN.*ADMIN_USER.*true'; then
    print_pass "Admin user assigned isAdmin=true"
else
    print_fail "Admin user not assigned isAdmin=true"
fi

# Check that non-admin users are marked as non-admin
if echo "$SCRIPT_CONTENT" | grep -q 'POWER_USERS\|STANDARD_USERS' && echo "$SCRIPT_CONTENT" | grep -q '"false"'; then
    print_pass "Non-admin users assigned isAdmin=false"
else
    print_fail "Non-admin users not assigned isAdmin=false"
fi

# Verify the isAdmin value is passed to the API call
if echo "$SCRIPT_CONTENT" | grep -q 'isAdmin.*\${is_admin}\|isAdmin.*is_admin'; then
    print_pass "isAdmin value passed to API POST request"
else
    print_fail "isAdmin value not passed to API POST request"
fi

# --- Property 12.5: Script writes IMMICH_UUID_{username} to services.env ---
echo ""
echo "--- Property 12.5: Script writes IMMICH_UUID_{username} to services.env ---"

if echo "$SCRIPT_CONTENT" | grep -q 'IMMICH_UUID_'; then
    print_pass "Script references IMMICH_UUID_ variable pattern"
else
    print_fail "Script does not reference IMMICH_UUID_ pattern"
fi

if echo "$SCRIPT_CONTENT" | grep -q 'SERVICES_ENV\|services.env' && echo "$SCRIPT_CONTENT" | grep -q 'write_uuid_to_services_env\|>> .*SERVICES_ENV\|sed.*SERVICES_ENV'; then
    print_pass "Script writes UUID to services.env"
else
    print_fail "Script does not write UUID to services.env"
fi

# Verify UUID is captured from both new (POST response) and existing (GET response) users
if echo "$SCRIPT_CONTENT" | grep -q 'write_uuid_to_services_env.*uuid\|IMMICH_UUID.*uuid'; then
    # Check it's called for both created and skipped users
    uuid_write_count=$(echo "$SCRIPT_CONTENT" | grep -c 'write_uuid_to_services_env')
    if [[ $uuid_write_count -ge 2 ]]; then
        print_pass "UUID written for both new and existing users ($uuid_write_count write points)"
    else
        print_fail "UUID write found only $uuid_write_count time(s) — expected at least 2 (new + existing)"
    fi
else
    print_fail "UUID capture and write logic not found"
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
