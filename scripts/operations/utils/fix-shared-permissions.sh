#!/bin/bash
# MUST be run as root/sudo
# Usage: sudo bash scripts/operations/utils/fix-shared-permissions.sh [--dry-run]
set -euo pipefail

# Fix permissions for shared folders (Family and Media)
# Ensures correct group ownership and permissions for existing files/directories

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/fix-shared-permissions.log"
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Usage: $0 [--dry-run]"
            exit 1
            ;;
    esac
done

# Logging function
function log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Validate directory exists
function validate_dir() {
    local dir=$1
    if [ ! -d "${dir}" ]; then
        log "ERROR: Directory ${dir} does not exist"
        return 1
    fi
    return 0
}

# Fix Family share permissions
function fix_family_permissions() {
    local family_dir="/mnt/data/family"
    
    log "=== Fixing Family Share Permissions ==="
    
    if ! validate_dir "${family_dir}"; then
        return 1
    fi
    
    # Count files and directories
    local total_dirs=$(find "${family_dir}" -type d | wc -l)
    local total_files=$(find "${family_dir}" -type f | wc -l)
    log "Found ${total_dirs} directories and ${total_files} files in ${family_dir}"
    
    # Check for incorrect permissions
    local incorrect_group=$(find "${family_dir}" -not -group family | wc -l)
    local incorrect_dir_perms=$(find "${family_dir}" -type d -not -perm 2775 | wc -l)
    local incorrect_file_perms=$(find "${family_dir}" -type f -not -perm 664 | wc -l)
    
    log "Issues found:"
    log "  - ${incorrect_group} items with incorrect group (should be family)"
    log "  - ${incorrect_dir_perms} directories with incorrect permissions (should be 2775)"
    log "  - ${incorrect_file_perms} files with incorrect permissions (should be 664)"
    
    if [ "${DRY_RUN}" = true ]; then
        log "DRY RUN: Would fix Family share permissions"
        return 0
    fi
    
    if [ "${incorrect_group}" -eq 0 ] && [ "${incorrect_dir_perms}" -eq 0 ] && [ "${incorrect_file_perms}" -eq 0 ]; then
        log "No fixes needed for Family share"
        return 0
    fi
    
    # Fix group ownership
    log "Changing group ownership to family..."
    chgrp -R family "${family_dir}"
    
    # Fix directory permissions (setgid bit)
    log "Applying setgid bit (2775) to directories..."
    find "${family_dir}" -type d -exec chmod 2775 {} +
    
    # Fix file permissions
    log "Setting file permissions to 664..."
    find "${family_dir}" -type f -exec chmod 664 {} +
    
    log "Family share permissions fixed"
}

# Fix Media share permissions
function fix_media_permissions() {
    local media_dir="/mnt/data/media"
    
    log "=== Fixing Media Share Permissions ==="
    
    if ! validate_dir "${media_dir}"; then
        return 1
    fi
    
    # Verify media user and group exist
    if ! getent passwd media > /dev/null; then
        log "ERROR: media user does not exist"
        return 1
    fi
    
    if ! getent group media > /dev/null; then
        log "ERROR: media group does not exist"
        return 1
    fi
    
    # Count files and directories
    local total_dirs=$(find "${media_dir}" -type d | wc -l)
    local total_files=$(find "${media_dir}" -type f | wc -l)
    log "Found ${total_dirs} directories and ${total_files} files in ${media_dir}"
    
    # Check for incorrect permissions
    local incorrect_group=$(find "${media_dir}" -not -group media | wc -l)
    local incorrect_dir_perms=$(find "${media_dir}" -type d -not -perm 2775 | wc -l)
    local incorrect_file_perms=$(find "${media_dir}" -type f -not -perm 664 | wc -l)
    
    log "Issues found:"
    log "  - ${incorrect_group} items with incorrect group (should be media)"
    log "  - ${incorrect_dir_perms} directories with incorrect permissions (should be 2775)"
    log "  - ${incorrect_file_perms} files with incorrect permissions (should be 664)"
    
    if [ "${DRY_RUN}" = true ]; then
        log "DRY RUN: Would fix Media share permissions"
        return 0
    fi
    
    if [ "${incorrect_group}" -eq 0 ] && [ "${incorrect_dir_perms}" -eq 0 ] && [ "${incorrect_file_perms}" -eq 0 ]; then
        log "No fixes needed for Media share"
        return 0
    fi
    
    # Fix group ownership
    log "Changing group ownership to media..."
    chgrp -R media "${media_dir}"
    
    # Fix directory permissions (setgid bit)
    log "Applying setgid bit (2775) to directories..."
    find "${media_dir}" -type d -exec chmod 2775 {} +
    
    # Fix file permissions
    log "Setting file permissions to 664..."
    find "${media_dir}" -type f -exec chmod 664 {} +
    
    log "Media share permissions fixed"
}

# Verify fixes
function verify_fixes() {
    log "=== Verifying Fixes ==="
    
    local family_dir="/mnt/data/family"
    local media_dir="/mnt/data/media"
    local all_good=true
    
    # Verify Family share
    if [ -d "${family_dir}" ]; then
        local family_incorrect=$(find "${family_dir}" -not -group family -o -type d -not -perm 2775 -o -type f -not -perm 664 | wc -l)
        if [ "${family_incorrect}" -gt 0 ]; then
            log "WARNING: ${family_incorrect} items in Family share still have incorrect permissions"
            all_good=false
        else
            log "SUCCESS: All Family share permissions correct"
        fi
    fi
    
    # Verify Media share
    if [ -d "${media_dir}" ]; then
        local media_incorrect=$(find "${media_dir}" -not -group media -o -type d -not -perm 2775 -o -type f -not -perm 664 | wc -l)
        if [ "${media_incorrect}" -gt 0 ]; then
            log "WARNING: ${media_incorrect} items in Media share still have incorrect permissions"
            all_good=false
        else
            log "SUCCESS: All Media share permissions correct"
        fi
    fi
    
    if [ "${all_good}" = true ]; then
        log "All permissions verified successfully"
    else
        log "Some permissions may need manual correction"
    fi
}

# Main execution
function main() {
    log "Starting shared permissions fix..."
    log "Dry run: ${DRY_RUN}"
    
    # Fix Family share
    if ! fix_family_permissions; then
        log "ERROR: Failed to fix Family share permissions"
    fi
    
    # Fix Media share
    if ! fix_media_permissions; then
        log "ERROR: Failed to fix Media share permissions"
    fi
    
    # Verify fixes (skip in dry-run)
    if [ "${DRY_RUN}" = false ]; then
        verify_fixes
    fi
    
    log "Shared permissions fix complete"
}

# Execute
main
