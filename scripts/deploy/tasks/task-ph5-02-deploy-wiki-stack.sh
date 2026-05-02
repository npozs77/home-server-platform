#!/bin/bash
# Task: Deploy Wiki.js Docker Compose stack
# Phase: 5 (Wiki + LLM Platform — Sub-phase A)
# Number: 02
# Prerequisites:
#   - Phase 2 complete (Docker, homeserver network)
#   - Wiki.js directories created (Task 3.1 / task-ph5-01)
#   - services.env and secrets.env configured with Wiki.js variables
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required (services.env):
#   WIKI_DB_USER, WIKI_DB_NAME, WIKI_PORT, WIKI_MEM_LIMIT, WIKI_CPU_LIMIT,
#   WIKI_DB_MEM_LIMIT, WIKI_DB_CPU_LIMIT, TIMEZONE
# Environment Variables Required (secrets.env):
#   WIKI_DB_PASSWORD
# Satisfies: Requirements 1.1, 1.2, 2.2, 2.3, 2.4, 2.5, 20.1

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
COMPOSE_FILE="${COMPOSE_DIR}/wiki.yml"

# Docker compose command with all env files
COMPOSE_CMD="docker compose --env-file $FOUNDATION_ENV --env-file $SERVICES_ENV --env-file $SECRETS_ENV -f $COMPOSE_FILE"

# Source environment files (only if vars not already exported by orchestrator)
if [[ -z "${WIKI_DB_USER:-}" ]]; then
    print_info "Loading configuration..."
    [[ -f "$FOUNDATION_ENV" ]] && source "$FOUNDATION_ENV"
    if [[ ! -f "$SERVICES_ENV" ]]; then
        print_error "services.env not found at $SERVICES_ENV"
        exit 3
    fi
    source "$SERVICES_ENV"
    if [[ -f "$SECRETS_ENV" ]]; then
        set +u; source "$SECRETS_ENV"; set -u
    fi
else
    print_info "Using exported configuration from orchestrator..."
fi

# Validate required env vars
REQUIRED_VARS=(WIKI_DB_USER WIKI_DB_NAME TIMEZONE)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        print_error "$var not set in services.env"
        exit 3
    fi
done

if [[ -z "${WIKI_DB_PASSWORD:-}" ]]; then
    print_error "WIKI_DB_PASSWORD not set in secrets.env"
    exit 3
fi

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
    # Generate wiki.yml from example template if not present
    EXAMPLE_FILE="${COMPOSE_DIR}/wiki.yml.example"
    if [[ -f "$EXAMPLE_FILE" ]]; then
        print_info "Generating wiki.yml from wiki.yml.example..."
        cp "$EXAMPLE_FILE" "$COMPOSE_FILE"
        print_success "Generated $COMPOSE_FILE"
    else
        print_error "wiki.yml not found and wiki.yml.example not available"
        exit 3
    fi
fi

# Wiki.js containers to check
WIKI_CONTAINERS=(wiki-db wiki-server)

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would deploy Wiki.js stack"
    print_info "[DRY-RUN] Configuration:"
    print_info "  - WIKI_DB_USER: $WIKI_DB_USER"
    print_info "  - WIKI_DB_NAME: $WIKI_DB_NAME"
    print_info "  - WIKI_PORT: ${WIKI_PORT:-3000}"
    print_info "  - WIKI_MEM_LIMIT: ${WIKI_MEM_LIMIT:-512M}"
    print_info "  - WIKI_DB_MEM_LIMIT: ${WIKI_DB_MEM_LIMIT:-512M}"
    print_info "  - TIMEZONE: $TIMEZONE"
    print_info "[DRY-RUN] Would run: docker compose ... -f wiki.yml up -d"
    print_info "[DRY-RUN] Would wait for containers to reach healthy status (max 120s)"
    print_info "[DRY-RUN] Containers: ${WIKI_CONTAINERS[*]}"

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
    for container in "${WIKI_CONTAINERS[@]}"; do
        STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
        if [[ "$STATUS" != "healthy" ]]; then
            ALL_RUNNING=false
            break
        fi
    done

    if [[ "$ALL_RUNNING" == true ]]; then
        print_success "Wiki.js containers already running and healthy — skipping deploy"
        docker ps --filter "name=wiki" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        # Ensure SERVER_IP is available (may not be sourced if orchestrator exported other vars)
        if [[ -z "${SERVER_IP:-}" ]] && [[ -f "$FOUNDATION_ENV" ]]; then
            source "$FOUNDATION_ENV"
        fi
        WIKI_URL="http://${SERVER_IP:-localhost}:${WIKI_PORT:-3000}"
        print_info "Wiki.js setup wizard: ${WIKI_URL}"
        print_info "HTTPS via https://${WIKI_DOMAIN:-WIKI_DOMAIN} available after Caddy + DNS tasks"
        print_success "Task complete"
        exit 0
    fi

    print_info "Deploying Wiki.js stack..."
    $COMPOSE_CMD up -d

    # Wait for all containers to reach healthy status (max 120 seconds)
    print_info "Waiting for containers to reach healthy status (max 120s)..."
    TIMEOUT=120
    ELAPSED=0
    INTERVAL=5
    ALL_HEALTHY=false

    while [[ $ELAPSED -lt $TIMEOUT ]]; do
        ALL_HEALTHY=true
        for container in "${WIKI_CONTAINERS[@]}"; do
            STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
            if [[ "$STATUS" != "healthy" ]]; then
                ALL_HEALTHY=false
                break
            fi
        done

        if [[ "$ALL_HEALTHY" == true ]]; then
            print_success "All Wiki.js containers are healthy"
            break
        fi

        sleep "$INTERVAL"
        ELAPSED=$((ELAPSED + INTERVAL))
        print_info "Waiting... ${ELAPSED}s / ${TIMEOUT}s"
    done

    if [[ "$ALL_HEALTHY" != true ]]; then
        print_error "Not all containers reached healthy status within ${TIMEOUT}s"
        print_info "Current container status:"
        for container in "${WIKI_CONTAINERS[@]}"; do
            STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not found")
            echo "  $container: $STATUS"
        done
        print_error "Check logs: docker logs <container-name>"
        exit 1
    fi

    # Verify all containers running
    print_info "Verifying all Wiki.js containers are running..."
    for container in "${WIKI_CONTAINERS[@]}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            print_error "Container $container is not running"
            exit 1
        fi
    done

    # Display container status
    print_info "Wiki.js container status:"
    docker ps --filter "name=wiki" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    print_success "Wiki.js stack deployed successfully"
    # Ensure SERVER_IP is available
    if [[ -z "${SERVER_IP:-}" ]] && [[ -f "$FOUNDATION_ENV" ]]; then
        source "$FOUNDATION_ENV"
    fi
    WIKI_URL="http://${SERVER_IP:-localhost}:${WIKI_PORT:-3000}"
    print_info "Complete the Wiki.js setup wizard at: ${WIKI_URL}"
    print_info "HTTPS via https://${WIKI_DOMAIN:-WIKI_DOMAIN} available after Caddy + DNS tasks"
fi

print_success "Task complete"
exit 0
