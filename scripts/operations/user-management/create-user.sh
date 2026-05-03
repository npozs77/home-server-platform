#!/bin/bash
# User Provisioning Script: Create User
# Creates Linux user, Samba user, personal folders, and Samba share

set -euo pipefail

# Configuration
LOG_FILE="/var/log/user-provisioning.log"
SAMBA_CONTAINER="samba"
SMB_CONF="/opt/homeserver/configs/samba/smb.conf"

# Functions
function log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

function validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-z][a-z0-9_]*$ ]]; then
        echo "Error: Invalid username format. Must be lowercase alphanumeric with underscores, starting with letter" >&2
        return 1
    fi
    return 0
}

function validate_role() {
    local role="$1"
    if [[ ! "$role" =~ ^(admin|power|standard)$ ]]; then
        echo "Error: Invalid role. Must be one of: admin, power, standard" >&2
        return 1
    fi
    return 0
}

function user_exists() {
    local username="$1"
    id "$username" &>/dev/null
}

# Main
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Parse arguments
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <username> <role> [ssh-public-key-file]" >&2
    echo "  role: admin, power, or standard" >&2
    echo "  ssh-public-key-file: Optional path to SSH public key" >&2
    exit 1
fi

USERNAME="$1"
ROLE="$2"
SSH_KEY_FILE="${3:-}"

# Validate inputs
validate_username "$USERNAME" || exit 1
validate_role "$ROLE" || exit 1

# Check if user exists - if so, make script idempotent (fix permissions/groups)
if user_exists "$USERNAME"; then
    echo "User $USERNAME already exists - updating permissions and groups..."
    log_message "User $USERNAME exists - running idempotent updates"
    USER_EXISTS=true
    
    # Update GECOS field for existing users (idempotent)
    usermod -c "$USERNAME" "$USERNAME"
else
    echo "Creating new user $USERNAME..."
    log_message "Creating user: $USERNAME (role: $ROLE)"
    USER_EXISTS=false
fi

if [[ -n "$SSH_KEY_FILE" ]] && [[ ! -f "$SSH_KEY_FILE" ]]; then
    echo "Error: SSH key file not found: $SSH_KEY_FILE" >&2
    exit 1
fi

# Validate SSH key format if provided
if [[ -n "$SSH_KEY_FILE" ]]; then
    if ! grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) ' "$SSH_KEY_FILE"; then
        echo "Error: Invalid SSH key format in $SSH_KEY_FILE" >&2
        exit 4
    fi
fi

# Create Linux user (skip if exists)
if [[ "$USER_EXISTS" == false ]]; then
    echo "Creating Linux user..."
    useradd -m -s /bin/bash -c "$USERNAME" -G family "$USERNAME"

    # Generate random password and expire it
    PASSWORD=$(openssl rand -base64 32)
    echo "$USERNAME:$PASSWORD" | chpasswd
    passwd -e "$USERNAME" &>/dev/null
fi

# Add to role-specific groups (idempotent - always update)
echo "Updating groups for role: $ROLE..."

# Ensure user is in family group (for both new and existing users)
usermod -aG family "$USERNAME"

case "$ROLE" in
    admin)
        usermod -aG sudo,docker "$USERNAME"
        log_message "Updated $USERNAME groups: family, sudo, docker"
        ;;
    power)
        # Remove from sudo if downgrading
        gpasswd -d "$USERNAME" sudo 2>/dev/null || true
        usermod -aG docker "$USERNAME"
        log_message "Updated $USERNAME groups: family, docker"
        ;;
    standard)
        # Remove from sudo and docker if downgrading
        gpasswd -d "$USERNAME" sudo 2>/dev/null || true
        gpasswd -d "$USERNAME" docker 2>/dev/null || true
        log_message "Updated $USERNAME groups: family"
        ;;
esac

# Create/update Samba user (idempotent)
# Check if Samba user actually exists in container (not just Linux user)
SAMBA_USER_EXISTS=false
if docker exec "$SAMBA_CONTAINER" pdbedit -L | grep -q "^${USERNAME}:"; then
    SAMBA_USER_EXISTS=true
fi

if [[ "$SAMBA_USER_EXISTS" == false ]]; then
    echo "Creating Samba user..."
    # Create Unix user inside container (required for smbpasswd)
    docker exec "$SAMBA_CONTAINER" useradd -M -s /usr/sbin/nologin "$USERNAME" 2>/dev/null || true
    
    # Get password from environment variable SAMBA_PASSWORD_<username>
    PASSWORD_VAR="SAMBA_PASSWORD_${USERNAME}"
    SAMBA_PASSWORD="${!PASSWORD_VAR:-}"
    
    if [[ -z "$SAMBA_PASSWORD" ]]; then
        echo "Error: Samba password not found in environment" >&2
        echo "Expected variable: $PASSWORD_VAR" >&2
        echo "Ensure secrets.env is loaded with: source /opt/homeserver/configs/secrets.env" >&2
        if [[ "$USER_EXISTS" == false ]]; then
            userdel -r "$USERNAME" 2>/dev/null || true
        fi
        exit 3
    fi
    
    # Set password non-interactively
    if ! echo -e "$SAMBA_PASSWORD\n$SAMBA_PASSWORD" | docker exec -i "$SAMBA_CONTAINER" smbpasswd -a -s "$USERNAME"; then
        echo "Error: Failed to create Samba user" >&2
        if [[ "$USER_EXISTS" == false ]]; then
            userdel -r "$USERNAME" 2>/dev/null || true
        fi
        exit 3
    fi
    docker exec "$SAMBA_CONTAINER" smbpasswd -e "$USERNAME" &>/dev/null
    log_message "Created Samba user: $USERNAME"
else
    echo "Samba user already exists in container - skipping password setup"
    echo "To reset password, run: docker exec -it samba smbpasswd $USERNAME"
fi

# Create personal folders
echo "Creating personal folders..."
PERSONAL_DIR="/mnt/data/users/$USERNAME"
mkdir -p "$PERSONAL_DIR"/{Documents,Photos,Videos,Music}
mkdir -p "$PERSONAL_DIR/.recycle/$USERNAME"

# CRITICAL: Group must be 'family' so Samba (running with PGID=family) can access
# Always fix ownership and permissions (idempotent)
chown -R "$USERNAME:family" "$PERSONAL_DIR"
chmod 770 "$PERSONAL_DIR"
chmod 770 "$PERSONAL_DIR"/{Documents,Photos,Videos,Music}
chmod 770 "$PERSONAL_DIR/.recycle/$USERNAME"

if [[ "$USER_EXISTS" == false ]]; then
    log_message "Created personal folders: $PERSONAL_DIR"
else
    log_message "Fixed permissions for personal folders: $PERSONAL_DIR"
fi

# Configure SSH access (if key provided and role allows)
if [[ -n "$SSH_KEY_FILE" ]] && [[ "$ROLE" != "standard" ]]; then
    echo "Configuring SSH access..."
    SSH_DIR="/home/$USERNAME/.ssh"
    mkdir -p "$SSH_DIR"
    cat "$SSH_KEY_FILE" > "$SSH_DIR/authorized_keys"
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_DIR/authorized_keys"
    chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
    log_message "Configured SSH access for $USERNAME"
    SSH_STATUS="Enabled"
elif [[ "$ROLE" == "standard" ]] && [[ -n "$SSH_KEY_FILE" ]]; then
    echo "Note: SSH key provided but ignored (standard users cannot have SSH access)"
    SSH_STATUS="Disabled (standard user)"
else
    SSH_STATUS="Disabled"
fi

# Add personal share to Samba configuration (idempotent - check if exists first)
if grep -q "^\[$USERNAME\]" "$SMB_CONF" 2>/dev/null; then
    echo "Personal share already exists in smb.conf - updating permissions..."
    # Update existing share permissions (0700 → 0770)
    sed -i "/^\[$USERNAME\]/,/^$/s/create mask = 0700/create mask = 0770/" "$SMB_CONF"
    sed -i "/^\[$USERNAME\]/,/^$/s/directory mask = 0700/directory mask = 0770/" "$SMB_CONF"
    log_message "Updated personal share permissions for $USERNAME"
else
    echo "Adding personal share to Samba configuration..."
    cat >> "$SMB_CONF" << EOF

[$USERNAME]
   path = /mnt/data/users/$USERNAME
   browseable = yes
   read only = no
   valid users = $USERNAME
   write list = $USERNAME
   create mask = 0770
   directory mask = 0770
   vfs objects = recycle
   recycle:repository = .recycle/%U
EOF
    log_message "Added personal share for $USERNAME"
fi

# Reload Samba configuration
echo "Reloading Samba configuration..."
if ! docker exec "$SAMBA_CONTAINER" smbcontrol all reload-config &>/dev/null; then
    echo "Error: Failed to reload Samba configuration" >&2
    log_message "ERROR: Failed to reload Samba configuration for $USERNAME"
    exit 3
fi

# Output summary
echo ""
echo "========================================"
if [[ "$USER_EXISTS" == false ]]; then
    echo "User Created Successfully"
else
    echo "User Updated Successfully"
fi
echo "========================================"
echo ""
echo "  Username: $USERNAME"
echo "  Role: $ROLE"
echo "  Groups: $(groups "$USERNAME" | cut -d: -f2)"
echo "  Home Directory: /home/$USERNAME"
echo "  Personal Folder: $PERSONAL_DIR"
printf '  Samba Share: \\\\192.168.1.2\\%s\n' "$USERNAME"
echo "  SSH Access: $SSH_STATUS"
echo ""

if [[ "$USER_EXISTS" == false ]]; then
    log_message "Successfully created user: $USERNAME"
else
    log_message "Successfully updated user: $USERNAME"
fi
exit 0
