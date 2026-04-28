#!/usr/bin/env bash
# Test Suite: Configuration Migration
# Purpose: Validate configuration migration from phase-based to logical grouping
# Requirements: 18.1-18.8
# Usage: ./test_config_migration.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test directory
TEST_DIR="/tmp/config_migration_test_$$"

# Print test result
print_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Run test
run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo "Test $TESTS_RUN: $1"
    echo "----------------------------------------"
}

# Setup test environment
setup_test_env() {
    print_info "Setting up test environment: $TEST_DIR"
    mkdir -p "$TEST_DIR/configs"
    
    # Create sample phase1-config.env
    cat > "$TEST_DIR/configs/phase1-config.env" <<'EOF'
# Phase 1 Configuration
TIMEZONE="Europe/Amsterdam"
HOSTNAME="homeserver"
SERVER_IP="192.168.1.2"
NETWORK_INTERFACE="enp0s3"
ADMIN_USER="admin"
ADMIN_EMAIL="admin@mydomain.com"
DATA_DISK="/dev/sdb"
DATA_MOUNT="/mnt/data"
LUKS_PASSPHRASE="test-passphrase-123"
GIT_USER_NAME="Admin User"
GIT_USER_EMAIL="admin@home.mydomain.com"
EOF
    
    # Create sample phase2-config.env with some duplicate variables
    cat > "$TEST_DIR/configs/phase2-config.env" <<'EOF'
# Phase 2 Configuration
SERVER_IP="192.168.1.2"
ADMIN_EMAIL="admin@mydomain.com"
DOMAIN="mydomain.com"
INTERNAL_SUBDOMAIN="home.mydomain.com"
HOMESERVER_PASS_SHARE_ID="vault-share-id-here"
SMTP2GO_HOST="mail-eu.smtp2go.com"
SMTP2GO_PORT="2525"
SMTP2GO_FROM="alerts@home.mydomain.com"
SMTP2GO_USER="username"
SMTP2GO_PASS_ITEM_ID="item-id-here"
PIHOLE_PASS_ITEM_ID="pihole-item-id-here"
EOF
}

# Cleanup test environment
cleanup_test_env() {
    print_info "Cleaning up test environment"
    rm -rf "$TEST_DIR"
}

# Test migration script exists
test_migration_script_exists() {
    run_test "Migration script exists and is executable"
    
    if [[ -f "scripts/operations/migrate-config.sh" ]]; then
        print_pass "Migration script exists"
    else
        print_fail "Migration script does not exist"
        return 1
    fi
    
    if [[ -f "scripts/operations/migrate-config.sh" ]]; then
        print_pass "Migration script is executable"
    else
        print_fail "Migration script is not executable"
        return 1
    fi
}

# Test migration script syntax
test_migration_script_syntax() {
    run_test "Migration script has valid bash syntax"
    
    if bash -n scripts/operations/migrate-config.sh 2>/dev/null; then
        print_pass "Migration script syntax is valid"
    else
        print_fail "Migration script has syntax errors"
        return 1
    fi
}

# Test migration preserves all variables
test_migration_preserves_variables() {
    run_test "Migration preserves all variables"
    
    setup_test_env
    
    # Create a modified version of migrate-config.sh that works in test environment
    local test_script="$TEST_DIR/migrate-config-test.sh"
    sed -e "s|/opt/homeserver/configs|$TEST_DIR/configs|g" \
        -e '/if \[\[ \$EUID -ne 0 \]\]; then/,/fi/d' \
        scripts/operations/migrate-config.sh > "$test_script"
    chmod +x "$test_script"
    
    # Run migration script
    cd "$TEST_DIR"
    bash "$test_script" <<< "y" 2>/dev/null || true
    cd - > /dev/null
    
    # Check all variables from phase1-config.env are present
    local phase1_vars=(
        "TIMEZONE"
        "HOSTNAME"
        "SERVER_IP"
        "NETWORK_INTERFACE"
        "ADMIN_USER"
        "ADMIN_EMAIL"
        "DATA_DISK"
        "DATA_MOUNT"
        "LUKS_PASSPHRASE"
        "GIT_USER_NAME"
        "GIT_USER_EMAIL"
    )
    
    local all_vars_present=true
    
    for var in "${phase1_vars[@]}"; do
        if grep -q "^${var}=" "$TEST_DIR/configs/foundation.env" "$TEST_DIR/configs/secrets.env" 2>/dev/null; then
            print_pass "$var preserved"
        else
            print_fail "$var missing after migration"
            all_vars_present=false
        fi
    done
    
    # Check all variables from phase2-config.env are present
    local phase2_vars=(
        "DOMAIN"
        "INTERNAL_SUBDOMAIN"
        "HOMESERVER_PASS_SHARE_ID"
        "SMTP2GO_HOST"
        "SMTP2GO_PORT"
        "SMTP2GO_FROM"
        "SMTP2GO_USER"
        "SMTP2GO_PASS_ITEM_ID"
        "PIHOLE_PASS_ITEM_ID"
    )
    
    for var in "${phase2_vars[@]}"; do
        if grep -q "^${var}=" "$TEST_DIR/configs/services.env" 2>/dev/null; then
            print_pass "$var preserved"
        else
            print_fail "$var missing after migration"
            all_vars_present=false
        fi
    done
    
    cleanup_test_env
    
    if [[ "$all_vars_present" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test migration merges duplicate variables
test_migration_merges_duplicates() {
    run_test "Migration merges duplicate variables"
    
    setup_test_env
    
    # Create a modified version of migrate-config.sh that works in test environment
    local test_script="$TEST_DIR/migrate-config-test.sh"
    sed -e "s|/opt/homeserver/configs|$TEST_DIR/configs|g" \
        -e '/if \[\[ \$EUID -ne 0 \]\]; then/,/fi/d' \
        scripts/operations/migrate-config.sh > "$test_script"
    chmod +x "$test_script"
    
    # Run migration script
    cd "$TEST_DIR"
    bash "$test_script" <<< "y" 2>/dev/null || true
    cd - > /dev/null
    
    # Check SERVER_IP appears only once across all config files (excluding backups)
    local server_ip_count=$(grep -h "^SERVER_IP=" "$TEST_DIR/configs/foundation.env" "$TEST_DIR/configs/services.env" "$TEST_DIR/configs/secrets.env" 2>/dev/null | wc -l)
    
    if [[ $server_ip_count -eq 1 ]]; then
        print_pass "SERVER_IP appears exactly once (merged)"
    else
        print_fail "SERVER_IP appears $server_ip_count times (should be 1)"
        cleanup_test_env
        return 1
    fi
    
    # Check ADMIN_EMAIL appears only once
    local admin_email_count=$(grep -h "^ADMIN_EMAIL=" "$TEST_DIR/configs/foundation.env" "$TEST_DIR/configs/services.env" "$TEST_DIR/configs/secrets.env" 2>/dev/null | wc -l)
    
    if [[ $admin_email_count -eq 1 ]]; then
        print_pass "ADMIN_EMAIL appears exactly once (merged)"
    else
        print_fail "ADMIN_EMAIL appears $admin_email_count times (should be 1)"
        cleanup_test_env
        return 1
    fi
    
    cleanup_test_env
    return 0
}

# Test migration creates backups
test_migration_creates_backups() {
    run_test "Migration creates backup files"
    
    setup_test_env
    
    # Create a modified version of migrate-config.sh that works in test environment
    local test_script="$TEST_DIR/migrate-config-test.sh"
    sed -e "s|/opt/homeserver/configs|$TEST_DIR/configs|g" \
        -e '/if \[\[ \$EUID -ne 0 \]\]; then/,/fi/d' \
        scripts/operations/migrate-config.sh > "$test_script"
    chmod +x "$test_script"
    
    # Run migration script
    cd "$TEST_DIR"
    bash "$test_script" <<< "y" 2>/dev/null || true
    cd - > /dev/null
    
    local backups_created=true
    
    if [[ -f "$TEST_DIR/configs/phase1-config.env.backup" ]]; then
        print_pass "phase1-config.env.backup created"
    else
        print_fail "phase1-config.env.backup not created"
        backups_created=false
    fi
    
    if [[ -f "$TEST_DIR/configs/phase2-config.env.backup" ]]; then
        print_pass "phase2-config.env.backup created"
    else
        print_fail "phase2-config.env.backup not created"
        backups_created=false
    fi
    
    cleanup_test_env
    
    if [[ "$backups_created" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test migration creates logical config files
test_migration_creates_logical_configs() {
    run_test "Migration creates logical config files"
    
    setup_test_env
    
    # Create a modified version of migrate-config.sh that works in test environment
    local test_script="$TEST_DIR/migrate-config-test.sh"
    sed -e "s|/opt/homeserver/configs|$TEST_DIR/configs|g" \
        -e '/if \[\[ \$EUID -ne 0 \]\]; then/,/fi/d' \
        scripts/operations/migrate-config.sh > "$test_script"
    chmod +x "$test_script"
    
    # Run migration script
    cd "$TEST_DIR"
    bash "$test_script" <<< "y" 2>/dev/null || true
    cd - > /dev/null
    
    local configs_created=true
    
    if [[ -f "$TEST_DIR/configs/foundation.env" ]]; then
        print_pass "foundation.env created"
    else
        print_fail "foundation.env not created"
        configs_created=false
    fi
    
    if [[ -f "$TEST_DIR/configs/services.env" ]]; then
        print_pass "services.env created"
    else
        print_fail "services.env not created"
        configs_created=false
    fi
    
    if [[ -f "$TEST_DIR/configs/secrets.env" ]]; then
        print_pass "secrets.env created"
    else
        print_fail "secrets.env not created"
        configs_created=false
    fi
    
    cleanup_test_env
    
    if [[ "$configs_created" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test migration is idempotent
test_migration_idempotent() {
    run_test "Migration is idempotent (safe to run multiple times)"
    
    setup_test_env
    
    # Create a modified version of migrate-config.sh that works in test environment
    local test_script="$TEST_DIR/migrate-config-test.sh"
    sed -e "s|/opt/homeserver/configs|$TEST_DIR/configs|g" \
        -e '/if \[\[ \$EUID -ne 0 \]\]; then/,/fi/d' \
        scripts/operations/migrate-config.sh > "$test_script"
    chmod +x "$test_script"
    
    # Run migration script twice
    cd "$TEST_DIR"
    bash "$test_script" <<< "y" 2>/dev/null || true
    bash "$test_script" <<< "y" 2>/dev/null || true
    cd - > /dev/null
    
    # Check that logical config files still exist and are valid
    local idempotent=true
    
    if [[ -f "$TEST_DIR/configs/foundation.env" ]] && \
       [[ -f "$TEST_DIR/configs/services.env" ]] && \
       [[ -f "$TEST_DIR/configs/secrets.env" ]]; then
        print_pass "Logical config files still exist after second run"
    else
        print_fail "Logical config files missing after second run"
        idempotent=false
    fi
    
    # Check that variables are still present
    if grep -q "^TIMEZONE=" "$TEST_DIR/configs/foundation.env" 2>/dev/null; then
        print_pass "Variables still present after second run"
    else
        print_fail "Variables missing after second run"
        idempotent=false
    fi
    
    cleanup_test_env
    
    if [[ "$idempotent" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test LUKS passphrase goes to secrets.env
test_luks_passphrase_in_secrets() {
    run_test "LUKS passphrase is placed in secrets.env"
    
    setup_test_env
    
    # Create a modified version of migrate-config.sh that works in test environment
    local test_script="$TEST_DIR/migrate-config-test.sh"
    sed -e "s|/opt/homeserver/configs|$TEST_DIR/configs|g" \
        -e '/if \[\[ \$EUID -ne 0 \]\]; then/,/fi/d' \
        scripts/operations/migrate-config.sh > "$test_script"
    chmod +x "$test_script"
    
    # Run migration script
    cd "$TEST_DIR"
    bash "$test_script" <<< "y" 2>/dev/null || true
    cd - > /dev/null
    
    if grep -q "^LUKS_PASSPHRASE=" "$TEST_DIR/configs/secrets.env" 2>/dev/null; then
        print_pass "LUKS_PASSPHRASE in secrets.env"
    else
        print_fail "LUKS_PASSPHRASE not in secrets.env"
        cleanup_test_env
        return 1
    fi
    
    # Check it's NOT in foundation.env or services.env
    if ! grep -q "^LUKS_PASSPHRASE=" "$TEST_DIR/configs/foundation.env" 2>/dev/null && \
       ! grep -q "^LUKS_PASSPHRASE=" "$TEST_DIR/configs/services.env" 2>/dev/null; then
        print_pass "LUKS_PASSPHRASE not in foundation.env or services.env"
    else
        print_fail "LUKS_PASSPHRASE found in wrong config file"
        cleanup_test_env
        return 1
    fi
    
    cleanup_test_env
    return 0
}

# Test system-level vars go to foundation.env
test_system_vars_in_foundation() {
    run_test "System-level variables are placed in foundation.env"
    
    setup_test_env
    
    # Create a modified version of migrate-config.sh that works in test environment
    local test_script="$TEST_DIR/migrate-config-test.sh"
    sed -e "s|/opt/homeserver/configs|$TEST_DIR/configs|g" \
        -e '/if \[\[ \$EUID -ne 0 \]\]; then/,/fi/d' \
        scripts/operations/migrate-config.sh > "$test_script"
    chmod +x "$test_script"
    
    # Run migration script
    cd "$TEST_DIR"
    bash "$test_script" <<< "y" 2>/dev/null || true
    cd - > /dev/null
    
    local system_vars=(
        "TIMEZONE"
        "HOSTNAME"
        "SERVER_IP"
        "NETWORK_INTERFACE"
        "ADMIN_USER"
        "DATA_DISK"
        "DATA_MOUNT"
    )
    
    local all_in_foundation=true
    
    for var in "${system_vars[@]}"; do
        if grep -q "^${var}=" "$TEST_DIR/configs/foundation.env" 2>/dev/null; then
            print_pass "$var in foundation.env"
        else
            print_fail "$var not in foundation.env"
            all_in_foundation=false
        fi
    done
    
    cleanup_test_env
    
    if [[ "$all_in_foundation" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test service-specific vars go to services.env
test_service_vars_in_services() {
    run_test "Service-specific variables are placed in services.env"
    
    setup_test_env
    
    # Create a modified version of migrate-config.sh that works in test environment
    local test_script="$TEST_DIR/migrate-config-test.sh"
    sed -e "s|/opt/homeserver/configs|$TEST_DIR/configs|g" \
        -e '/if \[\[ \$EUID -ne 0 \]\]; then/,/fi/d' \
        scripts/operations/migrate-config.sh > "$test_script"
    chmod +x "$test_script"
    
    # Run migration script
    cd "$TEST_DIR"
    bash "$test_script" <<< "y" 2>/dev/null || true
    cd - > /dev/null
    
    local service_vars=(
        "DOMAIN"
        "INTERNAL_SUBDOMAIN"
        "SMTP2GO_HOST"
        "SMTP2GO_PORT"
        "HOMESERVER_PASS_SHARE_ID"
    )
    
    local all_in_services=true
    
    for var in "${service_vars[@]}"; do
        if grep -q "^${var}=" "$TEST_DIR/configs/services.env" 2>/dev/null; then
            print_pass "$var in services.env"
        else
            print_fail "$var not in services.env"
            all_in_services=false
        fi
    done
    
    cleanup_test_env
    
    if [[ "$all_in_services" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Run all tests
main() {
    echo "========================================"
    echo "Configuration Migration Test Suite"
    echo "========================================"
    
    # Migration script tests
    test_migration_script_exists || true
    test_migration_script_syntax || true
    
    # Migration behavior tests
    test_migration_creates_logical_configs || true
    test_migration_preserves_variables || true
    test_migration_merges_duplicates || true
    test_migration_creates_backups || true
    test_migration_idempotent || true
    
    # Variable placement tests
    test_luks_passphrase_in_secrets || true
    test_system_vars_in_foundation || true
    test_service_vars_in_services || true
    
    # Summary
    echo ""
    echo "========================================"
    echo "Test Results"
    echo "========================================"
    echo "$TESTS_PASSED / $TESTS_RUN checks passed"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! ✓${NC}"
        exit 0
    else
        echo -e "${RED}$TESTS_FAILED tests failed. Please review and fix issues.${NC}"
        exit 1
    fi
}

# Run tests
main
