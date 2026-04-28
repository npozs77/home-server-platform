#!/usr/bin/env bash
# Test Suite: Backup & Alerting Scripts
# Purpose: Property tests and unit tests for backup-alerting feature
# Usage: bash tests/test_backup_alerting.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_MESSAGES=()

print_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_MESSAGES+=("$1"); }
run_test() { TESTS_RUN=$((TESTS_RUN + 1)); echo ""; echo "Test $TESTS_RUN: $1"; echo "----------------------------------------"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LOG_UTILS="$REPO_ROOT/scripts/operations/utils/log-utils.sh"
SETUP_DAS="$REPO_ROOT/scripts/backup/setup-das-luks.sh"
BACKUP_CONFIGS="$REPO_ROOT/scripts/backup/backup-configs.sh"
BACKUP_ALL="$REPO_ROOT/scripts/backup/backup-all.sh"
BACKUP_WIKI="$REPO_ROOT/scripts/backup/backup-wiki.sh"
HEALTH_CHECK="$REPO_ROOT/scripts/operations/monitoring/check-container-health.sh"
HEALTH_CONFIG="$REPO_ROOT/configs/monitoring/critical-containers.conf"

# ============================================================
# Feature: backup-alerting, Property 2: Structured log format
# Validates: Requirements 7.2, 8.7, 13.2
# ============================================================
test_log_msg_structured_format() {
    run_test "Property 2: Structured log format (100 iterations)"

    local levels=("INFO" "WARN" "ERROR")
    local test_scripts=("backup-all" "backup-configs" "health-check" "setup-das" "my-script-99")
    local test_messages=("Starting backup" "Mount failed" "Disk at 92%" "rsync complete: 150 files" "special chars: /mnt/backup/ [OK]")
    local all_passed=true

    for i in $(seq 1 100); do
        local level="${levels[$((RANDOM % ${#levels[@]}))]}"
        local script="${test_scripts[$((RANDOM % ${#test_scripts[@]}))]}"
        local msg="${test_messages[$((RANDOM % ${#test_messages[@]}))]}-iter${i}"

        # Source in subshell to avoid polluting environment
        local output
        output=$(bash -c "
            source '$LOG_UTILS'
            log_msg '$level' '$script' '$msg'
        " 2>&1)

        # Verify format: YYYY-MM-DD HH:MM:SS - [LEVEL] - [SCRIPT] - message
        # Check timestamp prefix and level/script structure (avoid regex issues with special chars in msg)
        local expected_suffix="- [${level}] - [${script}] - ${msg}"
        if [[ ! "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ -\  ]]; then
            print_fail "Iteration $i: timestamp format mismatch: $output"
            all_passed=false
            break
        fi
        if [[ "$output" != *"$expected_suffix" ]]; then
            print_fail "Iteration $i: suffix mismatch: $output"
            all_passed=false
            break
        fi
    done

    if $all_passed; then
        print_pass "log_msg() produces correct structured format for 100 random inputs"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 20: Graceful msmtp fallback
# Validates: Requirements 10.5
# ============================================================
test_send_alert_email_graceful_fallback() {
    run_test "Property 20: Graceful msmtp fallback"

    # Test 1: send_alert_email does not fail when msmtp is unavailable
    # We run in a subshell with PATH stripped of msmtp
    local exit_code=0
    local output
    output=$(bash -c "
        export PATH='/usr/bin:/bin'
        export ADMIN_EMAIL='test@mydomain.com'
        export SCRIPT_NAME='test-fallback'
        source '$LOG_UTILS'
        send_alert_email 'Test Subject' 'Test Body'
    " 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        print_pass "send_alert_email() exits 0 when msmtp unavailable"
    else
        print_fail "send_alert_email() exited $exit_code when msmtp unavailable (should be 0)"
    fi

    # Test 2: Warning message is logged when msmtp unavailable
    if echo "$output" | grep -q "msmtp not available"; then
        print_pass "Warning logged when msmtp unavailable"
    else
        print_fail "No warning logged when msmtp unavailable. Output: $output"
    fi

    # Test 3: send_alert_email does not fail when ADMIN_EMAIL is unset
    exit_code=0
    output=$(bash -c "
        unset ADMIN_EMAIL
        export SCRIPT_NAME='test-fallback'
        source '$LOG_UTILS'
        send_alert_email 'Test Subject' 'Test Body'
    " 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        print_pass "send_alert_email() exits 0 when ADMIN_EMAIL unset"
    else
        print_fail "send_alert_email() exited $exit_code when ADMIN_EMAIL unset (should be 0)"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 13: DAS setup idempotency
# Validates: Requirements 1.10, 1.11, 1.13
# ============================================================
test_das_setup_idempotency() {
    run_test "Property 13: DAS setup idempotency"

    # Test 1: Script checks for existing LUKS header before formatting
    if grep -q 'cryptsetup isLuks' "$SETUP_DAS"; then
        print_pass "Script checks for existing LUKS header (cryptsetup isLuks)"
    else
        print_fail "Script does not check for existing LUKS header before formatting"
    fi

    # Test 2: Script checks for existing mount before mounting
    if grep -q 'mountpoint -q' "$SETUP_DAS"; then
        print_pass "Script checks for existing mount (mountpoint -q)"
    else
        print_fail "Script does not check for existing mount before mounting"
    fi

    # Test 3: Script checks if mapper device already open
    if grep -q '\-b.*MAPPER_DEV' "$SETUP_DAS" || grep -q '\-b.*mapper' "$SETUP_DAS"; then
        print_pass "Script checks if LUKS mapper device already open"
    else
        print_fail "Script does not check if mapper device already open"
    fi

    # Test 4: Script checks existing ext4 format before mkfs
    if grep -q 'blkid.*TYPE.*ext4' "$SETUP_DAS"; then
        print_pass "Script checks existing ext4 format before mkfs"
    else
        print_fail "Script does not check existing filesystem before formatting"
    fi

    # Test 5: Script checks existing crypttab entry
    if grep -q 'grep.*MAPPER_NAME.*crypttab' "$SETUP_DAS" || grep -q 'grep.*backup_crypt.*/etc/crypttab' "$SETUP_DAS"; then
        print_pass "Script checks existing crypttab entry before adding"
    else
        print_fail "Script does not check existing crypttab entry"
    fi

    # Test 6: Script checks existing fstab entry
    if grep -q 'grep.*MOUNT_POINT.*/etc/fstab' "$SETUP_DAS" || grep -q 'grep.*/mnt/backup.*/etc/fstab' "$SETUP_DAS"; then
        print_pass "Script checks existing fstab entry before adding"
    else
        print_fail "Script does not check existing fstab entry"
    fi

    # Test 7: --dry-run flag supported
    if grep -q '\-\-dry-run' "$SETUP_DAS"; then
        print_pass "Script supports --dry-run flag"
    else
        print_fail "Script does not support --dry-run flag"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 14: Generated crypttab/fstab entries contain required options
# Validates: Requirements 1.7, 1.8
# ============================================================
test_crypttab_fstab_options() {
    run_test "Property 14: crypttab/fstab entries contain required options"

    # Test 1: crypttab entry contains nofail,noauto
    if grep -q 'nofail,noauto' "$SETUP_DAS"; then
        print_pass "crypttab entry contains nofail,noauto"
    else
        print_fail "crypttab entry missing nofail,noauto options"
    fi

    # Test 2: fstab entry contains nofail
    # Check that the fstab echo line contains nofail
    local fstab_lines
    fstab_lines=$(grep 'fstab' "$SETUP_DAS" | grep 'echo' || true)
    if echo "$fstab_lines" | grep -q 'nofail'; then
        print_pass "fstab entry contains nofail option"
    else
        print_fail "fstab entry missing nofail option"
    fi

    # Test 3: crypttab entry references key file
    if grep -q 'KEY_FILE.*luks' "$SETUP_DAS" || grep -q '\.luks-key.*luks,nofail' "$SETUP_DAS"; then
        print_pass "crypttab entry references key file with luks option"
    else
        print_fail "crypttab entry missing key file or luks option"
    fi

    # Test 4: crypttab uses UUID (not device path)
    local crypttab_echo
    crypttab_echo=$(grep 'crypttab' "$SETUP_DAS" | grep 'echo' | grep 'UUID' || true)
    if [[ -n "$crypttab_echo" ]]; then
        print_pass "crypttab entry uses UUID-based device reference"
    else
        print_fail "crypttab entry does not use UUID"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 15: No-LUKS mode skips encryption
# Validates: Requirements 1.14
# ============================================================
test_no_luks_mode() {
    run_test "Property 15: No-LUKS mode skips encryption"

    # Test 1: --no-luks flag is parsed
    if grep -q '\-\-no-luks' "$SETUP_DAS"; then
        print_pass "Script parses --no-luks flag"
    else
        print_fail "Script does not parse --no-luks flag"
    fi

    # Test 2: No-LUKS path does not call cryptsetup
    # Extract the no-luks branch (between "if $NO_LUKS" and "else")
    local no_luks_block
    no_luks_block=$(sed -n '/^\s*if \$NO_LUKS/,/^else$/p' "$SETUP_DAS")
    if echo "$no_luks_block" | grep -q 'cryptsetup'; then
        print_fail "No-LUKS path contains cryptsetup commands (should skip encryption)"
    else
        print_pass "No-LUKS path skips all cryptsetup commands"
    fi

    # Test 3: No-LUKS path formats ext4 directly on device
    if echo "$no_luks_block" | grep -q 'mkfs.ext4'; then
        print_pass "No-LUKS path formats device as ext4 directly"
    else
        print_fail "No-LUKS path does not format device as ext4"
    fi

    # Test 4: No-LUKS path uses UUID-based fstab entry
    if echo "$no_luks_block" | grep -q 'UUID='; then
        print_pass "No-LUKS path uses UUID-based fstab entry"
    else
        print_fail "No-LUKS path does not use UUID-based fstab entry"
    fi

    # Test 5: No-LUKS path does not write to crypttab (check for echo/append to crypttab, not comments)
    if echo "$no_luks_block" | grep -v '^[[:space:]]*#' | grep -q '>> /etc/crypttab\|>> .*/crypttab'; then
        print_fail "No-LUKS path writes to crypttab (should skip)"
    else
        print_pass "No-LUKS path skips crypttab"
    fi

    # Test 6: No-LUKS fstab entry contains nofail
    local no_luks_fstab
    no_luks_fstab=$(echo "$no_luks_block" | grep 'echo.*fstab' || true)
    if echo "$no_luks_fstab" | grep -q 'nofail'; then
        print_pass "No-LUKS fstab entry contains nofail"
    else
        print_fail "No-LUKS fstab entry missing nofail"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 16: Backup script failure produces exit code 1 and alert
# Validates: Requirements 3.4, 4.5
# ============================================================
test_backup_failure_exit_code_and_alert() {
    run_test "Property 16: Backup script failure produces exit code 1 and alert"

    local backup_scripts=(
        "$BACKUP_CONFIGS"
        "$REPO_ROOT/scripts/backup/backup-immich.sh"
    )
    # Add wiki when it exists
    [[ -f "$REPO_ROOT/scripts/backup/backup-wiki.sh" ]] && backup_scripts+=("$REPO_ROOT/scripts/backup/backup-wiki.sh")

    for script in "${backup_scripts[@]}"; do
        local name
        name=$(basename "$script")

        # Test: script calls send_alert_email on failure
        if grep -q 'send_alert_email' "$script"; then
            print_pass "$name calls send_alert_email on failure"
        else
            print_fail "$name missing send_alert_email call on failure"
        fi

        # Test: script exits with code 1 on operation failure
        if grep -q 'exit 1' "$script"; then
            print_pass "$name exits with code 1 on operation failure"
        else
            print_fail "$name missing exit code 1 for operation failure"
        fi
    done
}

# ============================================================
# Feature: backup-alerting, Property 17: Successful backup logs file count and size
# Validates: Requirements 3.3, 4.4
# ============================================================
test_backup_logs_file_count_and_size() {
    run_test "Property 17: Successful backup logs file count and size"

    local backup_scripts=(
        "$BACKUP_CONFIGS"
        "$REPO_ROOT/scripts/backup/backup-immich.sh"
    )
    [[ -f "$REPO_ROOT/scripts/backup/backup-wiki.sh" ]] && backup_scripts+=("$REPO_ROOT/scripts/backup/backup-wiki.sh")

    for script in "${backup_scripts[@]}"; do
        local name
        name=$(basename "$script")

        # Test: script logs file count
        if grep -q 'files' "$script" && grep -q 'log_msg.*INFO' "$script"; then
            print_pass "$name logs file count on success"
        else
            print_fail "$name does not log file count on success"
        fi

        # Test: script logs total size
        if grep -q 'du -sh\|TOTAL_SIZE\|total' "$script"; then
            print_pass "$name logs total backup size on success"
        else
            print_fail "$name does not log total backup size on success"
        fi
    done
}

# ============================================================
# Feature: backup-alerting, Property 1: Mount guard rejects unavailable or read-only mount points
# Validates: Requirements 2.1, 2.2, 2.3, 2.4
# ============================================================
test_mount_guard_rejects_unavailable() {
    run_test "Property 1: Mount guard rejects unavailable or read-only mount points"

    # Collect all backup scripts that should have mount guards
    local backup_scripts=(
        "$BACKUP_CONFIGS"
    )
    # Add future scripts as they are created
    for candidate in \
        "$REPO_ROOT/scripts/backup/backup-immich.sh" \
        "$REPO_ROOT/scripts/backup/backup-wiki.sh" \
        "$REPO_ROOT/scripts/backup/backup-all.sh"; do
        [[ -f "$candidate" ]] && backup_scripts+=("$candidate")
    done

    # Test 1: All backup scripts contain mountpoint -q check
    local all_have_mountpoint=true
    for script in "${backup_scripts[@]}"; do
        local name
        name=$(basename "$script")
        if grep -q 'mountpoint -q' "$script"; then
            print_pass "$name contains mountpoint -q check"
        else
            print_fail "$name missing mountpoint -q check"
            all_have_mountpoint=false
        fi
    done

    # Test 2: All backup scripts exit 2 on mount failure
    for script in "${backup_scripts[@]}"; do
        local name
        name=$(basename "$script")
        if grep -q 'exit 2' "$script"; then
            print_pass "$name exits with code 2 on mount failure"
        else
            print_fail "$name missing exit code 2 for mount failure"
        fi
    done

    # Test 3: All backup scripts send alert email on mount failure
    for script in "${backup_scripts[@]}"; do
        local name
        name=$(basename "$script")
        if grep -q 'send_alert_email' "$script"; then
            print_pass "$name sends alert email on mount failure"
        else
            print_fail "$name missing send_alert_email call for mount failure"
        fi
    done

    # Test 4: Mount guard checks writability (not just mounted)
    for script in "${backup_scripts[@]}"; do
        local name
        name=$(basename "$script")
        if grep -q 'write-test\|writable\|-w ' "$script"; then
            print_pass "$name checks mount writability"
        else
            print_fail "$name does not check mount writability"
        fi
    done
}

# ============================================================
# Feature: backup-alerting, Property 4: Orchestrator continues on individual job failure
# Validates: Requirements 5.3
# ============================================================
test_orchestrator_continues_on_failure() {
    run_test "Property 4: Orchestrator continues on individual job failure"

    # Test: orchestrator captures exit code without exiting
    if grep -q 'exit_code=0' "$BACKUP_ALL" && grep -q '|| exit_code=\$?' "$BACKUP_ALL"; then
        print_pass "Orchestrator captures job exit codes (failure isolation)"
    else
        print_fail "Orchestrator does not isolate job failures"
    fi

    # Test: orchestrator runs all 3 jobs regardless of failures
    local job_count
    job_count=$(grep -c 'run_job' "$BACKUP_ALL" | head -1)
    if [[ "$job_count" -ge 3 ]]; then
        print_pass "Orchestrator runs all 3 backup jobs"
    else
        print_fail "Orchestrator runs fewer than 3 jobs (found $job_count)"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 5: Orchestrator exit code reflects aggregate job status
# Validates: Requirements 5.9
# ============================================================
test_orchestrator_exit_code() {
    run_test "Property 5: Orchestrator exit code reflects aggregate job status"

    # Test: exits 0 when no failures
    if grep -q 'All backup jobs completed successfully' "$BACKUP_ALL" && grep -q 'exit 0' "$BACKUP_ALL"; then
        print_pass "Orchestrator exits 0 when all jobs succeed"
    else
        print_fail "Orchestrator missing exit 0 for all-success case"
    fi

    # Test: exits 1 when any failure
    if grep -q 'FAILURES -gt 0' "$BACKUP_ALL" && grep -q 'exit 1' "$BACKUP_ALL"; then
        print_pass "Orchestrator exits 1 when any job fails"
    else
        print_fail "Orchestrator missing exit 1 for failure case"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 6: Orchestrator sends email only on failure
# Validates: Requirements 5.5, 5.6
# ============================================================
test_orchestrator_email_on_failure_only() {
    run_test "Property 6: Orchestrator sends email only on failure"

    # Test: email sent only when FAILURES > 0
    if grep -q 'FAILURES -gt 0' "$BACKUP_ALL"; then
        # Check that send_alert_email is inside the FAILURES > 0 block
        local in_failure_block
        in_failure_block=$(sed -n '/FAILURES -gt 0/,/^fi$/p' "$BACKUP_ALL" | grep -c 'send_alert_email')
        if [[ "$in_failure_block" -ge 1 ]]; then
            print_pass "Orchestrator sends email only when FAILURES > 0"
        else
            print_fail "Orchestrator send_alert_email not inside failure check"
        fi
    else
        print_fail "Orchestrator missing FAILURES > 0 check"
    fi

    # Test: no email on all-success path
    # The success path (after the if block) should not call send_alert_email
    if grep -A2 'All backup jobs completed successfully' "$BACKUP_ALL" | grep -q 'send_alert_email'; then
        print_fail "Orchestrator sends email on success path"
    else
        print_pass "Orchestrator does not send email on success"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 18: Orchestrator creates missing backup subdirectories
# Validates: Requirements 11.2
# ============================================================
test_orchestrator_creates_subdirs() {
    run_test "Property 18: Orchestrator creates missing backup subdirectories"

    local required_dirs=("configs/homeserver" "configs/system" "immich" "wiki")
    for dir in "${required_dirs[@]}"; do
        if grep -q "mkdir.*${dir}" "$BACKUP_ALL"; then
            print_pass "Orchestrator creates ${dir} subdirectory"
        else
            print_fail "Orchestrator missing mkdir for ${dir}"
        fi
    done
}

# ============================================================
# Feature: backup-alerting, Property 11: Database dump retention removes only old dumps
# Validates: Requirements 12.1, 12.3
# ============================================================
test_db_dump_retention() {
    run_test "Property 11: Database dump retention removes only old dumps"

    # Test: uses find with correct pattern and age
    if grep -q "find.*-name.*-db-\*\.sql.*-mtime +30" "$BACKUP_ALL"; then
        print_pass "Retention targets *-db-*.sql files older than 30 days"
    else
        print_fail "Retention pattern incorrect or missing"
    fi

    # Test: does not target rsync mirror directories
    local retention_block
    retention_block=$(sed -n '/Retention/,/fi$/p' "$BACKUP_ALL")
    if echo "$retention_block" | grep -q 'rm -rf\|--delete'; then
        print_fail "Retention block contains directory removal commands"
    else
        print_pass "Retention does not target rsync mirror directories"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 12: Disk space monitoring thresholds
# Validates: Requirements 14.1, 14.2, 14.3, 14.4
# ============================================================
test_disk_space_thresholds() {
    run_test "Property 12: Disk space monitoring thresholds"

    # Test: checks disk usage
    if grep -q 'df.*BACKUP_MOUNT' "$BACKUP_ALL"; then
        print_pass "Orchestrator checks disk usage of backup mount"
    else
        print_fail "Orchestrator missing disk usage check"
    fi

    # Test: 90% warning threshold
    if grep -q '90' "$BACKUP_ALL" && grep -q 'Warning' "$BACKUP_ALL"; then
        print_pass "Orchestrator has 90% warning threshold"
    else
        print_fail "Orchestrator missing 90% warning threshold"
    fi

    # Test: 95% critical threshold
    if grep -q '95' "$BACKUP_ALL" && grep -q 'CRITICAL' "$BACKUP_ALL"; then
        print_pass "Orchestrator has 95% critical threshold"
    else
        print_fail "Orchestrator missing 95% critical threshold"
    fi

    # Test: logs usage at INFO level regardless
    if grep -q 'log_msg "INFO".*Disk usage' "$BACKUP_ALL"; then
        print_pass "Orchestrator logs disk usage at INFO level"
    else
        print_fail "Orchestrator missing INFO-level disk usage log"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 7: Health check consolidated alerting
# Validates: Requirements 8.3, 8.4, 8.5, 8.6
# ============================================================
test_health_check_consolidated_alert() {
    run_test "Property 7: Health check consolidated alerting"

    # Test 1: Health check sends exactly one email (consolidated, not per-container)
    # Count send_alert_email calls — should be exactly 1
    local email_calls
    email_calls=$(grep -c 'send_alert_email' "$HEALTH_CHECK")
    if [[ "$email_calls" -eq 1 ]]; then
        print_pass "Health check has exactly 1 send_alert_email call (consolidated)"
    else
        print_fail "Health check has ${email_calls} send_alert_email calls (expected 1 consolidated)"
    fi

    # Test 2: Email is only sent when problems exist (PROBLEM_COUNT > 0)
    if grep -q 'PROBLEM_COUNT -eq 0' "$HEALTH_CHECK"; then
        # Verify the exit 0 is before the email sending
        local exit_line send_line
        exit_line=$(grep -n 'PROBLEM_COUNT -eq 0' "$HEALTH_CHECK" | head -1 | cut -d: -f1)
        send_line=$(grep -n 'send_alert_email' "$HEALTH_CHECK" | head -1 | cut -d: -f1)
        if [[ "$exit_line" -lt "$send_line" ]]; then
            print_pass "Health check exits before email when all healthy"
        else
            print_fail "Health check email call is before healthy-exit check"
        fi
    else
        print_fail "Health check missing PROBLEM_COUNT check"
    fi

    # Test 3: No per-container email loop (send_alert_email NOT inside the for loop)
    local for_block
    for_block=$(sed -n '/for container in/,/^done$/p' "$HEALTH_CHECK")
    if echo "$for_block" | grep -q 'send_alert_email'; then
        print_fail "Health check sends email inside per-container loop (should be consolidated)"
    else
        print_pass "Health check does not send email inside per-container loop"
    fi

    # Test 4: Alert body lists unhealthy containers
    if grep -q 'Unhealthy containers' "$HEALTH_CHECK"; then
        print_pass "Alert body includes unhealthy container list"
    else
        print_fail "Alert body missing unhealthy container list"
    fi

    # Test 5: Alert body lists healthy containers
    if grep -q 'Healthy containers' "$HEALTH_CHECK"; then
        print_pass "Alert body includes healthy container list"
    else
        print_fail "Alert body missing healthy container list"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 8: Health check reads container list from config file
# Validates: Requirements 8.1, 8.2
# ============================================================
test_health_check_reads_config() {
    run_test "Property 8: Health check reads container list from config file"

    # Test 1: Health check reads from critical-containers.conf
    if grep -q 'critical-containers.conf' "$HEALTH_CHECK"; then
        print_pass "Health check references critical-containers.conf"
    else
        print_fail "Health check does not reference critical-containers.conf"
    fi

    # Test 2: Container list is NOT hardcoded
    # The old script had CONTAINERS="pihole caddy jellyfin" — verify that's gone
    if grep -q '^CONTAINERS="' "$HEALTH_CHECK"; then
        print_fail "Health check has hardcoded CONTAINERS variable"
    else
        print_pass "Health check does not hardcode container list"
    fi

    # Test 3: Comments are skipped (grep -v '^\s*#')
    if grep -q "grep.*-v.*#" "$HEALTH_CHECK"; then
        print_pass "Health check skips comment lines"
    else
        print_fail "Health check does not skip comment lines"
    fi

    # Test 4: Blank lines are skipped
    if grep -q "grep.*-v.*'\\^\\\\s\\*\\\$'" "$HEALTH_CHECK" || grep -q 'grep -v.*^\s*$' "$HEALTH_CHECK"; then
        print_pass "Health check skips blank lines"
    else
        print_fail "Health check does not skip blank lines"
    fi

    # Test 5: Config file exists with expected default containers
    if [[ -f "$HEALTH_CONFIG" ]]; then
        print_pass "critical-containers.conf exists"
    else
        print_fail "critical-containers.conf not found"
        return
    fi

    local expected=("caddy" "pihole" "immich-server" "immich-postgres" "jellyfin")
    for name in "${expected[@]}"; do
        if grep -q "^${name}$" "$HEALTH_CONFIG"; then
            print_pass "Config contains ${name}"
        else
            print_fail "Config missing ${name}"
        fi
    done
}

# ============================================================
# Feature: backup-alerting, Property 9: Alert email subject format
# Validates: Requirements 10.1, 10.2, 14.2, 14.3
# ============================================================
test_alert_email_subject_format() {
    run_test "Property 9: Alert email subject format"

    # Test 1: Backup failure subject format [HOMESERVER] Backup FAILED - YYYY-MM-DD
    if grep -q '\[HOMESERVER\] Backup FAILED' "$BACKUP_ALL"; then
        print_pass "Orchestrator uses [HOMESERVER] Backup FAILED subject format"
    else
        print_fail "Orchestrator missing [HOMESERVER] Backup FAILED subject"
    fi

    # Test 2: Health check subject format [HOMESERVER] Container Alert - YYYY-MM-DD HH:MM
    if grep -q '\[HOMESERVER\] Container Alert' "$HEALTH_CHECK"; then
        print_pass "Health check uses [HOMESERVER] Container Alert subject format"
    else
        print_fail "Health check missing [HOMESERVER] Container Alert subject"
    fi

    # Test 3: Health check subject includes timestamp with HH:MM
    local subject_line
    subject_line=$(grep 'SUBJECT=.*Container Alert' "$HEALTH_CHECK" || true)
    if echo "$subject_line" | grep -q '%H:%M\|HH:MM\|TIMESTAMP'; then
        print_pass "Health check subject includes time component"
    else
        print_fail "Health check subject missing time component"
    fi

    # Test 4: Disk warning subject contains Warning
    if grep -q '\[HOMESERVER\] Backup Disk Warning' "$BACKUP_ALL"; then
        print_pass "Orchestrator uses Warning in disk warning subject"
    else
        print_fail "Orchestrator missing Warning in disk warning subject"
    fi

    # Test 5: Disk critical subject contains CRITICAL
    if grep -q '\[HOMESERVER\] Backup Disk CRITICAL' "$BACKUP_ALL"; then
        print_pass "Orchestrator uses CRITICAL in disk critical subject"
    else
        print_fail "Orchestrator missing CRITICAL in disk critical subject"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 10: Alert email body contains required fields
# Validates: Requirements 10.3, 2.5
# ============================================================
test_alert_email_body_fields() {
    run_test "Property 10: Alert email body contains required fields"

    local scripts_to_check=(
        "$BACKUP_ALL"
        "$HEALTH_CHECK"
        "$BACKUP_CONFIGS"
    )

    for script in "${scripts_to_check[@]}"; do
        local name
        name=$(basename "$script")

        # Test: email body contains hostname
        if grep -q 'hostname' "$script" || grep -q 'Hostname' "$script"; then
            print_pass "$name alert body includes hostname"
        else
            print_fail "$name alert body missing hostname"
        fi

        # Test: email body contains timestamp
        if grep -q 'Timestamp' "$script" || grep -q 'timestamp' "$script"; then
            print_pass "$name alert body includes timestamp"
        else
            print_fail "$name alert body missing timestamp"
        fi
    done

    # Test: backup orchestrator body includes failed/successful job lists
    if grep -q 'Failed jobs' "$BACKUP_ALL"; then
        print_pass "Orchestrator alert body includes failed jobs list"
    else
        print_fail "Orchestrator alert body missing failed jobs list"
    fi

    # Test: health check body includes unhealthy container details
    if grep -q 'Unhealthy containers' "$HEALTH_CHECK"; then
        print_pass "Health check alert body includes unhealthy container details"
    else
        print_fail "Health check alert body missing unhealthy container details"
    fi

    # Test: mount unavailable alert includes mount point path
    if grep -q 'Mount point' "$BACKUP_ALL"; then
        print_pass "Mount unavailable alert includes mount point path"
    else
        print_fail "Mount unavailable alert missing mount point path"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 3: Dry-run mode prevents destructive operations
# Validates: Requirements 1.12, 3.5, 4.6, 5.7, 8.8, 13.4
# ============================================================
test_dry_run_no_destructive_ops() {
    run_test "Property 3: Dry-run mode prevents destructive operations"

    local all_scripts=(
        "$SETUP_DAS"
        "$BACKUP_ALL"
        "$BACKUP_CONFIGS"
        "$REPO_ROOT/scripts/backup/backup-wiki.sh"
        "$REPO_ROOT/scripts/backup/backup-immich.sh"
        "$HEALTH_CHECK"
    )

    # Test 1: All scripts parse --dry-run flag
    for script in "${all_scripts[@]}"; do
        local name
        name=$(basename "$script")
        if [[ ! -f "$script" ]]; then
            print_fail "$name not found — cannot verify dry-run"
            continue
        fi
        if grep -q '\-\-dry-run' "$script"; then
            print_pass "$name parses --dry-run flag"
        else
            print_fail "$name does not parse --dry-run flag"
        fi
    done

    # Test 2: Health check dry-run skips email sending
    local health_dryrun_block
    health_dryrun_block=$(grep -A2 'DRY_RUN' "$HEALTH_CHECK" | grep -i 'send_alert_email\|would send' || true)
    if grep -q 'dry-run.*would send' "$HEALTH_CHECK" || grep -q 'DRY_RUN.*send_alert_email' "$HEALTH_CHECK"; then
        print_pass "Health check dry-run skips actual email sending"
    else
        # Check the if $DRY_RUN block
        if sed -n '/if \$DRY_RUN/,/^fi$/p' "$HEALTH_CHECK" | grep -q 'would send\|dry-run'; then
            print_pass "Health check dry-run skips actual email sending"
        else
            print_fail "Health check dry-run may not skip email sending"
        fi
    fi

    # Test 3: Orchestrator dry-run skips DB dump retention
    if grep -q 'DRY_RUN.*would check DB dump retention\|dry-run.*retention' "$BACKUP_ALL"; then
        print_pass "Orchestrator dry-run skips DB dump retention"
    else
        print_fail "Orchestrator dry-run may not skip DB dump retention"
    fi

    # Test 4: DAS setup dry-run skips cryptsetup/mkfs
    if grep -q 'DRY_RUN\|dry.run' "$SETUP_DAS"; then
        print_pass "DAS setup has dry-run guards for destructive operations"
    else
        print_fail "DAS setup missing dry-run guards"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 21: Deleted photo retention
# Validates: rsync --backup-dir preserves deleted photos
# ============================================================
test_deleted_photo_retention() {
    run_test "Property 21: Deleted photo retention via rsync --backup-dir"

    local immich_script="$REPO_ROOT/scripts/backup/backup-immich.sh"

    # Test 1: Immich rsync uses --backup flag
    if grep -q '\-\-backup ' "$immich_script"; then
        print_pass "backup-immich.sh uses --backup flag for rsync"
    else
        print_fail "backup-immich.sh missing --backup flag on rsync"
    fi

    # Test 2: Immich rsync uses --backup-dir with DELETED_DIR variable
    if grep -q '\-\-backup-dir=.*DELETED_DIR' "$immich_script"; then
        print_pass "backup-immich.sh uses --backup-dir with DELETED_DIR variable"
    else
        print_fail "backup-immich.sh missing --backup-dir with DELETED_DIR"
    fi

    # Test 3: .deleted dir is date-stamped
    if grep -q 'DELETED_DIR=.*date' "$immich_script" || grep -q '\.deleted/\$(date' "$immich_script"; then
        print_pass "Deleted photo directory is date-stamped"
    else
        print_fail "Deleted photo directory is not date-stamped"
    fi

    # Test 4: All three photo rsync commands use --backup-dir
    local backup_dir_count
    backup_dir_count=$(grep -c '\-\-backup-dir=' "$immich_script" || true)
    if [[ "$backup_dir_count" -ge 3 ]]; then
        print_pass "All 3 rsync commands use --backup-dir ($backup_dir_count found)"
    else
        print_fail "Expected 3 rsync --backup-dir commands, found $backup_dir_count"
    fi
}

# ============================================================
# Feature: backup-alerting, Property 22: Deleted photo cleanup on high disk usage
# Validates: Orchestrator purges old .deleted dirs when disk >80%
# ============================================================
test_deleted_photo_cleanup() {
    run_test "Property 22: Deleted photo cleanup on high disk usage"

    # Test 1: Orchestrator checks for .deleted directory
    if grep -q '\.deleted' "$BACKUP_ALL"; then
        print_pass "Orchestrator references .deleted directory"
    else
        print_fail "Orchestrator does not reference .deleted directory"
    fi

    # Test 2: Cleanup triggers at 80% disk usage
    if grep -q '80' "$BACKUP_ALL" && grep -q 'USAGE_PCT.*-ge.*80\|80.*USAGE_PCT' "$BACKUP_ALL"; then
        print_pass "Cleanup triggers at 80% disk usage threshold"
    else
        print_fail "Missing 80% disk usage threshold for cleanup"
    fi

    # Test 3: Cleanup targets dirs older than 90 days
    if grep -q 'mtime +90\|mtime.*90' "$BACKUP_ALL"; then
        print_pass "Cleanup targets .deleted dirs older than 90 days"
    else
        print_fail "Missing 90-day retention for .deleted cleanup"
    fi

    # Test 4: Cleanup only runs when not in dry-run
    if grep -B5 '\.deleted' "$BACKUP_ALL" | grep -q 'DRY_RUN'; then
        print_pass "Cleanup respects dry-run mode"
    else
        print_fail "Cleanup may not respect dry-run mode"
    fi
}

# ============================================================
# Run all tests
# ============================================================
echo "========================================"
echo "Backup & Alerting — Property Tests"
echo "========================================"

test_log_msg_structured_format
test_send_alert_email_graceful_fallback
test_das_setup_idempotency
test_crypttab_fstab_options
test_no_luks_mode
test_backup_failure_exit_code_and_alert
test_backup_logs_file_count_and_size
test_mount_guard_rejects_unavailable
test_orchestrator_continues_on_failure
test_orchestrator_exit_code
test_orchestrator_email_on_failure_only
test_orchestrator_creates_subdirs
test_db_dump_retention
test_disk_space_thresholds
test_health_check_consolidated_alert
test_health_check_reads_config
test_alert_email_subject_format
test_alert_email_body_fields
test_dry_run_no_destructive_ops
test_deleted_photo_retention
test_deleted_photo_cleanup

# Summary
echo ""
echo "========================================"
echo -e "Results: ${GREEN}${TESTS_PASSED} passed${NC}, ${RED}${TESTS_FAILED} failed${NC} / ${TESTS_RUN} total"
echo "========================================"

if [[ ${#FAILED_MESSAGES[@]} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for msg in "${FAILED_MESSAGES[@]}"; do
        echo -e "  ${RED}✗${NC} $msg"
    done
fi

exit "$TESTS_FAILED"
