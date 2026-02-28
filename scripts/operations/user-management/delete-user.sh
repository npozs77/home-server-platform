#!/bin/bash
# User Provisioning Script: Delete User
# Deletes user and optionally archives personal data

set -euo pipefail

# Configuration
LOG_FILE="/var/log/user-provisioning.log"
SAMBA_CONTAINER="samba"
SMB_CONF="/opt/homeserver/configs/samba/smb.conf"

# Functions
function log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
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
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <username> [--keep-data]" >&2
    echo "  --keep-data: Archive personal data instead of deleting" >&2
    exit 1
fi

USERNAME="$1"
KEEP_DATA=false
[[ "${2:-}" == "--keep-data" ]] && KEEP_DATA=true

# Validate user exists
if ! user_exists "$USERNAME"; then
    echo "Error: User $USERNAME does not exist" >&2
    exit 2
fi

# Confirmation
echo "WARNING: This will delete user $USERNAME and all associated resources."
if [[ "$KEEP_DATA" == true ]]; then
    echo "Personal data will be archived."
else
    echo "Personal data will be PERMANENTLY DELETED."
fi
echo ""
echo "Type 'yes' to confirm:"
read -r confirmation

if [[ "$confirmation" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

log_message "Deleting user: $USERNAME (keep_data: $KEEP_DATA)"

# Remove Samba user
echo "Removing Samba user..."
docker exec "$SAMBA_CONTAINER" smbpasswd -x "$USERNAME" 2>/dev/null || true
log_message "Removed Samba user: $USERNAME"

# Remove personal share from Samba configuration
echo "Removing personal share from Samba configuration..."
sed -i "/^\[$USERNAME\]/,/^$/d" "$SMB_CONF"

# Reload Samba configuration
docker exec "$SAMBA_CONTAINER" smbcontrol all reload-config &>/dev/null || {
    log_message "WARNING: Failed to reload Samba configuration"
}

# Handle personal data
PERSONAL_DIR="/mnt/data/users/$USERNAME"
if [[ -d "$PERSONAL_DIR" ]]; then
    if [[ "$KEEP_DATA" == true ]]; then
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        ARCHIVE_DIR="/mnt/data/users/${USERNAME}.deleted.${TIMESTAMP}"
        echo "Archiving personal data to: $ARCHIVE_DIR"
        mv "$PERSONAL_DIR" "$ARCHIVE_DIR"
        chown -R root:root "$ARCHIVE_DIR"
        chmod 700 "$ARCHIVE_DIR"
        log_message "Archived personal data to: $ARCHIVE_DIR"
        echo "✓ Personal data archived"
    else
        echo "Deleting personal data..."
        rm -rf "$PERSONAL_DIR"
        log_message "Deleted personal data: $PERSONAL_DIR"
        echo "✓ Personal data deleted"
    fi
fi

# Remove Linux user
echo "Removing Linux user..."
userdel -r "$USERNAME" 2>/dev/null || userdel "$USERNAME" 2>/dev/null || true
log_message "Removed Linux user: $USERNAME"

echo ""
echo "✓ User $USERNAME deleted successfully"
log_message "Successfully deleted user: $USERNAME"
exit 0
