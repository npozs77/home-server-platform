#!/bin/bash
set -euo pipefail
# Validation Utilities: Docker Service Helper Layer
# Purpose: Validation functions for Phase 6 Docker Service Helper deployment
# Usage: Source this file in deployment/validation scripts

# Validate helper script exists and is executable
validate_helper_script_exists() {
    [[ -x /opt/homeserver/scripts/docker-helper/docker-service-helper.sh ]]
}

# Validate services.yml exists
validate_services_yml_exists() {
    [[ -f /opt/homeserver/configs/helper-services/services.yml ]]
}

# Validate yq is installed
validate_yq_installed() {
    command -v yq &>/dev/null
}

# Validate helper list command works
validate_list_command() {
    bash /opt/homeserver/scripts/docker-helper/docker-service-helper.sh list >/dev/null 2>&1
}

# Validate lint passes on services.yml
validate_lint_passes() {
    bash /opt/homeserver/scripts/docker-helper/docker-service-helper.sh lint >/dev/null 2>&1
}

# Validate compose-gen.sh library exists
validate_compose_gen_exists() {
    [[ -f /opt/homeserver/scripts/docker-helper/lib/compose-gen.sh ]]
}

# Validate service-ops.sh library exists
validate_service_ops_exists() {
    [[ -f /opt/homeserver/scripts/docker-helper/lib/service-ops.sh ]]
}

# Validate caddy-block.template exists
validate_caddy_template_exists() {
    [[ -f /opt/homeserver/scripts/docker-helper/templates/caddy-block.template ]]
}

# Validate helper-services config directory exists
validate_config_dir_exists() {
    [[ -d /opt/homeserver/configs/helper-services ]]
}

# Validate homeserver Docker network exists
validate_homeserver_network() {
    docker network inspect homeserver >/dev/null 2>&1
}

# Phase 6 checks array (name:function pairs)
PHASE6_CHECKS=(
    "Helper script exists:validate_helper_script_exists"
    "services.yml exists:validate_services_yml_exists"
    "yq installed:validate_yq_installed"
    "compose-gen.sh exists:validate_compose_gen_exists"
    "service-ops.sh exists:validate_service_ops_exists"
    "Caddy template exists:validate_caddy_template_exists"
    "Config directory exists:validate_config_dir_exists"
    "homeserver network:validate_homeserver_network"
    "List command works:validate_list_command"
    "Lint passes:validate_lint_passes"
)
