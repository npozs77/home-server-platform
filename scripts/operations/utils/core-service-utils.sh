#!/bin/bash
set -euo pipefail

# Utility Library: Core Service Updates
# Purpose: Pull + recreate + health-validate compose-based CORE platform
#          services (wiki, immich, ollama/open-webui, jellyfin), with an
#          optional pre-update backup for stateful ones. NOT for helper-managed
#          services (use docker-service-helper.sh) or docker-run infra
#          (caddy/pihole/netdata — different mechanism, excluded by design).
# Functions: csu_compose_cmd, csu_pull, csu_recreate, csu_wait_healthy, csu_run_backup
# Usage: source this file (after log-utils.sh + service-utils.sh), then call.

[[ -n "${CORE_SERVICE_UTILS_LOADED:-}" ]] && return 0
readonly CORE_SERVICE_UTILS_LOADED=1

CSU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CSU_DIR}/log-utils.sh"
# shellcheck source=/dev/null
source "${CSU_DIR}/service-utils.sh"

# Server paths (compose files + env files live under the repo root on the server).
CSU_REPO_DIR="${CSU_REPO_DIR:-/opt/homeserver}"
CSU_COMPOSE_DIR="${CSU_REPO_DIR}/configs/docker-compose"
CSU_ENV_FOUNDATION="${CSU_REPO_DIR}/configs/foundation.env"
CSU_ENV_SERVICES="${CSU_REPO_DIR}/configs/services.env"
CSU_ENV_SECRETS="${CSU_REPO_DIR}/configs/secrets.env"

# Build the `docker compose` command for a compose file, wiring all env files
# that exist. Echoes the command prefix (caller appends the subcommand).
# Parameters: $1=compose file path
csu_compose_cmd() {
    local compose_file="$1"
    local cmd="docker compose"
    [[ -f "$CSU_ENV_FOUNDATION" ]] && cmd="${cmd} --env-file ${CSU_ENV_FOUNDATION}"
    [[ -f "$CSU_ENV_SERVICES" ]]   && cmd="${cmd} --env-file ${CSU_ENV_SERVICES}"
    [[ -f "$CSU_ENV_SECRETS" ]]    && cmd="${cmd} --env-file ${CSU_ENV_SECRETS}"
    cmd="${cmd} -f ${compose_file}"
    printf '%s' "$cmd"
}

# Resolve a compose file path for a service name; verify it exists.
# Parameters: $1=compose basename (e.g. "wiki"); echoes full path, returns 1 if missing.
csu_compose_file() {
    local name="$1"
    local f="${CSU_COMPOSE_DIR}/${name}.yml"
    if [[ ! -f "$f" ]]; then
        log_msg "ERROR" "core-service-update" "Compose file not found: ${f}"
        return 1
    fi
    printf '%s' "$f"
}

# Run a service's pre-update backup script if one is configured.
# Parameters: $1=service label, $2=backup script path ("" = none), $3=dry_run(true/false)
# Returns non-zero only if the backup script exists and fails.
csu_run_backup() {
    local label="$1" backup_script="$2" dry_run="$3"
    if [[ -z "$backup_script" ]]; then
        log_msg "INFO" "core-service-update" "${label}: no pre-update backup configured — skipping"
        return 0
    fi
    if [[ ! -x "$backup_script" && ! -f "$backup_script" ]]; then
        log_msg "WARN" "core-service-update" "${label}: backup script not found (${backup_script}) — skipping"
        return 0
    fi
    if [[ "$dry_run" == "true" ]]; then
        log_msg "INFO" "core-service-update" "${label}: dry-run — would run backup: ${backup_script}"
        return 0
    fi
    log_msg "INFO" "core-service-update" "${label}: running pre-update backup..."
    if bash "$backup_script"; then
        log_msg "INFO" "core-service-update" "${label}: backup complete"
        return 0
    fi
    log_msg "ERROR" "core-service-update" "${label}: pre-update backup FAILED — aborting update"
    return 1
}

# Pull the latest image(s) for a compose file.
# Parameters: $1=compose file, $2=dry_run
csu_pull() {
    local compose_file="$1" dry_run="$2"
    local cc; cc="$(csu_compose_cmd "$compose_file")"
    if [[ "$dry_run" == "true" ]]; then
        log_msg "INFO" "core-service-update" "dry-run: would run '${cc} pull'"
        return 0
    fi
    log_msg "INFO" "core-service-update" "Pulling images (${compose_file})..."
    eval "${cc} pull"
}

# Recreate service(s) from a compose file (only recreates containers whose
# image/config changed — compose leaves unchanged sidecars running).
# Parameters: $1=compose file, $2=dry_run
csu_recreate() {
    local compose_file="$1" dry_run="$2"
    local cc; cc="$(csu_compose_cmd "$compose_file")"
    if [[ "$dry_run" == "true" ]]; then
        log_msg "INFO" "core-service-update" "dry-run: would run '${cc} up -d'"
        return 0
    fi
    log_msg "INFO" "core-service-update" "Recreating (${compose_file})..."
    eval "${cc} up -d"
}

# Wait until a container reports healthy (or running if it has no healthcheck).
# Parameters: $1=container name, $2=timeout seconds (default 120)
# Returns 0 when healthy/running, 1 on timeout.
csu_wait_healthy() {
    local container="$1" timeout="${2:-120}" elapsed=0 interval=5 state
    while (( elapsed < timeout )); do
        state=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || echo "absent")
        if [[ "$state" == "healthy" || "$state" == "running" ]]; then
            log_msg "INFO" "core-service-update" "${container}: ${state}"
            return 0
        fi
        sleep "$interval"; elapsed=$(( elapsed + interval ))
        log_msg "INFO" "core-service-update" "${container}: ${state} (waited ${elapsed}s/${timeout}s)"
    done
    log_msg "ERROR" "core-service-update" "${container}: not healthy within ${timeout}s"
    return 1
}
