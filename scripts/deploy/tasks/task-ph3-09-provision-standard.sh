#!/bin/bash
# Task: Provision Standard Users
# Phase: 3 (Core Services)
# Number: 09
#
# Prerequisites:
#   - create-user.sh script exists and tested
#   - STANDARD_USERS variable exported by orchestration script
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
# Environment Variables Required:
#   STANDARD_USERS: Space-separated list of standard user usernames (exported by orchestration script)
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

# Validate required variables
if [[ -z "${STANDARD_USERS:-}" ]]; then
    echo "Warning: STANDARD_USERS variable not set or empty"
    echo "No standard users to provision"
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
while IFS='=' read -r varname _; do
    export "${varname?}"
done < <(grep "^SAMBA_PASSWORD_" "$SECRETS_ENV")

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would provision standard users: $STANDARD_USERS"
    for user in $STANDARD_USERS; do
        echo "[DRY-RUN] Would run: $CREATE_USER_SCRIPT $user standard"
    done
    echo "[DRY-RUN] Would verify all standard users created with correct permissions"
    echo "[DRY-RUN] Would verify NO SSH access configured"
else
    echo ""
    echo "========================================"
    echo "Provisioning Standard Users"
    echo "========================================"
    echo ""
    
    # Check if create-user.sh exists
    if [[ ! -f "$CREATE_USER_SCRIPT" ]]; then
        echo "Error: create-user.sh script not found: $CREATE_USER_SCRIPT" >&2
        echo "Run Task 4.1 first to create user provisioning scripts" >&2
        exit 1
    fi
    
    # Convert space-separated list to array
    read -ra STANDARD_USER_ARRAY <<< "$STANDARD_USERS"
    
    # Count users
    USER_COUNT=${#STANDARD_USER_ARRAY[@]}
    echo "Provisioning $USER_COUNT standard user(s)"
    echo "Standard users: Samba and personal folders only (NO SSH, NO docker, NO sudo)"
    echo ""
    
    # Track success/failure
    SUCCESS_COUNT=0
    FAILURE_COUNT=0
    SKIPPED_COUNT=0
    
    # Provision each standard user
    for i in "${!STANDARD_USER_ARRAY[@]}"; do
        username="${STANDARD_USER_ARRAY[$i]}"
        
        echo "[$((i+1))/$USER_COUNT] Provisioning standard user: $username"
        echo "Role: standard (Samba, personal folders only)"
        
        # Check if user already exists (create-user.sh is idempotent and will update)
        if id "$username" &>/dev/null; then
            echo "Note: User $username already exists - will update permissions and groups"
        fi
        
        echo ""
        
        # Run create-user.sh (no SSH key for standard users)
        if "$CREATE_USER_SCRIPT" "$username" standard; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "Error: Failed to provision standard user: $username" >&2
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
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
        echo "Error: Some standard users failed to provision" >&2
        exit 1
    fi
    
    # Verify all standard users
    if [[ $SUCCESS_COUNT -gt 0 ]]; then
        echo "Verifying standard users..."
        
        for username in "${STANDARD_USER_ARRAY[@]}"; do
            # Skip if user was skipped
            if ! id "$username" &>/dev/null; then
                continue
            fi
            
            # Check groups (must have family - may have others, must NOT have sudo or docker)
            user_groups=$(groups "$username" | cut -d: -f2)
            echo "$user_groups" | grep -q family || {
                echo "Error: $username: Missing family group" >&2
                echo "Current groups: $user_groups" >&2
                exit 1
            }
            has_sudo=$(echo "$user_groups" | grep -q sudo && echo "yes" || echo "no")
            has_docker=$(echo "$user_groups" | grep -q docker && echo "yes" || echo "no")
            
            if [[ "$has_sudo" == "yes" ]] || [[ "$has_docker" == "yes" ]]; then
                echo "Error: $username: Should not have sudo or docker groups" >&2
                echo "Current groups: $user_groups" >&2
                exit 1
            else
                echo "✓ $username: Has required groups (family only, no sudo, no docker)"
            fi
            
            # Check NO SSH access
            if [[ ! -f "/home/$username/.ssh/authorized_keys" ]]; then
                echo "✓ $username: No SSH access (correct for standard user)"
            else
                echo "Error: $username: SSH access configured (should not have SSH)" >&2
                exit 1
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
