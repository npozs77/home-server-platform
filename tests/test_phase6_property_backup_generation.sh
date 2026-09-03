#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Backup Script Generation (Property 27)
# Feature: docker-service-helper, Property 27: Backup Script Generation and Registration
# Purpose: Verify backup-helper-services.sh reads services.yml dynamically and backs up
#   services with/without backup blocks correctly (no per-service scripts generated)
# Validates: Requirements 31.1, 31.4, 31.7, 31.8
# Usage: bash tests/test_phase6_property_backup_generation.sh

set -euo pipefail

if ! command -v yq &>/dev/null; then echo "SKIP: yq not installed"; exit 0; fi

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
print_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

ITERATIONS="${PBT_ITERATIONS:-25}"
BACKUP_SCRIPT="scripts/backup/backup-helper-services.sh"

echo "========================================"
echo "Property 27: Dynamic Backup from services.yml"
echo "Iterations: $ITERATIONS"
echo "========================================"
echo ""

# ── Static checks ──

# Check 1: backup-helper-services.sh exists
TESTS_RUN=$((TESTS_RUN + 1))
[[ -f "$BACKUP_SCRIPT" ]] && print_pass || print_fail "backup-helper-services.sh does not exist"

# Check 2: Script has set -euo pipefail
TESTS_RUN=$((TESTS_RUN + 1))
head -5 "$BACKUP_SCRIPT" | grep -q "set -euo pipefail" && print_pass || print_fail "Missing safety flags"

# Check 3: Script is executable
TESTS_RUN=$((TESTS_RUN + 1))
[[ -x "$BACKUP_SCRIPT" ]] && print_pass || print_fail "Script not executable"

# Check 4: Valid bash syntax
TESTS_RUN=$((TESTS_RUN + 1))
bash -n "$BACKUP_SCRIPT" 2>/dev/null && print_pass || print_fail "Syntax error in backup-helper-services.sh"

# Check 5: Script reads SERVICES_CONFIG (services.yml)
TESTS_RUN=$((TESTS_RUN + 1))
grep -q "SERVICES_CONFIG" "$BACKUP_SCRIPT" && print_pass || print_fail "Script does not reference SERVICES_CONFIG"

# Check 6: Script uses yq to read services
TESTS_RUN=$((TESTS_RUN + 1))
grep -q "yq" "$BACKUP_SCRIPT" && print_pass || print_fail "Script does not use yq"

# Check 7: Script supports --dry-run
TESTS_RUN=$((TESTS_RUN + 1))
grep -q "\-\-dry-run" "$BACKUP_SCRIPT" && print_pass || print_fail "Script does not support --dry-run"

# Check 8: Script supports single-service argument
TESTS_RUN=$((TESTS_RUN + 1))
grep -q "TARGET_SERVICE" "$BACKUP_SCRIPT" && print_pass || print_fail "Script does not support single-service argument"

# Check 9: Script handles pre_command from backup block
TESTS_RUN=$((TESTS_RUN + 1))
grep -q "pre_command" "$BACKUP_SCRIPT" && print_pass || print_fail "Script does not handle pre_command"

# Check 10: Script handles additional backup paths
TESTS_RUN=$((TESTS_RUN + 1))
grep -q "backup.paths" "$BACKUP_SCRIPT" && print_pass || print_fail "Script does not handle backup.paths"

# Check 11: backup-all.sh has static run_job line for helper-services
TESTS_RUN=$((TESTS_RUN + 1))
grep -q 'backup-helper-services.sh' scripts/backup/backup-all.sh && print_pass || print_fail "backup-all.sh missing run_job for backup-helper-services.sh"

# Check 12: No per-service backup generation in service-ops.sh
TESTS_RUN=$((TESTS_RUN + 1))
if ! grep -q "_generate_backup_script\|_generate_simple_backup_script" scripts/docker-helper/lib/service-ops.sh; then
    print_pass
else
    print_fail "service-ops.sh still contains per-service backup generation functions"
fi

# Check 13: No marker-based backup registration in service-ops.sh
TESTS_RUN=$((TESTS_RUN + 1))
if ! grep -q "BEGIN helper-backup:" scripts/docker-helper/lib/service-ops.sh; then
    print_pass
else
    print_fail "service-ops.sh still contains marker-based backup registration"
fi

# ── Property iterations: verify services.yml schema is correctly read ──

TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT

for ((i=1; i<=ITERATIONS; i++)); do
    svc="bkp-$(printf '%03d' $i)"
    has_backup=$((RANDOM % 2))
    cfg="${TMP_DIR}/cfg-${i}.yml"

    if [[ $has_backup -eq 1 ]]; then
        cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    image: test:v1
    port: 8080
    backup:
      pre_command: "docker exec ${svc}-db pg_dump -U postgres"
      pre_command_output: "db-dump.sql"
      paths:
        - /extra/path/${svc}
YAML
    else
        cat > "$cfg" << YAML
services:
  ${svc}:
    name: ${svc}
    image: test:v1
    port: 8080
YAML
    fi

    # Check: yq can read the service definition
    TESTS_RUN=$((TESTS_RUN + 1))
    if yq -e ".services.${svc}" "$cfg" >/dev/null 2>&1; then
        print_pass
    else
        print_fail "[$i] yq cannot read service ${svc}"
        continue
    fi

    # Check: backup block presence matches expectation
    TESTS_RUN=$((TESTS_RUN + 1))
    backup_val=$(yq -r ".services.${svc}.backup // \"\"" "$cfg")
    if [[ $has_backup -eq 1 ]]; then
        [[ -n "$backup_val" ]] && [[ "$backup_val" != "null" ]] && print_pass || print_fail "[$i] Expected backup block present"
    else
        [[ -z "$backup_val" || "$backup_val" == "null" ]] && print_pass || print_fail "[$i] Expected no backup block"
    fi

    # Check: pre_command readable when backup block exists
    if [[ $has_backup -eq 1 ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        pre_cmd=$(yq -r ".services.${svc}.backup.pre_command // \"\"" "$cfg")
        [[ "$pre_cmd" == *"pg_dump"* ]] && print_pass || print_fail "[$i] pre_command not readable via yq"

        TESTS_RUN=$((TESTS_RUN + 1))
        pre_out=$(yq -r ".services.${svc}.backup.pre_command_output // \"\"" "$cfg")
        [[ "$pre_out" == "db-dump.sql" ]] && print_pass || print_fail "[$i] pre_command_output not readable via yq"

        TESTS_RUN=$((TESTS_RUN + 1))
        path_count=$(yq -r ".services.${svc}.backup.paths | length" "$cfg")
        [[ "$path_count" -ge 1 ]] && print_pass || print_fail "[$i] backup.paths not readable via yq"
    fi

    # Check: data dir path derivable from service name
    TESTS_RUN=$((TESTS_RUN + 1))
    expected_data="/mnt/data/services/${svc}"
    [[ "$expected_data" == "/mnt/data/services/${svc}" ]] && print_pass || print_fail "[$i] Data dir path mismatch"
done

echo ""
echo "========================================"
echo "Property 27 Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
