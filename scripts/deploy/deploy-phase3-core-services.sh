#!/bin/bash
set -euo pipefail

# Phase 03 - Core Services Layer Deployment Script
# Purpose: Orchestrate core services deployment with modular task execution
# Prerequisites: Phase 1 and 2 complete, SSH keys prepared, Samba passwords chosen
# Usage: sudo ./deploy-phase3-core-services.sh [--dry-run]

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility libraries (absolute paths)
source /opt/homeserver/scripts/operations/utils/output-utils.sh
source /opt/homeserver/scripts/operations/utils/env-utils.sh
source /opt/homeserver/scripts/operations/utils/validation-core-services-utils.sh

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
    
    if ! grep -q "# Phase 3 Configuration" "$SERVICES_CONFIG" 2>/dev/null; then
        cat >> "$SERVICES_CONFIG" << EOF

# Phase 3 Configuration (Core Services)
# Generated: $(date)

ADMIN_USER="$ADMIN_USER"
POWER_USERS="$POWER_USERS"
STANDARD_USERS="$STANDARD_USERS"
SAMBA_WORKGROUP="$SAMBA_WORKGROUP"
SAMBA_SERVER_STRING="$SAMBA_SERVER_STRING"
JELLYFIN_SERVER_NAME="$JELLYFIN_SERVER_NAME"
EOF
    else
        sed -i "s/^ADMIN_USER=.*/ADMIN_USER=\"$ADMIN_USER\"/" "$SERVICES_CONFIG"
        sed -i "s/^POWER_USERS=.*/POWER_USERS=\"$POWER_USERS\"/" "$SERVICES_CONFIG"
        sed -i "s/^STANDARD_USERS=.*/STANDARD_USERS=\"$STANDARD_USERS\"/" "$SERVICES_CONFIG"
        sed -i "s/^SAMBA_WORKGROUP=.*/SAMBA_WORKGROUP=\"$SAMBA_WORKGROUP\"/" "$SERVICES_CONFIG"
        sed -i "s/^SAMBA_SERVER_STRING=.*/SAMBA_SERVER_STRING=\"$SAMBA_SERVER_STRING\"/" "$SERVICES_CONFIG"
        sed -i "s/^JELLYFIN_SERVER_NAME=.*/JELLYFIN_SERVER_NAME=\"$JELLYFIN_SERVER_NAME\"/" "$SERVICES_CONFIG"
    fi
    
    chmod 644 "$SERVICES_CONFIG"
    print_success "Configuration saved"
}

# Initialize/Update configuration
init_config() {
    print_header "Configuration Initialization"
    echo ""
    
    load_config 2>/dev/null || true
    
    print_info "User Configuration"
    read -p "Admin username [${ADMIN_USER:-admin}]: " input
    ADMIN_USER="${input:-${ADMIN_USER:-admin}}"
    
    read -p "Power user usernames (space-separated) [${POWER_USERS:-dad son1}]: " input
    POWER_USERS="${input:-${POWER_USERS:-dad son1}}"
    
    read -p "Standard user usernames (space-separated) [${STANDARD_USERS:-mom son2}]: " input
    STANDARD_USERS="${input:-${STANDARD_USERS:-mom son2}}"
    
    echo ""
    print_info "Samba Configuration"
    read -p "Samba workgroup [${SAMBA_WORKGROUP:-WORKGROUP}]: " input
    SAMBA_WORKGROUP="${input:-${SAMBA_WORKGROUP:-WORKGROUP}}"
    
    read -p "Samba server description [${SAMBA_SERVER_STRING:-Home Media Server}]: " input
    SAMBA_SERVER_STRING="${input:-${SAMBA_SERVER_STRING:-Home Media Server}}"
    
    echo ""
    print_info "Jellyfin Configuration"
    read -p "Jellyfin server name [${JELLYFIN_SERVER_NAME:-Home Media Server}]: " input
    JELLYFIN_SERVER_NAME="${input:-${JELLYFIN_SERVER_NAME:-Home Media Server}}"
    
    echo ""
    save_config
    
    echo ""
    print_info "IMPORTANT: Set Samba passwords in secrets.env before provisioning users"
    echo "Required variables:"
    local all_users="$ADMIN_USER $POWER_USERS $STANDARD_USERS"
    for user in $all_users; do
        echo "  - SAMBA_PASSWORD_${user}"
    done
    echo ""
    echo "Edit: /opt/homeserver/configs/secrets.env"
    echo "Then run: sudo chmod 600 /opt/homeserver/configs/secrets.env"
}

# Validate configuration
validate_config() {
    print_header "Configuration Validation"
    echo ""
    
    load_config || { print_error "Configuration not found. Run option 0 first."; return 1; }
    
    local status=0
    validate_required_vars "ADMIN_USER" "POWER_USERS" "STANDARD_USERS" "SAMBA_WORKGROUP" "SAMBA_SERVER_STRING" "JELLYFIN_SERVER_NAME" || status=1
    
    # Validate usernames (lowercase, alphanumeric, underscore, space-separated)
    [[ "$ADMIN_USER" =~ ^[a-z0-9_]+$ ]] && print_success "Admin username valid" || { print_error "Admin username invalid"; status=1; }
    [[ "$POWER_USERS" =~ ^[a-z0-9_\ ]+$ ]] && print_success "Power user usernames valid" || { print_error "Power user usernames invalid"; status=1; }
    [[ "$STANDARD_USERS" =~ ^[a-z0-9_\ ]+$ ]] && print_success "Standard user usernames valid" || { print_error "Standard user usernames invalid"; status=1; }
    
    # Validate Samba configuration
    [[ -n "$SAMBA_WORKGROUP" ]] && print_success "Samba workgroup valid" || { print_error "Samba workgroup missing"; status=1; }
    [[ -n "$SAMBA_SERVER_STRING" ]] && print_success "Samba server description valid" || { print_error "Samba server description missing"; status=1; }
    
    # Validate Jellyfin configuration
    [[ -n "$JELLYFIN_SERVER_NAME" ]] && print_success "Jellyfin server name valid" || { print_error "Jellyfin server name missing"; status=1; }
    
    # Validate Samba passwords in secrets.env
    local all_users="$ADMIN_USER $POWER_USERS $STANDARD_USERS"
    for user in $all_users; do
        local password_var="SAMBA_PASSWORD_${user}"
        if [[ -n "${!password_var}" ]]; then
            print_success "Samba password for $user found"
        else
            print_error "Samba password for $user missing (set $password_var in secrets.env)"
            status=1
        fi
    done
    
    echo ""
    [[ $status -eq 0 ]] && { print_success "All checks passed!"; return 0; } || { print_error "Some checks failed"; return 1; }
}

# Task execution functions (delegate to task modules)
execute_task_2_1() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph3-01-create-media-dirs.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_2_2() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT
    /opt/homeserver/scripts/deploy/tasks/task-ph3-02-create-jellyfin-dirs.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_3_1() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export SAMBA_WORKGROUP SAMBA_SERVER_STRING
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-03-create-samba-config.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_3_2() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT SAMBA_WORKGROUP TIMEZONE
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-04-deploy-samba.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_3_3() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export SERVER_IP
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-05-verify-samba.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_4_1() {
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-06-create-user-scripts.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_5_1() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export ADMIN_USER
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-07-provision-admin.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_5_2() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export POWER_USERS
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-08-provision-power.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_5_3() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export STANDARD_USERS
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-09-provision-standard.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_6_1() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT TIMEZONE INTERNAL_SUBDOMAIN DOMAIN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-10-create-jellyfin-compose.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_6_2() {
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-11-deploy-jellyfin.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_6_3() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export INTERNAL_SUBDOMAIN DOMAIN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-12-configure-caddy-jellyfin.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_6_4() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export SERVER_IP INTERNAL_SUBDOMAIN DOMAIN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph3-13-configure-dns-jellyfin.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

# Validation function
validate_all() {
    print_header "Phase 03 Core Services Validation"
    echo ""
    
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT INTERNAL_SUBDOMAIN DOMAIN SERVER_IP ADMIN_USER POWER_USER STANDARD_USER
    
    local total=0 passed=0
    # PHASE3_CHECKS defined in validation-core-services-utils.sh (single source of truth)
    checks=("${PHASE3_CHECKS[@]}")
    
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
        print_header "Phase 03 - Core Services Layer"
        echo "========================================"
        echo ""
        echo "0. Initialize/Update configuration"
        echo "c. Validate configuration"
        echo ""
        echo "2.1. Create media library subdirectories"
        echo "2.2. Create services/jellyfin subdirectories"
        echo "3.1. Create Samba configuration files"
        echo "3.2. Deploy Samba container"
        echo "3.3. Verify Samba shares accessible"
        echo "4.1. Create user provisioning scripts"
        echo "5.1. Provision Admin_User"
        echo "5.2. Provision Power_User"
        echo "5.3. Provision Standard_User"
        echo "6.1. Create Jellyfin Docker Compose configuration"
        echo "6.2. Deploy Jellyfin container"
        echo "6.3. Configure Caddy reverse proxy for Jellyfin"
        echo "6.4. Configure DNS record for Jellyfin"
        echo ""
        echo "v. Validate all"
        echo "q. Quit"
        echo ""
        read -p "Select option: " option
        echo ""
        
        case $option in
            0) init_config ;;
            c) validate_config ;;
            2.1) execute_task_2_1 ;;
            2.2) execute_task_2_2 ;;
            3.1) execute_task_3_1 ;;
            3.2) execute_task_3_2 ;;
            3.3) execute_task_3_3 ;;
            4.1) execute_task_4_1 ;;
            5.1) execute_task_5_1 ;;
            5.2) execute_task_5_2 ;;
            5.3) execute_task_5_3 ;;
            6.1) execute_task_6_1 ;;
            6.2) execute_task_6_2 ;;
            6.3) execute_task_6_3 ;;
            6.4) execute_task_6_4 ;;
            v) validate_all ;;
            q) echo "Exiting..."; exit 0 ;;
            *) print_error "Invalid option" ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

main_menu
