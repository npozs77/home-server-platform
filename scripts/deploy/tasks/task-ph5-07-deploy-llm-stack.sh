#!/bin/bash
# Task: Deploy Ollama + Open WebUI Docker Compose stack
# Phase: 5 (Wiki + LLM Platform — Sub-phase B)
# Number: 07
# Prerequisites:
#   - Phase 2 complete (Docker, homeserver network)
#   - LLM directories created (Task 9.1 / task-ph5-06)
#   - services.env configured with Ollama/Open WebUI variables
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required (services.env):
#   OLLAMA_VERSION, OLLAMA_MEM_LIMIT, OLLAMA_CPU_LIMIT,
#   OPENWEBUI_VERSION, OPENWEBUI_PORT, OPENWEBUI_MEM_LIMIT,
#   OPENWEBUI_CPU_LIMIT, ENABLE_WEB_SEARCH, WEB_SEARCH_ENGINE, TIMEZONE
# Satisfies: Requirements 7.1, 9.1

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utilities (absolute paths)
source /opt/homeserver/scripts/operations/utils/output-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Configuration paths
FOUNDATION_ENV="/opt/homeserver/configs/foundation.env"
SERVICES_ENV="/opt/homeserver/configs/services.env"
SECRETS_ENV="/opt/homeserver/configs/secrets.env"
COMPOSE_DIR="/opt/homeserver/configs/docker-compose"
COMPOSE_FILE="${COMPOSE_DIR}/ollama.yml"

# Docker compose command with all env files
COMPOSE_CMD="docker compose --env-file $FOUNDATION_ENV --env-file $SERVICES_ENV -f $COMPOSE_FILE"

# Source environment files (only if vars not already exported by orchestrator)
if [[ -z "${OLLAMA_VERSION:-}" ]]; then
    print_info "Loading configuration..."
    [[ -f "$FOUNDATION_ENV" ]] && source "$FOUNDATION_ENV"
    if [[ ! -f "$SERVICES_ENV" ]]; then
        print_error "services.env not found at $SERVICES_ENV"
        exit 3
    fi
    source "$SERVICES_ENV"
else
    print_info "Using exported configuration from orchestrator..."
fi

# Validate required env vars
REQUIRED_VARS=(TIMEZONE)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        print_error "$var not set in services.env / foundation.env"
        exit 3
    fi
done

# Validate prerequisites
print_info "Validating prerequisites..."

if ! docker info &> /dev/null; then
    print_error "Docker is not running"
    exit 3
fi

if ! docker network inspect homeserver &> /dev/null; then
    print_error "Docker network 'homeserver' does not exist (should be created in Phase 2)"
    exit 3
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
    # Generate ollama.yml from example template if not present
    EXAMPLE_FILE="${COMPOSE_DIR}/ollama.yml.example"
    if [[ -f "$EXAMPLE_FILE" ]]; then
        print_info "Generating ollama.yml from ollama.yml.example..."
        cp "$EXAMPLE_FILE" "$COMPOSE_FILE"
        print_success "Generated $COMPOSE_FILE"
    else
        print_error "ollama.yml not found and ollama.yml.example not available"
        exit 3
    fi
fi

# LLM containers to check
LLM_CONTAINERS=(ollama open-webui)

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would deploy Ollama + Open WebUI stack"
    print_info "[DRY-RUN] Configuration:"
    print_info "  - OLLAMA_VERSION: ${OLLAMA_VERSION:-latest}"
    print_info "  - OLLAMA_MEM_LIMIT: ${OLLAMA_MEM_LIMIT:-6G}"
    print_info "  - OLLAMA_CPU_LIMIT: ${OLLAMA_CPU_LIMIT:-4.0}"
    print_info "  - OPENWEBUI_VERSION: ${OPENWEBUI_VERSION:-latest}"
    print_info "  - OPENWEBUI_PORT: ${OPENWEBUI_PORT:-8080}"
    print_info "  - OPENWEBUI_MEM_LIMIT: ${OPENWEBUI_MEM_LIMIT:-1G}"
    print_info "  - OPENWEBUI_CPU_LIMIT: ${OPENWEBUI_CPU_LIMIT:-2.0}"
    print_info "  - ENABLE_WEB_SEARCH: ${ENABLE_WEB_SEARCH:-true}"
    print_info "  - WEB_SEARCH_ENGINE: ${WEB_SEARCH_ENGINE:-duckduckgo}"
    print_info "  - TIMEZONE: $TIMEZONE"
    print_info "[DRY-RUN] Would run: docker compose ... -f ollama.yml up -d"
    print_info "[DRY-RUN] Would wait for containers to reach healthy status (max 120s)"
    print_info "[DRY-RUN] Containers: ${LLM_CONTAINERS[*]}"

    # Validate compose syntax even in dry-run
    print_info "[DRY-RUN] Validating Docker Compose syntax..."
    if $COMPOSE_CMD config &> /dev/null; then
        print_success "Docker Compose syntax valid"
    else
        print_error "Docker Compose syntax invalid"
        $COMPOSE_CMD config 2>&1 | head -20
        exit 1
    fi
else
    # Idempotency: skip if all containers already running and healthy
    ALL_RUNNING=true
    for container in "${LLM_CONTAINERS[@]}"; do
        STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
        if [[ "$STATUS" != "healthy" ]]; then
            ALL_RUNNING=false
            break
        fi
    done

    if [[ "$ALL_RUNNING" == true ]]; then
        print_success "Ollama + Open WebUI containers already running and healthy — skipping deploy"
        docker ps --filter "name=ollama" --filter "name=open-webui" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        print_info "Open WebUI setup: https://${OPENWEBUI_DOMAIN:-OPENWEBUI_DOMAIN} (after Caddy + DNS tasks)"
        print_success "Task complete"
        exit 0
    fi

    print_info "Deploying Ollama + Open WebUI stack..."
    $COMPOSE_CMD up -d

    # Wait for all containers to reach healthy status (max 120 seconds)
    print_info "Waiting for containers to reach healthy status (max 120s)..."
    TIMEOUT=120
    ELAPSED=0
    INTERVAL=5
    ALL_HEALTHY=false

    while [[ $ELAPSED -lt $TIMEOUT ]]; do
        ALL_HEALTHY=true
        for container in "${LLM_CONTAINERS[@]}"; do
            STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
            if [[ "$STATUS" != "healthy" ]]; then
                ALL_HEALTHY=false
                break
            fi
        done

        if [[ "$ALL_HEALTHY" == true ]]; then
            print_success "All LLM containers are healthy"
            break
        fi

        sleep "$INTERVAL"
        ELAPSED=$((ELAPSED + INTERVAL))
        print_info "Waiting... ${ELAPSED}s / ${TIMEOUT}s"
    done

    if [[ "$ALL_HEALTHY" != true ]]; then
        print_error "Not all containers reached healthy status within ${TIMEOUT}s"
        print_info "Current container status:"
        for container in "${LLM_CONTAINERS[@]}"; do
            STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not found")
            echo "  $container: $STATUS"
        done
        print_error "Check logs: docker logs <container-name>"
        exit 1
    fi

    # Verify all containers running
    print_info "Verifying all LLM containers are running..."
    for container in "${LLM_CONTAINERS[@]}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            print_error "Container $container is not running"
            exit 1
        fi
    done

    # Display container status
    print_info "LLM container status:"
    docker ps --filter "name=ollama" --filter "name=open-webui" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    print_success "Ollama + Open WebUI stack deployed successfully"
    print_info "Complete the Open WebUI first-user setup at: https://${OPENWEBUI_DOMAIN:-OPENWEBUI_DOMAIN}"
    print_info "(HTTPS available after Caddy + DNS tasks)"
fi

print_success "Task complete"
exit 0
