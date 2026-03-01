#!/bin/bash
# Jellyfin Validation Utilities
# Provides functions to validate Jellyfin library configuration
# Usage: source /opt/homeserver/scripts/operations/utils/jellyfin-validation-utils.sh

# Validate Jellyfin library folder exists and has correct permissions
# Args:
#   $1: Library path (e.g., /mnt/data/media/Movies)
#   $2: Expected owner (e.g., media)
#   $3: Expected group (e.g., media)
#   $4: Expected permissions (e.g., 2775)
# Returns:
#   0 if valid, 1 if invalid
function validate_jellyfin_library_folder() {
    local library_path="$1"
    local expected_owner="$2"
    local expected_group="$3"
    local expected_perms="$4"
    
    # Check folder exists
    if [[ ! -d "$library_path" ]]; then
        echo "ERROR: Library folder does not exist: $library_path"
        return 1
    fi
    
    # Check ownership
    local actual_owner=$(stat -c "%U" "$library_path")
    local actual_group=$(stat -c "%G" "$library_path")
    if [[ "$actual_owner" != "$expected_owner" ]] || [[ "$actual_group" != "$expected_group" ]]; then
        echo "ERROR: Library folder has incorrect ownership: $library_path"
        echo "  Expected: $expected_owner:$expected_group"
        echo "  Actual: $actual_owner:$actual_group"
        return 1
    fi
    
    # Check permissions
    local actual_perms=$(stat -c "%a" "$library_path")
    if [[ "$actual_perms" != "$expected_perms" ]]; then
        echo "ERROR: Library folder has incorrect permissions: $library_path"
        echo "  Expected: $expected_perms"
        echo "  Actual: $actual_perms"
        return 1
    fi
    
    echo "OK: $library_path ($actual_owner:$actual_group, $actual_perms)"
    return 0
}

# Validate Jellyfin container has media group access
# Returns:
#   0 if valid, 1 if invalid
function validate_jellyfin_media_group_access() {
    # Check Jellyfin container is running
    if ! docker ps --format '{{.Names}}' | grep -q '^jellyfin$'; then
        echo "ERROR: Jellyfin container is not running"
        return 1
    fi
    
    # Get media group GID
    local media_gid=$(getent group media | cut -d: -f3)
    if [[ -z "$media_gid" ]]; then
        echo "ERROR: media group does not exist"
        return 1
    fi
    
    # Check container has media group
    local container_groups=$(docker exec jellyfin id -G 2>/dev/null)
    if [[ ! "$container_groups" =~ $media_gid ]]; then
        echo "ERROR: Jellyfin container does not have media group access (GID $media_gid)"
        echo "  Container groups: $container_groups"
        return 1
    fi
    
    echo "OK: Jellyfin container has media group access (GID $media_gid)"
    return 0
}

# Validate Jellyfin can read media directory
# Returns:
#   0 if valid, 1 if invalid
function validate_jellyfin_can_read_media() {
    # Check Jellyfin container is running
    if ! docker ps --format '{{.Names}}' | grep -q '^jellyfin$'; then
        echo "ERROR: Jellyfin container is not running"
        return 1
    fi
    
    # Try to list /media directory in container
    if ! docker exec jellyfin ls -la /media >/dev/null 2>&1; then
        echo "ERROR: Jellyfin container cannot read /media directory"
        return 1
    fi
    
    # Try to list subdirectories
    local subdirs=("Movies" "TV Shows" "Music")
    for subdir in "${subdirs[@]}"; do
        if ! docker exec jellyfin ls -la "/media/$subdir" >/dev/null 2>&1; then
            echo "ERROR: Jellyfin container cannot read /media/$subdir"
            return 1
        fi
    done
    
    echo "OK: Jellyfin container can read all media directories"
    return 0
}

# Validate all Jellyfin library folders
# Returns:
#   0 if all valid, 1 if any invalid
function validate_all_jellyfin_libraries() {
    local all_valid=true
    
    echo "Validating Jellyfin library folders..."
    
    # Dynamically discover and validate all subdirectories in /mnt/data/media/
    for dir in /mnt/data/media/*/; do
        if [[ -d "$dir" ]]; then
            # Remove trailing slash
            dir="${dir%/}"
            validate_jellyfin_library_folder "$dir" "media" "media" "2775" || all_valid=false
        fi
    done
    
    # Validate Jellyfin container access
    validate_jellyfin_media_group_access || all_valid=false
    validate_jellyfin_can_read_media || all_valid=false
    
    if [[ "$all_valid" == true ]]; then
        echo "All Jellyfin library validations passed"
        return 0
    else
        echo "Some Jellyfin library validations failed"
        return 1
    fi
}
