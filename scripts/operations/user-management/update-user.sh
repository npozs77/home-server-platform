#!/bin/bash
# User Provisioning Script: Update User
# Updates user role, SSH key, or Samba password

set -euo pipefail

# Configuration
LOG_FILE="/var/log/user-provisioning.log"
SAMBA_CONTAINER="samba"

# Functions
function log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

function user_exists() {
    local username="$1"
    id "$username" &>/dev/null
}

function validate_role() {
    local role="$1"
    if [[ ! "$role" =~ ^(admin|power|standard)$ ]]; then
        echo "Error: Invalid role. Must be one of: admin, power, standard" >&2
        return 1
    fi
    return 0
}

# Main
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Parse arguments
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <username> <update-type> [value]" >&2
    echo "  update-type: role, ssh-key, or samba-password" >&2
    echo "  value: new role or SSH key file path (for role/ssh-key updates)" >&2
    exit 1
fi

USERNAME="$1"
UPDATE_TYPE="$2"
VALUE="${3:-}"

# Validate user exists
if ! user_exists "$USERNAME"; then
    echo "Error: User $USERNAME does not exist" >&2
    exit 2
fi

# Process update
case "$UPDATE_TYPE" in
    role)
        if [[ -z "$VALUE" ]]; then
            echo "Error: New role required" >&2
            exit 1
        fi
        
        validate_role "$VALUE" || exit 1
        NEW_ROLE="$VALUE"
        
        echo "Updating role for $USERNAME to $NEW_ROLE..."
        
        # Remove from all role-specific groups
        gpasswd -d "$USERNAME" sudo 2>/dev/null || true
        gpasswd -d "$USERNAME" docker 2>/dev/null || true
        
        # Add to new role-specific groups
        case "$NEW_ROLE" in
            admin)
                usermod -aG sudo,docker "$USERNAME"
                ;;
            power)
                usermod -aG docker "$USERNAME"
                ;;
            standard)
                # Remove SSH access for standard users
                rm -f "/home/$USERNAME/.ssh/authorized_keys"
                ;;
        esac
        
        log_message "Updated role for $USERNAME to $NEW_ROLE"
        echo "✓ Role updated successfully"
        ;;
        
    ssh-key)
        if [[ -z "$VALUE" ]]; then
            echo "Error: SSH key file path required" >&2
            exit 1
        fi
        
        if [[ ! -f "$VALUE" ]]; then
            echo "Error: SSH key file not found: $VALUE" >&2
            exit 1
        fi
        
        # Validate SSH key format
        if ! grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) ' "$VALUE"; then
            echo "Error: Invalid SSH key format" >&2
            exit 1
        fi
        
        echo "Updating SSH key for $USERNAME..."
        
        # Backup existing key
        SSH_DIR="/home/$USERNAME/.ssh"
        if [[ -f "$SSH_DIR/authorized_keys" ]]; then
            cp "$SSH_DIR/authorized_keys" "$SSH_DIR/authorized_keys.backup.$(date +%Y%m%d_%H%M%S)"
        fi
        
        # Update key
        mkdir -p "$SSH_DIR"
        cat "$VALUE" > "$SSH_DIR/authorized_keys"
        chmod 700 "$SSH_DIR"
        chmod 600 "$SSH_DIR/authorized_keys"
        chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
        
        log_message "Updated SSH key for $USERNAME"
        echo "✓ SSH key updated successfully"
        ;;
        
    samba-password)
        echo "Updating Samba password for $USERNAME..."
        echo "Enter new Samba password (min 8 characters):"
        
        if ! docker exec -i "$SAMBA_CONTAINER" smbpasswd "$USERNAME"; then
            echo "Error: Failed to update Samba password" >&2
            exit 3
        fi
        
        log_message "Updated Samba password for $USERNAME"
        echo "✓ Samba password updated successfully"
        ;;
        
    *)
        echo "Error: Invalid update type. Must be one of: role, ssh-key, samba-password" >&2
        exit 1
        ;;
esac

exit 0
