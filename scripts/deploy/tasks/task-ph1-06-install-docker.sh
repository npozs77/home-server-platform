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

# Check if already completed (idempotency)
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    if systemctl is-active --quiet docker; then
        if groups "$ADMIN_USER" | grep -q docker; then
            print_info "Docker already installed and configured - skip"
            exit 0
        fi
    fi
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would install Docker prerequisites"
    print_info "[DRY-RUN] Would add Docker repository"
    print_info "[DRY-RUN] Would install Docker Engine and Docker Compose"
    print_info "[DRY-RUN] Would configure Docker daemon (log rotation, overlay2)"
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

# Configure Docker daemon
print_info "Configuring Docker daemon..."
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

# Restart Docker
print_info "Restarting Docker..."
systemctl restart docker

# Add admin user to docker group
print_info "Adding $ADMIN_USER to docker group..."
usermod -aG docker "$ADMIN_USER"

print_success "Task 6 complete"
print_info "Note: $ADMIN_USER needs to log out and back in for docker group to take effect"
exit 0
