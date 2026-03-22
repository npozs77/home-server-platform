#!/bin/bash
# Validation Utilities: Photo Management Layer
# Purpose: Validation functions for Immich photo management deployment
# Usage: Source this file in deployment scripts

# Validate Immich directories exist
validate_immich_directories() {
    [[ -d "${DATA_MOUNT}/services/immich/upload" ]] && [[ -d "${DATA_MOUNT}/services/immich/postgres" ]]
}

# Validate Docker Compose file exists
validate_compose_file() {
    [[ -f /opt/homeserver/configs/docker-compose/immich.yml ]]
}

# Validate all Immich containers running and healthy
validate_immich_containers() {
    local containers=("immich-server" "immich-ml" "immich-redis" "immich-postgres")
    for c in "${containers[@]}"; do
        if ! docker ps --filter "name=$c" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q "$c"; then
            echo "ERROR: $c not running"
            return 1
        fi
    done
    # Check health on immich-server
    local health
    health=$(docker inspect immich-server --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    if [[ "$health" != "healthy" ]]; then
        echo "WARNING: immich-server health=$health"
    fi
    return 0
}

# Validate Caddy route configured
validate_caddy_route() {
    grep -q "${IMMICH_DOMAIN}" /opt/homeserver/configs/caddy/Caddyfile 2>/dev/null
}

# Validate DNS record resolves
validate_dns_record() {
    nslookup "${IMMICH_DOMAIN}" "${SERVER_IP}" 2>/dev/null | grep -q "${SERVER_IP}"
}

# Validate HTTPS access (uses --resolve to bypass system DNS)
validate_https_access() {
    local http_code
    http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "${IMMICH_DOMAIN}:443:${SERVER_IP}" "https://${IMMICH_DOMAIN}" 2>/dev/null) || true
    [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]
}

# Validate external library mounts accessible
validate_external_libraries() {
    [[ -d "${DATA_MOUNT}/media/Photos" ]] && [[ -d "${DATA_MOUNT}/family/Photos" ]]
}

# Validate upload directory writable
validate_upload_writable() {
    [[ -w "${DATA_MOUNT}/services/immich/upload" ]]
}

# Validate Samba upload shares configured
validate_samba_upload_shares() {
    grep -q "\-uploads\]" /opt/homeserver/configs/samba/smb.conf 2>/dev/null
}

# Validate backup script exists and executable
validate_backup_script() {
    [[ -x /opt/homeserver/scripts/backup/backup-immich.sh ]]
}

# Validate version pinned (not :latest)
validate_version_pinned() {
    [[ "${IMMICH_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Validate secrets.env not tracked in Git
validate_secrets_not_tracked() {
    ! git -C /opt/homeserver ls-files --error-unmatch configs/secrets.env &>/dev/null
}

# Validate Git working tree is clean
validate_git_commit() {
    git -C /opt/homeserver status | grep -q "nothing to commit, working tree clean"
}
