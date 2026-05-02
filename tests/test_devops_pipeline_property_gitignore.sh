#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Sensitive Files Remain Gitignored (Property 1)
# Feature: devops-cicd-pipeline, Property 1: Sensitive files remain gitignored
# Purpose: Verify .gitignore contains rules for all sensitive file patterns
# Validates: Requirements 2.2
# Usage: bash tests/test_devops_pipeline_property_gitignore.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITIGNORE="${REPO_ROOT}/.gitignore"

echo "========================================"
echo "Property 1: Sensitive Files Remain Gitignored"
echo "========================================"
echo ""

TESTS_RUN=$((TESTS_RUN + 1))
if [[ ! -f "$GITIGNORE" ]]; then
    print_fail ".gitignore not found"
    exit 1
fi
print_pass ".gitignore exists"

# Sensitive patterns that MUST be in .gitignore
SENSITIVE_PATTERNS=(
    '*.key'
    '*.pem'
    '*.env'
    'configs/secrets.env'
    'configs/caddy/Caddyfile'
    'configs/caddy/root-ca.crt'
    'configs/pihole/*.conf'
    'configs/docker-compose/*.yml'
    'configs/netdata/'
)

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    # Use fgrep for literal match (patterns contain * and /)
    if grep -qF "$pattern" "$GITIGNORE"; then
        print_pass ".gitignore contains: $pattern"
    else
        print_fail ".gitignore MISSING: $pattern"
    fi
done

echo ""
echo "========================================"
echo "Property 1 Summary"
echo "========================================"
echo "Checks run:  $TESTS_RUN"
echo -e "Passed:      ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:      ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 1 holds: all sensitive files are gitignored${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 1 violated: ${TESTS_FAILED} check(s) failed${NC}"
    exit 1
fi
