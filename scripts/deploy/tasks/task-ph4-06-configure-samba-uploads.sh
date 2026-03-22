#!/bin/bash
# Task: Configure per-user Samba upload shares for Immich photo curation
# Phase: 4 (Photo Management)
# Number: 06
# Prerequisites:
#   - Phase 3 complete (Samba running with smb.conf)
#   - Task 6 complete (Immich users provisioned, UUIDs in services.env)
#   - IMMICH_UUID_{username} variables set in services.env
# Parameters:
#   --dry-run: Report planned actions without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Requirements: 36.1-36.10, 40.1-40.5

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utilities
source /opt/homeserver/scripts/operations/utils/output-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Configuration paths
SERVICES_ENV="/opt/homeserver/configs/services.env"
SMB_CONF="/opt/homeserver/configs/samba/smb.conf"
SAMBA_YML="/opt/homeserver/configs/docker-compose/samba.yml"
IMMICH_UPLOAD_DIR="/mnt/data/services/immich/upload/library"

# --- Validate Prerequisites ---

print_header "Task 4.6: Configure Per-User Samba Upload Shares"

for required_file in "$SERVICES_ENV" "$SMB_CONF"; do
    if [[ ! -f "$required_file" ]]; then
        print_error "Required file not found: $required_file"
        exit 3
    fi
done

# Source services.env to get IMMICH_UUID_* variables
set +u; source "$SERVICES_ENV"; set -u

# Collect IMMICH_UUID_* variables into arrays
declare -a USERNAMES=()
declare -A UUID_MAP=()

while IFS='=' read -r var_name var_value; do
    # Strip IMMICH_UUID_ prefix to get username
    username="${var_name#IMMICH_UUID_}"
    # Strip surrounding quotes from value
    uuid="${var_value//\"/}"
    if [[ -n "$uuid" ]]; then
        USERNAMES+=("$username")
        UUID_MAP["$username"]="$uuid"
    fi
done < <(grep '^IMMICH_UUID_' "$SERVICES_ENV" 2>/dev/null || true)

if [[ ${#USERNAMES[@]} -eq 0 ]]; then
    print_error "No IMMICH_UUID_* variables found in $SERVICES_ENV"
    print_info "Run task-ph4-05-provision-immich-users.sh first to populate UUIDs"
    exit 3
fi

print_info "Found ${#USERNAMES[@]} Immich user UUID(s): ${USERNAMES[*]}"

# --- Generate All-Uploads Share (Admin + Power Users) ---
# Admin and power users get a single read-only share covering all users' upload
# libraries for consolidated curation (browse all uploads, copy keepers to Media/Family)

# Read ADMIN_USER from foundation.env, POWER_USERS from services.env
FOUNDATION_ENV="/opt/homeserver/configs/foundation.env"
if [[ -f "$FOUNDATION_ENV" ]]; then
    set +u; source "$FOUNDATION_ENV"; set -u
fi
ADMIN="${ADMIN_USER:-}"
POWER="${POWER_USERS:-}"

# Build valid users list: admin + power users
ALL_UPLOADS_USERS=""
if [[ -n "$ADMIN" ]]; then
    ALL_UPLOADS_USERS="$ADMIN"
fi
for pu in $POWER; do
    [[ "$pu" == "$ADMIN" ]] && continue  # avoid duplicate
    ALL_UPLOADS_USERS="${ALL_UPLOADS_USERS:+$ALL_UPLOADS_USERS }${pu}"
done

if [[ -n "$ALL_UPLOADS_USERS" ]]; then
    if grep -q '^\[all-uploads\]' "$SMB_CONF" 2>/dev/null; then
        print_info "Share [all-uploads] already exists in smb.conf — skipping"
    elif [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would add [all-uploads] → ${IMMICH_UPLOAD_DIR} (users: ${ALL_UPLOADS_USERS})"
    else
        cat >> "$SMB_CONF" << EOFSMB

# Admin + Power Users: browse ALL users' Immich uploads for consolidated curation
[all-uploads]
   path = ${IMMICH_UPLOAD_DIR}
   browseable = yes
   read only = yes
   valid users = ${ALL_UPLOADS_USERS}
EOFSMB
        print_success "Added [all-uploads] → ${IMMICH_UPLOAD_DIR} (users: ${ALL_UPLOADS_USERS})"
    fi
else
    print_info "ADMIN_USER and POWER_USERS not set — skipping [all-uploads] share"
fi

# --- Generate Per-User Upload Share Entries ---

created=0
skipped=0

for username in "${USERNAMES[@]}"; do
    uuid="${UUID_MAP[$username]}"
    share_name="${username}-uploads"

    # Immich v2 storage labels:
    #   - Admin user → "admin" (literal string, NOT uuid or username)
    #   - Regular users → their UUID
    if [[ "$username" == "$ADMIN" ]]; then
        share_path="${IMMICH_UPLOAD_DIR}/admin"
    else
        share_path="${IMMICH_UPLOAD_DIR}/${uuid}"
    fi

    # Create directory if it doesn't exist yet (user hasn't uploaded photos)
    if [[ ! -d "$share_path" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY-RUN] Would create ${share_path}"
        else
            mkdir -p "$share_path"
            print_info "Created ${share_path} (user hasn't uploaded yet)"
        fi
    fi

    # Idempotency: check if share already exists in smb.conf
    if grep -q "^\[${share_name}\]" "$SMB_CONF" 2>/dev/null; then
        print_info "Share [${share_name}] already exists in smb.conf — skipping"
        skipped=$((skipped + 1))
        continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would add [${share_name}] → ${share_path}"
        print_info "[DRY-RUN]   read only = yes, valid users = ${username}, browseable = yes"
        created=$((created + 1))
        continue
    fi

    # Append share entry to smb.conf
    cat >> "$SMB_CONF" << EOFSMB

# Per-user Immich upload share (read-only for photo curation workflow)
[${share_name}]
   path = ${share_path}
   browseable = yes
   read only = yes
   valid users = ${username}
EOFSMB

    print_success "Added [${share_name}] → ${share_path}"
    created=$((created + 1))
done

# --- Verify Samba Container Has Access to Upload Directory ---
# The samba.yml mounts /mnt/data:/mnt/data which already includes
# /mnt/data/services/immich/upload/ — no additional volume mount needed.
# Verify this is the case.

print_info "Verifying Samba container volume mount covers Immich uploads..."
if [[ -f "$SAMBA_YML" ]]; then
    if grep -q '/mnt/data:/mnt/data' "$SAMBA_YML" || \
       grep -q '/mnt/data/services/immich/upload' "$SAMBA_YML"; then
        print_success "Samba container already has access to ${IMMICH_UPLOAD_DIR}"
    else
        print_info "Adding Immich upload volume mount to samba.yml..."
        if [[ "$DRY_RUN" == false ]]; then
            # Add read-only mount for Immich uploads to Samba container
            sed -i '/volumes:/a\      - /mnt/data/services/immich/upload:/mnt/data/services/immich/upload:ro  # Immich uploads for curation' "$SAMBA_YML"
            print_success "Added Immich upload volume mount to samba.yml"
        else
            print_info "[DRY-RUN] Would add Immich upload volume mount to samba.yml"
        fi
    fi
else
    print_error "samba.yml not found at $SAMBA_YML — cannot verify volume mount"
fi

# --- Reload Samba Configuration ---

if [[ "$DRY_RUN" == false && $created -gt 0 ]]; then
    print_info "Reloading Samba configuration..."
    if docker exec samba smbcontrol all reload-config &>/dev/null; then
        print_success "Samba configuration reloaded"
    else
        # Fallback: restart the container if smbcontrol not available
        print_info "smbcontrol not available, restarting Samba container..."
        if docker restart samba &>/dev/null; then
            print_success "Samba container restarted"
        else
            print_error "Failed to reload/restart Samba — reload manually"
        fi
    fi
elif [[ "$DRY_RUN" == true && $created -gt 0 ]]; then
    print_info "[DRY-RUN] Would reload Samba configuration"
fi

# --- Summary ---

echo ""
print_header "Samba Upload Share Summary"
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create: $created | Already exist: $skipped"
else
    print_info "Created: $created | Skipped (existing): $skipped"
fi

print_success "Task complete"
exit 0
