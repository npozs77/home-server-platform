#!/bin/bash
# Task: Deploy Jellyfin container
# Phase: 3 (Core Services)
# Number: 11
# Prerequisites:
#   - Phase 2 complete
#   - docker-compose.yml created (Task 6.1)
#   - Docker and Docker Compose installed
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   None
# Environment Variables Optional:
#   None

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

# Validate prerequisites
print_info "Validating prerequisites..."

# Check docker-compose.yml exists
if [[ ! -f configs/docker-compose/jellyfin.yml ]]; then
    print_error "configs/docker-compose/jellyfin.yml does not exist (run Task 6.1 first)"
    exit 3
fi

# Check Docker is running
if ! docker info &> /dev/null; then
    print_error "Docker is not running"
    exit 3
fi

# Check homeserver network exists
if ! docker network inspect homeserver &> /dev/null; then
    print_error "Docker network 'homeserver' does not exist (should be created in Phase 2)"
    exit 3
fi

# Check idempotency
if docker ps -a --format '{{.Names}}' | grep -q '^jellyfin$'; then
    print_info "Jellyfin container already exists"
    
    # Check if running
    if docker ps --format '{{.Names}}' | grep -q '^jellyfin$'; then
        print_info "Jellyfin container is already running"
        if [[ "$DRY_RUN" == false ]]; then
            print_info "Restarting Jellyfin container to apply any configuration changes..."
            docker compose -f configs/docker-compose/jellyfin.yml restart
            print_success "Jellyfin container restarted"
        fi
        exit 0
    else
        print_info "Jellyfin container exists but is not running"
        if [[ "$DRY_RUN" == false ]]; then
            print_info "Starting Jellyfin container..."
            docker compose -f configs/docker-compose/jellyfin.yml start
            print_success "Jellyfin container started"
        fi
        exit 0
    fi
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would deploy Jellyfin container"
    print_info "[DRY-RUN] Would run: docker compose -f configs/docker-compose/jellyfin.yml up -d"
else
    print_info "Deploying Jellyfin container..."
    
    # Deploy Jellyfin
    docker compose -f configs/docker-compose/jellyfin.yml up -d
    
    # Wait for container to be healthy (max 30 seconds)
    print_info "Waiting for Jellyfin container to start..."
    for i in {1..30}; do
        if docker ps --format '{{.Names}}' | grep -q '^jellyfin$'; then
            print_success "Jellyfin container is running"
            break
        fi
        sleep 1
    done
    
    # Verify container is running
    if ! docker ps --format '{{.Names}}' | grep -q '^jellyfin$'; then
        print_error "Jellyfin container failed to start"
        print_error "Check logs: docker logs jellyfin"
        exit 1
    fi
    
    # Display container info
    print_info "Jellyfin container details:"
    docker ps --filter name=jellyfin --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    print_success "Jellyfin container deployed successfully"
    print_info "Access Jellyfin at: http://192.168.1.2:8096 (internal)"
    print_info "After configuring Caddy and DNS, access at: https://media.home.mydomain.com"
fi

print_success "Task complete"
exit 0
