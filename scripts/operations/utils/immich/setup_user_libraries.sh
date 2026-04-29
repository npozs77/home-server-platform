#!/bin/bash
set -euo pipefail

# Immich User Library Setup — External Libraries + Partner Sharing
# Purpose: Create external libraries per user so all family members can browse
#          shared photos in both Timeline and Folders view.
# Location: scripts/operations/utils/immich/setup_user_libraries.sh
#
# RCA: Immich external libraries are per-user. If only the admin creates them,
#      other users see nothing in Folders view. Partner sharing only populates
#      the timeline, NOT the folder browser. Fix: create external libraries
#      owned by each user pointing to the same import paths.
#
# Usage: setup_user_libraries.sh [--dry-run]
#
# Prerequisites:
#   - Immich running and healthy
#   - IMMICH_API_KEY (admin) in secrets.env
#   - IMMICH_URL in services.env (e.g., https://photos.home.mydomain.com)
#   - External library import paths mounted in immich-server container
#
# What this script does:
#   1. Lists all Immich users via API
#   2. Lists existing libraries per user
#   3. For each non-admin user missing external libraries:
#      a. Creates external library with configured import paths
#      b. Triggers a library scan
#   4. Optionally sets up partner sharing (admin <-> each user)
#
# Safety: --dry-run previews all actions without making API calls
#
# Dependencies: curl, jq

# ─── Configuration ───────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN="${1:-}"

# Default import paths (container paths, not host paths)
# These must match the volume mounts in immich.yml
IMPORT_PATHS='["/mnt/media/Photos", "/mnt/family/Photos"]'

# Source config files if available, otherwise expect env vars
if [[ -f /opt/homeserver/configs/secrets.env ]]; then
    source /opt/homeserver/configs/secrets.env
fi
if [[ -f /opt/homeserver/configs/services.env ]]; then
    source /opt/homeserver/configs/services.env
fi

# Allow override via env vars
IMMICH_URL="${IMMICH_URL:-https://photos.home.mydomain.com}"
IMMICH_API_KEY="${IMMICH_API_KEY:?ERROR: IMMICH_API_KEY not set. Set in secrets.env or export it.}"

API_BASE="${IMMICH_URL}/api"

# ─── Helper Functions ────────────────────────────────────────────────────────

api_get() {
    local endpoint="$1"
    curl -sf -H "x-api-key: ${IMMICH_API_KEY}" \
        -H "Accept: application/json" \
        "${API_BASE}${endpoint}"
}

api_post() {
    local endpoint="$1"
    local data="$2"
    curl -sf -X POST \
        -H "x-api-key: ${IMMICH_API_KEY}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$data" \
        "${API_BASE}${endpoint}"
}

# ─── Validation ──────────────────────────────────────────────────────────────

validate_prerequisites() {
    if ! command -v curl &>/dev/null; then
        echo "ERROR: curl is not installed" >&2
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is not installed" >&2
        exit 1
    fi

    # Test API connectivity
    if ! api_get "/server/ping" &>/dev/null; then
        echo "ERROR: Cannot reach Immich API at ${API_BASE}" >&2
        echo "  Check IMMICH_URL and that Immich is running" >&2
        exit 1
    fi
    echo "OK: Immich API reachable at ${IMMICH_URL}"
}

# ─── Core Logic ──────────────────────────────────────────────────────────────

setup_libraries() {
    echo ""
    echo "--- Fetching users ---"
    local users
    users=$(api_get "/users")

    local user_count
    user_count=$(echo "$users" | jq 'length')
    echo "Found ${user_count} Immich users"

    # Get admin user ID (first admin found)
    local admin_id
    admin_id=$(echo "$users" | jq -r '[.[] | select(.isAdmin == true)][0].id')
    local admin_name
    admin_name=$(echo "$users" | jq -r '[.[] | select(.isAdmin == true)][0].name')
    echo "Admin: ${admin_name} (${admin_id})"

    echo ""
    echo "--- Fetching existing libraries ---"
    local libraries
    libraries=$(api_get "/libraries")

    echo ""
    echo "--- Processing users ---"

    echo "$users" | jq -c '.[]' | while read -r user; do
        local user_id user_name user_email is_admin
        user_id=$(echo "$user" | jq -r '.id')
        user_name=$(echo "$user" | jq -r '.name')
        user_email=$(echo "$user" | jq -r '.email')
        is_admin=$(echo "$user" | jq -r '.isAdmin')

        echo ""
        echo "User: ${user_name} (${user_email}) [admin=${is_admin}]"

        # Check if user already has external libraries with our import paths
        local existing_libs
        existing_libs=$(echo "$libraries" | jq -c "[.[] | select(.ownerId == \"${user_id}\" and .type == \"EXTERNAL\")]")
        local existing_count
        existing_count=$(echo "$existing_libs" | jq 'length')

        if [[ "$existing_count" -gt 0 ]]; then
            echo "  Already has ${existing_count} external library(ies) — checking import paths"

            # Check if existing libraries already cover our import paths
            local has_media has_family
            has_media=$(echo "$existing_libs" | jq "[.[].importPaths[] | select(. == \"/mnt/media/Photos\")] | length")
            has_family=$(echo "$existing_libs" | jq "[.[].importPaths[] | select(. == \"/mnt/family/Photos\")] | length")

            if [[ "$has_media" -gt 0 && "$has_family" -gt 0 ]]; then
                echo "  SKIP: Both import paths already configured"
                continue
            fi
            echo "  Missing paths: media=${has_media} family=${has_family}"
        fi

        # Create external library for this user
        local lib_data
        lib_data=$(jq -n \
            --arg ownerId "$user_id" \
            --arg name "Shared Photos (${user_name})" \
            --argjson importPaths "$IMPORT_PATHS" \
            '{ownerId: $ownerId, name: $name, importPaths: $importPaths, exclusionPatterns: []}')

        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            echo "  [DRY-RUN] Would create external library:"
            echo "    Owner: ${user_name}"
            echo "    Paths: /mnt/media/Photos, /mnt/family/Photos"
        else
            echo "  Creating external library..."
            local response
            if response=$(api_post "/libraries" "$lib_data"); then
                local lib_id
                lib_id=$(echo "$response" | jq -r '.id')
                echo "  CREATED: Library ${lib_id}"

                # Trigger scan
                echo "  Triggering library scan..."
                if api_post "/libraries/${lib_id}/scan" '{}' &>/dev/null; then
                    echo "  SCAN: Started for ${user_name}"
                else
                    echo "  WARNING: Scan trigger failed for library ${lib_id}"
                fi
            else
                echo "  ERROR: Failed to create library for ${user_name}"
            fi
        fi
    done
}

# ─── Partner Sharing Setup ───────────────────────────────────────────────────

setup_partner_sharing() {
    echo ""
    echo "--- Partner Sharing (admin <-> all users) ---"

    local users
    users=$(api_get "/users")

    local admin_id
    admin_id=$(echo "$users" | jq -r '[.[] | select(.isAdmin == true)][0].id')

    # Get existing partners
    local existing_partners
    existing_partners=$(api_get "/partners?direction=shared-by" 2>/dev/null || echo "[]")

    echo "$users" | jq -c '.[] | select(.isAdmin != true)' | while read -r user; do
        local user_id user_name
        user_id=$(echo "$user" | jq -r '.id')
        user_name=$(echo "$user" | jq -r '.name')

        # Check if already a partner
        local already_shared
        already_shared=$(echo "$existing_partners" | jq "[.[] | select(.id == \"${user_id}\")] | length")

        if [[ "$already_shared" -gt 0 ]]; then
            echo "  SKIP: ${user_name} already a partner"
            continue
        fi

        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            echo "  [DRY-RUN] Would share admin library with: ${user_name}"
        else
            echo "  Sharing with ${user_name}..."
            if api_post "/partners" "{\"sharedWithId\": \"${user_id}\"}" &>/dev/null; then
                echo "  SHARED: Admin → ${user_name}"
            else
                echo "  WARNING: Partner sharing failed for ${user_name} (may already exist)"
            fi
        fi
    done

    echo ""
    echo "NOTE: Each user must also accept partner sharing from their own"
    echo "      Account Settings → Partner Sharing → toggle 'Show in timeline'"
    echo "      This step cannot be automated via admin API key."
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    echo "=== IMMICH USER LIBRARY SETUP ==="
    echo "URL:  ${IMMICH_URL}"
    echo "Date: $(date)"
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        echo "Mode: DRY RUN (no changes)"
    else
        echo "Mode: LIVE"
    fi

    validate_prerequisites
    setup_libraries
    setup_partner_sharing

    echo ""
    echo "=== DONE ==="
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        echo "Hint: Remove --dry-run to apply changes."
    fi
}

main "$@"
