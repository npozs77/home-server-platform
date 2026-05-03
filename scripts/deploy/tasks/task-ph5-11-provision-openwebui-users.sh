#!/bin/bash
# Task: Provision Open WebUI users via REST API
# Phase: 5 (Wiki + LLM Platform — Sub-phase B)
# Number: 11
# Prerequisites:
#   - Open WebUI container running and healthy (Task 9.3)
#   - OPENWEBUI_PASSWORD_<username> set in secrets.env (option 0 generates them)
#   - ADMIN_USER, ADMIN_EMAIL, POWER_USERS, STANDARD_USERS defined
# Parameters:
#   --dry-run: Report planned actions without API calls
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Satisfies: Requirements 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7

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
COMPOSE_DIR="/opt/homeserver/configs/docker-compose"
COMPOSE_FILE="${COMPOSE_DIR}/ollama.yml"

# Source configuration
print_info "Loading configuration..."
for envfile in "$FOUNDATION_ENV" "$SERVICES_ENV"; do
    if [[ -f "$envfile" ]]; then
        source "$envfile"
    else
        print_error "Missing: $envfile"; exit 3
    fi
done
if [[ -f "$SECRETS_ENV" ]]; then
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        value="${value#\"}"; value="${value%\"}"; value="${value#\'}"; value="${value%\'}"
        export "$key=$value"
    done < <(grep -v '^\s*#' "$SECRETS_ENV" | grep -v '^\s*$' | grep '=')
fi

# Validate required variables
for var in ADMIN_USER ADMIN_EMAIL OPENWEBUI_DOMAIN; do
    if [[ -z "${!var:-}" ]]; then
        print_error "Required variable not set: $var"
        exit 3
    fi
done

# Validate admin password exists
ADMIN_PWD_VAR="OPENWEBUI_PASSWORD_${ADMIN_USER}"
if [[ -z "${!ADMIN_PWD_VAR:-}" ]]; then
    print_error "$ADMIN_PWD_VAR not set in secrets.env (run option 0 to generate)"
    exit 3
fi

# API URL (internal localhost since script runs on server with sudo)
API_URL="http://localhost:${OPENWEBUI_PORT:-8080}/api/v1"

# Validate Open WebUI is reachable
print_info "Checking Open WebUI API..."
if [[ "$DRY_RUN" == false ]]; then
    if ! curl -sf --max-time 5 "http://localhost:${OPENWEBUI_PORT:-8080}/health" &>/dev/null; then
        print_error "Open WebUI not reachable at localhost:${OPENWEBUI_PORT:-8080}"
        exit 3
    fi
    print_success "Open WebUI API reachable"
fi

# Build user list: admin first, then power users, then standard users
declare -a ALL_USERS=("$ADMIN_USER")
for user in ${POWER_USERS:-}; do ALL_USERS+=("$user"); done
for user in ${STANDARD_USERS:-}; do ALL_USERS+=("$user"); done

print_info "Users to provision: ${ALL_USERS[*]}"

# --- Helper: get email for user ---
get_email() {
    local u="$1"
    # shellcheck disable=SC2153  # ADMIN_EMAIL is sourced from foundation.env
    [[ "$u" == "$ADMIN_USER" ]] && echo "$ADMIN_EMAIL" || echo "${u}@${INTERNAL_SUBDOMAIN:-homeserver.local}"
}

# --- Helper: get password for user ---
get_password() {
    local u="$1"
    local var="OPENWEBUI_PASSWORD_${u}"
    echo "${!var:-}"
}

# --- Step 1: Create admin via signup API (first user = admin, no auth needed) ---

ADMIN_JWT=""
created=0; skipped=0; failed=0

admin_email=$(get_email "$ADMIN_USER")
admin_pass=$(get_password "$ADMIN_USER")
admin_name="${ADMIN_USER^}"

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would create admin: $ADMIN_USER ($admin_email) via signup API"
else
    # Check if admin already exists by trying to sign in
    # Escape password for JSON (handle special chars like #, @, $, etc.)
    admin_pass_escaped=$(echo "$admin_pass" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip())[1:-1])')
    signin_resp=$(curl -s --max-time 10 -X POST "${API_URL}/auths/signin" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"${admin_email}\",\"password\":\"${admin_pass_escaped}\"}" 2>&1)

    ADMIN_JWT=$(echo "$signin_resp" | jq -r '.token // empty' 2>/dev/null)

    if [[ -n "$ADMIN_JWT" ]]; then
        print_info "Admin already exists: $ADMIN_USER ($admin_email) — skipping creation"
        skipped=$((skipped + 1))
    else
        # Create admin via signup (first user gets admin role automatically)
        print_info "Creating admin account via signup API..."
        signup_resp=$(curl -s --max-time 10 -X POST "${API_URL}/auths/signup" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"${admin_name}\",\"email\":\"${admin_email}\",\"password\":\"${admin_pass_escaped}\"}" 2>&1)

        ADMIN_JWT=$(echo "$signup_resp" | jq -r '.token // empty' 2>/dev/null)

        if [[ -n "$ADMIN_JWT" ]]; then
            print_success "Created admin: $ADMIN_USER ($admin_email)"
            created=$((created + 1))
        else
            error_msg=$(echo "$signup_resp" | jq -r '.detail // "Unknown error"' 2>/dev/null)
            print_error "Failed to create admin: $error_msg"
            failed=$((failed + 1))
        fi
    fi
fi

# --- Step 2: Create other users via admin API ---

if [[ -z "$ADMIN_JWT" && "$DRY_RUN" == false ]]; then
    print_error "No admin JWT — cannot create other users"
    exit 1
fi

# Fetch existing users once (for idempotency check)
EXISTING_EMAILS_LIST=""
if [[ "$DRY_RUN" == false && -n "$ADMIN_JWT" ]]; then
    existing_json=$(curl -s --max-time 10 -H "Authorization: Bearer ${ADMIN_JWT}" \
        "${API_URL}/users/" 2>&1) || true
    EXISTING_EMAILS_LIST=$(echo "$existing_json" | jq -r '.users[].email // empty' 2>/dev/null) || true
    existing_count=$(echo "$EXISTING_EMAILS_LIST" | grep -c . 2>/dev/null) || true
    print_info "Found ${existing_count} existing user(s)"
fi

for username in "${ALL_USERS[@]}"; do
    [[ "$username" == "$ADMIN_USER" ]] && continue

    email=$(get_email "$username")
    password=$(get_password "$username")
    display_name="${username^}"

    if [[ -z "$password" ]]; then
        print_error "No password for $username (OPENWEBUI_PASSWORD_${username} not set)"
        failed=$((failed + 1))
        continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create user: $username ($email, role=user)"
        continue
    fi

    # Check if user already exists
    if echo "$EXISTING_EMAILS_LIST" | grep -q "^${email}$"; then
        print_info "User already exists: $username ($email) — skipping"
        skipped=$((skipped + 1))
        continue
    fi

    # Create user via admin endpoint
    # Escape password for JSON
    pass_escaped=$(echo "$password" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip())[1:-1])')
    resp=$(curl -s --max-time 10 -X POST "${API_URL}/auths/add" \
        -H "Authorization: Bearer ${ADMIN_JWT}" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"${email}\",\"name\":\"${display_name}\",\"password\":\"${pass_escaped}\",\"role\":\"user\"}" 2>&1)

    user_id=$(echo "$resp" | jq -r '.id // empty' 2>/dev/null)
    if [[ -n "$user_id" && "$user_id" != "null" ]]; then
        print_success "Created user: $username ($email)"
        created=$((created + 1))
    else
        error_msg=$(echo "$resp" | jq -r '.detail // "Unknown error"' 2>/dev/null)
        # Treat "already registered" as skip, not failure
        if echo "$error_msg" | grep -qi "already registered"; then
            print_info "User already exists: $username ($email) — skipping"
            skipped=$((skipped + 1))
        else
            print_error "Failed to create user: $username — $error_msg"
            failed=$((failed + 1))
        fi
    fi
done

# --- Step 3: Disable self-registration ---

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would disable signup (ENABLE_SIGNUP=false) and recreate container"
else
    if [[ $failed -eq 0 ]]; then
        # Check if signup is already disabled
        CURRENT_SIGNUP=$(docker exec open-webui env 2>/dev/null | grep "ENABLE_SIGNUP" | cut -d= -f2)
        if [[ "$CURRENT_SIGNUP" == "false" ]]; then
            print_success "Signup already disabled — skipping"
        else
            print_info "Disabling self-registration..."

            # Update ENABLE_SIGNUP in services.env
            if grep -q "^ENABLE_SIGNUP=" "$SERVICES_ENV" 2>/dev/null; then
                sed -i 's/^ENABLE_SIGNUP=.*/ENABLE_SIGNUP="false"/' "$SERVICES_ENV"
            else
                echo 'ENABLE_SIGNUP="false"' >> "$SERVICES_ENV"
            fi

            # Recreate open-webui container with updated env
            COMPOSE_CMD="docker compose --env-file $FOUNDATION_ENV --env-file $SERVICES_ENV -f $COMPOSE_FILE"
            $COMPOSE_CMD up -d open-webui

            # Wait for healthy
            print_info "Waiting for open-webui to become healthy..."
            STATUS="unknown"
            for i in $(seq 1 24); do
                STATUS=$(docker inspect --format='{{.State.Health.Status}}' open-webui 2>/dev/null || echo "missing")
                [[ "$STATUS" == "healthy" ]] && break
                sleep 5
            done

            if [[ "$STATUS" == "healthy" ]]; then
                print_success "Signup disabled and container healthy"
            else
                print_error "Container not healthy after disabling signup (status: $STATUS)"
            fi
        fi
    else
        print_info "Skipping signup disable — $failed user(s) failed provisioning"
    fi
fi

# --- Summary ---

echo ""
print_header "Open WebUI Provisioning Summary"
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
