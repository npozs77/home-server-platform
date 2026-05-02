#!/bin/bash
# Task: Provision Wiki.js user accounts via GraphQL API
# Phase: 5 (Wiki + LLM Platform — Sub-phase A)
# Number: 05
# Prerequisites:
#   - Wiki.js running and setup wizard completed
#   - WIKI_API_TOKEN set in secrets.env
#   - WIKI_DEFAULT_PASSWORD set in secrets.env
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   3 = Configuration error
# Environment Variables Required (services.env):
#   ADMIN_USER, POWER_USERS, STANDARD_USERS, WIKI_DOMAIN, WIKI_PORT
# Environment Variables Required (secrets.env):
#   WIKI_API_TOKEN, WIKI_DEFAULT_PASSWORD
# Environment Variables Required (foundation.env):
#   ADMIN_EMAIL
# Satisfies: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6

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

# Always source all env files — orchestrator may not export everything
[[ -f "$FOUNDATION_ENV" ]] && source "$FOUNDATION_ENV"
[[ -f "$SERVICES_ENV" ]] && source "$SERVICES_ENV"
if [[ -f "$SECRETS_ENV" ]]; then
    set +u; source "$SECRETS_ENV"; set -u
fi

# Validate required env vars
for var in ADMIN_USER ADMIN_EMAIL WIKI_DOMAIN INTERNAL_SUBDOMAIN; do
    if [[ -z "${!var:-}" ]]; then
        print_error "$var not set"
        exit 3
    fi
done
if [[ -z "${WIKI_API_TOKEN:-}" ]]; then
    print_error "WIKI_API_TOKEN not set in secrets.env (generate from Wiki.js admin panel)"
    exit 3
fi
if [[ -z "${WIKI_DEFAULT_PASSWORD:-}" ]]; then
    print_error "WIKI_DEFAULT_PASSWORD not set in secrets.env"
    exit 3
fi

# Wiki.js API endpoint (use localhost since script runs on server)
WIKI_API="http://localhost:${WIKI_PORT:-3000}/graphql"
AUTH_HEADER="Authorization: Bearer ${WIKI_API_TOKEN}"

# Validate API connectivity
print_info "Validating Wiki.js API connectivity..."
API_TEST=$(curl -sf -X POST "$WIKI_API" \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    -d '{"query": "{ groups { list { id name } } }"}' 2>/dev/null || echo "FAIL")

if [[ "$API_TEST" == "FAIL" ]] || echo "$API_TEST" | grep -q '"errors"'; then
    print_error "Cannot connect to Wiki.js API at $WIKI_API"
    exit 3
fi

# --- Helper functions ---

wiki_graphql() {
    local query="$1"
    curl -sf -X POST "$WIKI_API" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "{\"query\": \"$query\"}" 2>/dev/null
}

get_existing_users() {
    wiki_graphql "{ users { list { id name email } } }" | \
        grep -oP '"email":"[^"]*"' | sed 's/"email":"//;s/"//'
}

get_existing_groups() {
    wiki_graphql "{ groups { list { id name } } }"
}

ensure_group() {
    local group_name="$1"
    local groups_json
    groups_json=$(get_existing_groups)
    local group_id
    group_id=$(echo "$groups_json" | grep -oP "\"id\":[0-9]+,\"name\":\"${group_name}\"" | grep -oP '"id":[0-9]+' | cut -d: -f2)

    if [[ -n "$group_id" ]]; then
        echo "$group_id"
        return 0
    fi

    # Create group
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create group: $group_name"
        echo "0"
        return 0
    fi

    local result
    result=$(wiki_graphql "mutation { groups { create(name: \\\"${group_name}\\\") { responseResult { succeeded message } group { id } } } }")
    if echo "$result" | grep -q '"succeeded":true'; then
        group_id=$(echo "$result" | grep -oP '"id":[0-9]+' | tail -1 | cut -d: -f2)
        print_success "Created group: $group_name (id=$group_id)"
        echo "$group_id"
    else
        print_error "Failed to create group: $group_name"
        echo "$result" >&2
        echo "0"
    fi
}

create_user() {
    local username="$1"
    local email="$2"
    local group_id="$3"
    local password="$4"
    local group_name="$5"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create user: $username ($email) → group $group_name"
        return 0
    fi

    local result
    result=$(wiki_graphql "mutation { users { create(email: \\\"${email}\\\", name: \\\"${username}\\\", passwordRaw: \\\"${password}\\\", providerKey: \\\"local\\\", groups: [${group_id}], mustChangePassword: true, sendWelcomeEmail: false) { responseResult { succeeded message } } } }")

    if echo "$result" | grep -q '"succeeded":true'; then
        print_success "Created user: $username ($email) → $group_name"
        return 0
    else
        local msg
        msg=$(echo "$result" | grep -oP '"message":"[^"]*"' | head -1 | sed 's/"message":"//;s/"//')
        print_error "Failed to create user $username: $msg"
        return 1
    fi
}

# --- Main logic ---

print_info "Provisioning Wiki.js users..."

# Get existing users for idempotency
EXISTING_USERS=$(get_existing_users)

# Ensure required groups exist
print_info "Ensuring groups exist..."
EDITORS_ID=$(ensure_group "Editors")
READERS_ID=$(ensure_group "Readers")

# Counters
CREATED=0
SKIPPED=0
FAILED=0

# Admin user — already exists from setup wizard, skip
if echo "$EXISTING_USERS" | grep -q "$ADMIN_EMAIL"; then
    print_info "Admin user ($ADMIN_EMAIL) already exists — skipping"
    SKIPPED=$((SKIPPED + 1))
else
    print_info "Admin user ($ADMIN_EMAIL) not found — this is unexpected (setup wizard should have created it)"
    SKIPPED=$((SKIPPED + 1))
fi

# Power users → Editors group
for user in $POWER_USERS; do
    email="${user}@${INTERNAL_SUBDOMAIN:-homeserver}"
    if echo "$EXISTING_USERS" | grep -q "$email"; then
        print_info "User $user ($email) already exists — skipping"
        SKIPPED=$((SKIPPED + 1))
    else
        if create_user "$user" "$email" "$EDITORS_ID" "$WIKI_DEFAULT_PASSWORD" "Editors"; then
            CREATED=$((CREATED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    fi
done

# Standard users → Readers group
for user in $STANDARD_USERS; do
    email="${user}@${INTERNAL_SUBDOMAIN:-homeserver}"
    if echo "$EXISTING_USERS" | grep -q "$email"; then
        print_info "User $user ($email) already exists — skipping"
        SKIPPED=$((SKIPPED + 1))
    else
        if create_user "$user" "$email" "$READERS_ID" "$WIKI_DEFAULT_PASSWORD" "Readers"; then
            CREATED=$((CREATED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    fi
done

# Summary
print_info "Summary: $CREATED created, $SKIPPED skipped, $FAILED failed"

# Verify by listing all users
if [[ "$DRY_RUN" != true ]]; then
    print_info "Current Wiki.js users:"
    wiki_graphql "{ users { list { id name email } } }" | \
        grep -oP '\{"id":[0-9]+,"name":"[^"]*","email":"[^"]*"\}' | \
        while IFS= read -r line; do
            name=$(echo "$line" | grep -oP '"name":"[^"]*"' | sed 's/"name":"//;s/"//')
            email=$(echo "$line" | grep -oP '"email":"[^"]*"' | sed 's/"email":"//;s/"//')
            echo "  - $name ($email)"
        done
fi

print_success "Task complete"
exit 0
