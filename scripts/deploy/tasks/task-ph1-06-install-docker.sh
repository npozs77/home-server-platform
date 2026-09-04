#!/bin/bash
# Task: Install Docker and Docker Compose
# Phase: 1 (Foundation)
# Number: 06
# Prerequisites: Task 1 complete (system updated)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   ADMIN_USER
# Environment Variables Optional:
#   None

set -euo pipefail
# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utility libraries
source /opt/homeserver/scripts/operations/utils/output-utils.sh
source /opt/homeserver/scripts/operations/utils/env-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate required environment variables
validate_required_vars "ADMIN_USER" || exit 3

# Docker data-root location (encrypted data volume, keeps OS/root partition lean)
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/mnt/data/docker}"
DOCKER_DROPIN_DIR="/etc/systemd/system/docker.service.d"
DOCKER_DROPIN_FILE="${DOCKER_DROPIN_DIR}/10-data-root-mount.conf"

# Check if already completed (idempotency)
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    if systemctl is-active --quiet docker; then
        current_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "")
        if groups "$ADMIN_USER" | grep -q docker && [[ "$current_root" == "$DOCKER_DATA_ROOT" ]]; then
            print_info "Docker already installed and configured (data-root: ${DOCKER_DATA_ROOT}) - skip"
            exit 0
        fi
    fi
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would install Docker prerequisites"
    print_info "[DRY-RUN] Would add Docker repository"
    print_info "[DRY-RUN] Would install Docker Engine and Docker Compose"
    print_info "[DRY-RUN] Would create data-root directory ${DOCKER_DATA_ROOT}"
    print_info "[DRY-RUN] Would configure Docker daemon (data-root, log rotation, overlay2)"
    print_info "[DRY-RUN] Would install systemd drop-in ${DOCKER_DROPIN_FILE} (RequiresMountsFor=/mnt/data)"
    print_info "[DRY-RUN] Would add $ADMIN_USER to docker group"
    exit 0
fi

print_header "Task 6: Install Docker and Docker Compose"
echo ""

# Check if Docker already installed
if command -v docker &>/dev/null; then
    print_info "Docker already installed"
else
    # Install prerequisites
    print_info "Installing prerequisites..."
    apt install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    print_info "Adding Docker GPG key..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up Docker repository
    print_info "Setting up Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index
    apt update
    
    # Install Docker Engine and Docker Compose
    print_info "Installing Docker Engine and Docker Compose..."
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Guard: data-root lives on the encrypted /mnt/data volume — refuse if not mounted,
# otherwise the directory would be created on the root partition under the mountpoint.
if [[ "$DOCKER_DATA_ROOT" == /mnt/data/* ]] && ! mountpoint -q /mnt/data; then
    print_error "/mnt/data is not mounted — cannot place Docker data-root at ${DOCKER_DATA_ROOT}"
    print_error "Complete LUKS setup (task 2) and ensure /mnt/data is mounted before installing Docker"
    exit 1
fi

# Create data-root directory on the encrypted volume
print_info "Creating Docker data-root: ${DOCKER_DATA_ROOT}..."
mkdir -p "$DOCKER_DATA_ROOT"

# Configure Docker daemon (data-root relocated off the small OS/root partition)
print_info "Configuring Docker daemon (data-root: ${DOCKER_DATA_ROOT})..."
cat > /etc/docker/daemon.json << EOF
{
  "data-root": "${DOCKER_DATA_ROOT}",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

# Install systemd drop-in so Docker starts only after /mnt/data is mounted
print_info "Installing systemd drop-in (RequiresMountsFor=/mnt/data)..."
mkdir -p "$DOCKER_DROPIN_DIR"
cat > "$DOCKER_DROPIN_FILE" << 'EOF'
# Managed by task-ph1-06-install-docker.sh — do not edit manually
# Ensures dockerd starts only after the LUKS-encrypted /mnt/data volume is mounted
# (Docker data-root lives on that volume; see /etc/docker/daemon.json).
[Unit]
RequiresMountsFor=/mnt/data
EOF

# Reload systemd to pick up the drop-in, then restart Docker
print_info "Reloading systemd and restarting Docker..."
systemctl daemon-reload
systemctl restart docker

# Verify data-root took effect
active_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "")
if [[ "$active_root" != "$DOCKER_DATA_ROOT" ]]; then
    print_error "Docker data-root is '${active_root}', expected '${DOCKER_DATA_ROOT}'"
    exit 1
fi
print_success "Docker data-root confirmed: ${active_root}"

# Add admin user to docker group
print_info "Adding $ADMIN_USER to docker group..."
usermod -aG docker "$ADMIN_USER"

print_success "Task 6 complete"
print_info "Note: $ADMIN_USER needs to log out and back in for docker group to take effect"
exit 0
