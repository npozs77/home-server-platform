#!/bin/bash
# Task: Deploy Netdata monitoring container
# Phase: 2 (Infrastructure)
# Number: 12
# Prerequisites:
#   - Phase 1 complete
#   - Docker installed
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
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

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would deploy Netdata container"
    exit 0
fi

# Create Netdata config directory
mkdir -p /opt/homeserver/configs/netdata

# Check if Netdata already running
if docker ps | grep -q netdata; then
    print_info "Netdata is already running"
    exit 0
fi

if docker ps -a | grep -q netdata; then
    print_info "Starting existing Netdata container..."
    docker start netdata
    sleep 5
    if docker ps | grep -q netdata; then
        print_success "Netdata is running"
        exit 0
    fi
fi

# Deploy Netdata container
print_info "Deploying Netdata container..."
docker run -d \
    --name netdata \
    --restart unless-stopped \
    --network homeserver \
    -p 19999:19999 \
    --cap-add SYS_PTRACE \
    --security-opt apparmor=unconfined \
    -v /proc:/host/proc:ro \
    -v /sys:/host/sys:ro \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    -v /opt/homeserver/configs/netdata:/etc/netdata \
    netdata/netdata:latest

print_success "Netdata container deployed"
sleep 5

if docker ps | grep -q netdata; then
    print_success "Netdata is running"
    print_info "Access at http://localhost:19999"
else
    print_error "Netdata failed to start"
    docker logs netdata
    exit 1
fi

print_success "Task complete"
exit 0
