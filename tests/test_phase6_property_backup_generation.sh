#!/usr/bin/env bash
# CI_SAFE=true
# Property Test: Backup Script Generation (Property 27)
# Feature: docker-service-helper, Property 27: Backup Script Generation and Registration
# Purpose: Verify backup script generation logic for services with/without backup blocks
# Validates: Requirements 31.1, 31.4, 31.7, 31.8
# Usage: bash tests/test_phase6_property_backup_generation.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
print_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

ITERATIONS=100
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT

# Stubs for sourced utilities
print_info() { :; }; print_success() { :; }; print_error() { :; }; print_header() { :; }

# Set globals needed by service-ops.sh
SERVICES_CONFIG=""
COMPOSE_DIR="${TMP_DIR}/compose"
CADDYFILE="${TMP_DIR}/Caddyfile"
DATA_BASE="${TMP_DIR}/data"
LOG_FILE="${TMP_DIR}/helper.log"
BACKUP_ALL="${TMP_DIR}/backup-all.sh"
BACKUP_DIR="${TMP_DIR}/backup"
SERVER_IP="192.168.1.2"
TIMEZONE="UTC"
INTERNAL_SUBDOMAIN="home.example.com"
SCRIPT_DIR="scripts/docker-helper"

mkdir -p "$COMPOSE_DIR" "$DATA_BASE" "$BACKUP_DIR"
echo "#!/bin/bash" > "$BACKUP_ALL"
touch "$CADDYFILE"

COMPOSE_GEN_LOADED=""
SERVICE_OPS_LOADED=""
source "scripts/docker-helper/lib/compose-gen.sh"
source "scripts/docker-helper/lib/service-ops.sh"

echo "========================================"
echo "Property 27: Backup Script Generation"
echo "Iterations: $ITERATIONS"
echo "========================================"
echo ""

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
      pre_command: "docker exec ${svc}-db pg_dump -U postgres > /tmp/dump.sql"
      pre_command_output: "db-dump.sql"
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

    SERVICES_CONFIG="$cfg"

    # Reset backup-all.sh for each iteration
    echo "#!/bin/bash" > "$BACKUP_ALL"

    # Run register_backup (not dry-run)
    register_backup "$svc" "false" 2>/dev/null || true

    backup_script="${BACKUP_DIR}/backup-${svc}.sh"

    # Check 1: Backup script generated
    TESTS_RUN=$((TESTS_RUN + 1))
    [[ -f "$backup_script" ]] && print_pass || print_fail "[$i] Backup script not generated for ${svc}"

    # Check 2: Script has set -euo pipefail
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$backup_script" ]]; then
        grep -q "set -euo pipefail" "$backup_script" && print_pass || print_fail "[$i] Missing safety flags in backup script"
    else
        print_fail "[$i] Cannot check safety flags — script missing"
    fi

    # Check 3: Script is executable
    TESTS_RUN=$((TESTS_RUN + 1))
    [[ -x "$backup_script" ]] && print_pass || print_fail "[$i] Backup script not executable"

    # Check 4: If backup block, pre_command present
    if [[ $has_backup -eq 1 ]] && [[ -f "$backup_script" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        grep -q "pg_dump" "$backup_script" && print_pass || print_fail "[$i] pre_command missing from backup script"
    fi

    # Check 5: Registered in backup-all.sh
    TESTS_RUN=$((TESTS_RUN + 1))
    grep -q "BEGIN helper-backup:${svc}" "$BACKUP_ALL" && print_pass || print_fail "[$i] Not registered in backup-all.sh"

    # Cleanup for next iteration
    rm -f "$backup_script"
done

echo ""
echo "========================================"
echo "Property 27 Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
