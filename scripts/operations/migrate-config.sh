#!/bin/bash
# Configuration Migration Script
# Purpose: Convert phase-based config files to logical config files
# Usage: sudo ./migrate-config.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Configuration paths
PHASE1_CONFIG="/opt/homeserver/configs/phase1-config.env"
PHASE2_CONFIG="/opt/homeserver/configs/phase2-config.env"
FOUNDATION_CONFIG="/opt/homeserver/configs/foundation.env"
SERVICES_CONFIG="/opt/homeserver/configs/services.env"
SECRETS_CONFIG="/opt/homeserver/configs/secrets.env"

# Check if phase configs exist
if [[ ! -f "$PHASE1_CONFIG" ]]; then
    print_error "Phase 1 config not found: $PHASE1_CONFIG"
    exit 1
fi

if [[ ! -f "$PHASE2_CONFIG" ]]; then
    print_error "Phase 2 config not found: $PHASE2_CONFIG"
    exit 1
fi

# Check if already migrated (idempotency)
if [[ -f "$FOUNDATION_CONFIG" ]] && [[ -f "$SERVICES_CONFIG" ]] && [[ -f "$SECRETS_CONFIG" ]]; then
    print_info "Configuration already migrated"
    print_info "Existing files: foundation.env, services.env, secrets.env"
    read -p "Re-run migration? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        print_info "Migration skipped"
        exit 0
    fi
fi

# Create backups
print_info "Creating backups..."
cp "$PHASE1_CONFIG" "${PHASE1_CONFIG}.backup"
cp "$PHASE2_CONFIG" "${PHASE2_CONFIG}.backup"
print_success "Backups created: phase1-config.env.backup, phase2-config.env.backup"

# Source phase configs
source "$PHASE1_CONFIG"
source "$PHASE2_CONFIG"

# Create foundation.env (system-level)
print_info "Creating foundation.env..."
cat > "$FOUNDATION_CONFIG" << EOF
# Foundation Configuration (System-Level)
# Generated: $(date)
# Migrated from: phase1-config.env

# System Configuration
TIMEZONE="${TIMEZONE:-America/New_York}"
HOSTNAME="${HOSTNAME:-homeserver}"
SERVER_IP="${SERVER_IP}"
NETWORK_INTERFACE="${NETWORK_INTERFACE:-enp0s3}"

# User Configuration
ADMIN_USER="${ADMIN_USER}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

# Disk Configuration
DATA_DISK="${DATA_DISK}"
DATA_MOUNT="${DATA_MOUNT:-/mnt/data}"

# Git Configuration
GIT_USER_NAME="${GIT_USER_NAME}"
GIT_USER_EMAIL="${GIT_USER_EMAIL}"
EOF
chmod 644 "$FOUNDATION_CONFIG"
print_success "Created foundation.env (644 permissions)"

# Create services.env (service-specific)
print_info "Creating services.env..."
cat > "$SERVICES_CONFIG" << EOF
# Services Configuration (Service-Specific)
# Generated: $(date)
# Migrated from: phase2-config.env

# Domain Configuration
DOMAIN="${DOMAIN}"
INTERNAL_SUBDOMAIN="${INTERNAL_SUBDOMAIN}"

# SMTP Configuration
SMTP2GO_HOST="${SMTP2GO_HOST}"
SMTP2GO_PORT="${SMTP2GO_PORT}"
SMTP2GO_FROM="${SMTP2GO_FROM}"
SMTP2GO_USER="${SMTP2GO_USER}"

# Proton Pass Configuration
HOMESERVER_PASS_SHARE_ID="${HOMESERVER_PASS_SHARE_ID}"
SMTP2GO_PASS_ITEM_ID="${SMTP2GO_PASS_ITEM_ID}"
PIHOLE_PASS_ITEM_ID="${PIHOLE_PASS_ITEM_ID}"
EOF
chmod 644 "$SERVICES_CONFIG"
print_success "Created services.env (644 permissions)"

# Create secrets.env (root-protected)
print_info "Creating secrets.env..."
cat > "$SECRETS_CONFIG" << EOF
# Secrets Configuration (Root-Protected)
# Generated: $(date)
# Migrated from: phase1-config.env

# LUKS Encryption
LUKS_PASSPHRASE="${LUKS_PASSPHRASE}"
EOF
chmod 600 "$SECRETS_CONFIG"
chown root:root "$SECRETS_CONFIG"
print_success "Created secrets.env (600 permissions, root:root)"

# Validate migration
print_info "Validating migration..."

# Check all required variables present
REQUIRED_FOUNDATION_VARS="TIMEZONE HOSTNAME SERVER_IP ADMIN_USER ADMIN_EMAIL DATA_DISK GIT_USER_NAME GIT_USER_EMAIL"
REQUIRED_SERVICES_VARS="DOMAIN INTERNAL_SUBDOMAIN SMTP2GO_HOST SMTP2GO_PORT SMTP2GO_FROM SMTP2GO_USER HOMESERVER_PASS_SHARE_ID SMTP2GO_PASS_ITEM_ID PIHOLE_PASS_ITEM_ID"
REQUIRED_SECRETS_VARS="LUKS_PASSPHRASE"

source "$FOUNDATION_CONFIG"
for var in $REQUIRED_FOUNDATION_VARS; do
    if [[ -z "${!var:-}" ]]; then
        print_error "Missing variable in foundation.env: $var"
        exit 1
    fi
done
print_success "foundation.env validated"

source "$SERVICES_CONFIG"
for var in $REQUIRED_SERVICES_VARS; do
    if [[ -z "${!var:-}" ]]; then
        print_error "Missing variable in services.env: $var"
        exit 1
    fi
done
print_success "services.env validated"

source "$SECRETS_CONFIG"
for var in $REQUIRED_SECRETS_VARS; do
    if [[ -z "${!var:-}" ]]; then
        print_error "Missing variable in secrets.env: $var"
        exit 1
    fi
done
print_success "secrets.env validated"

# Print summary
echo ""
print_success "Migration complete!"
echo ""
echo "Summary of changes:"
echo "  - Created foundation.env (system-level configuration)"
echo "  - Created services.env (service-specific configuration)"
echo "  - Created secrets.env (root-protected secrets)"
echo "  - Backed up original files (.backup extension)"
echo ""
echo "Variable mapping:"
echo "  - SERVER_IP: Merged from both phase configs (duplicate removed)"
echo "  - ADMIN_EMAIL: Merged from both phase configs (duplicate removed)"
echo "  - All other variables: Migrated to appropriate logical config"
echo ""
echo "Next steps:"
echo "  1. Review new config files for correctness"
echo "  2. Update deployment scripts to use new config files"
echo "  3. Test deployment with new configuration"
echo ""
print_info "Original phase configs preserved as .backup files"
print_info "Rollback: Restore from .backup files if needed"

exit 0
