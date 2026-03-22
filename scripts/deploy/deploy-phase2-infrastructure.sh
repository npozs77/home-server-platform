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
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true && echo "Running in DRY-RUN mode" && echo ""

# Check if running as root
[[ $EUID -ne 0 ]] && { print_error "This script must be run as root (use sudo)"; exit 1; }

# Load configuration
load_config() {
    [[ -f "$FOUNDATION_CONFIG" ]] && source "$FOUNDATION_CONFIG" || { print_error "Foundation config missing"; return 1; }
    [[ -f "$SERVICES_CONFIG" ]] && source "$SERVICES_CONFIG" || { print_error "Services config missing"; return 1; }
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
    
    read -p "Domain [${DOMAIN:-mydomain.com}]: " input
    DOMAIN="${input:-${DOMAIN:-mydomain.com}}"
    
    read -p "Internal subdomain [${INTERNAL_SUBDOMAIN:-home.mydomain.com}]: " input
    INTERNAL_SUBDOMAIN="${input:-${INTERNAL_SUBDOMAIN:-home.mydomain.com}}"
    
    echo ""
    print_info "SMTP Configuration (SMTP2GO)"
    read -p "SMTP host [${SMTP2GO_HOST:-mail-eu.smtp2go.com}]: " input
    SMTP2GO_HOST="${input:-${SMTP2GO_HOST:-mail-eu.smtp2go.com}}"
    
    read -p "SMTP port [${SMTP2GO_PORT:-2525}]: " input
    SMTP2GO_PORT="${input:-${SMTP2GO_PORT:-2525}}"
    
    read -p "SMTP from address [${SMTP2GO_FROM:-alerts@home.mydomain.com}]: " input
    SMTP2GO_FROM="${input:-${SMTP2GO_FROM:-alerts@home.mydomain.com}}"
    
    read -p "SMTP username [${SMTP2GO_USER:-username}]: " input
    SMTP2GO_USER="${input:-${SMTP2GO_USER:-username}}"
    
    echo ""
    print_info "Proton Pass Configuration"
    read -p "Proton Pass share ID [${HOMESERVER_PASS_SHARE_ID:-}]: " input
    HOMESERVER_PASS_SHARE_ID="${input:-${HOMESERVER_PASS_SHARE_ID:-}}"
    
    read -p "SMTP2GO password item ID [${SMTP2GO_PASS_ITEM_ID:-}]: " input
    SMTP2GO_PASS_ITEM_ID="${input:-${SMTP2GO_PASS_ITEM_ID:-}}"
    
    read -p "Pi-hole password item ID [${PIHOLE_PASS_ITEM_ID:-}]: " input
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
    
    validate_domain "$DOMAIN" && print_success "Domain valid" || { print_error "Domain invalid"; status=1; }
    validate_domain "$INTERNAL_SUBDOMAIN" && print_success "Internal subdomain valid" || { print_error "Internal subdomain invalid"; status=1; }
    validate_email "$SMTP2GO_FROM" && print_success "SMTP from address valid" || { print_error "SMTP from address invalid"; status=1; }
    [[ "$SMTP2GO_PORT" =~ ^[0-9]+$ ]] && print_success "SMTP port valid" || { print_error "SMTP port invalid"; status=1; }
    
    echo ""
    [[ $status -eq 0 ]] && { print_success "All checks passed!"; return 0; } || { print_error "Some checks failed"; return 1; }
}

# Task execution functions
execute_create_data_dirs() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph2-01-create-data-dirs.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_create_family_dirs() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph2-02-create-family-dirs.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_create_backup_dirs() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph2-03-create-backup-dirs.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_create_services_yaml() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DOMAIN INTERNAL_SUBDOMAIN SERVER_IP SMTP2GO_HOST SMTP2GO_PORT SMTP2GO_USER SMTP2GO_FROM
    /opt/homeserver/scripts/deploy/tasks/task-ph2-04-create-services-yaml.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_deploy_caddy() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DOMAIN INTERNAL_SUBDOMAIN DATA_MOUNT ADMIN_EMAIL SERVER_IP
    /opt/homeserver/scripts/deploy/tasks/task-ph2-05-deploy-caddy.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_export_ca_cert() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph2-06-export-ca-cert.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_deploy_pihole() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT ADMIN_USER HOMESERVER_PASS_SHARE_ID PIHOLE_PASS_ITEM_ID
    /opt/homeserver/scripts/deploy/tasks/task-ph2-07-deploy-pihole.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_configure_dns() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export INTERNAL_SUBDOMAIN SERVER_IP ADMIN_USER HOMESERVER_PASS_SHARE_ID PIHOLE_PASS_ITEM_ID
    /opt/homeserver/scripts/deploy/tasks/task-ph2-08-configure-dns.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_install_msmtp() {
    /opt/homeserver/scripts/deploy/tasks/task-ph2-09-install-msmtp.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_configure_msmtp() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export SMTP2GO_HOST SMTP2GO_PORT SMTP2GO_FROM SMTP2GO_USER ADMIN_USER HOMESERVER_PASS_SHARE_ID SMTP2GO_PASS_ITEM_ID
    /opt/homeserver/scripts/deploy/tasks/task-ph2-10-configure-msmtp.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_test_email() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export ADMIN_EMAIL ADMIN_USER
    /opt/homeserver/scripts/deploy/tasks/task-ph2-11-test-email.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_deploy_netdata() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph2-12-deploy-netdata.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_configure_log_rotation() {
    /opt/homeserver/scripts/deploy/tasks/task-ph2-13-configure-log-rotation.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

# Validation function
validate_all() {
    print_header "Phase 02 Infrastructure Validation"
    echo ""
    
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT INTERNAL_SUBDOMAIN SERVER_IP
    
    local total=0 passed=0
    checks=(
        "Data Structure:validate_data_structure"
        "Family Directories:validate_family_subdirectories"
        "Backup Directories:validate_backup_subdirectories"
        "Compose Files:validate_services_yaml"
        "Caddy Service:validate_caddy_service"
        "Caddy HTTPS:validate_caddy_https"
        "CA Certificate:validate_certificate_trust"
        "Pi-hole Service:validate_dns_service"
        "DNS Resolution:validate_dns_resolution"
        "External DNS:validate_external_dns"
        "msmtp Service:validate_smtp_service"
        "msmtp Test:validate_smtp_test"
        "Netdata Service:validate_netdata_service"
        "Netdata Dashboard:validate_netdata_dashboard"
        "Logrotate Caddy:validate_logrotate_caddy"
        "Logrotate Pi-hole:validate_logrotate_pihole"
        "Logrotate msmtp:validate_logrotate_msmtp"
    )
    
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
    [[ $passed -eq $total ]] && { print_success "All checks passed!"; return 0; } || { print_error "Some checks failed"; return 1; }
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
        read -p "Select option [0,c,1-13,v,q]: " option
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
        read -p "Press Enter to continue..."
    done
}

# Entry point
main_menu
