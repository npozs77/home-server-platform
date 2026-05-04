#!/bin/bash
# shellcheck disable=SC2155
set -euo pipefail

# Docker Service Helper — Main Dispatcher
# Parses subcommands and flags, sources libraries, dispatches to cmd_* handlers.
# Location: scripts/docker-helper/docker-service-helper.sh
# Requirements: 13.1–13.7

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"
readonly UTILS_DIR="${SCRIPT_DIR}/../operations/utils"

# ---------------------------------------------------------------------------
# Source shared cross-phase utilities
# ---------------------------------------------------------------------------

if [[ -f "${UTILS_DIR}/output-utils.sh" ]]; then
    source "${UTILS_DIR}/output-utils.sh"
else
    echo "Error: output-utils.sh not found at ${UTILS_DIR}/output-utils.sh" >&2
    exit 1
fi

if [[ -f "${UTILS_DIR}/env-utils.sh" ]]; then
    source "${UTILS_DIR}/env-utils.sh"
else
    print_error "env-utils.sh not found at ${UTILS_DIR}/env-utils.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Load server configuration from env files
# ---------------------------------------------------------------------------

readonly _FOUNDATION_ENV="/opt/homeserver/configs/foundation.env"
readonly _SERVICES_ENV="/opt/homeserver/configs/services.env"

if [[ -f "$_FOUNDATION_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$_FOUNDATION_ENV"
else
    print_error "foundation.env not found at ${_FOUNDATION_ENV}"
    exit 1
fi

if [[ -f "$_SERVICES_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$_SERVICES_ENV"
fi

# ---------------------------------------------------------------------------
# Constants — paths used by libraries
# ---------------------------------------------------------------------------

readonly SERVICES_CONFIG="/opt/homeserver/configs/helper-services/services.yml"
readonly COMPOSE_DIR="/opt/homeserver/configs/helper-services"
readonly CADDYFILE="/opt/homeserver/configs/caddy/Caddyfile"
readonly DATA_BASE="/mnt/data/services"
readonly LOG_FILE="/var/log/docker-service-helper.log"
readonly BACKUP_ALL="/opt/homeserver/scripts/backup/backup-all.sh"
readonly BACKUP_DIR="/opt/homeserver/scripts/backup"

# Ensure key env vars are available for libraries
export SERVER_IP="${SERVER_IP:-}"
export TIMEZONE="${TIMEZONE:-UTC}"
export INTERNAL_SUBDOMAIN="${INTERNAL_SUBDOMAIN:-}"

# ---------------------------------------------------------------------------
# Source helper-specific libraries
# ---------------------------------------------------------------------------

if [[ -f "${LIB_DIR}/compose-gen.sh" ]]; then
    source "${LIB_DIR}/compose-gen.sh"
else
    print_error "compose-gen.sh not found at ${LIB_DIR}/compose-gen.sh"
    exit 1
fi

if [[ -f "${LIB_DIR}/service-ops.sh" ]]; then
    source "${LIB_DIR}/service-ops.sh"
else
    print_error "service-ops.sh not found at ${LIB_DIR}/service-ops.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

preflight() {
    if ! command -v yq &>/dev/null; then
        print_error "yq is required but not installed."
        print_info "Install: sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq"
        exit 1
    fi
    if [[ ! -f "$SERVICES_CONFIG" ]]; then
        print_error "Services config not found: ${SERVICES_CONFIG}"
        print_info "Copy the example: cp configs/helper-services/services.yml.example configs/helper-services/services.yml"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

main() {
    local subcommand="${1:-}"

    # lint doesn't need services.yml to exist (it checks itself)
    case "$subcommand" in
        lint)
            cmd_lint "$@"
            return
            ;;
    esac

    # All other subcommands need preflight
    preflight

    case "$subcommand" in
        add)      cmd_add "$@" ;;
        remove)   cmd_remove "$@" ;;
        update)   cmd_update "$@" ;;
        list)     cmd_list "$@" ;;
        validate) cmd_validate "$@" ;;
        logs)     cmd_logs "$@" ;;
        stop)     cmd_stop "$@" ;;
        start)    cmd_start "$@" ;;
        backup)   cmd_backup "$@" ;;
        *)        show_usage ;;
    esac
}

main "$@"
