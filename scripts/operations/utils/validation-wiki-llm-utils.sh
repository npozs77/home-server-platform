#!/bin/bash
set -euo pipefail
# Validation Utilities: Wiki + LLM Platform Layer
# Purpose: Validation functions for Phase 5 Wiki.js + Ollama + Open WebUI deployment
# Usage: Source this file in deployment scripts

# Validate Wiki.js directories exist
validate_wiki_directories() {
    [[ -d "${DATA_MOUNT}/services/wiki/postgres" ]] && [[ -d "${DATA_MOUNT}/services/wiki/content" ]]
}

# Validate LLM directories exist
validate_llm_directories() {
    [[ -d "${DATA_MOUNT}/services/ollama/models" ]] && [[ -d "${DATA_MOUNT}/services/openwebui/data" ]]
}

# Validate Wiki Docker Compose file exists
validate_wiki_compose_file() {
    [[ -f /opt/homeserver/configs/docker-compose/wiki.yml ]]
}

# Validate Ollama Docker Compose file exists
validate_ollama_compose_file() {
    [[ -f /opt/homeserver/configs/docker-compose/ollama.yml ]]
}

# Validate wiki-db container running and healthy
validate_wiki_db_container() {
    local health
    health=$(docker inspect wiki-db --format='{{.State.Health.Status}}' 2>/dev/null || echo "not_found")
    [[ "$health" == "healthy" ]]
}

# Validate wiki-server container running and healthy
validate_wiki_server_container() {
    local health
    health=$(docker inspect wiki-server --format='{{.State.Health.Status}}' 2>/dev/null || echo "not_found")
    [[ "$health" == "healthy" ]]
}

# Validate ollama container running and healthy
validate_ollama_container() {
    local health
    health=$(docker inspect ollama --format='{{.State.Health.Status}}' 2>/dev/null || echo "not_found")
    [[ "$health" == "healthy" ]]
}

# Validate open-webui container running and healthy
validate_openwebui_container() {
    local health
    health=$(docker inspect open-webui --format='{{.State.Health.Status}}' 2>/dev/null || echo "not_found")
    [[ "$health" == "healthy" ]]
}

# Validate Ollama API NOT published to host (port 11434 internal only)
validate_ollama_internal_only() {
    ! docker inspect ollama --format='{{json .HostConfig.PortBindings}}' 2>/dev/null | grep -q "11434"
}

# Validate Caddy route for Wiki.js
validate_wiki_caddy_route() {
    grep -q "${WIKI_DOMAIN}" /opt/homeserver/configs/caddy/Caddyfile 2>/dev/null
}

# Validate Caddy route for Open WebUI
validate_chat_caddy_route() {
    grep -q "${OPENWEBUI_DOMAIN}" /opt/homeserver/configs/caddy/Caddyfile 2>/dev/null
}

# Validate DNS record for Wiki.js
validate_wiki_dns_record() {
    nslookup "${WIKI_DOMAIN}" "${SERVER_IP}" 2>/dev/null | grep -q "${SERVER_IP}"
}

# Validate DNS record for Open WebUI
validate_chat_dns_record() {
    nslookup "${OPENWEBUI_DOMAIN}" "${SERVER_IP}" 2>/dev/null | grep -q "${SERVER_IP}"
}

# Validate HTTPS access to Wiki.js
validate_wiki_https_access() {
    local http_code
    http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "${WIKI_DOMAIN}:443:${SERVER_IP}" "https://${WIKI_DOMAIN}" 2>/dev/null) || true
    [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]
}

# Validate HTTPS access to Open WebUI
validate_chat_https_access() {
    local http_code
    http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "${OPENWEBUI_DOMAIN}:443:${SERVER_IP}" "https://${OPENWEBUI_DOMAIN}" 2>/dev/null) || true
    [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]
}

# Validate at least one LLM model available
validate_ollama_model_available() {
    docker exec ollama ollama list 2>/dev/null | grep -qv "^NAME"
}

# Validate Open WebUI can communicate with Ollama
validate_openwebui_ollama_connection() {
    docker exec open-webui curl -sf http://ollama:11434/ &>/dev/null
}

# Validate backup script exists and executable
validate_wiki_llm_backup_script() {
    [[ -x /opt/homeserver/scripts/backup/backup-wiki-llm.sh ]]
}

# Validate wiki-rag-sync script exists and executable
validate_wiki_rag_sync_script() {
    [[ -x /opt/homeserver/scripts/operations/wiki-rag-sync.sh ]]
}

# Validate Netdata discovers Phase 5 containers
validate_netdata_phase5() {
    local tmpfile="/tmp/netdata_charts_check.json"
    curl -s --max-time 15 http://localhost:19999/api/v1/charts > "$tmpfile" 2>/dev/null || true
    local result=1
    grep -qE "wiki|ollama|open.webui" "$tmpfile" 2>/dev/null && result=0
    rm -f "$tmpfile"
    return $result
}

# Validate secrets.env not tracked in Git
validate_secrets_not_tracked() {
    ! git -C /opt/homeserver ls-files --error-unmatch configs/secrets.env &>/dev/null
}

# Validate Git working tree is clean
validate_git_commit() {
    git -C /opt/homeserver status | grep -q "nothing to commit, working tree clean"
}

# Validate LOC governance for Phase 5 scripts (Warning not failure on exceed)
# Returns 0 always — prints warnings for scripts exceeding advisory limits
validate_loc_governance() {
    local DEPLOY_LIMIT=300
    local TASK_LIMIT=152
    local UTIL_LIMIT=200
    local warnings=0

    # Helper: count non-empty, non-comment lines
    _count_loc() {
        grep -v '^\s*#' "$1" | grep -v '^\s*$' | wc -l
    }

    # Check orchestration script
    local orch="/opt/homeserver/scripts/deploy/deploy-phase5-wiki-llm.sh"
    if [[ -f "$orch" ]]; then
        local loc; loc=$(_count_loc "$orch")
        if [[ $loc -gt $DEPLOY_LIMIT ]]; then
            echo "WARNING: deploy-phase5-wiki-llm.sh: $loc LOC exceeds advisory limit of $DEPLOY_LIMIT"
            warnings=$((warnings + 1))
        fi
    fi

    # Check Phase 5 task modules
    for task in /opt/homeserver/scripts/deploy/tasks/task-ph5-*.sh; do
        [[ -f "$task" ]] || continue
        local loc; loc=$(_count_loc "$task")
        if [[ $loc -gt $TASK_LIMIT ]]; then
            echo "WARNING: $(basename "$task"): $loc LOC exceeds advisory limit of $TASK_LIMIT"
            warnings=$((warnings + 1))
        fi
    done

    # Check Phase 5 validation utility
    local vutil="/opt/homeserver/scripts/operations/utils/validation-wiki-llm-utils.sh"
    if [[ -f "$vutil" ]]; then
        local loc; loc=$(_count_loc "$vutil")
        if [[ $loc -gt $UTIL_LIMIT ]]; then
            echo "WARNING: validation-wiki-llm-utils.sh: $loc LOC exceeds advisory limit of $UTIL_LIMIT"
            warnings=$((warnings + 1))
        fi
    fi

    # LOC governance is advisory — always pass, but print warnings
    if [[ $warnings -gt 0 ]]; then
        echo "LOC governance: $warnings advisory warning(s) — not blocking"
    fi
    return 0
}

# ── Checks Registry (single source of truth) ──
# Used by: deploy-phase5-wiki-llm.sh validate_all()
PHASE5_CHECKS=(
    "Wiki Directories:validate_wiki_directories"
    "LLM Directories:validate_llm_directories"
    "Wiki Compose File:validate_wiki_compose_file"
    "Ollama Compose File:validate_ollama_compose_file"
    "Wiki DB Container:validate_wiki_db_container"
    "Wiki Server Container:validate_wiki_server_container"
    "Ollama Container:validate_ollama_container"
    "Open WebUI Container:validate_openwebui_container"
    "Ollama Internal Only:validate_ollama_internal_only"
    "Caddy Route (Wiki):validate_wiki_caddy_route"
    "Caddy Route (Chat):validate_chat_caddy_route"
    "DNS Record (Wiki):validate_wiki_dns_record"
    "DNS Record (Chat):validate_chat_dns_record"
    "HTTPS Access (Wiki):validate_wiki_https_access"
    "HTTPS Access (Chat):validate_chat_https_access"
    "Ollama Model Available:validate_ollama_model_available"
    "WebUI-Ollama Connection:validate_openwebui_ollama_connection"
    "Backup Script:validate_wiki_llm_backup_script"
    "RAG Sync Script:validate_wiki_rag_sync_script"
    "Netdata Phase 5:validate_netdata_phase5"
    "LOC Governance:validate_loc_governance"
    "Secrets Not Tracked:validate_secrets_not_tracked"
    "Git Clean:validate_git_commit"
)
