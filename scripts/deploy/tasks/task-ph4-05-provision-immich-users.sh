#!/bin/bash
# Task: Automated Immich User Provisioning via API
# Phase: 4 (Photo Management)
# Number: 05
# Prerequisites:
#   - Immich stack running and healthy (Checkpoint 5 complete)
#   - Admin setup wizard completed (Task 4.4)
#   - IMMICH_API_KEY stored in secrets.env
#   - Family users defined in services.env (POWER_USERS, STANDARD_USERS)
#   - ADMIN_USER and ADMIN_EMAIL defined in foundation.env
# Parameters:
#   --dry-run: Report planned actions without API calls
# Exit Codes:
#   0 = Success
#   1 = Failure (one or more users failed)
#   3 = Configuration error (missing prerequisites)
# Requirements: 33.1-33.10, 40.1-40.6, 42.1-42.11

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
FOUNDATION_ENV="/opt/homeserver/configs/foundation.env"
SERVICES_ENV="/opt/homeserver/configs/services.env"
SECRETS_ENV="/opt/homeserver/configs/secrets.env"

# Source configuration files
print_info "Loading configuration..."
for envfile in "$FOUNDATION_ENV" "$SERVICES_ENV" "$SECRETS_ENV"; do
    if [[ ! -f "$envfile" ]]; then
        print_error "Configuration file not found: $envfile"
        exit 3
    fi
    set +u; source "$envfile"; set -u
done

# Validate required variables
for var in ADMIN_USER ADMIN_EMAIL IMMICH_API_KEY IMMICH_DOMAIN; do
    if [[ -z "${!var:-}" ]]; then
        print_error "Required variable not set: $var"
        exit 3
    fi
done

# Determine API URL: prefer internal localhost (script runs on server with sudo),
# fall back to HTTPS domain if localhost unreachable
IMMICH_API_URL_INTERNAL="http://localhost:${IMMICH_PORT:-2283}/api"
IMMICH_API_URL_EXTERNAL="https://${IMMICH_DOMAIN}/api"
IMMICH_API_URL="$IMMICH_API_URL_INTERNAL"

# --- Helper Functions ---

# Generate random 16-character password
generate_password() {
    tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 16 || true
}

# Get email for a user (admin uses real email, others use placeholder)
get_user_email() {
    local username="$1"
    if [[ "$username" == "$ADMIN_USER" ]]; then
        echo "$ADMIN_EMAIL"
    else
        echo "${username}@homeserver"
    fi
}

# Get password for a user (from secrets.env or generate new)
get_user_password() {
    local username="$1"
    local var_name="IMMICH_PASSWORD_${username}"
    if [[ -n "${!var_name:-}" ]]; then
        echo "${!var_name}"
    else
        local new_pass
        new_pass=$(generate_password)
        # Write generated password to secrets.env
        if [[ "$DRY_RUN" == false ]]; then
            echo "${var_name}=\"${new_pass}\"" >> "$SECRETS_ENV"
        fi
        echo "$new_pass"
    fi
}

# Enable all user features via preferences API (PUT, not PATCH)
set_user_preferences() {
    local uuid="$1"
    local username="$2"
    local prefs_json='{"folders":{"enabled":true,"sidebarWeb":true},"memories":{"enabled":true},"people":{"enabled":true,"sidebarWeb":true},"tags":{"enabled":true,"sidebarWeb":true},"ratings":{"enabled":true},"sharedLinks":{"enabled":true,"sidebarWeb":true},"cast":{"gCastEnabled":true},"emailNotifications":{"enabled":true,"albumInvite":true,"albumUpdate":true}}'

    local prefs_response
    prefs_response=$(curl -s --max-time 10 \
        -H "x-api-key: ${IMMICH_API_KEY}" \
        -H "Content-Type: application/json" \
        -X PUT "${IMMICH_API_URL}/admin/users/${uuid}/preferences" \
        -d "$prefs_json" 2>&1)

    if echo "$prefs_response" | jq -e '.folders' &>/dev/null; then
        print_success "Enabled all features for $username"
    else
        print_error "Failed to set preferences for $username: $prefs_response"
    fi
}

# Write or update IMMICH_UUID_{username} in services.env
write_uuid_to_services_env() {
    local username="$1"
    local uuid="$2"
    local var_name="IMMICH_UUID_${username}"

    if grep -q "^${var_name}=" "$SERVICES_ENV" 2>/dev/null; then
        # Update existing entry
        sed -i "s|^${var_name}=.*|${var_name}=\"${uuid}\"|" "$SERVICES_ENV"
    else
        echo "${var_name}=\"${uuid}\"" >> "$SERVICES_ENV"
    fi
}

# --- Validate Immich API Reachability ---

print_info "Checking Immich API reachability..."
if [[ "$DRY_RUN" == false ]]; then
    # Try internal URL first (localhost), fall back to external (HTTPS domain)
    ping_response=$(curl -s --max-time 5 "${IMMICH_API_URL_INTERNAL}/server/ping" 2>&1) || true
    if echo "$ping_response" | grep -q "pong"; then
        IMMICH_API_URL="$IMMICH_API_URL_INTERNAL"
        print_success "Immich API reachable at $IMMICH_API_URL (internal)"
    else
        ping_response=$(curl -sk --max-time 5 "${IMMICH_API_URL_EXTERNAL}/server/ping" 2>&1) || true
        if echo "$ping_response" | grep -q "pong"; then
            IMMICH_API_URL="$IMMICH_API_URL_EXTERNAL"
            print_success "Immich API reachable at $IMMICH_API_URL (external)"
        else
            print_error "Immich API not reachable at $IMMICH_API_URL_INTERNAL or $IMMICH_API_URL_EXTERNAL"
            exit 3
        fi
    fi
else
    print_info "[DRY-RUN] Would check Immich API at $IMMICH_API_URL"
fi

# --- Get Existing Users ---

declare -A EXISTING_USERS_BY_EMAIL  # email -> uuid

if [[ "$DRY_RUN" == false ]]; then
    print_info "Fetching existing Immich users..."
    # Immich v1.131+/v2.x uses /api/admin/users (admin-only endpoint)
    existing_json=$(curl -sk --max-time 10 \
        -H "x-api-key: ${IMMICH_API_KEY}" \
        "${IMMICH_API_URL}/admin/users" 2>&1)

    # Parse existing users (email -> id mapping)
    while IFS= read -r line; do
        email=$(echo "$line" | jq -r '.email // empty')
        uuid=$(echo "$line" | jq -r '.id // empty')
        if [[ -n "$email" && -n "$uuid" ]]; then
            EXISTING_USERS_BY_EMAIL["$email"]="$uuid"
        fi
    done < <(echo "$existing_json" | jq -c '.[]' 2>/dev/null)

    print_info "Found ${#EXISTING_USERS_BY_EMAIL[@]} existing Immich user(s)"
fi

# --- Build Family User List ---

# ADMIN_USER (isAdmin=true) + POWER_USERS + STANDARD_USERS (isAdmin=false)
declare -a ALL_USERS=()
declare -A USER_IS_ADMIN=()

ALL_USERS+=("$ADMIN_USER")
USER_IS_ADMIN["$ADMIN_USER"]="true"

for user in ${POWER_USERS:-}; do
    ALL_USERS+=("$user")
    USER_IS_ADMIN["$user"]="true"
done
for user in ${STANDARD_USERS:-}; do
    ALL_USERS+=("$user")
    USER_IS_ADMIN["$user"]="false"
done

print_info "Family users to provision: ${ALL_USERS[*]}"

# --- Provision Users ---

created=0
skipped=0
failed=0

for username in "${ALL_USERS[@]}"; do
    email=$(get_user_email "$username")
    is_admin="${USER_IS_ADMIN[$username]}"
    display_name="${username^}"  # Capitalize first letter

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would provision: $username ($email, isAdmin=$is_admin)"
        continue
    fi

    # Check if user already exists (match by email)
    if [[ -n "${EXISTING_USERS_BY_EMAIL[$email]:-}" ]]; then
        uuid="${EXISTING_USERS_BY_EMAIL[$email]}"
        print_info "User already exists: $username ($email) — UUID: $uuid"
        write_uuid_to_services_env "$username" "$uuid"
        set_user_preferences "$uuid" "$username"
        skipped=$((skipped + 1))
        continue
    fi

    # Get or generate password
    password=$(get_user_password "$username")

    # Create user via API (Immich v1.131+/v2.x uses /api/admin/users)
    response=$(curl -sk --max-time 10 \
        -H "x-api-key: ${IMMICH_API_KEY}" \
        -H "Content-Type: application/json" \
        -X POST "${IMMICH_API_URL}/admin/users" \
        -d "{\"email\":\"${email}\",\"password\":\"${password}\",\"name\":\"${display_name}\",\"isAdmin\":${is_admin}}" \
        2>&1)

    uuid=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)

    if [[ -n "$uuid" && "$uuid" != "null" ]]; then
        write_uuid_to_services_env "$username" "$uuid"
        set_user_preferences "$uuid" "$username"
        print_success "Created user: $username ($email) — UUID: $uuid"
        created=$((created + 1))
    else
        error_msg=$(echo "$response" | jq -r '.message // "Unknown error"' 2>/dev/null)
        print_error "Failed to create user: $username ($email) — $error_msg"
        failed=$((failed + 1))
    fi
done

# --- Summary ---

echo ""
print_header "Provisioning Summary"
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] ${#ALL_USERS[@]} user(s) would be provisioned"
else
    print_info "Created: $created | Skipped (existing): $skipped | Failed: $failed"
fi

if [[ $failed -gt 0 ]]; then
    print_error "Some users failed to provision"
    exit 1
fi

print_success "Task complete"
exit 0
