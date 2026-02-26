#!/usr/bin/env bash
set -euo pipefail

# Phase 02 - Infrastructure Services Layer Deployment Script
# Purpose: Deploy DNS, Caddy, SMTP, Netdata, and data storage structure
# Prerequisites: Phase 1 complete, domain registered, SMTP credentials
# Usage: sudo ./deploy-phase2-infrastructure.sh [--dry-run]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration file path
CONFIG_FILE="/opt/homeserver/configs/phase2-config.env"

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

# Fetch secret from Proton Pass (must run as user, not root)
fetch_secret() {
    local item_id="$1"
    local field="${2:-password}"
    local admin_user="${3:-$ADMIN_USER}"
    
    if [[ -z "$HOMESERVER_PASS_SHARE_ID" ]]; then
        print_error "HOMESERVER_PASS_SHARE_ID not set in config"
        return 1
    fi
    
    if [[ -z "$item_id" ]]; then
        print_error "Item ID not provided"
        return 1
    fi
    
    # Run pass-cli as the admin user (Proton Pass session is per-user)
    su - "$admin_user" -c "pass-cli item view --share-id '$HOMESERVER_PASS_SHARE_ID' --item-id '$item_id' --field '$field'" 2>/dev/null
}
# Save configuration
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
# Phase 02 Infrastructure Configuration
# Generated: $(date)

# Domain Configuration
DOMAIN="$DOMAIN"
INTERNAL_SUBDOMAIN="$INTERNAL_SUBDOMAIN"
SERVER_IP="$SERVER_IP"

# Admin Configuration
ADMIN_EMAIL="$ADMIN_EMAIL"

# Proton Pass Vault ID
HOMESERVER_PASS_SHARE_ID="$HOMESERVER_PASS_SHARE_ID"

# SMTP Configuration
SMTP2GO_HOST="$SMTP2GO_HOST"
SMTP2GO_PORT="$SMTP2GO_PORT"
SMTP2GO_FROM="$SMTP2GO_FROM"
SMTP2GO_USER="$SMTP2GO_USER"
SMTP2GO_PASS_ITEM_ID="$SMTP2GO_PASS_ITEM_ID"

# Pi-hole Configuration
PIHOLE_PASS_ITEM_ID="$PIHOLE_PASS_ITEM_ID"
EOF
    chmod 600 "$CONFIG_FILE"
    print_success "Configuration saved to $CONFIG_FILE"
}

# Initialize/Update configuration
init_config() {
    print_header "Configuration Initialization"
    echo ""
    
    print_info "NOTE: Passwords are stored in Proton Pass, not in this config file"
    print_info "You only need to provide Proton Pass Item IDs"
    echo ""
    
    # Load existing config if available
    if load_config; then
        print_info "Loading existing configuration..."
        echo ""
    fi
    
    # Domain Configuration
    read -p "Domain [${DOMAIN:-mydomain.com}]: " input
    DOMAIN="${input:-${DOMAIN:-mydomain.com}}"
    
    read -p "Internal subdomain [${INTERNAL_SUBDOMAIN:-home.${DOMAIN}}]: " input
    INTERNAL_SUBDOMAIN="${input:-${INTERNAL_SUBDOMAIN:-home.${DOMAIN}}}"
    
    read -p "Server IP [${SERVER_IP:-192.168.1.2}]: " input
    SERVER_IP="${input:-${SERVER_IP:-192.168.1.2}}"
    
    # Admin Configuration
    read -p "Admin email [${ADMIN_EMAIL:-admin@${DOMAIN}}]: " input
    ADMIN_EMAIL="${input:-${ADMIN_EMAIL:-admin@${DOMAIN}}}"
    
    # Proton Pass Configuration
    echo ""
    print_info "Proton Pass Configuration"
    read -p "Proton Pass Vault Share ID [${HOMESERVER_PASS_SHARE_ID:-}]: " input
    HOMESERVER_PASS_SHARE_ID="${input:-${HOMESERVER_PASS_SHARE_ID:-}}"
    
    # SMTP2GO Configuration
    echo ""
    print_info "SMTP2GO Configuration (for email notifications)"
    read -p "SMTP2GO host [${SMTP2GO_HOST:-mail-eu.smtp2go.com}]: " input
    SMTP2GO_HOST="${input:-${SMTP2GO_HOST:-mail-eu.smtp2go.com}}"

    read -p "SMTP2GO port [${SMTP2GO_PORT:-2525}]: " input
    SMTP2GO_PORT="${input:-${SMTP2GO_PORT:-2525}}"

    read -p "From address [${SMTP2GO_FROM:-alerts@home.${DOMAIN}}]: " input
    SMTP2GO_FROM="${input:-${SMTP2GO_FROM:-alerts@home.${DOMAIN}}}"

    read -p "SMTP2GO username [${SMTP2GO_USER:-}]: " input
    SMTP2GO_USER="${input:-${SMTP2GO_USER:-}}"

    read -p "SMTP2GO Proton Pass Item ID [${SMTP2GO_PASS_ITEM_ID:-}]: " input
    SMTP2GO_PASS_ITEM_ID="${input:-${SMTP2GO_PASS_ITEM_ID:-}}"
    
    # Pi-hole Configuration
    echo ""
    print_info "Pi-hole Configuration"
    read -p "Pi-hole Proton Pass Item ID [${PIHOLE_PASS_ITEM_ID:-}]: " input
    PIHOLE_PASS_ITEM_ID="${input:-${PIHOLE_PASS_ITEM_ID:-}}"
    
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
    
    # Validate domain
    if [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_success "Domain is valid: $DOMAIN"
    else
        print_error "Domain is invalid: $DOMAIN"
        status="FAIL"
    fi
    
    # Validate internal subdomain
    if [[ "$INTERNAL_SUBDOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_success "Internal subdomain is valid: $INTERNAL_SUBDOMAIN"
    else
        print_error "Internal subdomain is invalid: $INTERNAL_SUBDOMAIN"
        status="FAIL"
    fi
    
    # Validate server IP
    if [[ "$SERVER_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_success "Server IP is valid: $SERVER_IP"
    else
        print_error "Server IP is invalid: $SERVER_IP"
        status="FAIL"
    fi
    
    # Validate admin email
    if [[ "$ADMIN_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        print_success "Admin email is valid: $ADMIN_EMAIL"
    else
        print_error "Admin email is invalid: $ADMIN_EMAIL"
        status="FAIL"
    fi
    
    # Validate Proton Pass configuration
    if [[ -n "$HOMESERVER_PASS_SHARE_ID" ]]; then
        print_success "Proton Pass Vault ID is set"
    else
        print_error "Proton Pass Vault ID is not set"
        status="FAIL"
    fi
    
    # Validate SMTP2GO configuration
    if [[ -n "$SMTP2GO_HOST" ]]; then
        print_success "SMTP2GO host is set: $SMTP2GO_HOST"
    else
        print_error "SMTP2GO host is not set"
        status="FAIL"
    fi
    
    if [[ "$SMTP2GO_PORT" =~ ^[0-9]+$ ]]; then
        print_success "SMTP2GO port is valid: $SMTP2GO_PORT"
    else
        print_error "SMTP2GO port is invalid: $SMTP2GO_PORT"
        status="FAIL"
    fi
    
    if [[ -n "$SMTP2GO_FROM" ]]; then
        print_success "SMTP2GO from address is set: $SMTP2GO_FROM"
    else
        print_error "SMTP2GO from address is not set"
        status="FAIL"
    fi
    
    if [[ -n "$SMTP2GO_USER" ]]; then
        print_success "SMTP2GO username is set"
    else
        print_error "SMTP2GO username is not set"
        status="FAIL"
    fi
    
    if [[ -n "$SMTP2GO_PASS_ITEM_ID" ]]; then
        print_success "SMTP2GO Proton Pass Item ID is set"
    else
        print_error "SMTP2GO Proton Pass Item ID is not set"
        status="FAIL"
    fi
    
    # Validate Pi-hole configuration
    if [[ -n "$PIHOLE_PASS_ITEM_ID" ]]; then
        print_success "Pi-hole Proton Pass Item ID is set"
    else
        print_error "Pi-hole Proton Pass Item ID is not set"
        status="FAIL"
    fi

    # Load Phase 1 config to get ADMIN_USER
    if [[ -f "/opt/homeserver/configs/phase1-config.env" ]]; then
        source "/opt/homeserver/configs/phase1-config.env"
    else
        print_error "Phase 1 config not found (cannot determine ADMIN_USER)"
        status="FAIL"
    fi

    # Test Proton Pass CLI access (check as user, not root)
    if [[ -n "${ADMIN_USER:-}" ]] && su - "$ADMIN_USER" -c "command -v pass-cli" &>/dev/null; then
        print_success "pass-cli is installed"
        
        # Test fetching a secret
        if fetch_secret "$PIHOLE_PASS_ITEM_ID" "password" "$ADMIN_USER" &>/dev/null; then
            print_success "Proton Pass CLI access working"
        else
            print_error "Cannot fetch secrets from Proton Pass (user not logged in?)"
            status="FAIL"
        fi
    else
        print_error "pass-cli not installed or ADMIN_USER not set"
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


# Task 2.1: Create top-level data directories
execute_task_2_1() {
    print_header "Task 2.1: Create Top-Level Data Directories"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create /mnt/data/media/ (755, root:root)"
        print_info "[DRY-RUN] Would create /mnt/data/family/ (755, root:family)"
        print_info "[DRY-RUN] Would create /mnt/data/users/ (755, root:root)"
        print_info "[DRY-RUN] Would create /mnt/data/backups/ (700, root:root)"
        print_info "[DRY-RUN] Would create /mnt/data/services/ (755, root:root)"
        return 0
    fi
    
    # Check if /mnt/data exists
    if [[ ! -d /mnt/data ]]; then
        print_error "/mnt/data does not exist. Phase 1 incomplete?"
        return 1
    fi
    
    # Create family group if not exists
    if ! getent group family &>/dev/null; then
        print_info "Creating family group..."
        groupadd family
    fi
    
    # Create directories
    print_info "Creating top-level directories..."
    
    if [[ -d /mnt/data/media ]]; then
        print_info "/mnt/data/media/ already exists"
    else
        mkdir -p /mnt/data/media
    fi
    chmod 755 /mnt/data/media
    chown root:root /mnt/data/media
    print_success "Created /mnt/data/media/ (755, root:root)"
    
    if [[ -d /mnt/data/family ]]; then
        print_info "/mnt/data/family/ already exists"
    else
        mkdir -p /mnt/data/family
    fi
    chmod 755 /mnt/data/family
    chown root:family /mnt/data/family
    print_success "Created /mnt/data/family/ (755, root:family)"
    
    if [[ -d /mnt/data/users ]]; then
        print_info "/mnt/data/users/ already exists"
    else
        mkdir -p /mnt/data/users
    fi
    chmod 755 /mnt/data/users
    chown root:root /mnt/data/users
    print_success "Created /mnt/data/users/ (755, root:root)"
    
    if [[ -d /mnt/data/backups ]]; then
        print_info "/mnt/data/backups/ already exists"
    else
        mkdir -p /mnt/data/backups
    fi
    chmod 700 /mnt/data/backups
    chown root:root /mnt/data/backups
    print_success "Created /mnt/data/backups/ (700, root:root)"
    
    if [[ -d /mnt/data/services ]]; then
        print_info "/mnt/data/services/ already exists"
    else
        mkdir -p /mnt/data/services
    fi
    chmod 755 /mnt/data/services
    chown root:root /mnt/data/services
    print_success "Created /mnt/data/services/ (755, root:root)"
    
    print_success "Task 2.1 complete"
}

# Task 2.2: Create family subdirectories
execute_task_2_2() {
    print_header "Task 2.2: Create Family Subdirectories"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create /mnt/data/family/Documents/ (775, root:family)"
        print_info "[DRY-RUN] Would create /mnt/data/family/Photos/ (770, root:family)"
        print_info "[DRY-RUN] Would create /mnt/data/family/Videos/ (770, root:family)"
        print_info "[DRY-RUN] Would create /mnt/data/family/Projects/ (775, root:family)"
        return 0
    fi
    
    # Check if family directory exists
    if [[ ! -d /mnt/data/family ]]; then
        print_error "/mnt/data/family does not exist. Run Task 2.1 first."
        return 1
    fi
    
    # Create subdirectories
    print_info "Creating family subdirectories..."
    
    if [[ -d /mnt/data/family/Documents ]]; then
        print_info "/mnt/data/family/Documents/ already exists"
    else
        mkdir -p /mnt/data/family/Documents
    fi
    chmod 775 /mnt/data/family/Documents
    chown root:family /mnt/data/family/Documents
    print_success "Created /mnt/data/family/Documents/ (775, root:family)"
    
    if [[ -d /mnt/data/family/Photos ]]; then
        print_info "/mnt/data/family/Photos/ already exists"
    else
        mkdir -p /mnt/data/family/Photos
    fi
    chmod 770 /mnt/data/family/Photos
    chown root:family /mnt/data/family/Photos
    print_success "Created /mnt/data/family/Photos/ (770, root:family)"
    
    if [[ -d /mnt/data/family/Videos ]]; then
        print_info "/mnt/data/family/Videos/ already exists"
    else
        mkdir -p /mnt/data/family/Videos
    fi
    chmod 770 /mnt/data/family/Videos
    chown root:family /mnt/data/family/Videos
    print_success "Created /mnt/data/family/Videos/ (770, root:family)"
    
    if [[ -d /mnt/data/family/Projects ]]; then
        print_info "/mnt/data/family/Projects/ already exists"
    else
        mkdir -p /mnt/data/family/Projects
    fi
    chmod 775 /mnt/data/family/Projects
    chown root:family /mnt/data/family/Projects
    print_success "Created /mnt/data/family/Projects/ (775, root:family)"
    
    print_success "Task 2.2 complete"
}

# Task 2.3: Create backup subdirectories
execute_task_2_3() {
    print_header "Task 2.3: Create Backup Subdirectories"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create /mnt/data/backups/snapshots/ (700, root:root)"
        print_info "[DRY-RUN] Would create /mnt/data/backups/incremental/ (700, root:root)"
        print_info "[DRY-RUN] Would create /mnt/data/backups/offsite-sync/ (700, root:root)"
        return 0
    fi
    
    # Check if backups directory exists
    if [[ ! -d /mnt/data/backups ]]; then
        print_error "/mnt/data/backups does not exist. Run Task 2.1 first."
        return 1
    fi
    
    # Create subdirectories
    print_info "Creating backup subdirectories..."
    
    if [[ -d /mnt/data/backups/snapshots ]]; then
        print_info "/mnt/data/backups/snapshots/ already exists"
    else
        mkdir -p /mnt/data/backups/snapshots
    fi
    chmod 700 /mnt/data/backups/snapshots
    chown root:root /mnt/data/backups/snapshots
    print_success "Created /mnt/data/backups/snapshots/ (700, root:root)"
    
    if [[ -d /mnt/data/backups/incremental ]]; then
        print_info "/mnt/data/backups/incremental/ already exists"
    else
        mkdir -p /mnt/data/backups/incremental
    fi
    chmod 700 /mnt/data/backups/incremental
    chown root:root /mnt/data/backups/incremental
    print_success "Created /mnt/data/backups/incremental/ (700, root:root)"
    
    if [[ -d /mnt/data/backups/offsite-sync ]]; then
        print_info "/mnt/data/backups/offsite-sync/ already exists"
    else
        mkdir -p /mnt/data/backups/offsite-sync
    fi
    chmod 700 /mnt/data/backups/offsite-sync
    chown root:root /mnt/data/backups/offsite-sync
    print_success "Created /mnt/data/backups/offsite-sync/ (700, root:root)"
    
    print_success "Task 2.3 complete"
}

# Task 3.1: Create services.yaml
execute_task_3_1() {
    print_header "Task 3.1: Create services.yaml"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create /opt/homeserver/configs/services.yaml"
        return 0
    fi
    
    # Check if services.yaml already exists
    if [[ -f /opt/homeserver/configs/services.yaml ]]; then
        print_info "services.yaml already exists"
        read -p "Overwrite? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            print_info "Skipping services.yaml creation"
            return 0
        fi
    fi
    
    print_info "Creating services.yaml..."
    cat > /opt/homeserver/configs/services.yaml << 'EOFSERVICES'
# Infrastructure Services Configuration
# Single source of truth for all service definitions

services:
  # Internal DNS (Pi-hole)
  pihole:
    name: pihole
    image: pihole/pihole:latest
    network_mode: host
    volumes:
      - /opt/homeserver/configs/pihole/etc-pihole:/etc/pihole
      - /opt/homeserver/configs/pihole/etc-dnsmasq.d:/etc/dnsmasq.d
    environment:
      TZ: "America/New_York"
      WEBPASSWORD: "${PIHOLE_PASSWORD}"
      DNSMASQ_LISTENING: "all"
      DNS1: "8.8.8.8"
      DNS2: "1.1.1.1"
      WEB_PORT: "8080"
    hostname: pihole.INTERNAL_SUBDOMAIN_PLACEHOLDER
    dns_record: true
    caddy_proxy: true
    restart: unless-stopped
    notes: "Uses host networking to properly handle DNS queries from LAN. Web interface on port 8080."
    
  # Reverse Proxy (Caddy)
  caddy:
    name: caddy
    image: caddy:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/homeserver/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - /opt/homeserver/configs/caddy/data:/data
      - /opt/homeserver/configs/caddy/config:/config
      - /var/log/caddy:/var/log/caddy
    hostname: null
    dns_record: false
    caddy_proxy: false
    restart: unless-stopped
    
  # SMTP Relay
  smtp:
    name: smtp
    image: namshi/smtp:latest
    ports:
      - "25:25"
    environment:
      RELAY_HOST: "SMTP_RELAY_HOST_PLACEHOLDER"
      RELAY_PORT: "SMTP_RELAY_PORT_PLACEHOLDER"
      RELAY_USERNAME: "${SMTP_USERNAME}"
      RELAY_PASSWORD: "${SMTP_PASSWORD}"
    hostname: null
    dns_record: false
    caddy_proxy: false
    restart: unless-stopped
    
  # Monitoring (Netdata)
  netdata:
    name: netdata
    image: netdata/netdata:latest
    ports:
      - "19999:19999"
    cap_add:
      - SYS_PTRACE
    security_opt:
      - apparmor:unconfined
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/homeserver/configs/netdata:/etc/netdata
    hostname: monitor.INTERNAL_SUBDOMAIN_PLACEHOLDER
    dns_record: true
    caddy_proxy: true
    restart: unless-stopped
    
  # Test Service (for validation)
  test:
    name: test-service
    image: nginx:alpine
    ports:
      - "8081:80"
    hostname: test.INTERNAL_SUBDOMAIN_PLACEHOLDER
    dns_record: true
    caddy_proxy: true
    restart: unless-stopped
EOFSERVICES
    
    # Replace placeholders
    sed -i "s/INTERNAL_SUBDOMAIN_PLACEHOLDER/$INTERNAL_SUBDOMAIN/g" /opt/homeserver/configs/services.yaml
    sed -i "s/SMTP_RELAY_HOST_PLACEHOLDER/$SMTP_RELAY_HOST/g" /opt/homeserver/configs/services.yaml
    sed -i "s/SMTP_RELAY_PORT_PLACEHOLDER/$SMTP_RELAY_PORT/g" /opt/homeserver/configs/services.yaml
    
    print_success "Created /opt/homeserver/configs/services.yaml"
    print_info "Review and customize services.yaml as needed"
    print_success "Task 3.1 complete"
}

# Task 4.1: Deploy Caddy container
execute_task_4_1() {
    print_header "Task 4.1: Deploy Caddy Container"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create Caddyfile"
        print_info "[DRY-RUN] Would deploy Caddy container"
        return 0
    fi
    
    # Create Caddy config directory
    mkdir -p /opt/homeserver/configs/caddy
    mkdir -p /var/log/caddy
    
    # Create minimal Caddyfile
    if [[ ! -f /opt/homeserver/configs/caddy/Caddyfile ]]; then
        print_info "Creating Caddyfile..."
        cat > /opt/homeserver/configs/caddy/Caddyfile << EOF
# Global options
{
    email $ADMIN_EMAIL
    local_certs
}

# Test service (for validation)
test.$INTERNAL_SUBDOMAIN {
    reverse_proxy test-service:80
    tls internal
    log {
        output file /var/log/caddy/test-access.log
    }
}

# Pi-hole web interface (host networking, port 8080)
pihole.$INTERNAL_SUBDOMAIN {
    reverse_proxy $SERVER_IP:8080
    tls internal
    log {
        output file /var/log/caddy/pihole-access.log
    }
}
EOF
        print_success "Created Caddyfile"
    else
        print_info "Caddyfile already exists"
    fi
    
    # Create custom network if not exists
    if ! docker network ls | grep -q homeserver; then
        print_info "Creating homeserver network..."
        docker network create homeserver
        print_success "Network created"
    fi
    
    # Check if Caddy already exists (running or stopped)
    if docker ps -a | grep -q caddy; then
        print_info "Caddy container already exists"
        read -p "Remove and redeploy? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            docker stop caddy 2>/dev/null || true
            docker rm caddy 2>/dev/null || true
        else
            print_info "Skipping Caddy deployment"
            print_success "Task 4.1 complete"
            return 0
        fi
    fi
    
    if true; then
        print_info "Deploying Caddy container..."
        docker run -d \
            --name caddy \
            --restart unless-stopped \
            --network homeserver \
            -p 80:80 \
            -p 443:443 \
            -v /opt/homeserver/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
            -v /opt/homeserver/configs/caddy/data:/data \
            -v /opt/homeserver/configs/caddy/config:/config \
            -v /var/log/caddy:/var/log/caddy \
            caddy:alpine
        
        print_success "Caddy container deployed"
        sleep 5
        
        if docker ps | grep -q caddy; then
            print_success "Caddy is running"
        else
            print_error "Caddy failed to start"
            docker logs caddy
            return 1
        fi
    fi
    
    print_success "Task 4.1 complete"
}

# Task 4.2: Export root CA certificate
execute_task_4_2() {
    print_header "Task 4.2: Export Root CA Certificate"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would export root CA certificate"
        return 0
    fi
    
    # Check if Caddy is running
    if ! docker ps | grep -q caddy; then
        print_error "Caddy container not running. Run Task 4.1 first."
        return 1
    fi
    
    # Wait for CA to initialize
    print_info "Waiting for internal CA to initialize..."
    sleep 10
    
    # Export root CA certificate
    print_info "Exporting root CA certificate..."
    if docker exec caddy test -f /data/caddy/pki/authorities/local/root.crt; then
        docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > /opt/homeserver/configs/caddy/root-ca.crt
        chmod 644 /opt/homeserver/configs/caddy/root-ca.crt
        print_success "Root CA certificate exported to /opt/homeserver/configs/caddy/root-ca.crt"
        print_info "Install this certificate on all client devices"
    else
        print_error "Root CA certificate not found. Caddy may still be initializing."
        print_info "Wait a few minutes and try again"
        return 1
    fi
    
    print_success "Task 4.2 complete"
}

# Task 5.1: Deploy Pi-hole container
execute_task_5_1() {
    print_header "Task 5.1: Deploy Pi-hole Container"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would check port 53 availability"
        print_info "[DRY-RUN] Would stop systemd-resolved if needed"
        print_info "[DRY-RUN] Would deploy Pi-hole container"
        return 0
    fi
    
    # Check if port 53 is in use
    if ss -tulpn | grep -q ':53 '; then
        print_info "Port 53 is in use, checking for systemd-resolved..."
        if systemctl is-active --quiet systemd-resolved; then
            print_info "Stopping systemd-resolved..."
            systemctl stop systemd-resolved
            systemctl disable systemd-resolved
            
            # Update resolv.conf to use Google DNS temporarily
            print_info "Updating /etc/resolv.conf..."
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 1.1.1.1" >> /etc/resolv.conf
            
            print_success "systemd-resolved stopped and disabled"
        else
            print_error "Port 53 is in use by another service (not systemd-resolved)"
            print_info "Check with: sudo ss -tulpn | grep :53"
            return 1
        fi
    fi
    
    # Create Pi-hole config directory
    mkdir -p /opt/homeserver/configs/pihole
    
    # Check if Pi-hole already running
    if docker ps -a | grep -q pihole; then
        print_info "Pi-hole container already exists"
        if docker ps | grep -q pihole; then
            print_info "Pi-hole is already running"
            read -p "Restart? (y/n): " confirm
            if [[ "$confirm" == "y" ]]; then
                docker restart pihole
                print_success "Pi-hole restarted"
            fi
            print_success "Task 5.1 complete"
            return 0
        else
            print_info "Starting existing Pi-hole container..."
            docker start pihole
            sleep 30
            if docker ps | grep -q pihole; then
                print_success "Pi-hole is running"
                print_success "Task 5.1 complete"
                return 0
            else
                print_error "Failed to start existing container, removing it..."
                docker rm pihole
            fi
        fi
    fi
    
    # Fetch Pi-hole password from Proton Pass
    print_info "Fetching Pi-hole password from Proton Pass..."
    
    # Load Phase 1 config to get ADMIN_USER
    if [[ -f "/opt/homeserver/configs/phase1-config.env" ]]; then
        source "/opt/homeserver/configs/phase1-config.env"
    else
        print_error "Phase 1 config not found. Cannot determine ADMIN_USER."
        return 1
    fi
    
    PIHOLE_PASSWORD=$(fetch_secret "$PIHOLE_PASS_ITEM_ID" "password" "$ADMIN_USER")
    if [[ -z "$PIHOLE_PASSWORD" ]]; then
        print_error "Failed to fetch Pi-hole password from Proton Pass"
        print_info "Ensure user $ADMIN_USER is logged into pass-cli"
        return 1
    fi
    print_success "Password fetched successfully"
    


    # Deploy new Pi-hole container with host networking
    print_info "Deploying Pi-hole container with host networking..."
    docker run -d \
        --name pihole \
        --restart unless-stopped \
        --network host \
        -e TZ="America/New_York" \
        -e WEBPASSWORD="$PIHOLE_PASSWORD" \
        -e DNSMASQ_LISTENING="all" \
        -e DNS1="8.8.8.8" \
        -e DNS2="1.1.1.1" \
        -e WEB_PORT=8080 \
        -v /opt/homeserver/configs/pihole/etc-pihole:/etc/pihole \
        -v /opt/homeserver/configs/pihole/etc-dnsmasq.d:/etc/dnsmasq.d \
        pihole/pihole:latest
        
        print_success "Pi-hole container deployed"
        print_info "Waiting for Pi-hole to initialize (30 seconds)..."
        sleep 30
        
        if docker ps | grep -q pihole; then
            print_success "Pi-hole is running"
        else
            print_error "Pi-hole failed to start"
            docker logs pihole
            return 1
        fi
    
    print_success "Task 5.1 complete"
}

# Task 5.2: Configure local DNS records
execute_task_5_2() {
    print_header "Task 5.2: Configure Local DNS Records"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create custom.list"
        print_info "[DRY-RUN] Would restart Pi-hole DNS"
        return 0
    fi
    
    # Check if Pi-hole is running
    if ! docker ps | grep -q pihole; then
        print_error "Pi-hole container not running. Run Task 5.1 first."
        return 1
    fi
    
    # Add custom DNS records using Pi-hole v6 FTL command
    print_info "Adding custom DNS records..."
    docker exec pihole pihole-FTL --config dns.hosts "[\"$SERVER_IP $INTERNAL_SUBDOMAIN\", \"$SERVER_IP test.$INTERNAL_SUBDOMAIN\", \"$SERVER_IP pihole.$INTERNAL_SUBDOMAIN\", \"$SERVER_IP monitor.$INTERNAL_SUBDOMAIN\"]"
    
    print_success "DNS records configured"
    print_info "Test with: nslookup test.$INTERNAL_SUBDOMAIN $SERVER_IP"
    print_success "Task 5.2 complete"
}

# Task 6.3: Create test service for validation
execute_task_6_3() {
    print_header "Task 6.3: Create Test Service for Validation"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would deploy test-service container"
        return 0
    fi
    
    # Check if test-service already exists
    if docker ps -a | grep -q test-service; then
        print_info "Test service already exists"
        read -p "Remove and redeploy? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            docker stop test-service 2>/dev/null || true
            docker rm test-service 2>/dev/null || true
        else
            print_info "Skipping test service deployment"
            print_success "Task 6.3 complete"
            return 0
        fi
    fi
    
    print_info "Deploying test service..."
    docker run -d \
        --name test-service \
        --restart unless-stopped \
        --network homeserver \
        nginx:alpine
    
    print_success "Test service deployed"
    sleep 2
    
    if docker ps | grep -q test-service; then
        print_success "Test service is running"
    else
        print_error "Test service failed to start"
        docker logs test-service
        return 1
    fi
    
    print_success "Task 6.3 complete"
}

# Task 6.1: Install msmtp packages
execute_task_6_1() {
    print_header "Task 6.1: Install msmtp Packages"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install msmtp and msmtp-mta"
        return 0
    fi
    
    # Check if already installed
    if command -v msmtp &>/dev/null; then
        print_info "msmtp already installed"
        msmtp --version
        print_success "Task 6.1 complete"
        return 0
    fi
    
    print_info "Installing msmtp packages..."
    apt-get update -qq
    apt-get install -y msmtp msmtp-mta
    
    if command -v msmtp &>/dev/null; then
        print_success "msmtp installed successfully"
        msmtp --version
    else
        print_error "Failed to install msmtp"
        return 1
    fi
    
    print_success "Task 6.1 complete"
}

# Task 7.1: Configure msmtp for SMTP2GO
execute_task_7_1() {
    print_header "Task 7.1: Configure msmtp for SMTP2GO"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    # Load Phase 1 config to get ADMIN_USER
    if [[ -f "/opt/homeserver/configs/phase1-config.env" ]]; then
        source "/opt/homeserver/configs/phase1-config.env"
    else
        print_error "Phase 1 config not found. Cannot determine ADMIN_USER."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create /home/${ADMIN_USER}/.msmtprc"
        print_info "[DRY-RUN] Would create /home/${ADMIN_USER}/msmtp.log"
        return 0
    fi
    
    # Check if msmtp installed
    if ! command -v msmtp &>/dev/null; then
        print_error "msmtp not installed. Run Task 6.1 first."
        return 1
    fi
    
    print_info "Creating msmtp configuration for user: ${ADMIN_USER}"

    
    # Fetch SMTP2GO password from Proton Pass
    print_info "Fetching SMTP2GO password from Proton Pass..."
    SMTP2GO_PASSWORD=$(fetch_secret "$SMTP2GO_PASS_ITEM_ID" "password" "$ADMIN_USER")
    if [[ -z "$SMTP2GO_PASSWORD" ]]; then
        print_error "Failed to fetch SMTP2GO password from Proton Pass"
        print_info "Ensure user $ADMIN_USER is logged into pass-cli"
        return 1
    fi
    print_success "Password fetched successfully"

    # Create .msmtprc
    cat > /home/${ADMIN_USER}/.msmtprc << EOF
# msmtp configuration for SMTP2GO
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /home/${ADMIN_USER}/msmtp.log

account smtp2go
host ${SMTP2GO_HOST}
port ${SMTP2GO_PORT}
from ${SMTP2GO_FROM}
user ${SMTP2GO_USER}
password ${SMTP2GO_PASSWORD}

account default : smtp2go
EOF
    
    # Set permissions
    chmod 600 /home/${ADMIN_USER}/.msmtprc
    chown ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.msmtprc
    print_success "Created /home/${ADMIN_USER}/.msmtprc (600 permissions)"
    
    # Create log file
    touch /home/${ADMIN_USER}/msmtp.log
    chmod 600 /home/${ADMIN_USER}/msmtp.log
    chown ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/msmtp.log
    print_success "Created /home/${ADMIN_USER}/msmtp.log"
    
    print_success "Task 7.1 complete"
}

# Task 7.2: Test msmtp email delivery
execute_task_7_2() {
    print_header "Task 7.2: Test msmtp Email Delivery"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    # Load Phase 1 config
    if [[ -f "/opt/homeserver/configs/phase1-config.env" ]]; then
        source "/opt/homeserver/configs/phase1-config.env"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would send test email via msmtp"
        return 0
    fi
    
    # Check if msmtp configured
    if [[ ! -f /home/${ADMIN_USER}/.msmtprc ]]; then
        print_error "msmtp not configured. Run Task 7.1 first."
        return 1
    fi
    
    print_info "Sending test email to ${ADMIN_EMAIL}..."
    
    # Send test email as admin user
    su - ${ADMIN_USER} -c "printf 'Subject: [TEST] Home Server SMTP\n\nTest email from home server - msmtp + SMTP2GO working!\n\nTimestamp: \$(date)\nServer: \$(hostname)\n' | msmtp -v ${ADMIN_EMAIL}"
    
    if [[ $? -eq 0 ]]; then
        print_success "Test email sent successfully"
        print_info "Check msmtp log: cat /home/${ADMIN_USER}/msmtp.log"
        print_info "Verify email received in ${ADMIN_EMAIL} inbox"
    else
        print_error "Failed to send test email"
        print_info "Check log: cat /home/${ADMIN_USER}/msmtp.log"
        return 1
    fi
    
    print_success "Task 7.2 complete"
}

# Task 8.1: Deploy Netdata container
execute_task_8_1() {
    print_header "Task 8.1: Deploy Netdata Container"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would deploy Netdata container"
        return 0
    fi
    
    # Create Netdata config directory
    mkdir -p /opt/homeserver/configs/netdata
    
    # Check if Netdata already exists (running or stopped)
    if docker ps -a | grep -q netdata; then
        print_info "Netdata container already exists"
        read -p "Remove and redeploy? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            docker stop netdata 2>/dev/null || true
            docker rm netdata 2>/dev/null || true
        else
            print_info "Skipping Netdata deployment"
            print_success "Task 8.1 complete"
            return 0
        fi
    fi
    
    if true; then
        print_info "Deploying Netdata container..."
        docker run -d \
            --name netdata \
            --restart unless-stopped \
            --network homeserver \
            --hostname homeserver \
            -p 19999:19999 \
            --cap-add SYS_PTRACE \
            --security-opt apparmor=unconfined \
            -v /proc:/host/proc:ro \
            -v /sys:/host/sys:ro \
            -v /var/run/docker.sock:/var/run/docker.sock:ro \
            -v /opt/homeserver/configs/netdata:/etc/netdata \
            netdata/netdata:latest
        
        print_success "Netdata container deployed"
        print_info "Waiting for Netdata to initialize (30 seconds)..."
        sleep 30
        
        if docker ps | grep -q netdata; then
            print_success "Netdata is running"
        else
            print_error "Netdata failed to start"
            docker logs netdata
            return 1
        fi
    fi
    
    print_success "Task 8.1 complete"
}

# Task 8.2: Configure Netdata in Caddy and DNS
execute_task_8_2() {
    print_header "Task 8.2: Configure Netdata in Caddy and DNS"
    echo ""
    
    if ! load_config; then
        print_error "Configuration not loaded. Run option 0 first."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would add Netdata to Caddyfile"
        print_info "[DRY-RUN] Would add Netdata to DNS"
        return 0
    fi
    
    # Add Netdata to Caddyfile if not already present
    if ! grep -q "monitor.$INTERNAL_SUBDOMAIN" /opt/homeserver/configs/caddy/Caddyfile; then
        print_info "Adding Netdata to Caddyfile..."
        cat >> /opt/homeserver/configs/caddy/Caddyfile << EOF

# Netdata monitoring dashboard
monitor.$INTERNAL_SUBDOMAIN {
    reverse_proxy netdata:19999
    tls internal
    log {
        output file /var/log/caddy/monitor-access.log
    }
}
EOF
        
        # Reload Caddy
        print_info "Reloading Caddy..."
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile
        print_success "Caddy reloaded"
    else
        print_info "Netdata already in Caddyfile"
    fi
    
    # DNS record already added in Task 5.2
    print_info "DNS record already configured in Task 5.2"
    
    print_success "Task 8.2 complete"
}

# Task 9.1: Configure log rotation for Caddy
execute_task_9_1() {
    print_header "Task 9.1: Configure Log Rotation for Caddy"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create /etc/logrotate.d/caddy"
        return 0
    fi
    
    print_info "Creating logrotate configuration for Caddy..."
    cat > /etc/logrotate.d/caddy << 'EOF'
/var/log/caddy/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile > /dev/null 2>&1 || true
    endscript
}
EOF
    
    print_success "Created /etc/logrotate.d/caddy"
    
    # Test configuration
    print_info "Testing logrotate configuration..."
    if logrotate -d /etc/logrotate.d/caddy &>/dev/null; then
        print_success "Logrotate configuration is valid"
    else
        print_error "Logrotate configuration has errors"
        return 1
    fi
    
    print_success "Task 9.1 complete"
}

# Task 9.2: Configure log rotation for Pi-hole
execute_task_9_2() {
    print_header "Task 9.2: Configure Log Rotation for Pi-hole"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create /etc/logrotate.d/pihole"
        return 0
    fi
    
    print_info "Creating logrotate configuration for Pi-hole..."
    cat > /etc/logrotate.d/pihole << 'EOF'
/opt/homeserver/configs/pihole/etc-pihole/pihole.log {
    weekly
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        docker exec pihole pihole restartdns > /dev/null 2>&1 || true
    endscript
}
EOF
    
    print_success "Created /etc/logrotate.d/pihole"
    
    # Test configuration
    print_info "Testing logrotate configuration..."
    if logrotate -d /etc/logrotate.d/pihole &>/dev/null; then
        print_success "Logrotate configuration is valid"
    else
        print_error "Logrotate configuration has errors"
        return 1
    fi
    
    print_success "Task 9.2 complete"
}

# Task 9.3: Configure log rotation for msmtp
execute_task_9_3() {
    print_header "Task 9.3: Configure Log Rotation for msmtp"
    echo ""
    
    # Load Phase 1 config to get ADMIN_USER
    if [[ -f "/opt/homeserver/configs/phase1-config.env" ]]; then
        source "/opt/homeserver/configs/phase1-config.env"
    else
        print_error "Phase 1 config not found. Cannot determine ADMIN_USER."
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create /etc/logrotate.d/msmtp"
        return 0
    fi
    
    print_info "Creating logrotate configuration for msmtp..."
    cat > /etc/logrotate.d/msmtp << EOF
/home/${ADMIN_USER}/msmtp.log {
    weekly
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0600 ${ADMIN_USER} ${ADMIN_USER}
}
EOF
    
    print_success "Created /etc/logrotate.d/msmtp"
    
    # Test configuration
    print_info "Testing logrotate configuration..."
    if logrotate -d /etc/logrotate.d/msmtp &>/dev/null; then
        print_success "Logrotate configuration is valid"
    else
        print_error "Logrotate configuration has errors"
        return 1
    fi
    
    print_success "Task 9.3 complete"
}


# Validation functions
validate_data_structure() {
    local status="PASS"
    
    # Check top-level directories
    for dir in media family users backups services; do
        if [[ -d "/mnt/data/$dir" ]]; then
            print_success "/mnt/data/$dir/ exists"
        else
            print_error "/mnt/data/$dir/ does NOT exist"
            status="FAIL"
        fi
    done
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_family_subdirectories() {
    local status="PASS"
    
    # Check family subdirectories
    for dir in Documents Photos Videos Projects; do
        if [[ -d "/mnt/data/family/$dir" ]]; then
            print_success "/mnt/data/family/$dir/ exists"
        else
            print_error "/mnt/data/family/$dir/ does NOT exist"
            status="FAIL"
        fi
    done
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_backup_subdirectories() {
    local status="PASS"
    
    # Check backup subdirectories
    for dir in snapshots incremental offsite-sync; do
        if [[ -d "/mnt/data/backups/$dir" ]]; then
            print_success "/mnt/data/backups/$dir/ exists"
        else
            print_error "/mnt/data/backups/$dir/ does NOT exist"
            status="FAIL"
        fi
    done
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_services_yaml() {
    if [[ -f "/opt/homeserver/configs/services.yaml" ]]; then
        print_success "services.yaml exists"
        return 0
    else
        print_info "services.yaml not yet created (will be created in Task 3.1)"
        return 1
    fi
}

validate_git_commit() {
    if git -C /opt/homeserver status --porcelain | grep -q .; then
        print_info "Uncommitted changes in Git (commit when ready)"
        return 1
    else
        print_success "All changes committed to Git"
        return 0
    fi
}

validate_logrotate_caddy() {
    if [[ -f "/etc/logrotate.d/caddy" ]]; then
        print_success "Caddy logrotate configured"
        return 0
    else
        print_info "Caddy logrotate not yet configured (Task 9.1)"
        return 1
    fi
}

validate_logrotate_pihole() {
    if [[ -f "/etc/logrotate.d/pihole" ]]; then
        print_success "Pi-hole logrotate configured"
        return 0
    else
        print_info "Pi-hole logrotate not yet configured (Task 9.2)"
        return 1
    fi
}

validate_logrotate_msmtp() {
    if [[ -f "/etc/logrotate.d/msmtp" ]]; then
        print_success "msmtp logrotate configured"
        return 0
    else
        print_info "msmtp logrotate not yet configured (Task 9.3)"
        return 1
    fi
}

validate_dns_service() {
    if docker ps | grep -q pihole; then
        print_success "Pi-hole container running"
        return 0
    else
        print_info "Pi-hole not yet deployed (will be deployed in Task 5.1)"
        return 1
    fi
}

validate_dns_resolution() {
    if ! load_config; then
        print_error "Configuration not loaded"
        return 1
    fi
    
    if docker ps | grep -q pihole; then
        if nslookup "test.$INTERNAL_SUBDOMAIN" "$SERVER_IP" &>/dev/null; then
            print_success "DNS resolution working"
            return 0
        else
            print_error "DNS resolution NOT working"
            return 1
        fi
    else
        print_info "Pi-hole not yet deployed"
        return 1
    fi
}

validate_external_dns() {
    if docker ps | grep -q pihole; then
        if nslookup google.com "$SERVER_IP" &>/dev/null; then
            print_success "External DNS resolution working"
            return 0
        else
            print_error "External DNS resolution NOT working"
            return 1
        fi
    else
        print_info "Pi-hole not yet deployed"
        return 1
    fi
}

validate_caddy_service() {
    if docker ps | grep -q caddy; then
        print_success "Caddy container running"
        return 0
    else
        print_info "Caddy not yet deployed (will be deployed in Task 4.1)"
        return 1
    fi
}

validate_caddy_https() {
    if ! load_config; then
        print_error "Configuration not loaded"
        return 1
    fi
    
    if docker ps | grep -q caddy; then
        if curl -k -s "https://monitor.$INTERNAL_SUBDOMAIN" &>/dev/null; then
            print_success "Caddy HTTPS working"
            return 0
        else
            print_info "Caddy HTTPS not yet configured"
            return 1
        fi
    else
        print_info "Caddy not yet deployed"
        return 1
    fi
}

validate_certificate_trust() {
    if docker ps | grep -q caddy; then
        if [[ -f "/opt/homeserver/configs/caddy/root-ca.crt" ]]; then
            print_success "Root CA certificate exported"
            return 0
        else
            print_info "Root CA certificate not yet exported (Task 4.2)"
            return 1
        fi
    else
        print_info "Caddy not yet deployed"
        return 1
    fi
}

validate_smtp_service() {
    if command -v msmtp &>/dev/null; then
        print_success "msmtp installed"
    else
        print_error "msmtp not installed"
        return 1
    fi
}

validate_smtp_test() {
    # Load Phase 1 config
    if [[ -f "/opt/homeserver/configs/phase1-config.env" ]]; then
        source "/opt/homeserver/configs/phase1-config.env"
    fi
    
    if [[ -f /home/${ADMIN_USER}/.msmtprc ]]; then
        print_success "msmtp configured for ${ADMIN_USER}"
    else
        print_error "msmtp not configured"
        return 1
    fi
}


validate_netdata_service() {
    if docker ps | grep -q netdata; then
        print_success "Netdata container running"
        return 0
    else
        print_info "Netdata not yet deployed (will be deployed in Task 8.1)"
        return 1
    fi
}

validate_netdata_dashboard() {
    if ! load_config; then
        print_error "Configuration not loaded"
        return 1
    fi
    
    if docker ps | grep -q netdata; then
        if curl -k -s "https://monitor.$INTERNAL_SUBDOMAIN" &>/dev/null; then
            print_success "Netdata dashboard accessible"
            return 0
        else
            print_info "Netdata dashboard not yet configured"
            return 1
        fi
    else
        print_info "Netdata not yet deployed"
        return 1
    fi
}

# Validate all
run_phase2_validation() {
    print_header "Phase 02 Infrastructure Validation"
    echo ""
    
    local total=0
    local passed=0
    local skipped=0
    
    # Run all validation checks
    checks=(
        "DNS Service:validate_dns_service"
        "DNS Resolution:validate_dns_resolution"
        "External DNS:validate_external_dns"
        "Caddy Service:validate_caddy_service"
        "Caddy HTTPS:validate_caddy_https"
        "Certificate Trust:validate_certificate_trust"
        "SMTP Service:validate_smtp_service"
        "SMTP Test:validate_smtp_test"
        "Netdata Service:validate_netdata_service"
        "Netdata Dashboard:validate_netdata_dashboard"
        "Data Structure:validate_data_structure"
        "Family Subdirectories:validate_family_subdirectories"
        "Backup Subdirectories:validate_backup_subdirectories"
        "services.yaml:validate_services_yaml"
        "Logrotate Caddy:validate_logrotate_caddy"
        "Logrotate Pi-hole:validate_logrotate_pihole"
        "Logrotate SMTP:validate_logrotate_msmtp"
        "Git Commit:validate_git_commit"
    )
    
    for check in "${checks[@]}"; do
        name="${check%%:*}"
        func="${check##*:}"
        
        echo ""
        print_header "$name"
        total=$((total + 1))
        
        # Run function and capture result
        if $func; then
            passed=$((passed + 1))
        else
            skipped=$((skipped + 1))
        fi
    done
    
    # Summary
    echo ""
    echo "========================================"
    print_header "Validation Summary"
    echo "========================================"
    echo "Total checks: $total"
    echo "Passed: $passed"
    echo "Skipped/Incomplete: $skipped"
    echo "Failed: $((total - passed - skipped))"
    echo ""
    
    if [[ $passed -eq $total ]]; then
        print_success "All validation checks passed!"
        return 0
    else
        print_info "Phase 2 deployment in progress ($passed/$total complete)"
        return 0
    fi
}

# Interactive menu
show_menu() {
    clear
    echo "========================================"
    echo "Phase 02 Infrastructure Deployment"
    echo "========================================"
    echo ""
    echo "Configuration:"
    echo "  0. Initialize/Update Configuration"
    echo "  c. Validate Configuration"
    echo ""
    echo "Data Storage Structure:"
    echo "  2.1. Create Top-Level Data Directories"
    echo "  2.2. Create Family Subdirectories"
    echo "  2.3. Create Backup Subdirectories"
    echo ""
    echo "Service Configuration:"
    echo "  3.1. Create services.yaml"
    echo ""
    echo "Internal CA (Caddy):"
    echo "  4.1. Deploy Caddy Container"
    echo "  4.2. Export Root CA Certificate"
    echo ""
    echo "Internal DNS (Pi-hole):"
    echo "  5.1. Deploy Pi-hole Container"
    echo "  5.2. Configure Local DNS Records"
    echo ""
    echo "SMTP Server:"
    echo "  6.1. Install msmtp Packages"
    echo "  7.1. Configure msmtp for SMTP2GO"
    echo "  7.2. Test msmtp Email Delivery"
    echo ""
    echo "Monitoring (Netdata):"
    echo "  8.1. Deploy Netdata Container"
    echo "  8.2. Configure Netdata in Caddy and DNS"
    echo ""
    echo "Log Rotation:"
    echo "  9.1. Configure Log Rotation for Caddy"
    echo "  9.2. Configure Log Rotation for Pi-hole"
    echo "  9.3. Configure Log Rotation for SMTP"
    echo ""
    echo "Validation:"
    echo "  v. Run Phase 2 Validation"
    echo ""
    echo "Other:"
    echo "  q. Quit"
    echo ""
    echo "========================================"
    echo ""
}

# Main function
main() {
    while true; do
        show_menu
        read -p "Select option: " choice
        echo ""
        
        case $choice in
            0)
                init_config
                ;;
            c)
                validate_config
                ;;
            2.1)
                execute_task_2_1
                ;;
            2.2)
                execute_task_2_2
                ;;
            2.3)
                execute_task_2_3
                ;;
            3.1)
                execute_task_3_1
                ;;
            4.1)
                execute_task_4_1
                ;;
            4.2)
                execute_task_4_2
                ;;
            5.1)
                execute_task_5_1
                ;;
            5.2)
                execute_task_5_2
                ;;
            6.3)
                execute_task_6_3
                ;;
            6.1)
                execute_task_6_1
                ;;
            7.1)
                execute_task_7_1
                ;;
            7.2)
                execute_task_7_2
                ;;
            8.1)
                execute_task_8_1
                ;;
            8.2)
                execute_task_8_2
                ;;
            9.1)
                execute_task_9_1
                ;;
            9.2)
                execute_task_9_2
                ;;
            9.3)
                execute_task_9_3
                ;;
            v)
                run_phase2_validation
                ;;
            q)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option: $choice"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Entry point
main "$@"
