#!/bin/bash
set -euo pipefail

# Unified E2E Validation Script
# Purpose: Run all phase validations in a single pass (regression, health check, alerting-ready)
# Usage: sudo ./validate-all.sh [--phase N] [--json] [--quiet]
# Options:
#   --phase N   Run only phase N (1-5), omit for all phases
#   --json      Output results as JSON (for future alerting integration)
#   --quiet     Only print summary (suppress per-check detail)
# Exit codes: 0 = all pass, 1 = failures detected, 2 = config/setup error
#
# Check arrays are defined in each validation-*-utils.sh (PHASE1_CHECKS, PHASE2_CHECKS, etc.)
# This script sources them — no duplication. When a new phase is added:
#   1. Create scripts/operations/utils/validation-{name}-utils.sh with PHASEN_CHECKS array
#   2. Add source + run_phase line below
#   3. Update docs/14-e2e-validation.md
#
# Excluded from E2E (justified):
#   - validate_config(): pre-deployment gate, not runtime health
#   - Manual checklists: need human + client device
#   - validate_prerequisites() (Phase 4): redundant with Phase 1-3 checks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/utils"

# Source shared utilities
source "${UTILS_DIR}/output-utils.sh"
source "${UTILS_DIR}/env-utils.sh"

# Parse arguments
PHASE_FILTER=""
JSON_OUTPUT=false
QUIET=false
for arg in "$@"; do
    case "$arg" in
        --phase) shift; PHASE_FILTER="${1:-}"; shift || true ;;
        --json) JSON_OUTPUT=true ;;
        --quiet) QUIET=true ;;
        [1-9]) PHASE_FILTER="$arg" ;;
    esac
done

# Check root
if [[ $EUID -ne 0 ]]; then print_error "Must run as root (use sudo)"; exit 2; fi

# Load all config files
load_env_files || { print_error "No config files found in /opt/homeserver/configs/"; exit 2; }

# Export variables needed by validation functions
export DATA_DISK="${DATA_DISK:-}"
export DATA_MOUNT="${DATA_MOUNT:-/mnt/data}"
export ADMIN_USER="${ADMIN_USER:-}"
export POWER_USERS="${POWER_USERS:-}"
export STANDARD_USERS="${STANDARD_USERS:-}"
export SERVER_IP="${SERVER_IP:-}"
export INTERNAL_SUBDOMAIN="${INTERNAL_SUBDOMAIN:-}"
export DOMAIN="${DOMAIN:-}"
export IMMICH_DOMAIN="${IMMICH_DOMAIN:-}"
export IMMICH_VERSION="${IMMICH_VERSION:-}"
export WIKI_DOMAIN="${WIKI_DOMAIN:-}"
export OPENWEBUI_DOMAIN="${OPENWEBUI_DOMAIN:-}"

# Source validation libraries (each defines PHASEN_CHECKS array + functions)
source "${UTILS_DIR}/validation-foundation-utils.sh"       # → PHASE1_CHECKS
source "${UTILS_DIR}/validation-infrastructure-utils.sh"    # → PHASE2_CHECKS
source "${UTILS_DIR}/validation-core-services-utils.sh"     # → PHASE3_CHECKS
source "${UTILS_DIR}/validation-photo-management-utils.sh"  # → PHASE4_CHECKS
source "${UTILS_DIR}/validation-wiki-llm-utils.sh"         # → PHASE5_CHECKS

# Counters
GRAND_TOTAL=0
GRAND_PASSED=0
GRAND_FAILED=0
PHASE_RESULTS=()
JSON_ENTRIES=()
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Run a single check
run_check() {
    local phase="$1" name="$2" func="$3"
    GRAND_TOTAL=$((GRAND_TOTAL + 1))

    [[ "$QUIET" == false ]] && printf "  %-35s " "$name" || true

    if $func > /tmp/validate_all_output 2>&1; then
        GRAND_PASSED=$((GRAND_PASSED + 1))
        if [[ "$QUIET" == false ]]; then echo -e "\033[0;32m✓ PASS\033[0m"; fi
        if [[ "$JSON_OUTPUT" == true ]]; then JSON_ENTRIES+=("{\"phase\":$phase,\"check\":\"$name\",\"status\":\"pass\"}"); fi
    else
        GRAND_FAILED=$((GRAND_FAILED + 1))
        if [[ "$QUIET" == false ]]; then
            echo -e "\033[0;31m✗ FAIL\033[0m"
            sed 's/^/    /' /tmp/validate_all_output
        fi
        if [[ "$JSON_OUTPUT" == true ]]; then
            local detail
            detail=$(head -3 /tmp/validate_all_output 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')
            JSON_ENTRIES+=("{\"phase\":$phase,\"check\":\"$name\",\"status\":\"fail\",\"detail\":\"$detail\"}")
        fi
    fi
}

# Run all checks for a phase
run_phase() {
    local phase_num="$1" phase_name="$2"
    shift 2
    local checks=("$@")
    local phase_total=${#checks[@]}

    if [[ "$QUIET" == false ]]; then echo "" && echo -e "\033[0;34m── Phase $phase_num: $phase_name ($phase_total checks) ──\033[0m"; fi

    local before=$GRAND_PASSED
    for check in "${checks[@]}"; do
        run_check "$phase_num" "${check%%:*}" "${check##*:}"
    done
    PHASE_RESULTS+=("Phase $phase_num ($phase_name): $((GRAND_PASSED - before))/$phase_total")
}

# ── Execute ──
if [[ "$QUIET" == false ]]; then print_header "Home Server E2E Validation" && echo "Timestamp: $TIMESTAMP" && echo "Server:    ${SERVER_IP:-unknown}"; fi

if [[ -z "$PHASE_FILTER" || "$PHASE_FILTER" == "1" ]]; then run_phase 1 "Foundation"        "${PHASE1_CHECKS[@]}"; fi
if [[ -z "$PHASE_FILTER" || "$PHASE_FILTER" == "2" ]]; then run_phase 2 "Infrastructure"    "${PHASE2_CHECKS[@]}"; fi
if [[ -z "$PHASE_FILTER" || "$PHASE_FILTER" == "3" ]]; then run_phase 3 "Core Services"     "${PHASE3_CHECKS[@]}"; fi
if [[ -z "$PHASE_FILTER" || "$PHASE_FILTER" == "4" ]]; then run_phase 4 "Photo Management"  "${PHASE4_CHECKS[@]}"; fi
if [[ -z "$PHASE_FILTER" || "$PHASE_FILTER" == "5" ]]; then run_phase 5 "Wiki & LLM"       "${PHASE5_CHECKS[@]}"; fi

# ── Summary ──
echo ""
echo "========================================"
echo "E2E VALIDATION SUMMARY"
echo "========================================"
for result in "${PHASE_RESULTS[@]}"; do
    echo "  $result"
done
echo "----------------------------------------"
echo "  TOTAL: $GRAND_PASSED/$GRAND_TOTAL passed"
if [[ $GRAND_FAILED -gt 0 ]]; then
    echo -e "  \033[0;31m$GRAND_FAILED check(s) FAILED\033[0m"
else
    echo -e "  \033[0;32mAll checks passed!\033[0m"
fi
echo "========================================"

# ── JSON output ──
if [[ "$JSON_OUTPUT" == true ]]; then
    echo ""
    echo "--- JSON ---"
    echo "{"
    echo "  \"timestamp\": \"$TIMESTAMP\","
    echo "  \"server\": \"${SERVER_IP:-unknown}\","
    echo "  \"total\": $GRAND_TOTAL,"
    echo "  \"passed\": $GRAND_PASSED,"
    echo "  \"failed\": $GRAND_FAILED,"
    echo "  \"checks\": ["
    first=true
    for entry in "${JSON_ENTRIES[@]}"; do
        if [[ "$first" == true ]]; then echo "    $entry"; first=false; else echo "    ,$entry"; fi
    done
    echo "  ]"
    echo "}"
fi

rm -f /tmp/validate_all_output
[[ $GRAND_FAILED -eq 0 ]] && exit 0 || exit 1
