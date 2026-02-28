#!/bin/bash
# Task: Validate user provisioning scripts
# Phase: 3 (Core Services)
# Number: 06
#
# Prerequisites:
#   - User provisioning scripts exist in scripts/operations/user-management/
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Script directory
SCRIPT_DIR="/opt/homeserver/scripts/operations/user-management"

# Required scripts
REQUIRED_SCRIPTS=(
    "create-user.sh"
    "update-user.sh"
    "delete-user.sh"
    "list-users.sh"
)

# Execute task
echo ""
echo "========================================"
echo "Validating User Provisioning Scripts"
echo "========================================"
echo ""

# Check directory exists
if [[ ! -d "$SCRIPT_DIR" ]]; then
    echo "Error: Directory not found: $SCRIPT_DIR" >&2
    exit 1
fi
echo "✓ Directory exists: $SCRIPT_DIR"

# Check all required scripts exist
for script in "${REQUIRED_SCRIPTS[@]}"; do
    script_path="$SCRIPT_DIR/$script"
    if [[ ! -f "$script_path" ]]; then
        echo "✗ Script missing: $script" >&2
        exit 1
    fi
    echo "✓ Script exists: $script"
done

# Check scripts are executable
for script in "${REQUIRED_SCRIPTS[@]}"; do
    script_path="$SCRIPT_DIR/$script"
    if [[ ! -x "$script_path" ]]; then
        echo "Making $script executable..."
        chmod +x "$script_path"
    fi
    echo "✓ Script executable: $script"
done

# Validate script syntax
echo ""
echo "Validating script syntax..."
for script in "${REQUIRED_SCRIPTS[@]}"; do
    script_path="$SCRIPT_DIR/$script"
    if bash -n "$script_path" 2>/dev/null; then
        echo "✓ $script syntax valid"
    else
        echo "✗ $script syntax invalid" >&2
        bash -n "$script_path"
        exit 1
    fi
done

echo ""
echo "========================================"
echo "User Provisioning Scripts Validated"
echo "========================================"
echo ""
echo "Scripts location: $SCRIPT_DIR"
echo ""
echo "  - create-user.sh: Create new user"
echo "  - update-user.sh: Update existing user"
echo "  - delete-user.sh: Delete user"
echo "  - list-users.sh: List all users"
echo ""
echo "All scripts exist, are executable, and have valid syntax"
echo ""

echo "✓ Task complete"
exit 0
