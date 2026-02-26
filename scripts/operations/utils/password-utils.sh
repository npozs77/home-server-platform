#!/bin/bash
set -euo pipefail

# Utility Library: Password Management
# Purpose: Retrieve secrets from Proton Pass using pass-cli
# Functions: fetch_secret
# Usage: source this file, then call functions
#
# Prerequisites:
#   - pass-cli installed and configured
#   - HOMESERVER_PASS_SHARE_ID environment variable set
#   - User logged into Proton Pass
#
# Example:
#   source scripts/operations/utils/password-utils.sh
#   SMTP_PASSWORD=$(fetch_secret "$SMTP2GO_PASS_ITEM_ID" "password" "$ADMIN_USER")

# Source output utilities for error messages
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/output-utils.sh"

# Fetch secret from Proton Pass
# Parameters:
#   $1: item_id - Proton Pass item ID
#   $2: field - Field to retrieve (default: password)
#   $3: admin_user - User to run pass-cli as (default: $ADMIN_USER)
# Returns:
#   Secret value on stdout
#   Exit code 0 on success, 1 on failure
# Example:
#   fetch_secret "item-id-here" "password" "admin"
fetch_secret() {
    local item_id="$1"
    local field="${2:-password}"
    local admin_user="${3:-${ADMIN_USER:-}}"
    
    # Validate inputs
    if [[ -z "$item_id" ]]; then
        print_error "fetch_secret: item_id parameter is required"
        return 1
    fi
    
    if [[ -z "$admin_user" ]]; then
        print_error "fetch_secret: admin_user parameter is required (or set ADMIN_USER environment variable)"
        return 1
    fi
    
    # Validate HOMESERVER_PASS_SHARE_ID is set
    if [[ -z "${HOMESERVER_PASS_SHARE_ID:-}" ]]; then
        print_error "fetch_secret: HOMESERVER_PASS_SHARE_ID environment variable is not set"
        return 1
    fi
    
    # Fetch secret from Proton Pass as the specified user (not root)
    local secret
    if ! secret=$(su - "$admin_user" -c "pass-cli item view --share-id '$HOMESERVER_PASS_SHARE_ID' --item-id '$item_id' --field '$field' 2>/dev/null"); then
        print_error "fetch_secret: Failed to retrieve secret from Proton Pass (item_id: $item_id, field: $field)"
        print_error "  Possible causes:"
        print_error "    - User not logged into Proton Pass (run: pass-cli auth login)"
        print_error "    - Invalid item ID or field name"
        print_error "    - Invalid share ID"
        return 1
    fi
    
    if [[ -z "$secret" ]]; then
        print_error "fetch_secret: Retrieved secret is empty (item_id: $item_id, field: $field)"
        return 1
    fi
    
    # Output secret to stdout
    echo "$secret"
    return 0
}
