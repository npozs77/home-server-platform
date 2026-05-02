#!/bin/bash
set -euo pipefail

# Phase 04 - Photo Management with Immich Deployment Script
# Purpose: Orchestrate Immich photo management deployment with modular task execution
# Prerequisites: Phase 1, 2, and 3 complete
# Usage: sudo ./deploy-phase4-photo-management.sh [--dry-run]

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility libraries (absolute paths)
source /opt/homeserver/scripts/operations/utils/output-utils.sh
source /opt/homeserver/scripts/operations/utils/env-utils.sh
source /opt/homeserver/scripts/operations/utils/validation-photo-management-utils.sh

# Configuration file paths
FOUNDATION_CONFIG="/opt/homeserver/configs/foundation.env"
SERVICES_CONFIG="/opt/homeserver/configs/services.env"
SECRETS_CONFIG="/opt/homeserver/configs/secrets.env"

# Dry-run mode
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true && echo "Running in DRY-RUN mode" && echo ""

# Check if running as root
[[ $EUID -ne 0 ]] && { print_error "This script must be run as root (use sudo)"; exit 1; }

# Load configuration from foundation.env, services.env, secrets.env
load_config() {
    [[ -f "$FOUNDATION_CONFIG" ]] && source "$FOUNDATION_CONFIG" || { print_error "Foundation config missing: $FOUNDATION_CONFIG"; return 1; }
    [[ -f "$SERVICES_CONFIG" ]] && source "$SERVICES_CONFIG" || { print_error "Services config missing: $SERVICES_CONFIG"; return 1; }
    # Source secrets safely (passwords may contain $ ! ` and other shell-special chars)
    # Use grep+eval with single-quote wrapping to prevent expansion
    if [[ -f "$SECRETS_CONFIG" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            # Strip surrounding quotes if present
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            export "$key=$value"
        done < <(grep -v '^\s*#' "$SECRETS_CONFIG" | grep -v '^\s*$' | grep '=')
    fi
    return 0
}

# Save Immich configuration to services.env
save_config() {
    mkdir -p "$(dirname "$SERVICES_CONFIG")"

    if ! grep -q "# Phase 4: Immich Photo Management" "$SERVICES_CONFIG" 2>/dev/null; then
        cat >> "$SERVICES_CONFIG" << EOF

# Phase 4: Immich Photo Management
# Generated: $(date)
IMMICH_VERSION="$IMMICH_VERSION"
IMMICH_DOMAIN="$IMMICH_DOMAIN"
IMMICH_PORT="$IMMICH_PORT"
MEDIA_GROUP_GID="$MEDIA_GROUP_GID"
UPLOAD_LOCATION="$UPLOAD_LOCATION"
DB_DATA_LOCATION="$DB_DATA_LOCATION"
DB_USERNAME="$DB_USERNAME"
DB_DATABASE_NAME="$DB_DATABASE_NAME"
EOF
    else
        sed -i "s/^IMMICH_VERSION=.*/IMMICH_VERSION=\"$IMMICH_VERSION\"/" "$SERVICES_CONFIG"
        sed -i "s/^IMMICH_DOMAIN=.*/IMMICH_DOMAIN=\"$IMMICH_DOMAIN\"/" "$SERVICES_CONFIG"
        sed -i "s/^IMMICH_PORT=.*/IMMICH_PORT=\"$IMMICH_PORT\"/" "$SERVICES_CONFIG"
        sed -i "s/^MEDIA_GROUP_GID=.*/MEDIA_GROUP_GID=\"$MEDIA_GROUP_GID\"/" "$SERVICES_CONFIG"
        sed -i "s|^UPLOAD_LOCATION=.*|UPLOAD_LOCATION=\"$UPLOAD_LOCATION\"|" "$SERVICES_CONFIG"
        sed -i "s|^DB_DATA_LOCATION=.*|DB_DATA_LOCATION=\"$DB_DATA_LOCATION\"|" "$SERVICES_CONFIG"
        sed -i "s/^DB_USERNAME=.*/DB_USERNAME=\"$DB_USERNAME\"/" "$SERVICES_CONFIG"
        sed -i "s/^DB_DATABASE_NAME=.*/DB_DATABASE_NAME=\"$DB_DATABASE_NAME\"/" "$SERVICES_CONFIG"
    fi

    chmod 644 "$SERVICES_CONFIG"
    print_success "Configuration saved to $SERVICES_CONFIG"
}

# Initialize/Update Immich configuration interactively
init_config() {
    print_header "Phase 4: Immich Configuration"

    load_config 2>/dev/null || true

    # Detect media group GID
    local detected_gid=""
    if getent group media &>/dev/null; then
        detected_gid=$(getent group media | cut -d: -f3)
    fi

    print_info "Immich Configuration"
    read -p "Immich version [${IMMICH_VERSION:-v2.5.6}]: " input
    IMMICH_VERSION="${input:-${IMMICH_VERSION:-v2.5.6}}"

    read -p "Immich domain [${IMMICH_DOMAIN:-photos.${INTERNAL_SUBDOMAIN:-home.mydomain.com}}]: " input
    IMMICH_DOMAIN="${input:-${IMMICH_DOMAIN:-photos.${INTERNAL_SUBDOMAIN:-home.mydomain.com}}}"

    read -p "Immich internal port [${IMMICH_PORT:-2283}]: " input
    IMMICH_PORT="${input:-${IMMICH_PORT:-2283}}"

    read -p "Media group GID [${MEDIA_GROUP_GID:-${detected_gid:-1002}}]: " input
    MEDIA_GROUP_GID="${input:-${MEDIA_GROUP_GID:-${detected_gid:-1002}}}"

    read -p "Upload location [${UPLOAD_LOCATION:-/mnt/data/services/immich/upload}]: " input
    UPLOAD_LOCATION="${input:-${UPLOAD_LOCATION:-/mnt/data/services/immich/upload}}"

    read -p "DB data location [${DB_DATA_LOCATION:-/mnt/data/services/immich/postgres}]: " input
    DB_DATA_LOCATION="${input:-${DB_DATA_LOCATION:-/mnt/data/services/immich/postgres}}"

    read -p "DB username [${DB_USERNAME:-postgres}]: " input
    DB_USERNAME="${input:-${DB_USERNAME:-postgres}}"

    read -p "DB database name [${DB_DATABASE_NAME:-immich}]: " input
    DB_DATABASE_NAME="${input:-${DB_DATABASE_NAME:-immich}}"

    echo ""
    save_config

    echo ""
    print_info "IMPORTANT: Set DB_PASSWORD in secrets.env before deploying"
    echo "Required before deployment:"
    echo "  - DB_PASSWORD (PostgreSQL password — generate a strong random password)"
    echo ""
    echo "Obtained after deployment (setup wizard):"
    echo "  - IMMICH_API_KEY (admin API key — add to secrets.env after initial setup)"
    echo ""
    echo "Edit: /opt/homeserver/configs/secrets.env"
    echo "Then run: sudo chmod 600 /opt/homeserver/configs/secrets.env"
}

# Validate Immich configuration
validate_config() {
    print_header "Configuration Validation"

    load_config || { print_error "Configuration not found. Run option 0 first."; return 1; }

    local status=0
    validate_required_vars "IMMICH_VERSION" "IMMICH_DOMAIN" "IMMICH_PORT" "MEDIA_GROUP_GID" "UPLOAD_LOCATION" "DB_DATA_LOCATION" "DB_USERNAME" "DB_DATABASE_NAME" || status=1

    # Validate version format (vN.N.N)
    [[ "$IMMICH_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && print_success "Immich version valid: $IMMICH_VERSION" || { print_error "Immich version invalid (expected vN.N.N): $IMMICH_VERSION"; status=1; }

    # Validate domain
    validate_domain "$IMMICH_DOMAIN" && print_success "Immich domain valid: $IMMICH_DOMAIN" || status=1

    # Validate port
    [[ "$IMMICH_PORT" =~ ^[0-9]+$ ]] && print_success "Immich port valid: $IMMICH_PORT" || { print_error "Immich port invalid: $IMMICH_PORT"; status=1; }

    # Validate GID
    [[ "$MEDIA_GROUP_GID" =~ ^[0-9]+$ ]] && print_success "Media group GID valid: $MEDIA_GROUP_GID" || { print_error "Media group GID invalid: $MEDIA_GROUP_GID"; status=1; }

    # Check secrets (consistent with Phase 3 pattern: check non-empty only)
    if [[ -n "${DB_PASSWORD:-}" ]]; then
        print_success "DB_PASSWORD set in secrets.env"
    else
        print_info "DB_PASSWORD not set (required before deploying stack)"
    fi

    echo ""
    [[ $status -eq 0 ]] && { print_success "All configuration checks passed!"; return 0; } || { print_error "Some checks failed"; return 1; }
}

# Task execution functions (delegate to task modules)
execute_task_4_1() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT MEDIA_GROUP_GID UPLOAD_LOCATION DB_DATA_LOCATION
    bash /opt/homeserver/scripts/deploy/tasks/task-ph4-01-create-immich-directories.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_4_2() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export DATA_MOUNT IMMICH_VERSION DB_PASSWORD TIMEZONE MEDIA_GROUP_GID UPLOAD_LOCATION DB_DATA_LOCATION DB_USERNAME DB_DATABASE_NAME
    bash /opt/homeserver/scripts/deploy/tasks/task-ph4-02-deploy-immich-stack.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_4_3() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export IMMICH_DOMAIN IMMICH_PORT INTERNAL_SUBDOMAIN DOMAIN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph4-03-configure-caddy.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_4_4() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export SERVER_IP IMMICH_DOMAIN
    bash /opt/homeserver/scripts/deploy/tasks/task-ph4-04-configure-dns.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_4_5() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    export ADMIN_USER ADMIN_EMAIL
    bash /opt/homeserver/scripts/deploy/tasks/task-ph4-05-provision-immich-users.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_4_6() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    bash /opt/homeserver/scripts/deploy/tasks/task-ph4-06-configure-samba-uploads.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

execute_task_4_7() {
    load_config || { print_error "Configuration not loaded"; return 1; }
    bash /opt/homeserver/scripts/deploy/tasks/task-ph4-07-deploy-backup-script.sh $([[ "$DRY_RUN" == true ]] && echo "--dry-run")
}

# Validate all Phase 4 checks
validate_all() {
    print_header "Phase 04 Photo Management Validation"
    echo ""

    load_config || { print_error "Configuration not loaded"; return 1; }

    local total=0 passed=0
    # PHASE4_CHECKS defined in validation-photo-management-utils.sh (single source of truth)
    local checks=("${PHASE4_CHECKS[@]}")

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

# Validate prerequisites (Phase 1-3 complete)
validate_prerequisites() {
    print_header "Prerequisite Validation"

    load_config || { print_error "Configuration not loaded"; return 1; }

    local status=0

    # Phase 1: Foundation
    [[ -d "${DATA_MOUNT:-/mnt/data}" ]] && print_success "Data mount exists" || { print_error "Data mount missing"; status=1; }

    # Phase 2: Infrastructure (check key containers)
    command -v docker &>/dev/null && print_success "Docker installed" || { print_error "Docker not installed"; status=1; }

    # Phase 3: Core Services
    [[ -d "${DATA_MOUNT:-/mnt/data}/media/Photos" ]] && print_success "Media Photos directory exists" || { print_error "Media Photos directory missing"; status=1; }
    [[ -d "${DATA_MOUNT:-/mnt/data}/family/Photos" ]] && print_success "Family Photos directory exists" || { print_error "Family Photos directory missing"; status=1; }
    getent group media &>/dev/null && print_success "media group exists" || { print_error "media group missing"; status=1; }

    echo ""
    [[ $status -eq 0 ]] && { print_success "All prerequisites met!"; return 0; } || { print_error "Prerequisites not met"; return 1; }
}

# Interactive menu
main_menu() {
    while true; do
        echo ""
        echo "========================================"
        print_header "Phase 04 - Photo Management with Immich"
        echo "========================================"
        echo ""
        echo "0. Initialize/Update configuration"
        echo "c. Validate configuration"
        echo "p. Validate prerequisites (Phase 1-3)"
        echo ""
        echo "4.1. Create Immich data directories"
        echo "4.2. Deploy Immich Docker Compose stack"
        echo "4.3. Configure Caddy reverse proxy"
        echo "4.4. Configure Pi-hole DNS"
        echo "4.5. Provision Immich users via API"
        echo "4.6. Configure Samba upload shares"
        echo "4.7. Deploy backup script"
        echo ""
        echo "v. Validate all"
        echo "q. Quit"
        echo ""
        read -p "Select option: " option
        echo ""

        case $option in
            0) init_config ;;
            c) validate_config ;;
            p) validate_prerequisites ;;
            4.1) execute_task_4_1 ;;
            4.2) execute_task_4_2 ;;
            4.3) execute_task_4_3 ;;
            4.4) execute_task_4_4 ;;
            4.5) execute_task_4_5 ;;
            4.6) execute_task_4_6 ;;
            4.7) execute_task_4_7 ;;
            v) validate_all ;;
            q) echo "Exiting..."; exit 0 ;;
            *) print_error "Invalid option" ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

# Non-blocking drift check (skip silently if script not yet deployed)
if [[ -x /opt/homeserver/scripts/operations/monitoring/check-drift.sh ]]; then
    bash /opt/homeserver/scripts/operations/monitoring/check-drift.sh --warn-only || true
fi

main_menu
