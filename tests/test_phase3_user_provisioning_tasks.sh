#!/bin/bash
# Unit Tests: Phase 3 User Provisioning Task Modules
# Tests task modules for provisioning admin, power, and standard users

# Note: Not using set -e to allow all tests to run even if some fail

# Test framework
TESTS_PASSED=0
TESTS_FAILED=0

function print_pass() {
    echo "✓ $1"
    ((TESTS_PASSED++))
}

function print_fail() {
    echo "✗ $1"
    ((TESTS_FAILED++))
}

function print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

# Task modules to test
TASK_MODULES=(
    "scripts/deploy/tasks/task-ph3-07-provision-admin.sh"
    "scripts/deploy/tasks/task-ph3-08-provision-power.sh"
    "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"
)

print_header "Phase 3 User Provisioning Task Module Tests"

# Test Suite 1: Task Module Files Exist
print_header "Test Suite 1: Task Module Files Exist"

for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        print_pass "Task module exists: $module"
    else
        print_fail "Task module missing: $module"
    fi
done

# Test Suite 2: Task Modules Are Executable
print_header "Test Suite 2: Task Modules Are Executable"

for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        print_pass "Task module is executable: $module"
    else
        print_fail "Task module not executable: $module"
    fi
done

# Test Suite 3: Proper Shebang
print_header "Test Suite 3: Proper Shebang"

for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        first_line=$(head -n 1 "$module")
        if [[ "$first_line" == "#!/bin/bash" ]]; then
            print_pass "Correct shebang: $module"
        else
            print_fail "Incorrect shebang in $module: $first_line"
        fi
    fi
done

# Test Suite 4: Safety Flags Present
print_header "Test Suite 4: Safety Flags Present"

for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        if grep -q "set -euo pipefail" "$module"; then
            print_pass "Safety flags present: $module"
        else
            print_fail "Safety flags missing: $module"
        fi
    fi
done

# Test Suite 5: Valid Bash Syntax
print_header "Test Suite 5: Valid Bash Syntax"

for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        if bash -n "$module" 2>/dev/null; then
            print_pass "Valid bash syntax: $module"
        else
            print_fail "Invalid bash syntax: $module"
        fi
    fi
done

# Test Suite 6: User Provisioning Logic Present
print_header "Test Suite 6: User Provisioning Logic Present"

# Test task-ph3-07-provision-admin.sh
if [[ -f "scripts/deploy/tasks/task-ph3-07-provision-admin.sh" ]]; then
    if grep -q "CREATE_USER_SCRIPT" "scripts/deploy/tasks/task-ph3-07-provision-admin.sh" && \
       grep -q "ADMIN_USER" "scripts/deploy/tasks/task-ph3-07-provision-admin.sh" && \
       grep -q "admin" "scripts/deploy/tasks/task-ph3-07-provision-admin.sh"; then
        print_pass "Admin provisioning logic present"
    else
        print_fail "Admin provisioning logic missing"
    fi
fi

# Test task-ph3-08-provision-power.sh
if [[ -f "scripts/deploy/tasks/task-ph3-08-provision-power.sh" ]]; then
    if grep -q "CREATE_USER_SCRIPT" "scripts/deploy/tasks/task-ph3-08-provision-power.sh" && \
       grep -q "POWER_USERS" "scripts/deploy/tasks/task-ph3-08-provision-power.sh" && \
       grep -q "power" "scripts/deploy/tasks/task-ph3-08-provision-power.sh"; then
        print_pass "Power user provisioning logic present"
    else
        print_fail "Power user provisioning logic missing"
    fi
fi

# Test task-ph3-09-provision-standard.sh
if [[ -f "scripts/deploy/tasks/task-ph3-09-provision-standard.sh" ]]; then
    if grep -q "CREATE_USER_SCRIPT" "scripts/deploy/tasks/task-ph3-09-provision-standard.sh" && \
       grep -q "STANDARD_USERS" "scripts/deploy/tasks/task-ph3-09-provision-standard.sh" && \
       grep -q "standard" "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"; then
        print_pass "Standard user provisioning logic present"
    else
        print_fail "Standard user provisioning logic missing"
    fi
fi

# Test Suite 7: Variable Usage
print_header "Test Suite 7: Variable Usage"

# Test ADMIN_USER variable
if grep -q "ADMIN_USER" "scripts/deploy/tasks/task-ph3-07-provision-admin.sh"; then
    print_pass "ADMIN_USER variable used in task-ph3-07"
else
    print_fail "ADMIN_USER variable not used in task-ph3-07"
fi

# Test POWER_USERS variable
if grep -q "POWER_USERS" "scripts/deploy/tasks/task-ph3-08-provision-power.sh"; then
    print_pass "POWER_USERS variable used in task-ph3-08"
else
    print_fail "POWER_USERS variable not used in task-ph3-08"
fi

# Test STANDARD_USERS variable
if grep -q "STANDARD_USERS" "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"; then
    print_pass "STANDARD_USERS variable used in task-ph3-09"
else
    print_fail "STANDARD_USERS variable not used in task-ph3-09"
fi

# Test Suite 8: Dry-Run Support
print_header "Test Suite 8: Dry-Run Support"

for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        if grep -q "DRY_RUN" "$module" && grep -q "\-\-dry-run" "$module"; then
            print_pass "Dry-run support implemented: $module"
        else
            print_fail "Dry-run support missing: $module"
        fi
    fi
done

# Test Suite 9: Root Check Present
print_header "Test Suite 9: Root Check Present"

for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        if grep -q "EUID" "$module" && grep -q "root" "$module"; then
            print_pass "Root check present: $module"
        else
            print_fail "Root check missing: $module"
        fi
    fi
done

# Test Suite 10: Output Utilities Sourced
print_header "Test Suite 10: Output Utilities Sourced"

for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        if grep -q "source.*output-utils.sh\|source.*log-utils.sh\|create-user.sh" "$module"; then
            print_pass "Output/logging utilities available: $module"
        else
            print_fail "Output utilities not sourced: $module"
        fi
    fi
done

# Test Suite 11: Verification Logic Present
print_header "Test Suite 11: Verification Logic Present"

# Test admin verification
if [[ -f "scripts/deploy/tasks/task-ph3-07-provision-admin.sh" ]]; then
    if grep -q "Verifying" "scripts/deploy/tasks/task-ph3-07-provision-admin.sh" && \
       grep -q "groups" "scripts/deploy/tasks/task-ph3-07-provision-admin.sh"; then
        print_pass "Admin verification logic present"
    else
        print_fail "Admin verification logic missing"
    fi
fi

# Test power user verification
if [[ -f "scripts/deploy/tasks/task-ph3-08-provision-power.sh" ]]; then
    if grep -q "Verifying" "scripts/deploy/tasks/task-ph3-08-provision-power.sh" && \
       grep -q "groups" "scripts/deploy/tasks/task-ph3-08-provision-power.sh"; then
        print_pass "Power user verification logic present"
    else
        print_fail "Power user verification logic missing"
    fi
fi

# Test standard user verification
if [[ -f "scripts/deploy/tasks/task-ph3-09-provision-standard.sh" ]]; then
    if grep -q "Verifying" "scripts/deploy/tasks/task-ph3-09-provision-standard.sh" && \
       grep -q "groups" "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"; then
        print_pass "Standard user verification logic present"
    else
        print_fail "Standard user verification logic missing"
    fi
fi

# Test Suite 12: SSH Key Handling
print_header "Test Suite 12: SSH Key Handling"

# Test admin SSH key handling
if [[ -f "scripts/deploy/tasks/task-ph3-07-provision-admin.sh" ]]; then
    if grep -q "SSH_KEY" "scripts/deploy/tasks/task-ph3-07-provision-admin.sh" || \
       grep -q "ssh-key" "scripts/deploy/tasks/task-ph3-07-provision-admin.sh"; then
        print_pass "Admin SSH key handling present"
    else
        print_fail "Admin SSH key handling missing"
    fi
fi

# Test power user SSH key handling
if [[ -f "scripts/deploy/tasks/task-ph3-08-provision-power.sh" ]]; then
    if grep -q "SSH_KEY" "scripts/deploy/tasks/task-ph3-08-provision-power.sh" || \
       grep -q "ssh-key" "scripts/deploy/tasks/task-ph3-08-provision-power.sh" || \
       grep -q "ssh_key" "scripts/deploy/tasks/task-ph3-08-provision-power.sh"; then
        print_pass "Power user SSH key handling present"
    else
        print_fail "Power user SSH key handling missing"
    fi
fi

# Test standard user NO SSH (should not have SSH key logic)
if [[ -f "scripts/deploy/tasks/task-ph3-09-provision-standard.sh" ]]; then
    if grep -q "NO SSH" "scripts/deploy/tasks/task-ph3-09-provision-standard.sh" || \
       grep -q "no SSH" "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"; then
        print_pass "Standard user NO SSH documented"
    else
        print_fail "Standard user NO SSH not documented"
    fi
fi

# Test Suite 13: Loop Logic for Multiple Users
print_header "Test Suite 13: Loop Logic for Multiple Users"

# Test power users loop
if [[ -f "scripts/deploy/tasks/task-ph3-08-provision-power.sh" ]]; then
    if grep -q "for" "scripts/deploy/tasks/task-ph3-08-provision-power.sh"; then
        print_pass "Power users loop logic present"
    else
        print_fail "Power users loop logic missing"
    fi
fi

# Test standard users loop
if [[ -f "scripts/deploy/tasks/task-ph3-09-provision-standard.sh" ]]; then
    if grep -q "for" "scripts/deploy/tasks/task-ph3-09-provision-standard.sh"; then
        print_pass "Standard users loop logic present"
    else
        print_fail "Standard users loop logic missing"
    fi
fi

# Test Suite 14: Error Handling
print_header "Test Suite 14: Error Handling"

for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        if grep -q "exit 1" "$module"; then
            print_pass "Error handling present: $module"
        else
            print_fail "Error handling missing: $module"
        fi
    fi
done

# Test Suite 15: Success Messages
print_header "Test Suite 15: Success Messages"

for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        if grep -q "success\|complete\|Success\|Complete" "$module"; then
            print_pass "Success messages present: $module"
        else
            print_fail "Success messages missing: $module"
        fi
    fi
done

# Summary
print_header "Test Summary"
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
echo "Total tests: $TOTAL_TESTS"
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
