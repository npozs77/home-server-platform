#!/bin/bash
# Task: Verify Samba shares accessible
# Phase: 3 (Core Services)
# Number: 05
# Prerequisites:
#   - Samba container running
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
# Environment Variables Required:
#   None
# Environment Variables Optional:
#   None

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate prerequisites
if ! docker ps --format '{{.Names}}' | grep -q '^samba$'; then
    echo "Error: Samba container not running - run task 3.2 first" >&2
    exit 1
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would verify Samba container is running"
    echo "[DRY-RUN] Would test Samba connectivity"
    echo "[DRY-RUN] Would list available shares"
else
    echo ""
    echo "========================================"
    echo "Verifying Samba Service"
    echo "========================================"
    echo ""
    
    # Check container health
    echo "Checking Samba container status..."
    container_status=$(docker inspect --format='{{.State.Status}}' samba 2>/dev/null || echo "not found")
    
    if [[ "$container_status" == "running" ]]; then
        echo "✓ Samba container is running"
    else
        echo "✗ Samba container status: $container_status" >&2
        exit 1
    fi
    
    # Check if smbclient is available
    if ! command -v smbclient &> /dev/null; then
        echo "smbclient not installed, installing..."
        apt-get update -qq
        apt-get install -y -qq smbclient
    fi
    
    # Test Samba connectivity
    echo "Testing Samba connectivity..."
    if smbclient -L //localhost -N &> /dev/null; then
        echo "✓ Samba is responding to connections"
    else
        echo "✗ Samba is not responding to connections" >&2
        docker logs samba --tail 50
        exit 1
    fi
    
    # List available shares
    echo "Listing available shares..."
    echo ""
    smbclient -L //localhost -N 2>/dev/null | grep -A 100 "Sharename" || true
    echo ""
    
    # Verify expected shares exist
    echo "Verifying expected shares..."
    shares_output=$(smbclient -L //localhost -N 2>/dev/null || echo "")
    
    if echo "$shares_output" | grep -q "Family"; then
        echo "✓ Family share is available"
    else
        echo "✗ Family share not found" >&2
        exit 1
    fi
    
    if echo "$shares_output" | grep -q "Media"; then
        echo "✓ Media share is available"
    else
        echo "✗ Media share not found" >&2
        exit 1
    fi
    
    # Verify Samba ports are listening
    echo "Verifying Samba ports..."
    if netstat -tuln 2>/dev/null | grep -q ":139 "; then
        echo "✓ Port 139 (NetBIOS) is listening"
    else
        echo "✗ Port 139 (NetBIOS) is not listening" >&2
        exit 1
    fi
    
    if netstat -tuln 2>/dev/null | grep -q ":445 "; then
        echo "✓ Port 445 (SMB) is listening"
    else
        echo "✗ Port 445 (SMB) is not listening" >&2
        exit 1
    fi
    
    # Display connection instructions
    echo ""
    echo "========================================"
    echo "Samba Access Information"
    echo "========================================"
    echo ""
    echo "Samba is accessible from client devices:"
    echo ""
    printf '  Windows:  \\\\192.168.1.2\n'
    echo "  macOS:    smb://192.168.1.2"
    echo "  Linux:    smb://192.168.1.2"
    echo ""
    echo "Available shares:"
    echo "  - Family: Shared family folder (RW for family group)"
    echo "  - Media:  Curated media library (RW for media group, RO for others)"
    echo "  - Personal shares will be created during user provisioning"
    echo ""
    echo "Note: Users must be provisioned before they can access shares"
    echo "      Run user provisioning scripts in Task 4 to create users"
    echo ""
fi

echo "✓ Task complete"
exit 0
