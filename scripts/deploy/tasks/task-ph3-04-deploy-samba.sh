#!/bin/bash
# Task: Deploy Samba container
# Phase: 3 (Core Services)
# Number: 04
# Prerequisites:
#   - Docker installed
#   - smb.conf created
#   - Configuration loaded (TIMEZONE, SAMBA_WORKGROUP)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   TIMEZONE, SAMBA_WORKGROUP
# Environment Variables Optional:
#   None

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate required environment variables
if [[ -z "${TIMEZONE:-}" ]]; then
    echo "Error: TIMEZONE environment variable not set" >&2
    exit 3
fi

if [[ -z "${SAMBA_WORKGROUP:-}" ]]; then
    echo "Error: SAMBA_WORKGROUP environment variable not set" >&2
    exit 3
fi

# Validate prerequisites
if [[ ! -f configs/samba/smb.conf ]]; then
    echo "Error: smb.conf not found - run task 3.1 first" >&2
    exit 1
fi

# Check idempotency
if docker ps -a --format '{{.Names}}' | grep -q '^samba$'; then
    echo "Samba container already exists"
    if [[ "$DRY_RUN" == false ]]; then
        read -p "Recreate? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            echo "Skipping Samba container deployment"
            exit 0
        fi
        echo "Stopping and removing existing container..."
        docker stop samba &> /dev/null || true
        docker rm samba &> /dev/null || true
    fi
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would create configs/docker-compose/samba.yml"
    echo "[DRY-RUN] Would start Samba container"
    echo "[DRY-RUN] Would verify UFW allows ports 139/445"
else
    echo "Creating docker-compose.yml for Samba..."
    mkdir -p configs/docker-compose
    
    # Create Samba persistent data directory structure
    echo "Creating Samba persistent data directory..."
    mkdir -p /mnt/data/services/samba/lib/private/msg.sock
    chmod 700 /mnt/data/services/samba/lib/private/msg.sock
    chmod 755 /mnt/data/services/samba/lib/private
    chmod 755 /mnt/data/services/samba/lib
    echo "✓ Created /mnt/data/services/samba/lib with subdirectories"
    
    # Get family group GID
    FAMILY_GID=$(getent group family | cut -d: -f3)
    
    cat > configs/docker-compose/samba.yml << EOFSAMBA
services:
  samba:
    image: dperson/samba:latest
    container_name: samba
    restart: unless-stopped
    ports:
      - "139:139"
      - "445:445"
    volumes:
      - /mnt/data:/mnt/data
      - /opt/homeserver/configs/samba/smb.conf:/etc/samba/smb.conf:ro
      - /mnt/data/services/samba/lib:/var/lib/samba:rw
      - /etc/passwd:/etc/passwd:ro
      - /etc/group:/etc/group:ro
    environment:
      TZ: "${TIMEZONE}"
      WORKGROUP: "${SAMBA_WORKGROUP}"
      RECYCLE: "true"
      PGID: "${FAMILY_GID}"
    networks:
      - homeserver

networks:
  homeserver:
    external: true
EOFSAMBA
    
    echo "✓ Created configs/docker-compose/samba.yml (PGID=${FAMILY_GID})"
    
    # Create homeserver network if it doesn't exist
    if ! docker network ls --format '{{.Name}}' | grep -q '^homeserver$'; then
        echo "Creating homeserver Docker network..."
        docker network create homeserver
        echo "✓ Created homeserver network"
    fi
    
    # Start Samba container
    echo "Starting Samba container..."
    cd configs/docker-compose
    docker compose -f samba.yml up -d
    
    # Wait for container to be healthy
    echo "Waiting for Samba container to start..."
    sleep 5
    
    # Verify container is running
    if docker ps --format '{{.Names}}' | grep -q '^samba$'; then
        echo "✓ Samba container is running"
    else
        echo "✗ Samba container failed to start" >&2
        docker logs samba
        exit 1
    fi
    
    # Verify container can see family group
    echo "Verifying container can access host groups..."
    if docker exec samba getent group family &>/dev/null; then
        echo "✓ Container can see family group"
    else
        echo "✗ Container cannot see family group - check /etc/group mount" >&2
        exit 1
    fi
    
    # Verify UFW allows Samba ports
    echo "Verifying UFW firewall rules..."
    if ! ufw status | grep -q "139/tcp.*ALLOW.*192.168.1.0/24"; then
        echo "Adding UFW rule for Samba NetBIOS (port 139)..."
        ufw allow from 192.168.1.0/24 to any port 139 proto tcp comment 'Samba NetBIOS'
    fi
    
    if ! ufw status | grep -q "445/tcp.*ALLOW.*192.168.1.0/24"; then
        echo "Adding UFW rule for Samba SMB (port 445)..."
        ufw allow from 192.168.1.0/24 to any port 445 proto tcp comment 'Samba SMB'
    fi
    
    echo "✓ UFW allows Samba ports 139 and 445 from LAN"
    
    echo "Samba is accessible at \\\\192.168.1.2 (Windows) or smb://192.168.1.2 (macOS/Linux)"
fi

echo "✓ Task complete"
exit 0
