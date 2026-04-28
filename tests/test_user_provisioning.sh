#!/bin/bash
# Unit Tests: User Provisioning Scripts
# Tests the actual user provisioning scripts in scripts/operations/user-management/

# Note: Not using set -e to allow all tests to run even if some fail

# Test framework
TESTS_PASSED=0
TESTS_FAILED=0

function print_pass() {
    echo "✓ $1"
    ((TESTS_PASSED+=1))
}

function print_fail() {
    echo "✗ $1"
    ((TESTS_FAILED+=1))
}

function print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

# Script paths
SCRIPT_DIR="scripts/operations/user-management"
CREATE_USER="$SCRIPT_DIR/create-user.sh"
UPDATE_USER="$SCRIPT_DIR/update-user.sh"
DELETE_USER="$SCRIPT_DIR/delete-user.sh"
LIST_USERS="$SCRIPT_DIR/list-users.sh"

print_header "User Provisioning Scripts - Unit Tests"

# Test 1: Scripts exist
print_header "Test 1: Checking if scripts exist..."
[[ -f "$CREATE_USER" ]] && print_pass "create-user.sh exists" || print_fail "create-user.sh missing"
[[ -f "$UPDATE_USER" ]] && print_pass "update-user.sh exists" || print_fail "update-user.sh missing"
[[ -f "$DELETE_USER" ]] && print_pass "delete-user.sh exists" || print_fail "delete-user.sh missing"
[[ -f "$LIST_USERS" ]] && print_pass "list-users.sh exists" || print_fail "list-users.sh missing"

# Test 2: Scripts are executable
print_header "Test 2: Checking if scripts are executable..."
[[ -x "$CREATE_USER" ]] && print_pass "create-user.sh is executable" || print_fail "create-user.sh not executable"
[[ -x "$UPDATE_USER" ]] && print_pass "update-user.sh is executable" || print_fail "update-user.sh not executable"
[[ -x "$DELETE_USER" ]] && print_pass "delete-user.sh is executable" || print_fail "delete-user.sh not executable"
[[ -x "$LIST_USERS" ]] && print_pass "list-users.sh is executable" || print_fail "list-users.sh not executable"

# Test 3: Proper shebang
print_header "Test 3: Checking for proper shebang..."
for script in "$CREATE_USER" "$UPDATE_USER" "$DELETE_USER" "$LIST_USERS"; do
    first_line=$(head -n 1 "$script")
    [[ "$first_line" == "#!/bin/bash" ]] && print_pass "$(basename $script) has proper shebang" || print_fail "$(basename $script) has incorrect shebang"
done

# Test 4: Safety flags
print_header "Test 4: Checking for safety flags (set -euo pipefail)..."
for script in "$CREATE_USER" "$UPDATE_USER" "$DELETE_USER" "$LIST_USERS"; do
    grep -q "set -euo pipefail" "$script" && print_pass "$(basename $script) has safety flags" || print_fail "$(basename $script) missing safety flags"
done

# Test 5: Valid bash syntax
print_header "Test 5: Validating bash syntax..."
for script in "$CREATE_USER" "$UPDATE_USER" "$DELETE_USER" "$LIST_USERS"; do
    bash -n "$script" 2>/dev/null && print_pass "$(basename $script) has valid syntax" || print_fail "$(basename $script) has invalid syntax"
done

# Test 6: create-user.sh functions
print_header "Test 6: Checking required functions in create-user.sh..."
grep -q "function validate_username" "$CREATE_USER" && print_pass "validate_username function exists" || print_fail "validate_username function missing"
grep -q "function validate_role" "$CREATE_USER" && print_pass "validate_role function exists" || print_fail "validate_role function missing"
grep -q "function user_exists" "$CREATE_USER" && print_pass "user_exists function exists" || print_fail "user_exists function missing"
grep -q "function log_message" "$CREATE_USER" && print_pass "log_message function exists" || print_fail "log_message function missing"

# Test 7: Automated password handling
print_header "Test 7: Checking automated Samba password handling..."
grep -q "SAMBA_PASSWORD_" "$CREATE_USER" && print_pass "Reads password from environment" || print_fail "Doesn't read password from environment"
grep -q "PASSWORD_VAR=" "$CREATE_USER" && print_pass "Uses PASSWORD_VAR pattern" || print_fail "Doesn't use PASSWORD_VAR pattern"
grep -q "smbpasswd -a -s" "$CREATE_USER" && print_pass "Sets password non-interactively" || print_fail "Doesn't set password non-interactively"

# Test 8: Root check
print_header "Test 8: Checking for root privileges check..."
grep -q "EUID" "$CREATE_USER" && print_pass "create-user.sh checks for root" || print_fail "create-user.sh doesn't check for root"
grep -q "EUID" "$UPDATE_USER" && print_pass "update-user.sh checks for root" || print_fail "update-user.sh doesn't check for root"
grep -q "EUID" "$DELETE_USER" && print_pass "delete-user.sh checks for root" || print_fail "delete-user.sh doesn't check for root"

# Test 9: User creation components
print_header "Test 9: Checking user creation components..."
grep -q "useradd" "$CREATE_USER" && print_pass "Creates Linux user" || print_fail "Doesn't create Linux user"
grep -q "smbpasswd" "$CREATE_USER" && print_pass "Creates Samba user" || print_fail "Doesn't create Samba user"
grep -q "PERSONAL_DIR=" "$CREATE_USER" && print_pass "Creates personal folders" || print_fail "Doesn't create personal folders"
grep -q "chmod 770" "$CREATE_USER" && print_pass "Sets permissions (770)" || print_fail "Doesn't set permissions"
grep -q "chown.*:family" "$CREATE_USER" && print_pass "Sets ownership (user:family)" || print_fail "Doesn't set ownership"

# Test 10: SSH key configuration
print_header "Test 10: Checking SSH key configuration..."
grep -q "authorized_keys" "$CREATE_USER" && print_pass "Configures SSH keys" || print_fail "Doesn't configure SSH keys"
grep -q 'standard.*SSH' "$CREATE_USER" && print_pass "Restricts SSH for standard users" || print_fail "Doesn't restrict SSH for standard users"

# Test 11: Samba configuration
print_header "Test 11: Checking Samba share configuration..."
grep -q "smb.conf" "$CREATE_USER" && print_pass "Configures Samba share" || print_fail "Doesn't configure Samba share"
grep -q "smbcontrol.*reload" "$CREATE_USER" && print_pass "Reloads Samba" || print_fail "Doesn't reload Samba"

# Test 12: Idempotency
print_header "Test 12: Checking idempotency..."
grep -q "user_exists" "$CREATE_USER" && print_pass "Checks if user exists" || print_fail "Doesn't check if user exists"
grep -q "USER_EXISTS" "$CREATE_USER" && print_pass "Handles existing users" || print_fail "Doesn't handle existing users"

# Summary
print_header "Test Summary"
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
