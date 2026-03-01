#!/bin/bash
# Validation Utilities: Core Services Layer
# Purpose: Validation functions for Samba, Jellyfin, and user provisioning
# Usage: Source this file in deployment scripts

# Validate Samba container running
validate_samba_container() {
    docker ps --filter "name=samba" --filter "status=running" --format "{{.Names}}" | grep -q "samba"
}

# Validate personal folders exist
validate_personal_folders() {
    local all_users="$ADMIN_USER $POWER_USERS $STANDARD_USERS"
    for user in $all_users; do
        if [[ ! -d "${DATA_MOUNT}/users/${user}" ]]; then
            echo "ERROR: Personal folder missing for user: $user"
            return 1
        fi
    done
    return 0
}

# Validate family folders exist
validate_family_folders() {
    [[ -d "${DATA_MOUNT}/family/Documents" ]] && \
    [[ -d "${DATA_MOUNT}/family/Photos" ]] && \
    [[ -d "${DATA_MOUNT}/family/Videos" ]] && \
    [[ -d "${DATA_MOUNT}/family/Projects" ]]
}

# Validate media folders exist with correct ownership
validate_media_folders() {
    # Check all subdirectories in /mnt/data/media/
    local all_valid=true
    for dir in ${DATA_MOUNT}/media/*/; do
        if [[ -d "$dir" ]]; then
            local owner=$(stat -c "%U" "$dir")
            local group=$(stat -c "%G" "$dir")
            local perms=$(stat -c "%a" "$dir")
            
            if [[ "$owner" != "media" ]] || [[ "$group" != "media" ]] || [[ "$perms" != "2775" ]]; then
                echo "ERROR: $dir has incorrect ownership/permissions ($owner:$group, $perms)"
                all_valid=false
            fi
        fi
    done
    
    [[ "$all_valid" == true ]]
}

# Validate personal shares accessible
validate_personal_shares() {
    local all_users="$ADMIN_USER $POWER_USERS $STANDARD_USERS"
    for user in $all_users; do
        if ! smbclient -L "${SERVER_IP}" -N 2>/dev/null | grep -q "${user}"; then
            echo "ERROR: Personal share missing for user: $user"
            return 1
        fi
    done
    return 0
}

# Validate Family share accessible
validate_family_share() {
    smbclient -L "${SERVER_IP}" -N 2>/dev/null | grep -q "Family"
}

# Validate Media share accessible
validate_media_share() {
    smbclient -L "${SERVER_IP}" -N 2>/dev/null | grep -q "Media"
}

# Validate recycle bin enabled
validate_recycle_bin() {
    grep -q "vfs objects = recycle" /opt/homeserver/configs/samba/smb.conf
}

# Validate user provisioning scripts exist
validate_user_scripts() {
    [[ -x /opt/homeserver/scripts/operations/user-management/create-user.sh ]] && \
    [[ -x /opt/homeserver/scripts/operations/user-management/update-user.sh ]] && \
    [[ -x /opt/homeserver/scripts/operations/user-management/delete-user.sh ]] && \
    [[ -x /opt/homeserver/scripts/operations/user-management/list-users.sh ]]
}

# Validate Jellyfin container running and has media group access
validate_jellyfin_container() {
    # Check container running
    if ! docker ps --filter "name=jellyfin" --filter "status=running" --format "{{.Names}}" | grep -q "jellyfin"; then
        echo "ERROR: Jellyfin container not running"
        return 1
    fi
    
    # Check container has media group access
    local media_gid=$(getent group media | cut -d: -f3)
    if [[ -z "$media_gid" ]]; then
        echo "ERROR: media group does not exist"
        return 1
    fi
    
    local container_groups=$(docker exec jellyfin id -G 2>/dev/null)
    if [[ ! "$container_groups" =~ $media_gid ]]; then
        echo "ERROR: Jellyfin container missing media group access (GID $media_gid)"
        return 1
    fi
    
    return 0
}

# Validate Jellyfin HTTPS access
validate_jellyfin_https() {
    local http_code=$(curl -k -s -o /dev/null -w "%{http_code}" "https://media.${INTERNAL_SUBDOMAIN}")
    [[ "$http_code" == "200" ]] || [[ "$http_code" == "302" ]]
}

# Validate Jellyfin can access all media folders with correct permissions
validate_jellyfin_media_access() {
    # Source Jellyfin validation utilities
    source /opt/homeserver/scripts/operations/utils/jellyfin-validation-utils.sh
    
    # Run comprehensive validation
    validate_all_jellyfin_libraries
}

# Validate Jellyfin DNS record
validate_jellyfin_dns() {
    nslookup "media.${INTERNAL_SUBDOMAIN}" "${SERVER_IP}" 2>/dev/null | grep -q "${SERVER_IP}"
}

# Validate Git commit
validate_git_commit() {
    git -C /opt/homeserver status | grep -q "nothing to commit, working tree clean"
}
