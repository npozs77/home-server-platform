#!/bin/bash
# Check critical containers and send email if unhealthy
# Purpose: Monitor Docker container health status
# Usage: ./check-container-health.sh

set -euo pipefail

# Load configuration
if [[ -f /opt/homeserver/configs/foundation.env ]]; then
    source /opt/homeserver/configs/foundation.env
fi

# Configuration
CONTAINERS="pihole caddy jellyfin"
ALERT_EMAIL="${ADMIN_EMAIL:-admin@mydomain.com}"
ADMIN_USER="${ADMIN_USER:-$(whoami)}"

# Check each container
for container in $CONTAINERS; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
    
    if [[ "$STATUS" != "healthy" ]]; then
        sudo -u "$ADMIN_USER" bash -c "echo -e 'Subject: [ALERT] Container $container unhealthy\n\nContainer $container status: $STATUS\nTimestamp: $(date)' | msmtp '$ALERT_EMAIL'"
    fi
done
