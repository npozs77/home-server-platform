#!/bin/bash
# Task: Initialize infrastructure Git repository
# Phase: 1 (Foundation)
# Number: 07
# Prerequisites: Task 1 complete (git installed)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required:
#   ADMIN_USER, GIT_USER_NAME, GIT_USER_EMAIL
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
validate_required_vars "ADMIN_USER" "GIT_USER_NAME" "GIT_USER_EMAIL" || exit 3
# Check if already completed (idempotency)
if [[ -d /opt/homeserver/.git ]]; then
    if git -C /opt/homeserver log &>/dev/null; then
        print_info "Git repository already initialized - skip"
        exit 0
    fi
fi
# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create /opt/homeserver directory"
    print_info "[DRY-RUN] Would initialize Git repository"
    print_info "[DRY-RUN] Would create directory structure (docs, scripts, configs, assets, templates)"
    print_info "[DRY-RUN] Would create README.md and .gitignore"
    print_info "[DRY-RUN] Would make initial commit"
    exit 0
fi
print_header "Task 7: Initialize Infrastructure Git Repository"
echo ""
# Create infrastructure directory
print_info "Creating infrastructure directory..."
mkdir -p /opt/homeserver
chown "$ADMIN_USER:$ADMIN_USER" /opt/homeserver
# Initialize Git if not already initialized
if [[ ! -d /opt/homeserver/.git ]]; then
    print_info "Initializing Git repository..."
    cd /opt/homeserver
    sudo -u "$ADMIN_USER" git init -b main
    sudo -u "$ADMIN_USER" git config user.name "$GIT_USER_NAME"
    sudo -u "$ADMIN_USER" git config user.email "$GIT_USER_EMAIL"
else
    print_info "Git repository already initialized"
    cd /opt/homeserver
fi

# Create directory structure
print_info "Creating directory structure..."
sudo -u "$ADMIN_USER" mkdir -p docs
sudo -u "$ADMIN_USER" mkdir -p scripts/{backup,deploy,maintenance,monitoring,operations}
sudo -u "$ADMIN_USER" mkdir -p configs
sudo -u "$ADMIN_USER" mkdir -p configs/{docker-compose,caddy,samba,wiki,foundation}
sudo -u "$ADMIN_USER" mkdir -p assets
sudo -u "$ADMIN_USER" mkdir -p templates

# Create README.md if not exists
if [[ ! -f README.md ]]; then
    print_info "Creating README.md..."
    sudo -u "$ADMIN_USER" tee README.md > /dev/null << 'EOF'
# Home Media Server Infrastructure

Infrastructure as Code for home media server platform.

## Structure

- `docs/` - Documentation
- `scripts/` - Automation scripts
- `configs/` - Service configurations
- `assets/` - Diagrams and screenshots
- `templates/` - Reusable templates

## Phases

- Phase 01: Foundation Layer
- Phase 02: Infrastructure Services
- Phase 03: Core Services
- Phase 04: Applications

## Version

Current version: 0.1
EOF
fi

# Create .gitignore if not exists
if [[ ! -f .gitignore ]]; then
    print_info "Creating .gitignore..."
    sudo -u "$ADMIN_USER" tee .gitignore > /dev/null << 'EOF'
# Sensitive files
*.key
*.pem
*.env
.env
*.secret

# Backup files
*.backup
*.bak
*~

# OS files
.DS_Store
Thumbs.db

# Editor files
.vscode/
.idea/
*.swp
*.swo
EOF
fi

# Make initial commit if no commits yet
if ! sudo -u "$ADMIN_USER" git log &>/dev/null; then
    print_info "Making initial commit..."
    sudo -u "$ADMIN_USER" git add .
    sudo -u "$ADMIN_USER" git commit -m "Initial infrastructure repository setup"
else
    print_info "Repository already has commits"
fi

print_success "Task 7 complete"
exit 0
