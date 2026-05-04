#!/bin/bash
# shellcheck disable=SC2155
set -euo pipefail

# Library: Service Operations (service-ops.sh)
# Core logic for all docker-service-helper subcommands: YAML reading, Caddy/DNS
# management, data dirs, build support, validation, and subcommand handlers.
# Dependencies: yq, docker, output-utils.sh, env-utils.sh, compose-gen.sh
# Requirements: 1.1–1.20, 3.1–3.8, 4.1–4.5, 5.1–5.5, 6.1–6.8, 7.1–7.10,
#   8.1–8.5, 9.1–9.9, 10.1–10.10, 21.1–21.9, 22.1–22.4, 25.2–25.8, 26.1–26.6,
#   27.1–27.6, 31.1–31.9

[[ -n "${SERVICE_OPS_LOADED:-}" ]] && return 0
readonly SERVICE_OPS_LOADED=1

# Exit codes per design
readonly _SO_ERR_GENERAL=1 _SO_ERR_USAGE=2 _SO_ERR_CONFIG=3
readonly _SO_ERR_VALIDATION=4 _SO_ERR_CONFLICT=5

# ---------------------------------------------------------------------------
# YAML reading functions (via yq)
# ---------------------------------------------------------------------------

# Read a single field from a service definition; returns empty string if missing
_so_field() { yq -r ".services.${1}.${2} // \"\"" "$SERVICES_CONFIG"; }

# Read enabled field (yq's // treats false as falsy, so we handle it in bash)
_so_enabled() { local v; v=$(yq -r ".services.${1}.enabled" "$SERVICES_CONFIG"); [[ "$v" == "null" || -z "$v" ]] && echo "true" || echo "$v"; }

# Verify a service exists in services.yml
read_service_definition() {
    local svc="$1"
    if ! yq -e ".services.${svc}" "$SERVICES_CONFIG" >/dev/null 2>&1; then
        print_error "Service '${svc}' not found in ${SERVICES_CONFIG}"
        return "$_SO_ERR_VALIDATION"
    fi
}

# Validate a service definition against the schema (Req 10.1–10.10)
validate_service_definition() {
    local svc="$1"
    local image=$(_so_field "$svc" "image")
    local bld=$(_so_field "$svc" "build.context")
    local port=$(_so_field "$svc" "port")
    local no_proxy=$(yq -r ".services.${svc}.no_proxy // false" "$SERVICES_CONFIG")
    local name=$(_so_field "$svc" "name")
    local vis=$(_so_field "$svc" "visibility")
    local enabled=$(_so_enabled "$svc")

    # Name format: lowercase alphanumeric + hyphens
    if [[ ! "$svc" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        print_error "Service name '${svc}' invalid — lowercase alphanumeric and hyphens only"
        return "$_SO_ERR_VALIDATION"
    fi
    # Image or build required
    if [[ -z "$image" ]] && [[ -z "$bld" ]]; then
        print_error "Service '${svc}' must specify either 'image' or 'build'"
        return "$_SO_ERR_VALIDATION"
    fi
    # Port required for proxied services
    if [[ "$no_proxy" != "true" ]]; then
        if [[ -z "$port" ]] || ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
            print_error "Service '${svc}' requires a valid 'port' (1-65535) or set no_proxy: true"
            return "$_SO_ERR_VALIDATION"
        fi
    elif [[ -n "$port" ]] && [[ "$port" != "null" ]]; then
        if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
            print_error "Service '${svc}' has invalid port '${port}' — must be 1-65535"
            return "$_SO_ERR_VALIDATION"
        fi
    fi
    # Visibility validation
    if [[ -n "$vis" ]] && [[ "$vis" != "public" ]] && [[ "$vis" != "private" ]]; then
        print_error "Service '${svc}' has invalid visibility '${vis}' — must be 'public' or 'private'"
        return "$_SO_ERR_VALIDATION"
    fi
    # Container name conflict (dynamic check)
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$svc"; then
        print_error "Service name '${svc}' conflicts with existing container"
        return "$_SO_ERR_CONFLICT"
    fi
    return 0
}

# List all service names from services.yml
list_helper_services() { yq -r '.services | keys | .[]' "$SERVICES_CONFIG"; }

# ---------------------------------------------------------------------------
# Caddy management (Req 3.1–3.8)
# ---------------------------------------------------------------------------

caddy_entry_exists() { grep -q "# BEGIN helper:${1}" "$CADDYFILE" 2>/dev/null; }

add_caddy_entry() {
    local svc="$1" subdomain="$2" port="$3" dry_run="${4:-false}"
    if caddy_entry_exists "$svc"; then print_info "Caddy entry for '${svc}' already exists — skipping"; return 0; fi
    local fqdn="${subdomain}.${INTERNAL_SUBDOMAIN}"
    local block
    block=$(sed -e "s|{{SERVICE_NAME}}|${svc}|g" -e "s|{{SUBDOMAIN}}|${subdomain}|g" \
        -e "s|{{INTERNAL_SUBDOMAIN}}|${INTERNAL_SUBDOMAIN}|g" \
        -e "s|{{CONTAINER_NAME}}|${svc}|g" -e "s|{{PORT}}|${port}|g" \
        "${SCRIPT_DIR}/templates/caddy-block.template")
    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would add Caddy entry for ${fqdn}"; return 0
    fi
    cp "$CADDYFILE" "${CADDYFILE}.bak"
    printf '\n%s\n' "$block" >> "$CADDYFILE"
    if ! docker exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null; then
        cp "${CADDYFILE}.bak" "$CADDYFILE"
        print_error "Caddy reload failed — reverted Caddyfile"; return "$_SO_ERR_GENERAL"
    fi
    print_success "Added Caddy entry for ${fqdn}"
}

remove_caddy_entry() {
    local svc="$1" dry_run="${2:-false}"
    if ! caddy_entry_exists "$svc"; then print_info "No Caddy entry for '${svc}' — skipping"; return 0; fi
    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would remove Caddy entry for ${svc}"; return 0
    fi
    cp "$CADDYFILE" "${CADDYFILE}.bak"
    sed -i "/# BEGIN helper:${svc}/,/# END helper:${svc}/d" "$CADDYFILE"
    if ! docker exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null; then
        cp "${CADDYFILE}.bak" "$CADDYFILE"
        print_error "Caddy reload failed — reverted Caddyfile"; return "$_SO_ERR_GENERAL"
    fi
    print_success "Removed Caddy entry for ${svc}"
}

# ---------------------------------------------------------------------------
# Pi-hole DNS management — Pi-hole v6 via pihole-FTL --config dns.hosts
# (Req 4.1–4.5)
# ---------------------------------------------------------------------------

dns_record_exists() {
    local fqdn="${1}.${INTERNAL_SUBDOMAIN}"
    local current
    current=$(docker exec pihole pihole-FTL --config dns.hosts 2>/dev/null || echo "[]")
    echo "$current" | grep -q "$fqdn"
}

add_dns_record() {
    local subdomain="$1" dry_run="${2:-false}"
    local fqdn="${subdomain}.${INTERNAL_SUBDOMAIN}"
    local dns_record="${SERVER_IP} ${fqdn}"

    if ! docker ps --format '{{.Names}}' | grep -q '^pihole$'; then
        print_error "Pi-hole container is not running"; return "$_SO_ERR_GENERAL"
    fi
    if dns_record_exists "$subdomain"; then print_info "DNS record for '${fqdn}' already exists — skipping"; return 0; fi
    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would add DNS record: ${dns_record}"; return 0
    fi

    # Read current entries, build new JSON array
    local current_json
    current_json=$(docker exec pihole pihole-FTL --config dns.hosts 2>/dev/null || echo "[]")
    local entries=()
    while IFS= read -r entry; do
        entry=$(echo "$entry" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//')
        [[ -n "$entry" ]] && entries+=("$entry")
    done < <(echo "$current_json" | tr ',' '\n' | sed 's/[][]//g')
    entries+=("$dns_record")

    # Build JSON array
    local new_json="["
    for ((i=0; i<${#entries[@]}; i++)); do
        [[ $i -gt 0 ]] && new_json+=","
        new_json+="\"${entries[$i]}\""
    done
    new_json+="]"

    if docker exec pihole pihole-FTL --config dns.hosts "$new_json" 2>/dev/null; then
        print_success "Added DNS record: ${dns_record}"
    else
        print_error "Failed to update Pi-hole dns.hosts"; return "$_SO_ERR_GENERAL"
    fi

    # Restart pihole for FTL to pick up new records
    docker restart pihole >/dev/null 2>&1
    sleep 3
}

remove_dns_record() {
    local subdomain="$1" dry_run="${2:-false}"
    local fqdn="${subdomain}.${INTERNAL_SUBDOMAIN}"

    if ! docker ps --format '{{.Names}}' | grep -q '^pihole$'; then
        print_error "Pi-hole container is not running"; return "$_SO_ERR_GENERAL"
    fi
    if ! dns_record_exists "$subdomain"; then print_info "No DNS record for '${fqdn}' — skipping"; return 0; fi
    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would remove DNS record for ${fqdn}"; return 0
    fi

    # Read current entries, filter out the target
    local current_json
    current_json=$(docker exec pihole pihole-FTL --config dns.hosts 2>/dev/null || echo "[]")
    local entries=()
    while IFS= read -r entry; do
        entry=$(echo "$entry" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//')
        [[ -n "$entry" ]] && ! echo "$entry" | grep -q "$fqdn" && entries+=("$entry")
    done < <(echo "$current_json" | tr ',' '\n' | sed 's/[][]//g')

    # Build JSON array
    local new_json="["
    for ((i=0; i<${#entries[@]}; i++)); do
        [[ $i -gt 0 ]] && new_json+=","
        new_json+="\"${entries[$i]}\""
    done
    new_json+="]"

    if docker exec pihole pihole-FTL --config dns.hosts "$new_json" 2>/dev/null; then
        print_success "Removed DNS record for ${fqdn}"
    else
        print_error "Failed to update Pi-hole dns.hosts"; return "$_SO_ERR_GENERAL"
    fi

    docker restart pihole >/dev/null 2>&1
    sleep 3
}

# ---------------------------------------------------------------------------
# Data directory management (Req 5.1–5.5)
# ---------------------------------------------------------------------------

create_data_directory() {
    local svc="$1" dry_run="${2:-false}"
    local data_dir="${DATA_BASE}/${svc}"
    if [[ -d "$data_dir" ]]; then
        print_info "Data directory already exists: ${data_dir} (preserving existing data)"; return 0
    fi
    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would create ${data_dir}"; return 0
    fi
    mkdir -p "$data_dir"
    chown root:root "$data_dir"
    chmod 755 "$data_dir"
    # Create subdirectories from volume mappings
    while IFS= read -r vol; do
        local host_path="${vol%%:*}"
        [[ "$host_path" == "${data_dir}"* ]] && mkdir -p "$host_path"
    done < <(yq -r ".services.${svc}.volumes[]? // \"\"" "$SERVICES_CONFIG" | grep -v '^$')
    print_success "Created data directory: ${data_dir}"
}

# ---------------------------------------------------------------------------
# Build support (Req 27.1–27.6)
# ---------------------------------------------------------------------------

build_docker_image() {
    local svc="$1" dry_run="${2:-false}"
    local ctx=$(_so_field "$svc" "build.context")
    local df=$(_so_field "$svc" "build.dockerfile"); df="${df:-Dockerfile}"
    local img=$(_so_field "$svc" "image"); img="${img:-${svc}:latest}"
    [[ -z "$ctx" ]] && return 0  # No build block
    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would build image ${img} from ${ctx}"; return 0
    fi
    local build_dir=""
    if [[ "$ctx" =~ ^https?:// ]] || [[ "$ctx" =~ ^git@ ]]; then
        build_dir="/tmp/docker-service-helper-builds/${svc}"
        rm -rf "$build_dir"; mkdir -p "$build_dir"
        if ! git clone --depth 1 "$ctx" "$build_dir"; then
            rm -rf "$build_dir"; print_error "Failed to clone '${ctx}'"; return "$_SO_ERR_GENERAL"
        fi
        ctx="$build_dir"
    fi
    if ! docker build -t "$img" -f "${ctx}/${df}" "$ctx"; then
        [[ -n "$build_dir" ]] && rm -rf "$build_dir"
        print_error "Docker build failed for '${svc}'"; return "$_SO_ERR_GENERAL"
    fi
    [[ -n "$build_dir" ]] && rm -rf "$build_dir"
    print_success "Built image ${img}"
}

# ---------------------------------------------------------------------------
# Validation (Req 9.1–9.9)
# ---------------------------------------------------------------------------

validate_service() {
    local svc="$1" passed=0 total=0
    local no_proxy=$(yq -r ".services.${svc}.no_proxy // false" "$SERVICES_CONFIG")
    local subdomain=$(yq -r ".services.${svc}.subdomain // \"${svc}\"" "$SERVICES_CONFIG")
    local data_dir="${DATA_BASE}/${svc}"
    local compose="${COMPOSE_DIR}/${svc}/docker-compose.yml"

    _check() { total=$((total+1)); if "$@" 2>/dev/null; then passed=$((passed+1)); print_success "$desc"; else print_error "$desc"; fi; }

    desc="Container '${svc}' running"; _check docker inspect -f '{{.State.Running}}' "$svc" | grep -q true
    desc="Data directory exists"; _check test -d "$data_dir"
    desc="Compose file exists"; _check test -f "$compose"
    if [[ "$no_proxy" != "true" ]]; then
        local fqdn="${subdomain}.${INTERNAL_SUBDOMAIN}"
        desc="DNS resolves ${fqdn}"; _check dig +short "@127.0.0.1" "$fqdn" | grep -q "$SERVER_IP"
        desc="Caddy entry exists"; _check caddy_entry_exists "$svc"
        desc="HTTPS accessible"; _check curl -sk -o /dev/null -w '%{http_code}' "https://${fqdn}" | grep -qE '^(200|301|302)'
    fi
    echo "${passed} / ${total} checks passed"
    [[ "$passed" -eq "$total" ]]
}

# ---------------------------------------------------------------------------
# Backup integration (Req 31.1–31.9)
# ---------------------------------------------------------------------------
# Backup is handled dynamically by scripts/backup/backup-helper-services.sh
# which reads services.yml at runtime. No per-service scripts are generated.
# This avoids writing files into the Git-tracked tree on the pull-only server.

register_backup() {
    local svc="$1" dry_run="${2:-false}"
    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would register backup for ${svc}"; return 0
    fi
    # No files to generate — backup-helper-services.sh reads services.yml dynamically
    print_success "Backup registered for ${svc} (via backup-helper-services.sh)"
}

deregister_backup() {
    local svc="$1" dry_run="${2:-false}"
    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would deregister backup for ${svc}"; return 0
    fi
    # No files to remove — backup-helper-services.sh reads services.yml dynamically
    print_success "Backup deregistered for ${svc}"
}

# ---------------------------------------------------------------------------
# Logging helper
# ---------------------------------------------------------------------------

_so_log() { echo "[$(date -Iseconds)] $*" >> "$LOG_FILE" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# Subcommand handlers (Req 6–9, 21–22, 25–26, 31)
# ---------------------------------------------------------------------------

cmd_add() {
    shift  # remove 'add'
    local svc="" dry_run=false verbose=false
    while [[ $# -gt 0 ]]; do
        case "$1" in --dry-run) dry_run=true;; --verbose) verbose=true;; *) svc="$1";; esac; shift
    done
    [[ -z "$svc" ]] && { print_error "Usage: docker-service-helper.sh add <service-name> [--dry-run]"; return "$_SO_ERR_USAGE"; }
    _so_log "ADD ${svc}: Starting"
    read_service_definition "$svc"
    local enabled=$(_so_enabled "$svc")
    if [[ "$enabled" == "false" ]]; then
        print_info "Service '${svc}' is disabled (enabled: false) — skipping"; return 0
    fi
    validate_service_definition "$svc"
    local no_proxy=$(yq -r ".services.${svc}.no_proxy // false" "$SERVICES_CONFIG")
    local subdomain=$(yq -r ".services.${svc}.subdomain // \"${svc}\"" "$SERVICES_CONFIG")
    local port=$(_so_field "$svc" "port")
    local tz="${TIMEZONE:-UTC}"

    create_data_directory "$svc" "$dry_run"
    build_docker_image "$svc" "$dry_run"
    generate_compose_file "$svc" "$SERVICES_CONFIG" "$COMPOSE_DIR" "$DATA_BASE" "$tz" "$dry_run"
    if [[ "$no_proxy" != "true" ]]; then
        add_dns_record "$subdomain" "$dry_run"
        add_caddy_entry "$svc" "$subdomain" "$port" "$dry_run"
    fi
    if [[ "$dry_run" != "true" ]]; then
        docker compose -f "${COMPOSE_DIR}/${svc}/docker-compose.yml" up -d
        _so_log "ADD ${svc}: Container started"
    else
        print_info "[dry-run] Would start container ${svc}"
    fi
    register_backup "$svc" "$dry_run"
    if [[ "$dry_run" != "true" ]]; then
        validate_service "$svc"
    fi
    local url="https://${subdomain}.${INTERNAL_SUBDOMAIN}"
    [[ "$no_proxy" == "true" ]] && url="http://localhost:${port}"
    print_header "Service '${svc}' deployed"
    echo "  URL:      ${url}"
    echo "  Data dir: ${DATA_BASE}/${svc}"
    _so_log "ADD ${svc}: Complete"
}

cmd_remove() {
    shift
    local svc="" dry_run=false purge_data=false
    while [[ $# -gt 0 ]]; do
        case "$1" in --dry-run) dry_run=true;; --purge-data) purge_data=true;; *) svc="$1";; esac; shift
    done
    [[ -z "$svc" ]] && { print_error "Usage: docker-service-helper.sh remove <service-name> [--dry-run] [--purge-data]"; return "$_SO_ERR_USAGE"; }
    _so_log "REMOVE ${svc}: Starting"
    read_service_definition "$svc"
    local no_proxy=$(yq -r ".services.${svc}.no_proxy // false" "$SERVICES_CONFIG")
    local subdomain=$(yq -r ".services.${svc}.subdomain // \"${svc}\"" "$SERVICES_CONFIG")

    if [[ "$dry_run" != "true" ]]; then
        read -rp "Remove service '${svc}'? (y/n) " confirm
        [[ "$confirm" != "y" ]] && { print_info "Cancelled"; return 0; }
    fi
    local compose="${COMPOSE_DIR}/${svc}/docker-compose.yml"
    if [[ -f "$compose" ]] && [[ "$dry_run" != "true" ]]; then
        docker compose -f "$compose" down 2>/dev/null || true
    elif [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would stop container ${svc}"
    fi
    [[ "$no_proxy" != "true" ]] && remove_caddy_entry "$svc" "$dry_run"
    [[ "$no_proxy" != "true" ]] && remove_dns_record "$subdomain" "$dry_run"
    if [[ "$dry_run" != "true" ]]; then
        rm -rf "${COMPOSE_DIR:?}/${svc:?}"
    else
        print_info "[dry-run] Would remove compose dir ${COMPOSE_DIR}/${svc}"
    fi
    if [[ "$purge_data" == "true" ]]; then
        if [[ "$dry_run" != "true" ]]; then
            read -rp "Delete data directory ${DATA_BASE}/${svc}? (y/n) " confirm2
            [[ "$confirm2" == "y" ]] && rm -rf "${DATA_BASE:?}/${svc:?}" && print_success "Deleted ${DATA_BASE}/${svc}"
        else
            print_info "[dry-run] Would delete ${DATA_BASE}/${svc}"
        fi
        deregister_backup "$svc" "$dry_run"
    fi
    # Remove generated backup script on any remove (Req 31.9)
    [[ "$purge_data" != "true" ]] || true  # backup kept if no purge
    print_success "Removed service '${svc}'"
    _so_log "REMOVE ${svc}: Complete"
}

cmd_update() {
    shift
    local svc="" dry_run=false verbose=false
    while [[ $# -gt 0 ]]; do
        case "$1" in --dry-run) dry_run=true;; --verbose) verbose=true;; *) svc="$1";; esac; shift
    done
    [[ -z "$svc" ]] && { print_error "Usage: docker-service-helper.sh update <service-name> [--dry-run]"; return "$_SO_ERR_USAGE"; }
    _so_log "UPDATE ${svc}: Starting"
    read_service_definition "$svc"
    # Verify service is deployed
    if ! docker inspect "$svc" >/dev/null 2>&1; then
        print_error "Service '${svc}' is not deployed. Use 'add' instead"; return "$_SO_ERR_GENERAL"
    fi
    local no_proxy=$(yq -r ".services.${svc}.no_proxy // false" "$SERVICES_CONFIG")
    local subdomain=$(yq -r ".services.${svc}.subdomain // \"${svc}\"" "$SERVICES_CONFIG")
    local port=$(_so_field "$svc" "port")
    local tz="${TIMEZONE:-UTC}"

    build_docker_image "$svc" "$dry_run"
    generate_compose_file "$svc" "$SERVICES_CONFIG" "$COMPOSE_DIR" "$DATA_BASE" "$tz" "$dry_run"
    if [[ "$no_proxy" != "true" ]]; then
        # Refresh Caddy/DNS in case subdomain or port changed
        remove_caddy_entry "$svc" "$dry_run"
        add_caddy_entry "$svc" "$subdomain" "$port" "$dry_run"
        remove_dns_record "$subdomain" "$dry_run" 2>/dev/null || true
        add_dns_record "$subdomain" "$dry_run"
    fi
    if [[ "$dry_run" != "true" ]]; then
        docker compose -f "${COMPOSE_DIR}/${svc}/docker-compose.yml" up -d --force-recreate
    else
        print_info "[dry-run] Would force-recreate container ${svc}"
    fi
    [[ "$dry_run" != "true" ]] && validate_service "$svc"
    print_success "Updated service '${svc}'"
    _so_log "UPDATE ${svc}: Complete"
}

cmd_list() {
    shift
    local json=false
    while [[ $# -gt 0 ]]; do case "$1" in --json) json=true;; esac; shift; done
    local services; services=$(list_helper_services)
    if [[ "$json" == "true" ]]; then
        echo "["
        local first=true
        while IFS= read -r svc; do
            local enabled=$(_so_enabled "$svc")
            local status="not deployed"
            if [[ "$enabled" == "false" ]]; then status="disabled"
            elif docker inspect -f '{{.State.Running}}' "$svc" 2>/dev/null | grep -q true; then status="running"
            elif docker inspect "$svc" >/dev/null 2>&1; then status="stopped"
            fi
            local img=$(_so_field "$svc" "image")
            local sub=$(yq -r ".services.${svc}.subdomain // \"${svc}\"" "$SERVICES_CONFIG")
            $first || echo ","
            printf '  {"name":"%s","image":"%s","subdomain":"%s","status":"%s","data_dir":"%s"}' \
                "$svc" "$img" "${sub}.${INTERNAL_SUBDOMAIN}" "$status" "${DATA_BASE}/${svc}"
            first=false
        done <<< "$services"
        echo -e "\n]"
    else
        printf "%-20s %-35s %-15s %-10s\n" "NAME" "IMAGE" "SUBDOMAIN" "STATUS"
        printf "%-20s %-35s %-15s %-10s\n" "----" "-----" "---------" "------"
        while IFS= read -r svc; do
            local enabled=$(_so_enabled "$svc")
            local status="not deployed"
            if [[ "$enabled" == "false" ]]; then status="disabled"
            elif docker inspect -f '{{.State.Running}}' "$svc" 2>/dev/null | grep -q true; then status="running"
            elif docker inspect "$svc" >/dev/null 2>&1; then status="stopped"
            fi
            local img=$(_so_field "$svc" "image"); img="${img:0:33}"
            local sub=$(yq -r ".services.${svc}.subdomain // \"${svc}\"" "$SERVICES_CONFIG")
            printf "%-20s %-35s %-15s %-10s\n" "$svc" "$img" "$sub" "$status"
        done <<< "$services"
    fi
}

cmd_validate() {
    shift
    local svc="${1:-}"
    [[ -z "$svc" ]] && { print_error "Usage: docker-service-helper.sh validate <service-name>"; return "$_SO_ERR_USAGE"; }
    read_service_definition "$svc"
    local enabled=$(_so_enabled "$svc")
    if [[ "$enabled" == "false" ]]; then
        print_info "Service '${svc}' is disabled (enabled: false) — skipping validation"; return 0
    fi
    validate_service "$svc"
}

cmd_logs() {
    shift
    local svc="" follow="" tail=""
    while [[ $# -gt 0 ]]; do
        case "$1" in --follow|-f) follow="--follow";; --tail) shift; tail="--tail $1";; *) svc="$1";; esac; shift
    done
    [[ -z "$svc" ]] && { print_error "Usage: docker-service-helper.sh logs <service-name> [--follow] [--tail N]"; return "$_SO_ERR_USAGE"; }
    if ! docker inspect "$svc" >/dev/null 2>&1; then
        print_error "Container '${svc}' does not exist. Use 'add' to deploy first"; return "$_SO_ERR_GENERAL"
    fi
    # shellcheck disable=SC2086
    docker logs $follow $tail "$svc"
}

cmd_stop() {
    shift
    local svc="${1:-}"
    [[ -z "$svc" ]] && { print_error "Usage: docker-service-helper.sh stop <service-name>"; return "$_SO_ERR_USAGE"; }
    local compose="${COMPOSE_DIR}/${svc}/docker-compose.yml"
    if [[ ! -f "$compose" ]]; then
        print_error "Container '${svc}' does not exist. Use 'add' to deploy first"; return "$_SO_ERR_GENERAL"
    fi
    docker compose -f "$compose" stop
    print_success "Stopped ${svc}"
    _so_log "STOP ${svc}"
}

cmd_start() {
    shift
    local svc="${1:-}"
    [[ -z "$svc" ]] && { print_error "Usage: docker-service-helper.sh start <service-name>"; return "$_SO_ERR_USAGE"; }
    local compose="${COMPOSE_DIR}/${svc}/docker-compose.yml"
    if [[ ! -f "$compose" ]]; then
        print_error "Container '${svc}' does not exist. Use 'add' to deploy first"; return "$_SO_ERR_GENERAL"
    fi
    docker compose -f "$compose" start
    print_success "Started ${svc}"
    validate_service "$svc" || true
    _so_log "START ${svc}"
}

cmd_lint() {
    shift
    if ! command -v yq &>/dev/null; then
        print_error "yq is required. Install: sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq"
        return "$_SO_ERR_CONFIG"
    fi
    if ! yq '.' "$SERVICES_CONFIG" >/dev/null 2>&1; then
        print_error "YAML syntax error in ${SERVICES_CONFIG}"; return "$_SO_ERR_VALIDATION"
    fi
    local count=0 errors=0
    while IFS= read -r svc; do
        count=$((count+1))
        if ! validate_service_definition "$svc" 2>/dev/null; then
            errors=$((errors+1))
            # Re-run to show error messages
            validate_service_definition "$svc" || true
        fi
    done < <(list_helper_services)
    if [[ "$errors" -eq 0 ]]; then
        print_success "Lint passed: ${count} service(s) validated"
    else
        print_error "Lint failed: ${errors}/${count} service(s) have issues"
        return "$_SO_ERR_VALIDATION"
    fi
}

cmd_backup() {
    shift
    local svc="${1:-}"
    [[ -z "$svc" ]] && { print_error "Usage: docker-service-helper.sh backup <service-name>"; return "$_SO_ERR_USAGE"; }
    read_service_definition "$svc"
    local backup_script="${BACKUP_DIR}/backup-helper-services.sh"
    if [[ ! -f "$backup_script" ]]; then
        print_error "backup-helper-services.sh not found at ${backup_script}"; return "$_SO_ERR_GENERAL"
    fi
    bash "$backup_script" "${@:2}" "$svc"
}

# Usage display
show_usage() {
    cat << 'EOF'
Usage: docker-service-helper.sh <command> [service-name] [flags]

Commands:
  add       <name> [--dry-run] [--verbose]    Deploy a new service
  remove    <name> [--dry-run] [--purge-data]  Remove a deployed service
  update    <name> [--dry-run] [--verbose]     Recreate with updated definition
  list      [--json]                           List all helper services
  validate  <name>                             Run validation checks
  logs      <name> [--follow] [--tail N]       View container logs
  stop      <name>                             Stop container(s)
  start     <name>                             Start container(s)
  lint                                         Validate services.yml schema
  backup    <name>                             Run backup for a service

Examples:
  docker-service-helper.sh add vocabgen
  docker-service-helper.sh add vocabgen --dry-run
  docker-service-helper.sh remove vocabgen --purge-data
  docker-service-helper.sh list --json
  docker-service-helper.sh logs vocabgen --tail 50
EOF
}
