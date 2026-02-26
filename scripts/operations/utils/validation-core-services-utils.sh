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
    [[ -d "${DATA_MOUNT}/users/${ADMIN_USER}" ]] && \
    [[ -d "${DATA_MOUNT}/users/${POWER_USER}" ]] && \
    [[ -d "${DATA_MOUNT}/users/${STANDARD_USER}" ]]
}

# Validate family folders exist
validate_family_folders() {
    [[ -d "${DATA_MOUNT}/family/Documents" ]] && \
    [[ -d "${DATA_MOUNT}/family/Photos" ]] && \
    [[ -d "${DATA_MOUNT}/family/Videos" ]] && \
    [[ -d "${DATA_MOUNT}/family/Projects" ]]
}

# Validate media folders exist
validate_media_folders() {
    [[ -d "${DATA_MOUNT}/media/Movies" ]] && \
    [[ -d "${DATA_MOUNT}/media/TV Shows" ]] && \
    [[ -d "${DATA_MOUNT}/media/Music" ]]
}

# Validate personal shares accessible
validate_personal_shares() {
    smbclient -L "${SERVER_IP}" -N 2>/dev/null | grep -q "${ADMIN_USER}" && \
    smbclient -L "${SERVER_IP}" -N 2>/dev/null | grep -q "${POWER_USER}" && \
    smbclient -L "${SERVER_IP}" -N 2>/dev/null | grep -q "${STANDARD_USER}"
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

# Validate Jellyfin container running
validate_jellyfin_container() {
    docker ps --filter "name=jellyfin" --filter "status=running" --format "{{.Names}}" | grep -q "jellyfin"
}

# Validate Jellyfin HTTPS access
validate_jellyfin_https() {
    curl -k -s -o /dev/null -w "%{http_code}" "https://media.${INTERNAL_SUBDOMAIN}" | grep -q "200"
}

# Validate Jellyfin can access media
validate_jellyfin_media_access() {
    docker exec jellyfin ls -la /media >/dev/null 2>&1
}

# Validate Jellyfin DNS record
validate_jellyfin_dns() {
    nslookup "media.${INTERNAL_SUBDOMAIN}" "${SERVER_IP}" 2>/dev/null | grep -q "${SERVER_IP}"
}

# Validate Git commit
validate_git_commit() {
    git -C /opt/homeserver status | grep -q "nothing to commit, working tree clean"
}
