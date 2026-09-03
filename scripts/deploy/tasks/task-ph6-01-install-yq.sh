#!/bin/bash
# Task: Install yq YAML processor
# Phase: 6 (Docker Service Helper)
# Number: 01
# Prerequisites: None
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
# Requirements: 25.1, 25.9

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utility libraries
source /opt/homeserver/scripts/operations/utils/output-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

YQ_VERSION="v4.44.1"
YQ_BINARY="/usr/bin/yq"
YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"

# Check if already installed at correct version (idempotency)
if command -v yq &>/dev/null; then
    INSTALLED_VERSION=$(yq --version 2>/dev/null | grep -oP 'v[\d.]+' || echo "unknown")
    if [[ "$INSTALLED_VERSION" == "$YQ_VERSION" ]]; then
        print_info "yq ${YQ_VERSION} already installed — skip"
        exit 0
    fi
    print_info "yq installed but version ${INSTALLED_VERSION} (want ${YQ_VERSION}) — upgrading"
fi

# Dry-run mode
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would download yq ${YQ_VERSION} from GitHub releases"
    print_info "[DRY-RUN] Would install to ${YQ_BINARY}"
    print_info "[DRY-RUN] Would set executable permissions"
    exit 0
fi

print_header "Task ph6-01: Install yq YAML processor"
echo ""

# Download and install
print_info "Downloading yq ${YQ_VERSION}..."
if ! curl -fsSL "$YQ_URL" -o "$YQ_BINARY"; then
    print_fail "Failed to download yq from ${YQ_URL}"
    exit 1
fi

chmod +x "$YQ_BINARY"

# Verify installation
if ! yq --version &>/dev/null; then
    print_fail "yq installed but not working"
    exit 1
fi

INSTALLED_VERSION=$(yq --version 2>/dev/null | grep -oP 'v[\d.]+' || echo "unknown")
print_success "yq ${INSTALLED_VERSION} installed at ${YQ_BINARY}"
exit 0
