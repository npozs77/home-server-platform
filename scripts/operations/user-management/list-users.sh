#!/bin/bash
# User Provisioning Script: List Users
# Lists all provisioned users with details

set -euo pipefail

# Parse arguments
JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

# Get all users in family group
FAMILY_USERS=$(getent group family | cut -d: -f4 | tr ',' '\n' | sort)

if [[ -z "$FAMILY_USERS" ]]; then
    echo "No users found in family group"
    exit 0
fi

# Output format
if [[ "$JSON_OUTPUT" == true ]]; then
    echo "["
    FIRST=true
    for user in $FAMILY_USERS; do
        # Skip if user doesn't exist
        if ! id "$user" &>/dev/null; then
            continue
        fi
        
        # Determine role
        groups_output=$(groups "$user" | cut -d: -f2)
        if echo "$groups_output" | grep -q sudo; then
            role="admin"
        elif echo "$groups_output" | grep -q docker; then
            role="power"
        else
            role="standard"
        fi
        
        # Check SSH access
        ssh_access=false
        [[ -f "/home/$user/.ssh/authorized_keys" ]] && ssh_access=true
        
        # Get last login
        last_login=$(lastlog -u "$user" 2>/dev/null | tail -1 | awk '{print $4, $5, $6, $7}' | xargs)
        [[ "$last_login" == "** Never logged in **" ]] && last_login="Never"
        
        # Output JSON
        [[ "$FIRST" == false ]] && echo ","
        cat << EOF
  {
    "username": "$user",
    "role": "$role",
    "groups": [$(echo "$groups_output" | tr ' ' '\n' | sed 's/^/"/;s/$/"/' | paste -sd,)],
    "home_dir": "/home/$user",
    "personal_folder": "/mnt/data/users/$user",
    "samba_share": "\\\\\\\\192.168.1.2\\\\$user",
    "ssh_access": $ssh_access,
    "last_login": "$last_login"
  }
EOF
        FIRST=false
    done
    echo ""
    echo "]"
else
    # Table format
    printf "%-15s %-10s %-25s %-20s %-35s %-30s %-12s %-20s\n" \
        "USERNAME" "ROLE" "GROUPS" "HOME DIR" "PERSONAL FOLDER" "SAMBA SHARE" "SSH ACCESS" "LAST LOGIN"
    echo "-------------------------------------------------------------------------------------------------------------------------------------------------------------"
    
    for user in $FAMILY_USERS; do
        # Skip if user doesn't exist
        if ! id "$user" &>/dev/null; then
            continue
        fi
        
        # Determine role
        groups_output=$(groups "$user" | cut -d: -f2 | xargs)
        if echo "$groups_output" | grep -q sudo; then
            role="admin"
        elif echo "$groups_output" | grep -q docker; then
            role="power"
        else
            role="standard"
        fi
        
        # Check SSH access
        ssh_access="Disabled"
        [[ -f "/home/$user/.ssh/authorized_keys" ]] && ssh_access="Enabled"
        
        # Get last login
        last_login=$(lastlog -u "$user" 2>/dev/null | tail -1 | awk '{print $4, $5, $6, $7}' | xargs)
        [[ "$last_login" == "** Never logged in **" ]] && last_login="Never"
        
        # Output table row
        printf "%-15s %-10s %-25s %-20s %-35s %-30s %-12s %-20s\n" \
            "$user" \
            "$role" \
            "$groups_output" \
            "/home/$user" \
            "/mnt/data/users/$user" \
            "\\\\192.168.1.2\\$user" \
            "$ssh_access" \
            "$last_login"
    done
fi

exit 0
