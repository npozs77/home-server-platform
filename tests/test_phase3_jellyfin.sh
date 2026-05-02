#!/bin/bash
# CI_SAFE=true
# Unit Tests: Phase 3 Jellyfin Tasks
# Tests task modules for Jellyfin Docker Compose, deployment, Caddy config, and DNS config

set -euo pipefail

# Test configuration
TASK_MODULES=(
    "scripts/deploy/tasks/task-ph3-10-create-jellyfin-compose.sh"
    "scripts/deploy/tasks/task-ph3-11-deploy-jellyfin.sh"
    "scripts/deploy/tasks/task-ph3-12-configure-caddy-jellyfin.sh"
    "scripts/deploy/tasks/task-ph3-13-configure-dns-jellyfin.sh"
)
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Functions
function print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

function print_fail() {
    echo -e "${RED}✗${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

function print_section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

# Test Suite
print_section "Phase 3 Jellyfin Tasks - Unit Tests"

# Test 1: Task modules exist
echo "Test 1: Task modules exist..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]]; then
        print_pass "$(basename "$module") exists"
    else
        print_fail "$(basename "$module") not found"
    fi
done

# Test 2: Proper shebang
echo ""
echo "Test 2: Proper shebang..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && head -1 "$module" | grep -q '^#!/bin/bash'; then
        print_pass "$(basename "$module") has proper shebang"
    else
        print_fail "$(basename "$module") missing proper shebang"
    fi
done

# Test 3: Safety flags
echo ""
echo "Test 3: Safety flags (set -euo pipefail)..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q '^set -euo pipefail' "$module"; then
        print_pass "$(basename "$module") has safety flags"
    else
        print_fail "$(basename "$module") missing safety flags"
    fi
done

# Test 4: Valid syntax
echo ""
echo "Test 4: Valid bash syntax..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && bash -n "$module" 2>/dev/null; then
        print_pass "$(basename "$module") syntax valid"
    else
        print_fail "$(basename "$module") has syntax errors"
    fi
done

# Test 5: Absolute path sourcing
echo ""
echo "Test 5: Absolute path sourcing..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q 'source /opt/homeserver/scripts/operations/utils/output-utils.sh' "$module"; then
        print_pass "$(basename "$module") uses absolute path sourcing"
    else
        print_fail "$(basename "$module") missing absolute path sourcing"
    fi
done

# Test 6: Docker compose creation
echo ""
echo "Test 6: Docker compose creation logic..."
if grep -q 'jellyfin.yml' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-10 creates jellyfin.yml"
else
    print_fail "task-ph3-10 doesn't create jellyfin.yml"
fi

if grep -q 'jellyfin/jellyfin' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-10 uses jellyfin image"
else
    print_fail "task-ph3-10 missing jellyfin image"
fi

if grep -q 'group_add' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-10 includes group_add for media group"
else
    print_fail "task-ph3-10 missing group_add"
fi

if grep -q 'MEDIA_GID' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-10 gets media group GID"
else
    print_fail "task-ph3-10 doesn't get media group GID"
fi

# Test 7: Container deployment
echo ""
echo "Test 7: Container deployment logic..."
if grep -q 'docker compose\|docker-compose' "${TASK_MODULES[1]}"; then
    print_pass "task-ph3-11 uses docker compose"
else
    print_fail "task-ph3-11 missing docker compose"
fi

if grep -q 'jellyfin' "${TASK_MODULES[1]}"; then
    print_pass "task-ph3-11 references Jellyfin"
else
    print_fail "task-ph3-11 doesn't reference Jellyfin"
fi

if grep -q 'docker ps' "${TASK_MODULES[1]}"; then
    print_pass "task-ph3-11 verifies container running"
else
    print_fail "task-ph3-11 doesn't verify container"
fi

# Test 8: Caddy configuration
echo ""
echo "Test 8: Caddy configuration logic..."
if grep -q 'Caddyfile' "${TASK_MODULES[2]}"; then
    print_pass "task-ph3-12 modifies Caddyfile"
else
    print_fail "task-ph3-12 doesn't modify Caddyfile"
fi

if grep -q 'media\.' "${TASK_MODULES[2]}"; then
    print_pass "task-ph3-12 configures media subdomain"
else
    print_fail "task-ph3-12 missing media subdomain"
fi

if grep -q 'jellyfin:8096' "${TASK_MODULES[2]}"; then
    print_pass "task-ph3-12 proxies to jellyfin:8096"
else
    print_fail "task-ph3-12 missing proxy configuration"
fi

if grep -q 'caddy reload' "${TASK_MODULES[2]}"; then
    print_pass "task-ph3-12 reloads Caddy"
else
    print_fail "task-ph3-12 doesn't reload Caddy"
fi

# Test 9: DNS configuration
echo ""
echo "Test 9: DNS configuration logic..."
if grep -q 'custom.list' "${TASK_MODULES[3]}"; then
    print_pass "task-ph3-13 modifies custom.list"
else
    print_fail "task-ph3-13 doesn't modify custom.list"
fi

if grep -q 'media\.' "${TASK_MODULES[3]}"; then
    print_pass "task-ph3-13 adds media DNS record"
else
    print_fail "task-ph3-13 missing media DNS record"
fi

if grep -q 'pihole reloaddns' "${TASK_MODULES[3]}"; then
    print_pass "task-ph3-13 reloads Pi-hole DNS"
else
    print_fail "task-ph3-13 doesn't reload DNS"
fi

if grep -q 'nslookup' "${TASK_MODULES[3]}"; then
    print_pass "task-ph3-13 verifies DNS resolution"
else
    print_fail "task-ph3-13 doesn't verify DNS"
fi

# Test 10: Environment variables
echo ""
echo "Test 10: Environment variable usage..."
if grep -q 'TIMEZONE' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-10 uses TIMEZONE variable"
else
    print_fail "task-ph3-10 missing TIMEZONE variable"
fi

if grep -q 'INTERNAL_SUBDOMAIN' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-10 uses INTERNAL_SUBDOMAIN variable"
else
    print_fail "task-ph3-10 missing INTERNAL_SUBDOMAIN variable"
fi

if grep -q 'INTERNAL_SUBDOMAIN' "${TASK_MODULES[2]}"; then
    print_pass "task-ph3-12 uses INTERNAL_SUBDOMAIN variable"
else
    print_fail "task-ph3-12 missing INTERNAL_SUBDOMAIN variable"
fi

if grep -q 'SERVER_IP' "${TASK_MODULES[3]}"; then
    print_pass "task-ph3-13 uses SERVER_IP variable"
else
    print_fail "task-ph3-13 missing SERVER_IP variable"
fi

if grep -q 'INTERNAL_SUBDOMAIN' "${TASK_MODULES[3]}"; then
    print_pass "task-ph3-13 uses INTERNAL_SUBDOMAIN variable"
else
    print_fail "task-ph3-13 missing INTERNAL_SUBDOMAIN variable"
fi

# Test 11: Dry-run support
echo ""
echo "Test 11: Dry-run support..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q 'DRY_RUN' "$module"; then
        print_pass "$(basename "$module") supports dry-run"
    else
        print_fail "$(basename "$module") missing dry-run support"
    fi
done

# Test 12: Root check
echo ""
echo "Test 12: Root privilege check..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q 'EUID.*-ne.*0' "$module"; then
        print_pass "$(basename "$module") checks for root"
    else
        print_fail "$(basename "$module") missing root check"
    fi
done

# Test 13: Idempotency checks
echo ""
echo "Test 13: Idempotency checks..."
if grep -q 'jellyfin.yml.*exists' "${TASK_MODULES[0]}"; then
    print_pass "task-ph3-10 checks if file exists"
else
    print_fail "task-ph3-10 missing idempotency check"
fi

if grep -qi 'jellyfin.*already exists' "${TASK_MODULES[1]}"; then
    print_pass "task-ph3-11 checks if container exists"
else
    print_fail "task-ph3-11 missing idempotency check"
fi

if grep -q 'already exists.*Caddyfile' "${TASK_MODULES[2]}"; then
    print_pass "task-ph3-12 checks if entry exists"
else
    print_fail "task-ph3-12 missing idempotency check"
fi

if grep -q 'already exists.*custom.list' "${TASK_MODULES[3]}"; then
    print_pass "task-ph3-13 checks if record exists"
else
    print_fail "task-ph3-13 missing idempotency check"
fi

# Test 14: Error handling
echo ""
echo "Test 14: Error handling..."
for module in "${TASK_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q 'exit [13]' "$module"; then
        print_pass "$(basename "$module") has error handling"
    else
        print_fail "$(basename "$module") missing error handling"
    fi
done

# Test 15: Documentation exists
echo ""
echo "Test 15: Documentation exists..."
if [[ -f "docs/07-jellyfin-setup.md" ]]; then
    print_pass "Jellyfin setup documentation exists"
else
    print_fail "Jellyfin setup documentation missing"
fi

# Summary
print_section "Test Summary"
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
echo "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
