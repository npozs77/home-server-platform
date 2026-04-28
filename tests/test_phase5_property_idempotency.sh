#!/usr/bin/env bash
# Property Test: Deployment Script Idempotency (Property 14)
# Purpose: Verify each Phase 5 task module implements idempotency guards so that
#          running the same task twice with the same configuration does not create
#          duplicate containers, DNS records, Caddy entries, directories, or users.
# Approach: Static analysis — inspect each task module for idempotency patterns:
#   - "already exists" / "already running" skip messages
#   - Guard checks before creating resources (grep, docker inspect, test -d, etc.)
#   - Dry-run support (--dry-run flag handling)
# Validates: Requirements 18.6
# Usage: bash tests/test_phase5_property_idempotency.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

TASK_DIR="scripts/deploy/tasks"

# Collect all Phase 5 task modules
PH5_TASKS=()
for f in "${TASK_DIR}"/task-ph5-*.sh; do
    [[ -f "$f" ]] && PH5_TASKS+=("$f")
done

echo "========================================"
echo "Property 14: Deployment Script Idempotency (Phase 5)"
echo "========================================"
echo ""
echo "Task modules found: ${#PH5_TASKS[@]}"
echo ""

if [[ ${#PH5_TASKS[@]} -eq 0 ]]; then
    echo -e "${RED}✗ FATAL${NC}: No Phase 5 task modules found in ${TASK_DIR}"
    exit 1
fi

# --- Check 1: Every task module has an idempotency guard ---
# Each script should check whether its target resource already exists before
# creating it. We look for common idempotency patterns in the source code.

echo "=== Check 1: Idempotency guard present ==="
echo ""

IDEMPOTENCY_PATTERNS=(
    "already exists"
    "already running"
    "already healthy"
    "already exist"
    "skipping"
    "skip"
)

for task in "${PH5_TASKS[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    basename=$(basename "$task")
    content=$(cat "$task")

    found=false
    for pattern in "${IDEMPOTENCY_PATTERNS[@]}"; do
        if echo "$content" | grep -qi "$pattern"; then
            found=true
            break
        fi
    done

    if [[ "$found" == true ]]; then
        print_pass "$basename: has idempotency guard (skip-if-exists pattern)"
    else
        print_fail "$basename: MISSING idempotency guard (no skip-if-exists pattern found)"
    fi
done
echo ""

# --- Check 2: Directory-creating tasks use mkdir -p or pre-check ---
# Tasks that create directories should use mkdir -p (inherently idempotent)
# or check with test -d / [[ -d before creating.

echo "=== Check 2: Directory tasks use idempotent creation ==="
echo ""

DIR_TASKS=()
for task in "${PH5_TASKS[@]}"; do
    if echo "$task" | grep -qi "director"; then
        DIR_TASKS+=("$task")
    elif grep -ql "mkdir" "$task" 2>/dev/null; then
        DIR_TASKS+=("$task")
    fi
done

for task in "${DIR_TASKS[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    basename=$(basename "$task")
    content=$(cat "$task")

    if echo "$content" | grep -q 'mkdir -p' || echo "$content" | grep -qE '\[\[.*-d.*\]\]|test -d'; then
        print_pass "$basename: uses idempotent directory creation (mkdir -p or -d check)"
    else
        print_fail "$basename: creates directories without idempotency guard"
    fi
done

if [[ ${#DIR_TASKS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}  (no directory-creating tasks found — skipping)${NC}"
fi
echo ""

# --- Check 3: Caddy tasks check for existing entry before appending ---
# Tasks that modify the Caddyfile should grep for the domain before appending.

echo "=== Check 3: Caddy tasks check before appending ==="
echo ""

CADDY_TASKS=()
for task in "${PH5_TASKS[@]}"; do
    if echo "$task" | grep -qi "caddy"; then
        CADDY_TASKS+=("$task")
    fi
done

for task in "${CADDY_TASKS[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    basename=$(basename "$task")
    content=$(cat "$task")

    if echo "$content" | grep -qE 'grep.*Caddyfile|grep.*CADDYFILE|grep.*caddyfile'; then
        print_pass "$basename: checks Caddyfile for existing entry before appending"
    else
        print_fail "$basename: does NOT check Caddyfile before appending (risk of duplicates)"
    fi
done

if [[ ${#CADDY_TASKS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}  (no Caddy tasks found — skipping)${NC}"
fi
echo ""

# --- Check 4: DNS tasks check for existing record before adding ---
# Tasks that add DNS records should check whether the record already exists.

echo "=== Check 4: DNS tasks check before adding record ==="
echo ""

DNS_TASKS=()
for task in "${PH5_TASKS[@]}"; do
    if echo "$task" | grep -qi "dns"; then
        DNS_TASKS+=("$task")
    fi
done

for task in "${DNS_TASKS[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    basename=$(basename "$task")
    content=$(cat "$task")

    if echo "$content" | grep -qE 'grep.*DOMAIN|grep.*domain|grep.*dns'; then
        print_pass "$basename: checks for existing DNS record before adding"
    else
        print_fail "$basename: does NOT check for existing DNS record (risk of duplicates)"
    fi
done

if [[ ${#DNS_TASKS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}  (no DNS tasks found — skipping)${NC}"
fi
echo ""

# --- Check 5: Container deploy tasks check running state before deploying ---
# Tasks that deploy Docker containers should check if containers are already
# running/healthy before re-deploying.

echo "=== Check 5: Deploy tasks check container state before deploying ==="
echo ""

DEPLOY_TASKS=()
for task in "${PH5_TASKS[@]}"; do
    basename_t=$(basename "$task")
    # Match only tasks whose name contains "deploy" (e.g., task-ph5-02-deploy-*)
    # Exclude directory, caddy, dns, and provision tasks (tested separately)
    if echo "$basename_t" | grep -qi "deploy" && \
       ! echo "$basename_t" | grep -qi "caddy\|dns\|provision\|director\|backup"; then
        DEPLOY_TASKS+=("$task")
    fi
done

for task in "${DEPLOY_TASKS[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    basename=$(basename "$task")
    content=$(cat "$task")

    if echo "$content" | grep -qE 'docker inspect|docker ps|ALL_RUNNING|ALL_HEALTHY'; then
        print_pass "$basename: checks container state before deploying"
    else
        print_fail "$basename: does NOT check container state before deploying"
    fi
done

if [[ ${#DEPLOY_TASKS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}  (no deploy tasks found — skipping)${NC}"
fi
echo ""

# --- Check 6: User provisioning tasks check existing users before creating ---
# Tasks that provision users should query existing users and skip duplicates.

echo "=== Check 6: Provisioning tasks check existing users ==="
echo ""

PROVISION_TASKS=()
for task in "${PH5_TASKS[@]}"; do
    if echo "$task" | grep -qi "provision\|user"; then
        PROVISION_TASKS+=("$task")
    fi
done

for task in "${PROVISION_TASKS[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    basename=$(basename "$task")
    content=$(cat "$task")

    if echo "$content" | grep -qE 'existing.*user|EXISTING_USER|already exists|user.*exists|get_existing'; then
        print_pass "$basename: checks for existing users before provisioning"
    else
        print_fail "$basename: does NOT check for existing users (risk of duplicates)"
    fi
done

if [[ ${#PROVISION_TASKS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}  (no provisioning tasks found — skipping)${NC}"
fi
echo ""

# --- Check 7: All task modules support --dry-run ---
# Dry-run support is a prerequisite for safe idempotent execution.

echo "=== Check 7: All tasks support --dry-run ==="
echo ""

for task in "${PH5_TASKS[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    basename=$(basename "$task")
    content=$(cat "$task")

    if echo "$content" | grep -qE 'dry.run|DRY_RUN|dry-run'; then
        print_pass "$basename: supports --dry-run flag"
    else
        print_fail "$basename: MISSING --dry-run support"
    fi
done
echo ""

# --- Summary ---

echo "========================================"
echo "Idempotency Property Summary (Phase 5)"
echo "========================================"
echo "Task modules checked: ${#PH5_TASKS[@]}"
echo "Checks run:           $TESTS_RUN"
echo -e "Passed:               ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failures:             ${RED}$TESTS_FAILED${NC}"
echo "$TESTS_PASSED / $TESTS_RUN checks passed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Property 14 holds: All Phase 5 task modules implement idempotency guards${NC}"
    exit 0
else
    echo -e "${RED}✗ Property 14 violated: Some task modules missing idempotency guards${NC}"
    exit 1
fi
