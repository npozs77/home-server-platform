#!/bin/bash
# Task: Provision Power Users
# Phase: 3 (Core Services)
# Number: 08
#
# Prerequisites:
#   - create-user.sh script exists and tested
#   - SSH keys prepared for each power user
#   - POWER_USERS variable exported by orchestration script
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
# Environment Variables Required:
#   POWER_USERS: Space-separated list of power user usernames (exported by orchestration script)
# Environment Variables Optional:
#   POWER_USER_SSH_KEYS: Space-separated list of SSH key file paths (same order as POWER_USERS)

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
if [[ -z "${POWER_USERS:-}" ]]; then
    echo "Warning: POWER_USERS variable not set or empty"
    echo "No power users to provision"
    exit 0
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
export $(grep "^SAMBA_PASSWORD_" "$SECRETS_ENV" | cut -d= -f1)

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would provision power users: $POWER_USERS"
    for user in $POWER_USERS; do
        echo "[DRY-RUN] Would run: $CREATE_USER_SCRIPT $user power [ssh-key]"
    done
    echo "[DRY-RUN] Would verify all power users created with correct permissions"
else
    echo ""
    echo "========================================"
    echo "Provisioning Power Users"
    echo "========================================"
    echo ""
    
    # Check if create-user.sh exists
    if [[ ! -f "$CREATE_USER_SCRIPT" ]]; then
        echo "Error: create-user.sh script not found: $CREATE_USER_SCRIPT" >&2
        echo "Run Task 4.1 first to create user provisioning scripts" >&2
        exit 1
    fi
    
    # Convert space-separated lists to arrays
    read -ra POWER_USER_ARRAY <<< "$POWER_USERS"
    read -ra SSH_KEY_ARRAY <<< "${POWER_USER_SSH_KEYS:-}"
    
    # Count users
    USER_COUNT=${#POWER_USER_ARRAY[@]}
    echo "Provisioning $USER_COUNT power user(s)"
    echo ""
    
    # Track success/failure
    SUCCESS_COUNT=0
    FAILURE_COUNT=0
    SKIPPED_COUNT=0
    
    # Provision each power user
    for i in "${!POWER_USER_ARRAY[@]}"; do
        username="${POWER_USER_ARRAY[$i]}"
        ssh_key="${SSH_KEY_ARRAY[$i]:-}"
        
        echo "[$((i+1))/$USER_COUNT] Provisioning power user: $username"
        echo "Role: power (docker, SSH, Samba, personal folders, no sudo)"
        
        # Check if user already exists (create-user.sh is idempotent and will update)
        if id "$username" &>/dev/null; then
            echo "Note: User $username already exists - will update permissions and groups"
        fi
        
        # Check SSH key if provided
        if [[ -n "$ssh_key" ]]; then
            if [[ ! -f "$ssh_key" ]]; then
                echo "Error: SSH key file not found: $ssh_key" >&2
                echo "Skipping user $username" >&2
                FAILURE_COUNT=$((FAILURE_COUNT + 1))
                echo ""
                continue
            fi
            echo "Using SSH key: $ssh_key"
        else
            echo "Warning: No SSH key provided for $username"
            echo "User will be created without SSH access"
            echo "You can add SSH key later with: update-user.sh $username ssh-key /path/to/key.pub"
        fi
        
        echo ""
        
        # Run create-user.sh
        if [[ -n "$ssh_key" ]]; then
            if "$CREATE_USER_SCRIPT" "$username" power "$ssh_key"; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                echo "Error: Failed to provision power user: $username" >&2
                FAILURE_COUNT=$((FAILURE_COUNT + 1))
            fi
        else
            if "$CREATE_USER_SCRIPT" "$username" power; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                echo "Error: Failed to provision power user: $username" >&2
                FAILURE_COUNT=$((FAILURE_COUNT + 1))
            fi
        fi
        
        echo ""
    done
    
    # Summary
    echo "========================================"
    echo "Provisioning Summary"
    echo "========================================"
    echo "Total users: $USER_COUNT"
    echo "Successfully provisioned: $SUCCESS_COUNT"
    [[ $SKIPPED_COUNT -gt 0 ]] && echo "Skipped (already exist): $SKIPPED_COUNT"
    [[ $FAILURE_COUNT -gt 0 ]] && echo "Failed: $FAILURE_COUNT"
    echo ""
    
    # Exit with error if any failures
    if [[ $FAILURE_COUNT -gt 0 ]]; then
        echo "Error: Some power users failed to provision" >&2
        exit 1
    fi
    
    # Verify all power users
    if [[ $SUCCESS_COUNT -gt 0 ]]; then
        echo "Verifying power users..."
        
        for username in "${POWER_USER_ARRAY[@]}"; do
            # Skip if user was skipped
            if ! id "$username" &>/dev/null; then
                continue
            fi
            
            # Check groups (must have docker, family - may have others, must NOT have sudo)
            user_groups=$(groups "$username" | cut -d: -f2)
            missing_groups=""
            echo "$user_groups" | grep -q docker || missing_groups="$missing_groups docker"
            echo "$user_groups" | grep -q family || missing_groups="$missing_groups family"
            has_sudo=$(echo "$user_groups" | grep -q sudo && echo "yes" || echo "no")
            
            if [[ -n "$missing_groups" ]]; then
                echo "Error: $username: Missing required groups:$missing_groups" >&2
                echo "Current groups: $user_groups" >&2
                exit 1
            elif [[ "$has_sudo" == "yes" ]]; then
                echo "Error: $username: Should not have sudo group" >&2
                echo "Current groups: $user_groups" >&2
                exit 1
            else
                echo "✓ $username: Has required groups (docker, family, no sudo)"
            fi
            
            # Check personal folder
            if [[ -d "/mnt/data/users/$username" ]]; then
                echo "✓ $username: Personal folder exists"
            else
                echo "Error: $username: Personal folder not found" >&2
                exit 1
            fi
            
            # Check Samba share
            if grep -q "^\[$username\]" /opt/homeserver/configs/samba/smb.conf; then
                echo "✓ $username: Samba share configured"
            else
                echo "Error: $username: Samba share not found" >&2
                exit 1
            fi
        done
        
        echo ""
        echo "✓ All verification checks passed"
        echo ""
    fi
fi

echo "✓ Task complete"
exit 0
