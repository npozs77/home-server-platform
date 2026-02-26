#!/usr/bin/env bash
set -euo pipefail

# Phase 01 - Foundation Layer Deployment Script
# Purpose: Automate foundation layer deployment with validation
# Prerequisites: Ubuntu Server LTS 24.04, network configured
# Usage: sudo ./deploy-phase1-foundation.sh [--dry-run]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration file path
CONFIG_FILE="/opt/homeserver/configs/phase1-config.env"

# Dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "Running in DRY-RUN mode (no changes will be made)"
    echo ""
fi

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

print_header() {
    echo -e "${BLUE}$1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Load configuration if exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

# Save configuration
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
# Phase 01 Foundation Configuration
# Generated: $(date)

# Server Configuration
TIMEZONE="$TIMEZONE"
HOSTNAME="$HOSTNAME"
SERVER_IP="$SERVER_IP"

# User Configuration
ADMIN_USER="$ADMIN_USER"
ADMIN_EMAIL="$ADMIN_EMAIL"

# Security Configuration
DATA_DISK="$DATA_DISK"
LUKS_PASSPHRASE="$LUKS_PASSPHRASE"

# Git Configuration
GIT_USER_NAME="$GIT_USER_NAME"
GIT_USER_EMAIL="$GIT_USER_EMAIL"

# Network Configuration
NETWORK_INTERFACE="$NETWORK_INTERFACE"
EOF
    chmod 600 "$CONFIG_FILE"
    print_success "Configuration saved to $CONFIG_FILE"
}

# Initialize/Update configuration
init_config() {
    print_header "Configuration Initialization"
    echo ""
    
    # Load existing config if available
    if load_config; then
        print_info "Loading existing configuration..."
        echo ""
    fi
    
    # Server Configuration
    read -p "Timezone [${TIMEZONE:-Europe/Amsterdam}]: " input
    TIMEZONE="${input:-${TIMEZONE:-Europe/Amsterdam}}"
    
    read -p "Hostname [${HOSTNAME:-homeserver}]: " input
    HOSTNAME="${input:-${HOSTNAME:-homeserver}}"
    
    read -p "Server IP [${SERVER_IP:-192.168.1.2}]: " input
    SERVER_IP="${input:-${SERVER_IP:-192.168.1.2}}"
    
    # User Configuration
    read -p "Admin user [${ADMIN_USER:-$SUDO_USER}]: " input
    ADMIN_USER="${input:-${ADMIN_USER:-$SUDO_USER}}"
    
    read -p "Admin email [${ADMIN_EMAIL:-admin@example.com}]: " input
    ADMIN_EMAIL="${input:-${ADMIN_EMAIL:-admin@example.com}}"
    
    # Security Configuration
    echo ""
    print_info "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    echo ""
    read -p "Data disk [${DATA_DISK:-/dev/sdb}]: " input
    DATA_DISK="${input:-${DATA_DISK:-/dev/sdb}}"
    
    read -sp "LUKS passphrase (20+ characters): " input
    echo ""
    LUKS_PASSPHRASE="${input:-${LUKS_PASSPHRASE:-}}"
    
    # Git Configuration
    read -p "Git user name [${GIT_USER_NAME:-Admin User}]: " input
    GIT_USER_NAME="${input:-${GIT_USER_NAME:-Admin User}}"
    
    read -p "Git user email [${GIT_USER_EMAIL:-admin@home.mydomain.com}]: " input
    GIT_USER_EMAIL="${input:-${GIT_USER_EMAIL:-admin@home.mydomain.com}}"
    
    # Network Configuration
    NETWORK_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    read -p "Network interface [${NETWORK_INTERFACE}]: " input
    NETWORK_INTERFACE="${input:-${NETWORK_INTERFACE}}"
    
    echo ""
    save_config
}

# Validate configuration
validate_config() {
    print_header "Configuration Validation"
    echo ""
    
    if ! load_config; then
        print_error "Configuration file not found. Run option 0 to initialize."
        return 1
    fi
    
    local status="PASS"
    
    # Validate timezone
    if timedatectl list-timezones | grep -q "^${TIMEZONE}$"; then
        print_success "Timezone is valid: $TIMEZONE"
    else
        print_error "Timezone is invalid: $TIMEZONE"
        status="FAIL"
    fi
    
    # Validate hostname
    if [[ "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
        print_success "Hostname is valid: $HOSTNAME"
    else
        print_error "Hostname is invalid: $HOSTNAME"
        status="FAIL"
    fi
    
    # Validate server IP
    if [[ "$SERVER_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_success "Server IP is valid: $SERVER_IP"
    else
        print_error "Server IP is invalid: $SERVER_IP"
        status="FAIL"
    fi
    
    # Validate admin user
    if id "$ADMIN_USER" &>/dev/null; then
        print_success "Admin user exists: $ADMIN_USER"
    else
        print_error "Admin user does not exist: $ADMIN_USER"
        status="FAIL"
    fi
    
    # Validate admin email
    if [[ "$ADMIN_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        print_success "Admin email format is valid: $ADMIN_EMAIL"
    else
        print_error "Admin email format is invalid: $ADMIN_EMAIL"
        status="FAIL"
    fi
    
    # Validate data disk
    if [[ -b "$DATA_DISK" ]]; then
        print_success "Data disk exists: $DATA_DISK"
    else
        print_error "Data disk does not exist: $DATA_DISK"
        status="FAIL"
    fi
    
    # Validate LUKS passphrase
    if [[ ${#LUKS_PASSPHRASE} -ge 20 ]]; then
        print_success "LUKS passphrase is strong (20+ characters)"
    else
        print_error "LUKS passphrase is too weak (<20 characters)"
        status="FAIL"
    fi
    
    # Validate Git user name
    if [[ -n "$GIT_USER_NAME" ]]; then
        print_success "Git user name is set: $GIT_USER_NAME"
    else
        print_error "Git user name is not set"
        status="FAIL"
    fi
    
    # Validate Git user email
    if [[ "$GIT_USER_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        print_success "Git user email is valid: $GIT_USER_EMAIL"
    else
        print_error "Git user email is invalid: $GIT_USER_EMAIL"
        status="FAIL"
    fi
    
    echo ""
    if [[ "$status" == "PASS" ]]; then
        print_success "All checks passed!"
        return 0
    else
        print_error "Some checks failed. Please fix configuration."
        return 1
    fi
}

# Task 1: Update system packages and set timezone/hostname
execute_task_1() {
    print_header "Task 1: Update System Packages and Basic Security"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would update package lists"
        print_info "[DRY-RUN] Would upgrade all packages"
        print_info "[DRY-RUN] Would set timezone to: $TIMEZONE"
        print_info "[DRY-RUN] Would set hostname to: $HOSTNAME"
        print_info "[DRY-RUN] Would install essential tools"
        return 0
    fi
    
    # Update package lists
    print_info "Updating package lists..."
    apt update
    
    # Upgrade packages
    print_info "Upgrading packages..."
    apt upgrade -y
    
    # Set timezone
    print_info "Setting timezone to $TIMEZONE..."
    timedatectl set-timezone "$TIMEZONE"
    
    # Set hostname
    print_info "Setting hostname to $HOSTNAME..."
    hostnamectl set-hostname "$HOSTNAME"
    
    # Install essential tools
    print_info "Installing essential tools..."
    apt install -y git vim curl wget htop net-tools
    
    print_success "Task 1 complete"
}

# Task 2: Set up LUKS disk encryption
execute_task_2() {
    print_header "Task 2: Set up LUKS Disk Encryption"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would format $DATA_DISK with LUKS encryption"
        print_info "[DRY-RUN] Would create ext4 filesystem"
        print_info "[DRY-RUN] Would generate key file at /root/.luks-key"
        print_info "[DRY-RUN] Would configure /etc/crypttab and /etc/fstab"
        print_info "[DRY-RUN] Would create mount point /mnt/data"
        return 0
    fi
    
    # Check if already encrypted
    if cryptsetup isLuks "$DATA_DISK" 2>/dev/null; then
        print_info "Disk $DATA_DISK is already LUKS encrypted"
        
        # Check if already opened
        if [[ -e /dev/mapper/data_crypt ]]; then
            print_info "Encrypted partition already opened"
        else
            print_info "Opening encrypted partition..."
            echo -n "$LUKS_PASSPHRASE" | cryptsetup luksOpen "$DATA_DISK" data_crypt -
        fi
        
        # Check if filesystem exists
        if blkid /dev/mapper/data_crypt | grep -q "TYPE=\"ext4\""; then
            print_info "Filesystem already exists"
        else
            print_info "Creating ext4 filesystem..."
            mkfs.ext4 /dev/mapper/data_crypt
        fi
    else
        print_info "Formatting $DATA_DISK with LUKS encryption..."
        echo -n "$LUKS_PASSPHRASE" | cryptsetup luksFormat "$DATA_DISK" -
        
        print_info "Opening encrypted partition..."
        echo -n "$LUKS_PASSPHRASE" | cryptsetup luksOpen "$DATA_DISK" data_crypt -
        
        print_info "Creating ext4 filesystem..."
        mkfs.ext4 /dev/mapper/data_crypt
    fi
    
    # Generate key file if not exists
    if [[ ! -f /root/.luks-key ]]; then
        print_info "Generating key file..."
        dd if=/dev/urandom of=/root/.luks-key bs=1024 count=4
        chmod 600 /root/.luks-key
        chown root:root /root/.luks-key
        
        print_info "Adding key file to LUKS..."
        echo -n "$LUKS_PASSPHRASE" | cryptsetup luksAddKey "$DATA_DISK" /root/.luks-key -
    else
        print_info "Key file already exists"
    fi
    
    # Get UUID
    UUID=$(blkid -s UUID -o value "$DATA_DISK")
    
    # Configure /etc/crypttab if not already configured
    if ! grep -q "data_crypt" /etc/crypttab 2>/dev/null; then
        print_info "Configuring /etc/crypttab..."
        echo "data_crypt UUID=$UUID /root/.luks-key luks" >> /etc/crypttab
    else
        print_info "/etc/crypttab already configured"
    fi
    
    # Configure /etc/fstab if not already configured
    if ! grep -q "/mnt/data" /etc/fstab 2>/dev/null; then
        print_info "Configuring /etc/fstab..."
        echo "/dev/mapper/data_crypt /mnt/data ext4 defaults 0 2" >> /etc/fstab
    else
        print_info "/etc/fstab already configured"
    fi
    
    # Create mount point
    mkdir -p /mnt/data
    
    # Test mount
    print_info "Testing mount..."
    mount -a
    
    print_success "Task 2 complete"
}

# Task 3: Harden SSH access
execute_task_3() {
    print_header "Task 3: Harden SSH Access"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would backup SSH config"
        print_info "[DRY-RUN] Would set PasswordAuthentication no"
        print_info "[DRY-RUN] Would set PubkeyAuthentication yes"
        print_info "[DRY-RUN] Would set PermitRootLogin no"
        print_info "[DRY-RUN] Would restart SSH service"
        return 0
    fi
    
    # Backup SSH config if not already backed up
    if [[ ! -f /etc/ssh/sshd_config.backup ]]; then
        print_info "Backing up SSH config..."
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    fi
    
    # Update SSH config
    print_info "Updating SSH configuration..."
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
    sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 12/' /etc/ssh/sshd_config
    
    # Add if not present
    grep -q "^ClientAliveInterval" /etc/ssh/sshd_config || echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
    grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config || echo "ClientAliveCountMax 12" >> /etc/ssh/sshd_config
    
    # Test config
    print_info "Testing SSH configuration..."
    sshd -t
    
    # Restart SSH
    print_info "Restarting SSH service..."
    systemctl restart ssh
    
    print_success "Task 3 complete"
    print_info "IMPORTANT: Ensure SSH key authentication is working before logging out!"
}

# Task 4: Configure firewall (UFW)
execute_task_4() {
    print_header "Task 4: Configure Firewall (UFW)"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install UFW"
        print_info "[DRY-RUN] Would set default policies"
        print_info "[DRY-RUN] Would allow SSH from LAN"
        print_info "[DRY-RUN] Would allow HTTP/HTTPS from LAN"
        print_info "[DRY-RUN] Would allow Samba from LAN"
        print_info "[DRY-RUN] Would enable UFW"
        return 0
    fi
    
    # Install UFW
    if ! command -v ufw &> /dev/null; then
        print_info "Installing UFW..."
        apt install -y ufw
    else
        print_info "UFW already installed"
    fi
    
    # Set default policies
    print_info "Setting default policies..."
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH from LAN
    print_info "Allowing SSH from LAN..."
    ufw allow from 192.168.1.0/24 to any port 22
    
    # Allow HTTP/HTTPS from LAN
    print_info "Allowing HTTP/HTTPS from LAN..."
    ufw allow from 192.168.1.0/24 to any port 80
    ufw allow from 192.168.1.0/24 to any port 443
    
    # Allow Samba from LAN
    print_info "Allowing Samba from LAN..."
    ufw allow from 192.168.1.0/24 to any port 139
    ufw allow from 192.168.1.0/24 to any port 445
    
    # Allow DNS from LAN (for Pi-hole in Phase 2)
    print_info "Allowing DNS from LAN..."
    ufw allow from 192.168.1.0/24 to any port 53 proto tcp
    ufw allow from 192.168.1.0/24 to any port 53 proto udp
    
    # Enable UFW
    print_info "Enabling UFW..."
    echo "y" | ufw enable
    
    print_success "Task 4 complete"
}

# Task 5: Set up fail2ban
execute_task_5() {
    print_header "Task 5: Set up fail2ban"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install fail2ban"
        print_info "[DRY-RUN] Would create local configuration"
        print_info "[DRY-RUN] Would configure SSH jail"
        print_info "[DRY-RUN] Would start and enable fail2ban"
        return 0
    fi
    
    # Install fail2ban
    if ! command -v fail2ban-client &> /dev/null; then
        print_info "Installing fail2ban..."
        apt install -y fail2ban
    else
        print_info "fail2ban already installed"
    fi
    
    # Create local configuration if not exists
    if [[ ! -f /etc/fail2ban/jail.local ]]; then
        print_info "Creating local configuration..."
        cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    fi
    
    # Configure SSH jail
    print_info "Configuring SSH jail..."
    cat > /etc/fail2ban/jail.d/sshd.local << 'EOF'
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 3600
EOF
    
    # Start and enable fail2ban
    print_info "Starting fail2ban..."
    systemctl start fail2ban
    systemctl enable fail2ban
    
    print_success "Task 5 complete"
}

# Task 6: Install Docker and Docker Compose
execute_task_6() {
    print_header "Task 6: Install Docker and Docker Compose"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install Docker prerequisites"
        print_info "[DRY-RUN] Would add Docker repository"
        print_info "[DRY-RUN] Would install Docker Engine and Docker Compose"
        print_info "[DRY-RUN] Would configure Docker daemon"
        print_info "[DRY-RUN] Would add $ADMIN_USER to docker group"
        return 0
    fi
    
    # Check if Docker already installed
    if command -v docker &> /dev/null; then
        print_info "Docker already installed"
    else
        # Install prerequisites
        print_info "Installing prerequisites..."
        apt install -y ca-certificates curl gnupg lsb-release
        
        # Add Docker's official GPG key
        print_info "Adding Docker GPG key..."
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Set up Docker repository
        print_info "Setting up Docker repository..."
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Update package index
        apt update
        
        # Install Docker Engine and Docker Compose
        print_info "Installing Docker Engine and Docker Compose..."
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    
    # Configure Docker daemon
    print_info "Configuring Docker daemon..."
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
    
    # Restart Docker
    print_info "Restarting Docker..."
    systemctl restart docker
    
    # Add admin user to docker group
    print_info "Adding $ADMIN_USER to docker group..."
    usermod -aG docker "$ADMIN_USER"
    
    print_success "Task 6 complete"
    print_info "Note: $ADMIN_USER needs to log out and back in for docker group to take effect"
}

# Task 7: Initialize infrastructure Git repository
execute_task_7() {
    print_header "Task 7: Initialize Infrastructure Git Repository"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create /opt/homeserver directory"
        print_info "[DRY-RUN] Would initialize Git repository"
        print_info "[DRY-RUN] Would create directory structure"
        print_info "[DRY-RUN] Would create README.md and .gitignore"
        print_info "[DRY-RUN] Would make initial commit"
        return 0
    fi
    
    # Create infrastructure directory
    print_info "Creating infrastructure directory..."
    mkdir -p /opt/homeserver
    chown "$ADMIN_USER:$ADMIN_USER" /opt/homeserver
    
    # Initialize Git if not already initialized
    if [[ ! -d /opt/homeserver/.git ]]; then
        print_info "Initializing Git repository..."
        cd /opt/homeserver
        sudo -u "$ADMIN_USER" git init -b main
        sudo -u "$ADMIN_USER" git config user.name "$GIT_USER_NAME"
        sudo -u "$ADMIN_USER" git config user.email "$GIT_USER_EMAIL"
    else
        print_info "Git repository already initialized"
        cd /opt/homeserver
    fi
    
    # Create directory structure
    print_info "Creating directory structure..."
    sudo -u "$ADMIN_USER" mkdir -p docs
    sudo -u "$ADMIN_USER" mkdir -p scripts/{backup,deploy,maintenance,monitoring,operations}
    sudo -u "$ADMIN_USER" mkdir -p configs
    sudo -u "$ADMIN_USER" mkdir -p configs/{docker-compose,caddy,samba,wiki,foundation}
    sudo -u "$ADMIN_USER" mkdir -p assets
    sudo -u "$ADMIN_USER" mkdir -p templates
    
    # Create README.md if not exists
    if [[ ! -f README.md ]]; then
        print_info "Creating README.md..."
        sudo -u "$ADMIN_USER" tee README.md > /dev/null << 'EOF'
# Home Media Server Infrastructure

Infrastructure as Code for home media server platform.

## Structure

- `docs/` - Documentation
- `scripts/` - Automation scripts
- `configs/` - Service configurations
- `assets/` - Diagrams and screenshots
- `templates/` - Reusable templates

## Phases

- Phase 01: Foundation Layer
- Phase 02: Infrastructure Services
- Phase 03: Core Services
- Phase 04: Applications

## Version

Current version: 0.1
EOF
    fi
    
    # Create .gitignore if not exists
    if [[ ! -f .gitignore ]]; then
        print_info "Creating .gitignore..."
        sudo -u "$ADMIN_USER" tee .gitignore > /dev/null << 'EOF'
# Sensitive files
*.key
*.pem
*.env
.env
*.secret

# Backup files
*.backup
*.bak
*~

# OS files
.DS_Store
Thumbs.db

# Editor files
.vscode/
.idea/
*.swp
*.swo
EOF
    fi
    
    # Make initial commit if no commits yet
    if ! sudo -u "$ADMIN_USER" git log &>/dev/null; then
        print_info "Making initial commit..."
        sudo -u "$ADMIN_USER" git add .
        sudo -u "$ADMIN_USER" git commit -m "Initial infrastructure repository setup"
    else
        print_info "Repository already has commits"
    fi
    
    print_success "Task 7 complete"
}

# Task 8: Set up automated security updates
execute_task_8() {
    print_header "Task 8: Set up Automated Security Updates"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install unattended-upgrades"
        print_info "[DRY-RUN] Would configure automatic updates"
        print_info "[DRY-RUN] Would enable automatic reboot at 3:00 AM"
        print_info "[DRY-RUN] Would start and enable service"
        return 0
    fi
    
    # Install unattended-upgrades
    if ! dpkg -l | grep -q unattended-upgrades; then
        print_info "Installing unattended-upgrades..."
        apt install -y unattended-upgrades
    else
        print_info "unattended-upgrades already installed"
    fi
    
    # Configure unattended-upgrades
    print_info "Configuring unattended-upgrades..."
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
    
    # Enable automatic updates
    print_info "Enabling automatic updates..."
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    
    # Start and enable service
    print_info "Starting unattended-upgrades service..."
    systemctl start unattended-upgrades
    systemctl enable unattended-upgrades
    
    print_success "Task 8 complete"
}

# Validation functions
validate_ssh_hardening() {
    local status="PASS"
    
    # Check password auth disabled
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
        print_success "Password authentication disabled"
    else
        print_error "Password authentication NOT disabled"
        status="FAIL"
    fi
    
    # Check pubkey auth enabled
    if grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config; then
        print_success "Public key authentication enabled"
    else
        print_error "Public key authentication NOT enabled"
        status="FAIL"
    fi
    
    # Check root login disabled
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
        print_success "Root login disabled"
    else
        print_error "Root login NOT disabled"
        status="FAIL"
    fi
    
    # Check idle timeout configured
    if grep -q "^ClientAliveInterval 300" /etc/ssh/sshd_config; then
        print_success "Idle timeout configured (1 hour)"
    else
        print_error "Idle timeout NOT configured"
        status="FAIL"
    fi
    
    # Check SSH service running
    if systemctl is-active --quiet ssh; then
        print_success "SSH service running"
    else
        print_error "SSH service NOT running"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_ufw_firewall() {
    local status="PASS"
    
    # Check UFW active
    if ufw status | grep -q "Status: active"; then
        print_success "UFW firewall active"
    else
        print_error "UFW firewall NOT active"
        status="FAIL"
    fi
    
    # Check SSH rule
    if ufw status | grep -q "22.*ALLOW.*192.168.1.0/24"; then
        print_success "SSH allowed from LAN"
    else
        print_error "SSH NOT allowed from LAN"
        status="FAIL"
    fi
    
    # Check HTTP/HTTPS rules
    if ufw status | grep -q "80.*ALLOW.*192.168.1.0/24"; then
        print_success "HTTP allowed from LAN"
    else
        print_error "HTTP NOT allowed from LAN"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_fail2ban() {
    local status="PASS"
    
    # Check fail2ban service
    if systemctl is-active --quiet fail2ban; then
        print_success "fail2ban service running"
    else
        print_error "fail2ban service NOT running"
        status="FAIL"
    fi
    
    # Check SSH jail
    if fail2ban-client status sshd &>/dev/null; then
        print_success "SSH jail active"
    else
        print_error "SSH jail NOT active"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_docker() {
    local status="PASS"
    
    # Check Docker installed
    if command -v docker &> /dev/null; then
        print_success "Docker installed"
    else
        print_error "Docker NOT installed"
        status="FAIL"
    fi
    
    # Check Docker Compose
    if docker compose version &>/dev/null; then
        print_success "Docker Compose installed"
    else
        print_error "Docker Compose NOT installed"
        status="FAIL"
    fi
    
    # Check Docker service
    if systemctl is-active --quiet docker; then
        print_success "Docker service running"
    else
        print_error "Docker service NOT running"
        status="FAIL"
    fi
    
    # Test Docker
    if docker run --rm hello-world &>/dev/null; then
        print_success "Docker functional (hello-world test passed)"
    else
        print_error "Docker NOT functional (hello-world test failed)"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_git_repository() {
    local status="PASS"
    
    # Check Git repository exists
    if [[ -d /opt/homeserver/.git ]]; then
        print_success "Git repository initialized"
    else
        print_error "Git repository NOT initialized"
        status="FAIL"
    fi
    
    # Check directory structure
    if [[ -d /opt/homeserver/docs ]] && [[ -d /opt/homeserver/scripts ]] && [[ -d /opt/homeserver/configs ]]; then
        print_success "Directory structure exists"
    else
        print_error "Directory structure incomplete"
        status="FAIL"
    fi
    
    # Check initial commit
    if git -C /opt/homeserver log &>/dev/null; then
        print_success "Initial commit exists"
    else
        print_error "No commits in repository"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_unattended_upgrades() {
    local status="PASS"
    
    # Check service
    if systemctl is-active --quiet unattended-upgrades; then
        print_success "unattended-upgrades service running"
    else
        print_error "unattended-upgrades service NOT running"
        status="FAIL"
    fi
    
    # Check configuration
    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
        print_success "Auto-upgrades configured"
    else
        print_error "Auto-upgrades NOT configured"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_luks_encryption() {
    local status="PASS"
    
    if ! load_config; then
        print_error "Configuration not loaded"
        return 1
    fi
    
    # Check LUKS encryption
    if cryptsetup isLuks "$DATA_DISK" 2>/dev/null; then
        print_success "Data partition encrypted with LUKS"
    else
        print_error "Data partition NOT encrypted"
        status="FAIL"
    fi
    
    # Check mount
    if df -h | grep -q "/mnt/data"; then
        print_success "Data partition mounted"
    else
        print_error "Data partition NOT mounted"
        status="FAIL"
    fi
    
    # Check key file
    if [[ -f /root/.luks-key ]]; then
        if [[ "$(stat -c %a /root/.luks-key)" == "600" ]]; then
            print_success "Key file has correct permissions (600)"
        else
            print_error "Key file has incorrect permissions"
            status="FAIL"
        fi
    else
        print_error "Key file NOT found"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_docker_group() {
    local status="PASS"
    
    if ! load_config; then
        print_error "Configuration not loaded"
        return 1
    fi
    
    # Check user in docker group
    if groups "$ADMIN_USER" | grep -q docker; then
        print_success "$ADMIN_USER in docker group"
    else
        print_error "$ADMIN_USER NOT in docker group"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_essential_tools() {
    local status="PASS"
    
    # Check essential tools
    for tool in git vim curl wget htop; do
        if command -v "$tool" &> /dev/null; then
            print_success "$tool installed"
        else
            print_error "$tool NOT installed"
            status="FAIL"
        fi
    done
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

# Validate all
validate_all() {
    print_header "Phase 01 Foundation Validation"
    echo ""
    
    local total=0
    local passed=0
    
    # Run all validation checks
    checks=(
        "SSH Hardening:validate_ssh_hardening"
        "UFW Firewall:validate_ufw_firewall"
        "fail2ban:validate_fail2ban"
        "Docker:validate_docker"
        "Git Repository:validate_git_repository"
        "Unattended-upgrades:validate_unattended_upgrades"
        "LUKS Encryption:validate_luks_encryption"
        "Docker Group:validate_docker_group"
        "Essential Tools:validate_essential_tools"
    )
    
    for check in "${checks[@]}"; do
        name="${check%%:*}"
        func="${check##*:}"
        total=$((total + 1))
        
        printf "%-30s " "$name"
        if $func > /tmp/validation_output 2>&1; then
            echo -e "${GREEN}✓ PASS${NC}"
            passed=$((passed + 1))
        else
            echo -e "${RED}✗ FAIL${NC}"
            cat /tmp/validation_output
        fi
        echo ""
    done
    
    echo ""
    echo "========================================"
    echo "Results: $passed/$total checks passed"
    echo "========================================"
    
    if [[ $passed -eq $total ]]; then
        print_success "All checks passed! ✓"
        return 0
    else
        print_error "Some checks failed. Please review and fix issues."
        return 1
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "========================================"
    print_header "Phase 01 - Foundation Layer Deployment"
    echo "========================================"
    echo ""
    echo "0. Initialize/Update configuration"
    echo "c. Validate configuration"
    echo ""
    echo "1. Update system packages and set timezone/hostname"
    echo "2. Set up LUKS disk encryption"
    echo "3. Harden SSH access"
    echo "4. Configure firewall (UFW)"
    echo "5. Set up fail2ban"
    echo "6. Install Docker and Docker Compose"
    echo "7. Initialize infrastructure Git repository"
    echo "8. Set up automated security updates"
    echo ""
    echo "v. Validate all"
    echo "q. Quit"
    echo ""
}

# Main loop
main() {
    while true; do
        show_menu
        read -p "Select option [0,c,1-8,v,q]: " option
        echo ""
        
        case $option in
            0) init_config ;;
            c) validate_config ;;
            1) execute_task_1 ;;
            2) execute_task_2 ;;
            3) execute_task_3 ;;
            4) execute_task_4 ;;
            5) execute_task_5 ;;
            6) execute_task_6 ;;
            7) execute_task_7 ;;
            8) execute_task_8 ;;
            v) validate_all ;;
            q) 
                echo "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please try again."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main
main
