#!/bin/bash
set -euo pipefail
# Validation Utilities: Docker Service Helper Layer
# Purpose: Validation functions for Phase 6 Docker Service Helper deployment
# Usage: Source this file in deployment/validation scripts

HELPER="/opt/homeserver/scripts/docker-helper/docker-service-helper.sh"

# --- Infrastructure checks (after yq install + services.yml creation) ---

# Validate yq is installed and working
validate_yq_installed() {
    command -v yq &>/dev/null && yq --version &>/dev/null
}

# Validate homeserver Docker network exists
validate_homeserver_network() {
    docker network inspect homeserver >/dev/null 2>&1
}

# Validate services.yml exists and is valid YAML
validate_services_yml_valid() {
    local cfg="/opt/homeserver/configs/helper-services/services.yml"
    [[ -f "$cfg" ]] && yq '.' "$cfg" >/dev/null 2>&1
}

# Validate lint passes on services.yml
validate_lint_passes() {
    bash "$HELPER" lint >/dev/null 2>&1
}

# Validate list command works (integration: yq + services.yml + helper script)
validate_list_command() {
    bash "$HELPER" list >/dev/null 2>&1
}

# Validate add --dry-run works (full pipeline without side effects)
validate_add_dryrun() {
    local svc
    svc=$(yq -r '.services | keys | .[0]' /opt/homeserver/configs/helper-services/services.yml 2>/dev/null)
    [[ -n "$svc" ]] && [[ "$svc" != "null" ]] && bash "$HELPER" add "$svc" --dry-run >/dev/null 2>&1
}

# --- Service checks (after example service deployed) ---

# Validate at least one helper-managed container is running
validate_helper_container_running() {
    local svc
    svc=$(yq -r '.services | keys | .[0]' /opt/homeserver/configs/helper-services/services.yml 2>/dev/null)
    [[ -n "$svc" ]] && docker inspect -f '{{.State.Running}}' "$svc" 2>/dev/null | grep -q true
}

# Validate helper-managed service has data directory
validate_service_data_dir() {
    local svc
    svc=$(yq -r '.services | keys | .[0]' /opt/homeserver/configs/helper-services/services.yml 2>/dev/null)
    [[ -n "$svc" ]] && [[ -d "/mnt/data/services/${svc}" ]]
}

# Validate helper-managed service has generated compose file
validate_service_compose_exists() {
    local svc
    svc=$(yq -r '.services | keys | .[0]' /opt/homeserver/configs/helper-services/services.yml 2>/dev/null)
    [[ -n "$svc" ]] && [[ -f "/opt/homeserver/configs/helper-services/${svc}/docker-compose.yml" ]]
}

# Validate backup-helper-services.sh exists (dynamic backup, no per-service scripts)
validate_backup_script_exists() {
    [[ -f "/opt/homeserver/scripts/backup/backup-helper-services.sh" ]]
}

# Validate Caddy entry exists for deployed service
validate_caddy_entry() {
    local svc
    svc=$(yq -r '.services | keys | .[0]' /opt/homeserver/configs/helper-services/services.yml 2>/dev/null)
    [[ -n "$svc" ]] && grep -q "# BEGIN helper:${svc}" /opt/homeserver/configs/caddy/Caddyfile 2>/dev/null
}

# Validate DNS resolves for deployed service
validate_dns_resolves() {
    local svc subdomain fqdn
    svc=$(yq -r '.services | keys | .[0]' /opt/homeserver/configs/helper-services/services.yml 2>/dev/null)
    subdomain=$(yq -r ".services.${svc}.subdomain // \"${svc}\"" /opt/homeserver/configs/helper-services/services.yml 2>/dev/null)
    fqdn="${subdomain}.${INTERNAL_SUBDOMAIN}"
    dig +short "@127.0.0.1" "$fqdn" 2>/dev/null | grep -q "${SERVER_IP}"
}

# Validate HTTPS accessible for deployed service
validate_https_accessible() {
    local svc subdomain fqdn
    svc=$(yq -r '.services | keys | .[0]' /opt/homeserver/configs/helper-services/services.yml 2>/dev/null)
    subdomain=$(yq -r ".services.${svc}.subdomain // \"${svc}\"" /opt/homeserver/configs/helper-services/services.yml 2>/dev/null)
    fqdn="${subdomain}.${INTERNAL_SUBDOMAIN}"
    curl -sk -o /dev/null -w '%{http_code}' --resolve "${fqdn}:443:${SERVER_IP}" "https://${fqdn}" 2>/dev/null | grep -qE '^(200|301|302)'
}

# Phase 6 checks array (name:function pairs)
# Infrastructure checks run after tasks 1-2; service checks run after task 3
PHASE6_CHECKS=(
    "yq installed:validate_yq_installed"
    "homeserver network:validate_homeserver_network"
    "services.yml valid:validate_services_yml_valid"
    "Lint passes:validate_lint_passes"
    "List command works:validate_list_command"
    "Add dry-run works:validate_add_dryrun"
    "Container running:validate_helper_container_running"
    "Data directory exists:validate_service_data_dir"
    "Compose file generated:validate_service_compose_exists"
    "Caddy entry exists:validate_caddy_entry"
    "DNS resolves:validate_dns_resolves"
    "HTTPS accessible:validate_https_accessible"
    "Backup script exists:validate_backup_script_exists"
)
