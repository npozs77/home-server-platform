#!/bin/bash
set -euo pipefail

# Phase 05 - Wiki + Local LLM Platform Deployment Script
# Purpose: Orchestrate Wiki.js, Ollama + Open WebUI deployment with modular task execution
# Prerequisites: Phase 1, 2, 3, and 4 complete
# Usage: sudo ./deploy-phase5-wiki-llm.sh [--dry-run]

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility libraries (absolute paths)
source /opt/homeserver/scripts/operations/utils/output-utils.sh
source /opt/homeserver/scripts/operations/utils/env-utils.sh
source /opt/homeserver/scripts/operations/utils/validation-wiki-llm-utils.sh

# Configuration file paths
FOUNDATION_CONFIG="/opt/homeserver/configs/foundation.env"
SERVICES_CONFIG="/opt/homeserver/configs/services.env"
SECRETS_CONFIG="/opt/homeserver/configs/secrets.env"

# Dry-run mode
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true && echo "Running in DRY-RUN mode" && echo ""

# Check if running as root
[[ $EUID -ne 0 ]] && { print_error "This script must be run as root (use sudo)"; exit 1; }

# Run governance validation before executing tasks
if [[ -x /opt/homeserver/scripts/operations/validate-governance.sh ]]; then
    /opt/homeserver/scripts/operations/validate-governance.sh || { print_error "Governance validation failed"; exit 1; }
fi

# Load configuration from foundation.env, services.env, secrets.env
load_config() {
    [[ -f "$FOUNDATION_CONFIG" ]] && source "$FOUNDATION_CONFIG" || { print_error "Foundation config missing: $FOUNDATION_CONFIG"; return 1; }
    [[ -f "$SERVICES_CONFIG" ]] && source "$SERVICES_CONFIG" || { print_error "Services config missing: $SERVICES_CONFIG"; return 1; }
    if [[ -f "$SECRETS_CONFIG" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            value="${value#\"}"; value="${value%\"}"; value="${value#\'}"; value="${value%\'}"
            export "$key=$value"
        done < <(grep -v '^\s*#' "$SECRETS_CONFIG" | grep -v '^\s*$' | grep '=')
    fi
    return 0
}

# Save Phase 5 configuration to services.env
save_config() {
    mkdir -p "$(dirname "$SERVICES_CONFIG")"
    if ! grep -q "# Phase 5: Wiki.js Configuration" "$SERVICES_CONFIG" 2>/dev/null; then
        cat >> "$SERVICES_CONFIG" << EOF

# Phase 5: Wiki.js Configuration (Sub-phase A)
WIKI_DOMAIN="$WIKI_DOMAIN"
WIKI_PORT="$WIKI_PORT"
WIKI_DB_USER="$WIKI_DB_USER"
WIKI_DB_NAME="$WIKI_DB_NAME"
WIKI_MEM_LIMIT="$WIKI_MEM_LIMIT"
WIKI_CPU_LIMIT="$WIKI_CPU_LIMIT"
WIKI_DB_MEM_LIMIT="$WIKI_DB_MEM_LIMIT"
WIKI_DB_CPU_LIMIT="$WIKI_DB_CPU_LIMIT"

# Phase 5: Ollama Configuration (Sub-phase B)
OLLAMA_DEFAULT_MODEL="$OLLAMA_DEFAULT_MODEL"
OLLAMA_ADDITIONAL_MODELS="$OLLAMA_ADDITIONAL_MODELS"
OLLAMA_VERSION="$OLLAMA_VERSION"
OLLAMA_MEM_LIMIT="$OLLAMA_MEM_LIMIT"
OLLAMA_CPU_LIMIT="$OLLAMA_CPU_LIMIT"

# Phase 5: Open WebUI Configuration (Sub-phase B)
OPENWEBUI_VERSION="$OPENWEBUI_VERSION"
OPENWEBUI_DOMAIN="$OPENWEBUI_DOMAIN"
OPENWEBUI_PORT="$OPENWEBUI_PORT"
OPENWEBUI_MEM_LIMIT="$OPENWEBUI_MEM_LIMIT"
OPENWEBUI_CPU_LIMIT="$OPENWEBUI_CPU_LIMIT"
ENABLE_WEB_SEARCH="$ENABLE_WEB_SEARCH"
WEB_SEARCH_ENGINE="$WEB_SEARCH_ENGINE"
ENABLE_SIGNUP="$ENABLE_SIGNUP"
EOF
    fi
    chmod 644 "$SERVICES_CONFIG"
    print_success "Configuration saved to $SERVICES_CONFIG"
}

# Initialize/Update Phase 5 configuration interactively
init_config() {
    print_header "Phase 5: Wiki + LLM Configuration"
    load_config 2>/dev/null || true

    print_info "Wiki.js Configuration (Sub-phase A)"
    read -p "Wiki domain [${WIKI_DOMAIN:-wiki.${INTERNAL_SUBDOMAIN:-home.mydomain.com}}]: " input
    WIKI_DOMAIN="${input:-${WIKI_DOMAIN:-wiki.${INTERNAL_SUBDOMAIN:-home.mydomain.com}}}"
    read -p "Wiki port [${WIKI_PORT:-3000}]: " input; WIKI_PORT="${input:-${WIKI_PORT:-3000}}"
    read -p "Wiki DB user [${WIKI_DB_USER:-wikijs}]: " input; WIKI_DB_USER="${input:-${WIKI_DB_USER:-wikijs}}"
    read -p "Wiki DB name [${WIKI_DB_NAME:-wikijs}]: " input; WIKI_DB_NAME="${input:-${WIKI_DB_NAME:-wikijs}}"
    read -p "Wiki memory limit [${WIKI_MEM_LIMIT:-512M}]: " input; WIKI_MEM_LIMIT="${input:-${WIKI_MEM_LIMIT:-512M}}"
    read -p "Wiki CPU limit [${WIKI_CPU_LIMIT:-1.0}]: " input; WIKI_CPU_LIMIT="${input:-${WIKI_CPU_LIMIT:-1.0}}"
    read -p "Wiki DB memory limit [${WIKI_DB_MEM_LIMIT:-512M}]: " input; WIKI_DB_MEM_LIMIT="${input:-${WIKI_DB_MEM_LIMIT:-512M}}"
    read -p "Wiki DB CPU limit [${WIKI_DB_CPU_LIMIT:-1.0}]: " input; WIKI_DB_CPU_LIMIT="${input:-${WIKI_DB_CPU_LIMIT:-1.0}}"

    echo ""
    print_info "Ollama + Open WebUI Configuration (Sub-phase B)"
    read -p "Default LLM model [${OLLAMA_DEFAULT_MODEL:-llama3.2:3b}]: " input; OLLAMA_DEFAULT_MODEL="${input:-${OLLAMA_DEFAULT_MODEL:-llama3.2:3b}}"
    read -p "Additional models [${OLLAMA_ADDITIONAL_MODELS:-mistral:7b}]: " input; OLLAMA_ADDITIONAL_MODELS="${input:-${OLLAMA_ADDITIONAL_MODELS:-mistral:7b}}"
    read -p "Ollama version [${OLLAMA_VERSION:-latest}]: " input; OLLAMA_VERSION="${input:-${OLLAMA_VERSION:-latest}}"
    read -p "Ollama memory limit [${OLLAMA_MEM_LIMIT:-6G}]: " input; OLLAMA_MEM_LIMIT="${input:-${OLLAMA_MEM_LIMIT:-6G}}"
    read -p "Ollama CPU limit [${OLLAMA_CPU_LIMIT:-4.0}]: " input; OLLAMA_CPU_LIMIT="${input:-${OLLAMA_CPU_LIMIT:-4.0}}"
    read -p "Open WebUI version [${OPENWEBUI_VERSION:-latest}]: " input; OPENWEBUI_VERSION="${input:-${OPENWEBUI_VERSION:-latest}}"
    read -p "Open WebUI domain [${OPENWEBUI_DOMAIN:-chat.${INTERNAL_SUBDOMAIN:-home.mydomain.com}}]: " input
    OPENWEBUI_DOMAIN="${input:-${OPENWEBUI_DOMAIN:-chat.${INTERNAL_SUBDOMAIN:-home.mydomain.com}}}"
    read -p "Open WebUI port [${OPENWEBUI_PORT:-8080}]: " input; OPENWEBUI_PORT="${input:-${OPENWEBUI_PORT:-8080}}"
    read -p "Open WebUI memory limit [${OPENWEBUI_MEM_LIMIT:-1G}]: " input; OPENWEBUI_MEM_LIMIT="${input:-${OPENWEBUI_MEM_LIMIT:-1G}}"
    read -p "Open WebUI CPU limit [${OPENWEBUI_CPU_LIMIT:-2.0}]: " input; OPENWEBUI_CPU_LIMIT="${input:-${OPENWEBUI_CPU_LIMIT:-2.0}}"
    read -p "Enable web search [${ENABLE_WEB_SEARCH:-true}]: " input; ENABLE_WEB_SEARCH="${input:-${ENABLE_WEB_SEARCH:-true}}"
    read -p "Web search engine [${WEB_SEARCH_ENGINE:-duckduckgo}]: " input; WEB_SEARCH_ENGINE="${input:-${WEB_SEARCH_ENGINE:-duckduckgo}}"
    ENABLE_SIGNUP="${ENABLE_SIGNUP:-true}"

    echo ""
    save_config

    # Auto-generate Open WebUI user passwords in secrets.env if not already set
    print_info "Checking Open WebUI user passwords in secrets.env..."
    local all_users="${ADMIN_USER:-admin} ${POWER_USERS:-} ${STANDARD_USERS:-}"
    for user in $all_users; do
        local var_name="OPENWEBUI_PASSWORD_${user}"
        # Check if already set (uncommented) in secrets.env
        if grep -q "^${var_name}=" "$SECRETS_CONFIG" 2>/dev/null; then
            print_info "$var_name already set in secrets.env"
        else
            local new_pass
            new_pass=$(tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 16 || true)
            # Remove commented-out placeholder if present
            sed -i "/^# *${var_name}=/d" "$SECRETS_CONFIG" 2>/dev/null || true
            echo "${var_name}=\"${new_pass}\"" >> "$SECRETS_CONFIG"
            print_success "Generated $var_name in secrets.env"
        fi
    done
    chmod 600 "$SECRETS_CONFIG"

    echo ""
    print_info "IMPORTANT: Remaining secrets to set in secrets.env"
    echo "Required before Sub-phase A: WIKI_DB_PASSWORD"
    echo "Obtained after Wiki.js setup wizard: WIKI_API_TOKEN"
    echo "Obtained after Open WebUI login: OPENWEBUI_API_TOKEN"
}

# Validate Phase 5 configuration
validate_config() {
    print_header "Configuration Validation"
    load_config || { print_error "Configuration not found. Run option 0 first."; return 1; }
    local status=0
    validate_required_vars "WIKI_DOMAIN" "WIKI_PORT" "WIKI_DB_USER" "WIKI_DB_NAME" || status=1
    validate_required_vars "OLLAMA_DEFAULT_MODEL" "OPENWEBUI_DOMAIN" "OPENWEBUI_PORT" || status=1
    validate_domain "$WIKI_DOMAIN" && print_success "Wiki domain valid: $WIKI_DOMAIN" || status=1
    validate_domain "$OPENWEBUI_DOMAIN" && print_success "Chat domain valid: $OPENWEBUI_DOMAIN" || status=1
    [[ "$WIKI_PORT" =~ ^[0-9]+$ ]] && print_success "Wiki port valid: $WIKI_PORT" || { print_error "Wiki port invalid"; status=1; }
    [[ "$OPENWEBUI_PORT" =~ ^[0-9]+$ ]] && print_success "Chat port valid: $OPENWEBUI_PORT" || { print_error "Chat port invalid"; status=1; }
    if [[ -n "${WIKI_DB_PASSWORD:-}" ]]; then print_success "WIKI_DB_PASSWORD set"; else print_info "WIKI_DB_PASSWORD not set (required before deploying Wiki stack)"; fi
    # Check Open WebUI admin password
    local admin_pwd_var="OPENWEBUI_PASSWORD_${ADMIN_USER:-admin}"
    if [[ -n "${!admin_pwd_var:-}" ]]; then print_success "$admin_pwd_var set"; else print_info "$admin_pwd_var not set (required before provisioning Open WebUI users)"; fi
    echo ""
    [[ $status -eq 0 ]] && { print_success "All configuration checks passed!"; return 0; } || { print_error "Some checks failed"; return 1; }
}

# Task execution functions — Sub-phase A: Wiki.js
execute_task_5_1() {
    load_config || return 1; export DATA_MOUNT
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-01-create-wiki-directories.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}
execute_task_5_2() {
    load_config || return 1; export DATA_MOUNT WIKI_DB_USER WIKI_DB_NAME WIKI_DB_PASSWORD WIKI_MEM_LIMIT WIKI_CPU_LIMIT WIKI_DB_MEM_LIMIT WIKI_DB_CPU_LIMIT TIMEZONE
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-02-deploy-wiki-stack.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}
execute_task_5_3() {
    load_config || return 1; export WIKI_DOMAIN WIKI_PORT INTERNAL_SUBDOMAIN DOMAIN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-03-configure-wiki-caddy.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}
execute_task_5_4() {
    load_config || return 1; export SERVER_IP WIKI_DOMAIN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-04-configure-wiki-dns.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}
execute_task_5_5() {
    load_config || return 1; export ADMIN_USER ADMIN_EMAIL POWER_USERS STANDARD_USERS WIKI_DOMAIN WIKI_API_TOKEN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-05-provision-wiki-users.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

# Task execution functions — Sub-phase B: Ollama + Open WebUI
execute_task_5_6() {
    load_config || return 1; export DATA_MOUNT
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-06-create-ollama-directories.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}
execute_task_5_7() {
    load_config || return 1; export DATA_MOUNT OLLAMA_VERSION OPENWEBUI_VERSION OLLAMA_MEM_LIMIT OLLAMA_CPU_LIMIT OPENWEBUI_MEM_LIMIT OPENWEBUI_CPU_LIMIT ENABLE_WEB_SEARCH WEB_SEARCH_ENGINE ENABLE_SIGNUP TIMEZONE
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-07-deploy-llm-stack.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}
execute_task_5_8() {
    load_config || return 1; export OLLAMA_DEFAULT_MODEL OLLAMA_ADDITIONAL_MODELS
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-08-pull-default-model.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}
execute_task_5_9() {
    load_config || return 1; export OPENWEBUI_DOMAIN OPENWEBUI_PORT INTERNAL_SUBDOMAIN DOMAIN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-09-configure-chat-caddy.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}
execute_task_5_10() {
    load_config || return 1; export SERVER_IP OPENWEBUI_DOMAIN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-10-configure-chat-dns.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}
execute_task_5_11() {
    load_config || return 1; export ADMIN_USER ADMIN_EMAIL POWER_USERS STANDARD_USERS OPENWEBUI_DOMAIN OPENWEBUI_PORT
    # Export per-user passwords from secrets.env (OPENWEBUI_PASSWORD_<username>)
    for user in $ADMIN_USER $POWER_USERS $STANDARD_USERS; do
        local var="OPENWEBUI_PASSWORD_${user}"
        [[ -n "${!var:-}" ]] && export "$var"
    done
    # Export compose paths for signup disable step
    export FOUNDATION_CONFIG SERVICES_CONFIG SECRETS_CONFIG
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-11-provision-openwebui-users.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

# Task execution functions — Shared Components
execute_task_5_12() {
    load_config || return 1; export DATA_MOUNT WIKI_DB_USER WIKI_DB_NAME
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-12-deploy-backup-script.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}
execute_task_5_14() {
    load_config || return 1; export OPENWEBUI_DOMAIN OPENWEBUI_API_TOKEN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph5-14-deploy-wiki-rag-sync.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

# Validate all Phase 5 checks
validate_all() {
    print_header "Phase 05 Wiki + LLM Platform Validation"
    echo ""
    load_config || { print_error "Configuration not loaded"; return 1; }
    local total=0 passed=0
    local checks=("${PHASE5_CHECKS[@]}")
    for check in "${checks[@]}"; do
        local name="${check%%:*}"
        local func="${check##*:}"
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
        print_header "Phase 05 - Wiki + Local LLM Platform"
        echo "========================================"
        echo ""
        echo "0. Initialize/Update configuration"
        echo "c. Validate configuration"
        echo ""
        echo "--- Sub-phase A: Wiki.js ---"
        echo "5.1.  Create Wiki.js data directories"
        echo "5.2.  Deploy Wiki.js Docker Compose stack"
        echo "5.3.  Configure Wiki.js Caddy reverse proxy"
        echo "5.4.  Configure Wiki.js Pi-hole DNS"
        echo "5.5.  Provision Wiki.js users via GraphQL API"
        echo ""
        echo "--- Sub-phase B: Ollama + Open WebUI ---"
        echo "5.6.  Create LLM data directories"
        echo "5.7.  Deploy LLM Docker Compose stack"
        echo "5.8.  Pull default LLM model"
        echo "5.9.  Configure Open WebUI Caddy reverse proxy"
        echo "5.10. Configure Open WebUI Pi-hole DNS"
        echo "5.11. Provision Open WebUI users via REST API"
        echo ""
        echo "--- Shared Components ---"
        echo "5.12. Deploy backup script"
        echo "5.14. Deploy wiki-to-RAG sync script (*)"
        echo ""
        echo "v. Validate all"
        echo "q. Quit"
        echo ""
        read -p "Select option: " option
        echo ""

        case $option in
            0) init_config ;;
            c) validate_config ;;
            5.1) execute_task_5_1 ;;
            5.2) execute_task_5_2 ;;
            5.3) execute_task_5_3 ;;
            5.4) execute_task_5_4 ;;
            5.5) execute_task_5_5 ;;
            5.6) execute_task_5_6 ;;
            5.7) execute_task_5_7 ;;
            5.8) execute_task_5_8 ;;
            5.9) execute_task_5_9 ;;
            5.10) execute_task_5_10 ;;
            5.11) execute_task_5_11 ;;
            5.12) execute_task_5_12 ;;
            5.14) execute_task_5_14 ;;
            v) validate_all ;;
            q) echo "Exiting..."; exit 0 ;;
            *) print_error "Invalid option" ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

main_menu
