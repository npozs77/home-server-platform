#!/bin/bash
set -euo pipefail

# Phase 01 - Foundation Layer Deployment Script (Refactored)
# Purpose: Orchestrate foundation layer deployment with modular task execution
# Prerequisites: Ubuntu Server LTS 24.04, network configured
# Usage: sudo ./deploy-phase1-foundation.sh [--dry-run]

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility libraries (use absolute paths to avoid nested sourcing issues)
source "/opt/homeserver/scripts/operations/utils/output-utils.sh"
source "/opt/homeserver/scripts/operations/utils/env-utils.sh"
source "/opt/homeserver/scripts/operations/utils/validation-foundation-utils.sh"

# Configuration file paths
FOUNDATION_CONFIG="/opt/homeserver/configs/foundation.env"
SECRETS_CONFIG="/opt/homeserver/configs/secrets.env"

# Dry-run mode
DRY_RUN=false
DRY_RUN_ARG=""
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=true; DRY_RUN_ARG="--dry-run"; echo "Running in DRY-RUN mode"; echo ""; fi

# Check if running as root
[[ $EUID -ne 0 ]] && { print_error "This script must be run as root (use sudo)"; exit 1; }

# Load configuration
load_config() {
    [[ -f "$FOUNDATION_CONFIG" ]] && source "$FOUNDATION_CONFIG" || return 1
    [[ -f "$SECRETS_CONFIG" ]] && source "$SECRETS_CONFIG" || return 1
    return 0
}

# Save configuration
save_config() {
    mkdir -p "$(dirname "$FOUNDATION_CONFIG")"
    mkdir -p "$(dirname "$SECRETS_CONFIG")"
    
    cat > "$FOUNDATION_CONFIG" << EOF
# Foundation Configuration (System-Level)
# Generated: $(date)

# System Configuration
TIMEZONE="$TIMEZONE"
HOSTNAME="$HOSTNAME"
SERVER_IP="$SERVER_IP"
NETWORK_INTERFACE="$NETWORK_INTERFACE"

# User Configuration
ADMIN_USER="$ADMIN_USER"
ADMIN_EMAIL="$ADMIN_EMAIL"

# Disk Configuration
DATA_DISK="$DATA_DISK"
DATA_MOUNT="$DATA_MOUNT"

# Backup DAS Configuration
BACKUP_DISK="$BACKUP_DISK"
BACKUP_MOUNT="$BACKUP_MOUNT"
BACKUP_MAPPER="$BACKUP_MAPPER"

# Git Configuration
GIT_USER_NAME="$GIT_USER_NAME"
GIT_USER_EMAIL="$GIT_USER_EMAIL"
EOF
    chmod 644 "$FOUNDATION_CONFIG"
    
    cat > "$SECRETS_CONFIG" << EOF
# Secrets Configuration (Root-Protected)
# Generated: $(date)
# Permissions: 600 (root-only)

# LUKS Encryption
LUKS_PASSPHRASE="$LUKS_PASSPHRASE"
EOF
    chmod 600 "$SECRETS_CONFIG"
    
    print_success "Configuration saved"
}

# Initialize/Update configuration
init_config() {
    print_header "Configuration Initialization"
    echo ""
    
    load_config 2>/dev/null || true
    
    read -rp "Timezone [${TIMEZONE:-Europe/Amsterdam}]: " input
    TIMEZONE="${input:-${TIMEZONE:-Europe/Amsterdam}}"
    
    read -rp "Hostname [${HOSTNAME:-homeserver}]: " input
    HOSTNAME="${input:-${HOSTNAME:-homeserver}}"
    
    read -rp "Server IP [${SERVER_IP:-192.168.1.2}]: " input
    SERVER_IP="${input:-${SERVER_IP:-192.168.1.2}}"
    
    read -rp "Admin user [${ADMIN_USER:-$SUDO_USER}]: " input
    ADMIN_USER="${input:-${ADMIN_USER:-$SUDO_USER}}"
    
    read -rp "Admin email [${ADMIN_EMAIL:-admin@mydomain.com}]: " input
    ADMIN_EMAIL="${input:-${ADMIN_EMAIL:-admin@mydomain.com}}"
    
    echo ""
    print_info "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    echo ""
    read -rp "Data disk [${DATA_DISK:-/dev/sdb}]: " input
    DATA_DISK="${input:-${DATA_DISK:-/dev/sdb}}"
    
    DATA_MOUNT="${DATA_MOUNT:-/mnt/data}"
    
    echo ""
    print_info "Backup DAS configuration (external USB/DAS drive for backups):"
    print_info "  Leave blank if no backup drive is connected yet."
    read -rp "Backup disk partition [${BACKUP_DISK:-/dev/sdb2}]: " input
    BACKUP_DISK="${input:-${BACKUP_DISK:-/dev/sdb2}}"
    BACKUP_MOUNT="${BACKUP_MOUNT:-/mnt/backup}"
    BACKUP_MAPPER="${BACKUP_MAPPER:-backup_crypt}"
    
    read -rsp "LUKS passphrase (20+ characters): " input
    echo ""
    LUKS_PASSPHRASE="${input:-${LUKS_PASSPHRASE:-}}"
    
    read -rp "Git user name [${GIT_USER_NAME:-Admin User}]: " input
    GIT_USER_NAME="${input:-${GIT_USER_NAME:-Admin User}}"
    
    read -rp "Git user email [${GIT_USER_EMAIL:-admin@home.mydomain.com}]: " input
    GIT_USER_EMAIL="${input:-${GIT_USER_EMAIL:-admin@home.mydomain.com}}"
    
    NETWORK_INTERFACE="${NETWORK_INTERFACE:-$(ip route | grep default | awk '{print $5}' | head -n1)}"
    read -rp "Network interface [${NETWORK_INTERFACE}]: " input
    NETWORK_INTERFACE="${input:-${NETWORK_INTERFACE}}"
    
    echo ""
    save_config
}

# Validate configuration
validate_config() {
    print_header "Configuration Validation"
    echo ""
    
    load_config || { print_error "Configuration not found. Run option 0 first."; return 1; }
    
    local status=0
    validate_required_vars "TIMEZONE" "HOSTNAME" "SERVER_IP" "ADMIN_USER" "ADMIN_EMAIL" "DATA_DISK" "LUKS_PASSPHRASE" "GIT_USER_NAME" "GIT_USER_EMAIL" "NETWORK_INTERFACE" || status=1
    
    if timedatectl list-timezones | grep -q "^${TIMEZONE}$"; then print_success "Timezone valid"; else print_error "Timezone invalid"; status=1; fi
    if [[ "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then print_success "Hostname valid"; else print_error "Hostname invalid"; status=1; fi
    if validate_ip_address "$SERVER_IP"; then print_success "Server IP valid"; else print_error "Server IP invalid"; status=1; fi
    if id "$ADMIN_USER" &>/dev/null; then print_success "Admin user exists"; else print_error "Admin user missing"; status=1; fi
    if validate_email "$ADMIN_EMAIL"; then print_success "Admin email valid"; else print_error "Admin email invalid"; status=1; fi
    if [[ -b "$DATA_DISK" ]]; then print_success "Data disk exists"; else print_error "Data disk missing"; status=1; fi
    if [[ ${#LUKS_PASSPHRASE} -ge 20 ]]; then print_success "LUKS passphrase strong"; else print_error "LUKS passphrase weak"; status=1; fi
    
    echo ""
    if [[ $status -eq 0 ]]; then print_success "All checks passed!"; return 0; else print_error "Some checks failed"; return 1; fi
}

# Task execution functions
execute_update_system() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export TIMEZONE HOSTNAME
    "${SCRIPT_DIR}/tasks/task-ph1-01-update-system.sh" ${DRY_RUN_ARG}
}

execute_setup_luks() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_DISK LUKS_PASSPHRASE DATA_MOUNT
    "${SCRIPT_DIR}/tasks/task-ph1-02-setup-luks.sh" ${DRY_RUN_ARG}
}

execute_harden_ssh() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    "${SCRIPT_DIR}/tasks/task-ph1-03-harden-ssh.sh" ${DRY_RUN_ARG}
}

execute_configure_firewall() {
    "${SCRIPT_DIR}/tasks/task-ph1-04-configure-firewall.sh" ${DRY_RUN_ARG}
}

execute_setup_fail2ban() {
    "${SCRIPT_DIR}/tasks/task-ph1-05-setup-fail2ban.sh" ${DRY_RUN_ARG}
}

execute_install_docker() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export ADMIN_USER
    "${SCRIPT_DIR}/tasks/task-ph1-06-install-docker.sh" ${DRY_RUN_ARG}
}

execute_init_git_repo() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export ADMIN_USER GIT_USER_NAME GIT_USER_EMAIL
    "${SCRIPT_DIR}/tasks/task-ph1-07-init-git-repo.sh" ${DRY_RUN_ARG}
}

execute_setup_auto_updates() {
    "${SCRIPT_DIR}/tasks/task-ph1-08-setup-auto-updates.sh" ${DRY_RUN_ARG}
}

execute_setup_shell_environment() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export ADMIN_USER
    "${SCRIPT_DIR}/tasks/task-ph1-09-setup-shell-environment.sh" ${DRY_RUN_ARG}
}

# Validation function
validate_all() {
    print_header "Phase 01 Foundation Validation"
    echo ""
    
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_DISK ADMIN_USER
    
    local total=0 passed=0
    # PHASE1_CHECKS defined in validation-foundation-utils.sh (single source of truth)
    checks=("${PHASE1_CHECKS[@]}")
    
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
        print_header "Phase 01 - Foundation Layer Deployment"
        echo "========================================"
        echo ""
        echo "0. Initialize/Update configuration"
        echo "c. Validate configuration"
        echo ""
        echo "1. Update system packages and set timezone/hostname"
        echo "2. Set up LUKS disk encryption"
        echo "3. Harden SSH access"
        echo "4. Configure firewall (UFW)"
        echo "5. Set up fail2ban"
        echo "6. Install Docker and Docker Compose"
        echo "7. Initialize infrastructure Git repository"
        echo "8. Set up automated security updates"
        echo "9. Set up global shell environment (Zsh + Oh-My-Zsh + Powerlevel10k)"
        echo ""
        echo "v. Validate all"
        echo "q. Quit"
        echo ""
        read -rp "Select option [0,c,1-9,v,q]: " option
        echo ""
        
        case $option in
            0) init_config ;;
            c) validate_config ;;
            1) execute_update_system ;;
            2) execute_setup_luks ;;
            3) execute_harden_ssh ;;
            4) execute_configure_firewall ;;
            5) execute_setup_fail2ban ;;
            6) execute_install_docker ;;
            7) execute_init_git_repo ;;
            8) execute_setup_auto_updates ;;
            9) execute_setup_shell_environment ;;
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
