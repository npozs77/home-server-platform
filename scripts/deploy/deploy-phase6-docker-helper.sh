#!/bin/bash
set -euo pipefail

# Phase 06 - Docker Service Helper Deployment Script
# Purpose: Orchestrate helper infrastructure deployment with modular task execution
# Prerequisites: Phase 1-5 complete (Docker, Caddy, Pi-hole, Netdata running)
# Usage: sudo ./deploy-phase6-docker-helper.sh [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility libraries
source /opt/homeserver/scripts/operations/utils/output-utils.sh
source /opt/homeserver/scripts/operations/utils/env-utils.sh

# Configuration file paths
FOUNDATION_CONFIG="/opt/homeserver/configs/foundation.env"
SERVICES_CONFIG="/opt/homeserver/configs/services.env"
SECRETS_CONFIG="/opt/homeserver/configs/secrets.env"

# Dry-run mode
DRY_RUN=false
DRY_RUN_ARG=""
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=true; DRY_RUN_ARG="--dry-run"; echo "Running in DRY-RUN mode"; echo ""; fi

# Check root
[[ $EUID -ne 0 ]] && { print_error "This script must be run as root (use sudo)"; exit 1; }

# Load configuration from env files
load_config() {
    if [[ -f "$FOUNDATION_CONFIG" ]]; then source "$FOUNDATION_CONFIG"; else print_error "Foundation config missing: $FOUNDATION_CONFIG"; return 1; fi
    if [[ -f "$SERVICES_CONFIG" ]]; then source "$SERVICES_CONFIG"; fi
    if [[ -f "$SECRETS_CONFIG" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            value="${value#\"}"; value="${value%\"}"
            value="${value#\'}"; value="${value%\'}"
            export "$key=$value"
        done < <(grep -v '^\s*#' "$SECRETS_CONFIG" | grep -v '^\s*$' | grep '=')
    fi
    return 0
}

HELPER="/opt/homeserver/scripts/docker-helper/docker-service-helper.sh"

# Task execution functions
execute_install_yq() {
    bash /opt/homeserver/scripts/deploy/tasks/task-ph6-01-install-yq.sh ${DRY_RUN_ARG}
}

execute_create_services_yml() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    bash /opt/homeserver/scripts/deploy/tasks/task-ph6-03-add-helper-services-yaml.sh ${DRY_RUN_ARG}
}

execute_deploy_example() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    bash /opt/homeserver/scripts/deploy/tasks/task-ph6-04-deploy-example-service.sh ${DRY_RUN_ARG}
}

# Validate Phase 6 deployment
validate_all() {
    print_header "Phase 06 Docker Service Helper Validation"
    echo ""

    load_config || { print_error "Configuration not loaded"; return 1; }

    source /opt/homeserver/scripts/operations/utils/validation-docker-helper-utils.sh

    local total=0 passed=0
    local checks=("${PHASE6_CHECKS[@]}")

    for check in "${checks[@]}"; do
        local name="${check%%:*}"
        local func="${check##*:}"
        total=$((total + 1))
        printf "%-40s " "$name"
        if $func > /tmp/validation_output 2>&1; then
            echo -e "\033[0;32m✓ PASS\033[0m"
            passed=$((passed + 1))
        else
            echo -e "\033[0;31m✗ FAIL\033[0m"
            cat /tmp/validation_output
        fi
    done

    echo ""
    echo "========================================"
    echo "Results: $passed/$total checks passed"
    echo "========================================"
    if [[ $passed -eq $total ]]; then print_success "All checks passed!"; return 0; else print_error "Some checks failed"; return 1; fi
}

# Validate prerequisites (Phase 1-5 complete)
validate_prerequisites() {
    print_header "Prerequisite Validation"
    load_config || { print_error "Configuration not loaded"; return 1; }

    local status=0
    command -v docker &>/dev/null && print_success "Docker installed" || { print_error "Docker not installed"; status=1; }
    docker inspect caddy >/dev/null 2>&1 && print_success "Caddy running" || { print_error "Caddy not running"; status=1; }
    docker inspect pihole >/dev/null 2>&1 && print_success "Pi-hole running" || { print_error "Pi-hole not running"; status=1; }
    docker network inspect homeserver >/dev/null 2>&1 && print_success "homeserver network exists" || { print_error "homeserver network missing"; status=1; }

    echo ""
    if [[ $status -eq 0 ]]; then print_success "All prerequisites met!"; return 0; else print_error "Prerequisites not met"; return 1; fi
}

# Interactive menu
main_menu() {
    while true; do
        echo ""
        echo "========================================"
        print_header "Phase 06 - Docker Service Helper"
        echo "========================================"
        echo ""
        echo "p. Validate prerequisites (Phase 1-5)"
        echo ""
        echo "1. Install yq YAML processor"
        echo "2. Create services.yml from example"
        echo "3. Deploy example service"
        echo ""
        echo "v. Validate all"
        echo "q. Quit"
        echo ""
        read -rp "Select option: " option
        echo ""

        case $option in
            p) validate_prerequisites ;;
            1) execute_install_yq ;;
            2) execute_create_services_yml ;;
            3) execute_deploy_example ;;
            v) validate_all ;;
            q) echo "Exiting..."; exit 0 ;;
            *) print_error "Invalid option" ;;
        esac

        echo ""
        read -rp "Press Enter to continue..."
    done
}

# Non-blocking drift check
if [[ -x /opt/homeserver/scripts/operations/monitoring/check-drift.sh ]]; then
    bash /opt/homeserver/scripts/operations/monitoring/check-drift.sh --warn-only || true
fi



main_menu
