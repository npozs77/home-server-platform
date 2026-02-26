#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Script for Network Configuration
# Purpose: Initial network setup on USB before SSH access available
# Prerequisites: Ubuntu Server LTS 24.04, root access
# Usage: sudo ./bootstrap.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

echo "========================================"
echo "Network Configuration Bootstrap"
echo "========================================"
echo ""

# Detect available network interfaces
print_info "Detecting network interfaces..."
interfaces=()
interface_names=()

# Get all network interfaces except loopback
while IFS= read -r iface; do
    if [[ "$iface" != "lo" ]]; then
        interfaces+=("$iface")
        # Get interface type (Ethernet or WiFi)
        if [[ -d "/sys/class/net/$iface/wireless" ]]; then
            interface_names+=("$iface (WiFi)")
        else
            interface_names+=("$iface (Ethernet)")
        fi
    fi
done < <(ls /sys/class/net/)

if [[ ${#interfaces[@]} -eq 0 ]]; then
    print_error "No network interfaces found"
    exit 1
fi

echo ""
echo "Detected interfaces:"
for i in "${!interface_names[@]}"; do
    echo "$((i+1)). ${interface_names[$i]}"
done
echo ""

# Select interface
while true; do
    read -p "Select interface [1-${#interfaces[@]}]: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#interfaces[@]} ]]; then
        break
    fi
    print_error "Invalid selection. Please enter a number between 1 and ${#interfaces[@]}"
done

selected_interface="${interfaces[$((selection-1))]}"
print_info "Selected interface: $selected_interface"
echo ""

# Check if WiFi interface
is_wifi=false
if [[ -d "/sys/class/net/$selected_interface/wireless" ]]; then
    is_wifi=true
fi

# Configure network
if [[ "$is_wifi" == true ]]; then
    print_info "Configuring WiFi..."
    echo ""
    
    # Get WiFi SSID
    read -p "Enter WiFi SSID: " wifi_ssid
    if [[ -z "$wifi_ssid" ]]; then
        print_error "SSID cannot be empty"
        exit 1
    fi
    
    # Get WiFi password
    read -sp "Enter WiFi password: " wifi_password
    echo ""
    if [[ -z "$wifi_password" ]]; then
        print_error "Password cannot be empty"
        exit 1
    fi
    
    # Create netplan configuration for WiFi
    cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  wifis:
    $selected_interface:
      dhcp4: true
      access-points:
        "$wifi_ssid":
          password: "$wifi_password"
EOF
    
else
    print_info "Configuring Ethernet..."
    
    # Create netplan configuration for Ethernet
    cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $selected_interface:
      dhcp4: true
EOF
fi

# Apply netplan configuration
print_info "Applying network configuration..."
netplan apply

# Wait for network to come up
print_info "Waiting for network connection..."
sleep 5

# Test connectivity
print_info "Testing connectivity..."
if ping -c 3 8.8.8.8 > /dev/null 2>&1; then
    print_success "Network configured successfully"
else
    print_error "Network connectivity test failed"
    print_info "Please check your network settings and try again"
    exit 1
fi

# Get and display MAC address
mac_address=$(ip link show "$selected_interface" | grep "link/ether" | awk '{print $2}')
echo ""
echo "========================================"
print_success "Bootstrap complete!"
echo "========================================"
echo ""
print_info "MAC Address: $mac_address"
echo ""
echo "Next steps:"
echo "1. Configure DHCP reservation on router"
echo "   - MAC Address: $mac_address"
echo "   - IP Address: 192.168.1.2"
echo "2. Reboot server to obtain new IP"
echo "3. SSH into server: ssh admin@192.168.1.2"
echo ""
