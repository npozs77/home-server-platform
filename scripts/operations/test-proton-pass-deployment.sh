#!/usr/bin/env bash
# test-proton-pass-deployment.sh
# Test Proton Pass fetch as deployment script will use it (root running pass-cli as user)

set -euo pipefail

# Must run as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Must run as root (use sudo)"
   exit 1
fi

# Load config
CONFIG_FILE="/opt/homeserver/configs/phase2-config.env"
source "$CONFIG_FILE"

# Get admin user from phase1 config
source "/opt/homeserver/configs/phase1-config.env"

echo "=== Deployment-Style Proton Pass Test ==="
echo "Running as: root"
echo "Fetching secrets as user: $ADMIN_USER"
echo ""

# Test 1: Pi-hole password (deployment style)
echo "Test 1: Fetching Pi-hole password..."
PIHOLE_PASSWORD=$(su - "$ADMIN_USER" -c "pass-cli item view --share-id '$HOMESERVER_PASS_SHARE_ID' --item-id '$PIHOLE_PASS_ITEM_ID' --field password" 2>&1) || true

if [[ -n "$PIHOLE_PASSWORD" && ! "$PIHOLE_PASSWORD" =~ "Error" ]]; then
    echo "✓ SUCCESS: Pi-hole password fetched (${#PIHOLE_PASSWORD} chars)"
    echo "  First 10 chars: ${PIHOLE_PASSWORD:0:10}..."
else
    echo "✗ FAILED: $PIHOLE_PASSWORD"
fi

echo ""

# Test 2: SMTP2GO password (deployment style)
echo "Test 2: Fetching SMTP2GO password..."
SMTP2GO_PASSWORD=$(su - "$ADMIN_USER" -c "pass-cli item view --share-id '$HOMESERVER_PASS_SHARE_ID' --item-id '$SMTP2GO_PASS_ITEM_ID' --field password" 2>&1) || true

if [[ -n "$SMTP2GO_PASSWORD" && ! "$SMTP2GO_PASSWORD" =~ "Error" ]]; then
    echo "✓ SUCCESS: SMTP2GO password fetched (${#SMTP2GO_PASSWORD} chars)"
    echo "  First 10 chars: ${SMTP2GO_PASSWORD:0:10}..."
else
    echo "✗ FAILED: $SMTP2GO_PASSWORD"
fi

echo ""
echo "=== Test Complete ==="
