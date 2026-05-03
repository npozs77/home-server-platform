#!/bin/bash
# Task: Provision Admin User
# Phase: 3 (Core Services)
# Number: 07
#
# Prerequisites:
#   - create-user.sh script exists and tested
#   - SSH key prepared for admin user
#   - ADMIN_USER variable exported by orchestration script
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
# Environment Variables Required:
#   ADMIN_USER: Admin username (exported by orchestration script)
# Environment Variables Optional:
#   ADMIN_SSH_KEY: Path to admin SSH public key file (optional)

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate required variables
if [[ -z "${ADMIN_USER:-}" ]]; then
    echo "Error: ADMIN_USER variable not set" >&2
    exit 1
fi

# Script paths
CREATE_USER_SCRIPT="/opt/homeserver/scripts/operations/user-management/create-user.sh"
SECRETS_ENV="/opt/homeserver/configs/secrets.env"

# Load secrets for Samba passwords
if [[ ! -f "$SECRETS_ENV" ]]; then
    echo "Error: secrets.env not found: $SECRETS_ENV" >&2
    exit 1
fi

# Source secrets (contains SAMBA_PASSWORD_* variables)
set +u  # Temporarily disable unset variable check for sourcing
source "$SECRETS_ENV"
set -u

# Export all SAMBA_PASSWORD_* variables so create-user.sh can access them
while IFS='=' read -r varname _; do
    export "${varname?}"
done < <(grep "^SAMBA_PASSWORD_" "$SECRETS_ENV")

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would provision admin user: $ADMIN_USER"
    echo "[DRY-RUN] Would run: $CREATE_USER_SCRIPT $ADMIN_USER admin [ssh-key]"
    echo "[DRY-RUN] Would verify admin user created with correct permissions"
    echo "[DRY-RUN] Would verify SSH access configured"
else
    echo ""
    echo "========================================"
    echo "Provisioning Admin User"
    echo "========================================"
    echo ""
    
    # Check if create-user.sh exists
    if [[ ! -f "$CREATE_USER_SCRIPT" ]]; then
        echo "Error: create-user.sh script not found: $CREATE_USER_SCRIPT" >&2
        echo "Run Task 4.1 first to create user provisioning scripts" >&2
        exit 1
    fi
    
    # Check if user already exists (create-user.sh is idempotent and will update)
    if id "$ADMIN_USER" &>/dev/null; then
        echo "Note: Admin user $ADMIN_USER already exists - will update permissions and groups"
    fi
    
    # Provision admin user
    echo "Provisioning admin user: $ADMIN_USER"
    echo "Role: admin (sudo, docker, SSH, Samba, personal folders)"
    echo ""
    
    # Check if SSH key provided
    if [[ -n "${ADMIN_SSH_KEY:-}" ]]; then
        if [[ ! -f "$ADMIN_SSH_KEY" ]]; then
            echo "Error: Admin SSH key file not found: $ADMIN_SSH_KEY" >&2
            exit 1
        fi
        
        echo "Using SSH key: $ADMIN_SSH_KEY"
        
        # Run create-user.sh with SSH key
        if ! "$CREATE_USER_SCRIPT" "$ADMIN_USER" admin "$ADMIN_SSH_KEY"; then
            echo "Error: Failed to provision admin user" >&2
            exit 1
        fi
    else
        echo "Warning: No SSH key provided (ADMIN_SSH_KEY not set)"
        echo "Admin user will be created without SSH access"
        echo "You can add SSH key later with: update-user.sh $ADMIN_USER ssh-key /path/to/key.pub"
        echo ""
        
        # Run create-user.sh without SSH key
        if ! "$CREATE_USER_SCRIPT" "$ADMIN_USER" admin; then
            echo "Error: Failed to provision admin user" >&2
            exit 1
        fi
    fi
    
    echo ""
    echo "✓ Admin user provisioned successfully"
    
    # Verify user created
    echo "Verifying admin user..."
    
    # Check Linux user exists
    if ! id "$ADMIN_USER" &>/dev/null; then
        echo "Error: Admin user not found in system" >&2
        exit 1
    fi
    echo "✓ Linux user exists"
    
    # Check groups (must have sudo, docker, family - may have others)
    user_groups=$(groups "$ADMIN_USER" | cut -d: -f2)
    missing_groups=""
    echo "$user_groups" | grep -q sudo || missing_groups="$missing_groups sudo"
    echo "$user_groups" | grep -q docker || missing_groups="$missing_groups docker"
    echo "$user_groups" | grep -q family || missing_groups="$missing_groups family"
    
    if [[ -z "$missing_groups" ]]; then
        echo "✓ User has required groups (sudo, docker, family)"
    else
        echo "Error: User missing required groups:$missing_groups" >&2
        echo "Current groups: $user_groups" >&2
        exit 1
    fi
    
    # Check personal folder
    if [[ -d "/mnt/data/users/$ADMIN_USER" ]]; then
        echo "✓ Personal folder exists"
    else
        echo "Error: Personal folder not found: /mnt/data/users/$ADMIN_USER" >&2
        exit 1
    fi
    
    # Check SSH access (if key was provided)
    if [[ -n "${ADMIN_SSH_KEY:-}" ]]; then
        if [[ -f "/home/$ADMIN_USER/.ssh/authorized_keys" ]]; then
            echo "✓ SSH access configured"
        else
            echo "Error: SSH access not configured" >&2
            exit 1
        fi
    fi
    
    # Check Samba share
    if grep -q "^\[$ADMIN_USER\]" /opt/homeserver/configs/samba/smb.conf; then
        echo "✓ Samba share configured"
    else
        echo "Error: Samba share not found in smb.conf" >&2
        exit 1
    fi
    
    echo ""
    echo "✓ All verification checks passed"
    echo ""
fi

echo "✓ Task complete"
exit 0
