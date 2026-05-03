#!/bin/bash
set -euo pipefail

# Phase 02 - Infrastructure Services Layer Deployment Script (Refactored)
# Purpose: Orchestrate infrastructure services deployment with modular task execution
# Prerequisites: Phase 1 complete, domain registered, SMTP credentials
# Usage: sudo ./deploy-phase2-infrastructure.sh [--dry-run]

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility libraries (use absolute paths to avoid nested sourcing issues)
source "/opt/homeserver/scripts/operations/utils/output-utils.sh"
source "/opt/homeserver/scripts/operations/utils/env-utils.sh"
source "/opt/homeserver/scripts/operations/utils/validation-infrastructure-utils.sh"

# Configuration file paths
FOUNDATION_CONFIG="/opt/homeserver/configs/foundation.env"
SERVICES_CONFIG="/opt/homeserver/configs/services.env"
SECRETS_CONFIG="/opt/homeserver/configs/secrets.env"

# Dry-run mode
DRY_RUN=false
DRY_RUN_ARG=""
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=true; DRY_RUN_ARG="--dry-run"; echo "Running in DRY-RUN mode"; echo ""; fi

# Check if running as root
[[ $EUID -ne 0 ]] && { print_error "This script must be run as root (use sudo)"; exit 1; }

# Load configuration
load_config() {
    if [[ -f "$FOUNDATION_CONFIG" ]]; then source "$FOUNDATION_CONFIG"; else print_error "Foundation config missing"; return 1; fi
    if [[ -f "$SERVICES_CONFIG" ]]; then source "$SERVICES_CONFIG"; else print_error "Services config missing"; return 1; fi
    [[ -f "$SECRETS_CONFIG" ]] && source "$SECRETS_CONFIG" || true
    return 0
}

# Save configuration
save_config() {
    mkdir -p "$(dirname "$SERVICES_CONFIG")"
    
    cat > "$SERVICES_CONFIG" << EOF
# Services Configuration (Service-Specific)
# Generated: $(date)

# Domain Configuration
DOMAIN="$DOMAIN"
INTERNAL_SUBDOMAIN="$INTERNAL_SUBDOMAIN"

# SMTP Configuration (SMTP2GO)
SMTP2GO_HOST="$SMTP2GO_HOST"
SMTP2GO_PORT="$SMTP2GO_PORT"
SMTP2GO_FROM="$SMTP2GO_FROM"
SMTP2GO_USER="$SMTP2GO_USER"

# Proton Pass Configuration
HOMESERVER_PASS_SHARE_ID="$HOMESERVER_PASS_SHARE_ID"
SMTP2GO_PASS_ITEM_ID="$SMTP2GO_PASS_ITEM_ID"
PIHOLE_PASS_ITEM_ID="$PIHOLE_PASS_ITEM_ID"
EOF
    chmod 644 "$SERVICES_CONFIG"
    
    print_success "Configuration saved"
}

# Initialize/Update configuration
init_config() {
    print_header "Configuration Initialization"
    echo ""
    
    load_config 2>/dev/null || true
    
    read -rp "Domain [${DOMAIN:-mydomain.com}]: " input
    DOMAIN="${input:-${DOMAIN:-mydomain.com}}"
    
    read -rp "Internal subdomain [${INTERNAL_SUBDOMAIN:-home.mydomain.com}]: " input
    INTERNAL_SUBDOMAIN="${input:-${INTERNAL_SUBDOMAIN:-home.mydomain.com}}"
    
    echo ""
    print_info "SMTP Configuration (SMTP2GO)"
    read -rp "SMTP host [${SMTP2GO_HOST:-mail-eu.smtp2go.com}]: " input
    SMTP2GO_HOST="${input:-${SMTP2GO_HOST:-mail-eu.smtp2go.com}}"
    
    read -rp "SMTP port [${SMTP2GO_PORT:-2525}]: " input
    SMTP2GO_PORT="${input:-${SMTP2GO_PORT:-2525}}"
    
    read -rp "SMTP from address [${SMTP2GO_FROM:-alerts@home.mydomain.com}]: " input
    SMTP2GO_FROM="${input:-${SMTP2GO_FROM:-alerts@home.mydomain.com}}"
    
    read -rp "SMTP username [${SMTP2GO_USER:-username}]: " input
    SMTP2GO_USER="${input:-${SMTP2GO_USER:-username}}"
    
    echo ""
    print_info "Proton Pass Configuration"
    read -rp "Proton Pass share ID [${HOMESERVER_PASS_SHARE_ID:-}]: " input
    HOMESERVER_PASS_SHARE_ID="${input:-${HOMESERVER_PASS_SHARE_ID:-}}"
    
    read -rp "SMTP2GO password item ID [${SMTP2GO_PASS_ITEM_ID:-}]: " input
    SMTP2GO_PASS_ITEM_ID="${input:-${SMTP2GO_PASS_ITEM_ID:-}}"
    
    read -rp "Pi-hole password item ID [${PIHOLE_PASS_ITEM_ID:-}]: " input
    PIHOLE_PASS_ITEM_ID="${input:-${PIHOLE_PASS_ITEM_ID:-}}"
    
    echo ""
    save_config
}

# Validate configuration
validate_config() {
    print_header "Configuration Validation"
    echo ""
    
    load_config || { print_error "Configuration not found. Run option 0 first."; return 1; }
    
    local status=0
    validate_required_vars "DOMAIN" "INTERNAL_SUBDOMAIN" "SMTP2GO_HOST" "SMTP2GO_PORT" "SMTP2GO_FROM" "SMTP2GO_USER" "HOMESERVER_PASS_SHARE_ID" "SMTP2GO_PASS_ITEM_ID" "PIHOLE_PASS_ITEM_ID" || status=1
    
    if validate_domain "$DOMAIN"; then print_success "Domain valid"; else print_error "Domain invalid"; status=1; fi
    if validate_domain "$INTERNAL_SUBDOMAIN"; then print_success "Internal subdomain valid"; else print_error "Internal subdomain invalid"; status=1; fi
    if validate_email "$SMTP2GO_FROM"; then print_success "SMTP from address valid"; else print_error "SMTP from address invalid"; status=1; fi
    if [[ "$SMTP2GO_PORT" =~ ^[0-9]+$ ]]; then print_success "SMTP port valid"; else print_error "SMTP port invalid"; status=1; fi
    
    echo ""
    if [[ $status -eq 0 ]]; then print_success "All checks passed!"; return 0; else print_error "Some checks failed"; return 1; fi
}

# Task execution functions
execute_create_data_dirs() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph2-01-create-data-dirs.sh ${DRY_RUN_ARG}
}

execute_create_family_dirs() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph2-02-create-family-dirs.sh ${DRY_RUN_ARG}
}

execute_create_backup_dirs() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph2-03-create-backup-dirs.sh ${DRY_RUN_ARG}
}

execute_create_services_yaml() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DOMAIN INTERNAL_SUBDOMAIN SERVER_IP SMTP2GO_HOST SMTP2GO_PORT SMTP2GO_USER SMTP2GO_FROM
    /opt/homeserver/scripts/deploy/tasks/task-ph2-04-create-services-yaml.sh ${DRY_RUN_ARG}
}

execute_deploy_caddy() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DOMAIN INTERNAL_SUBDOMAIN DATA_MOUNT ADMIN_EMAIL SERVER_IP
    /opt/homeserver/scripts/deploy/tasks/task-ph2-05-deploy-caddy.sh ${DRY_RUN_ARG}
}

execute_export_ca_cert() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph2-06-export-ca-cert.sh ${DRY_RUN_ARG}
}

execute_deploy_pihole() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT ADMIN_USER HOMESERVER_PASS_SHARE_ID PIHOLE_PASS_ITEM_ID
    /opt/homeserver/scripts/deploy/tasks/task-ph2-07-deploy-pihole.sh ${DRY_RUN_ARG}
}

execute_configure_dns() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export INTERNAL_SUBDOMAIN SERVER_IP ADMIN_USER HOMESERVER_PASS_SHARE_ID PIHOLE_PASS_ITEM_ID
    /opt/homeserver/scripts/deploy/tasks/task-ph2-08-configure-dns.sh ${DRY_RUN_ARG}
}

execute_install_msmtp() {
    /opt/homeserver/scripts/deploy/tasks/task-ph2-09-install-msmtp.sh ${DRY_RUN_ARG}
}

execute_configure_msmtp() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export SMTP2GO_HOST SMTP2GO_PORT SMTP2GO_FROM SMTP2GO_USER ADMIN_USER HOMESERVER_PASS_SHARE_ID SMTP2GO_PASS_ITEM_ID
    /opt/homeserver/scripts/deploy/tasks/task-ph2-10-configure-msmtp.sh ${DRY_RUN_ARG}
}

execute_test_email() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export ADMIN_EMAIL ADMIN_USER
    /opt/homeserver/scripts/deploy/tasks/task-ph2-11-test-email.sh ${DRY_RUN_ARG}
}

execute_deploy_netdata() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph2-12-deploy-netdata.sh ${DRY_RUN_ARG}
}

execute_configure_log_rotation() {
    /opt/homeserver/scripts/deploy/tasks/task-ph2-13-configure-log-rotation.sh ${DRY_RUN_ARG}
}

# Validation function
validate_all() {
    print_header "Phase 02 Infrastructure Validation"
    echo ""
    
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT INTERNAL_SUBDOMAIN SERVER_IP
    
    local total=0 passed=0
    # PHASE2_CHECKS defined in validation-infrastructure-utils.sh (single source of truth)
    checks=("${PHASE2_CHECKS[@]}")
    
    for check in "${checks[@]}"; do
        name="${check%%:*}"
        func="${check##*:}"
        total=$((total + 1))
        printf "%-30s " "$name"
        if $func > /tmp/validation_output 2>&1; then
            echo -e "\033[0;32m✓ PASS\033[0m"
            passed=$((passed + 1))
        else
            echo -e "\033[0;31m✗ FAIL\033[0m"
            cat /tmp/validation_output
        fi
        echo ""
    done
    
    echo "========================================"
    echo "Results: $passed/$total checks passed"
    echo "========================================"
    if [[ $passed -eq $total ]]; then print_success "All checks passed!"; return 0; else print_error "Some checks failed"; return 1; fi
}

# Interactive menu
main_menu() {
    while true; do
        echo ""
        echo "========================================"
        print_header "Phase 02 - Infrastructure Services Layer"
        echo "========================================"
        echo ""
        echo "0. Initialize/Update configuration"
        echo "c. Validate configuration"
        echo ""
        echo "1. Create data directories"
        echo "2. Create family directories"
        echo "3. Create backup directories"
        echo "4. Create services.yaml"
        echo "5. Deploy Caddy"
        echo "6. Export CA certificate"
        echo "7. Deploy Pi-hole"
        echo "8. Configure DNS"
        echo "9. Install msmtp"
        echo "10. Configure msmtp"
        echo "11. Test email"
        echo "12. Deploy Netdata"
        echo "13. Configure log rotation"
        echo ""
        echo "v. Validate all"
        echo "q. Quit"
        echo ""
        read -rp "Select option [0,c,1-13,v,q]: " option
        echo ""
        
        case $option in
            0) init_config ;;
            c) validate_config ;;
            1) execute_create_data_dirs ;;
            2) execute_create_family_dirs ;;
            3) execute_create_backup_dirs ;;
            4) execute_create_services_yaml ;;
            5) execute_deploy_caddy ;;
            6) execute_export_ca_cert ;;
            7) execute_deploy_pihole ;;
            8) execute_configure_dns ;;
            9) execute_install_msmtp ;;
            10) execute_configure_msmtp ;;
            11) execute_test_email ;;
            12) execute_deploy_netdata ;;
            13) execute_configure_log_rotation ;;
            v) validate_all ;;
            q) echo "Exiting..."; exit 0 ;;
            *) print_error "Invalid option" ;;
        esac
        
        echo ""
        read -rp "Press Enter to continue..."
    done
}

# Non-blocking drift check (skip silently if script not yet deployed)
if [[ -x /opt/homeserver/scripts/operations/monitoring/check-drift.sh ]]; then
    bash /opt/homeserver/scripts/operations/monitoring/check-drift.sh --warn-only || true
fi

# Entry point
main_menu
