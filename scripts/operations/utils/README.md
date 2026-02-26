# Utility Libraries

This directory contains reusable utility libraries for deployment scripts. These libraries provide common functionality used across multiple deployment phases and task modules.

## Available Libraries

### 1. output-utils.sh
Colored output functions for consistent user feedback.

**Functions:**
- `print_success(message)` - Green checkmark prefix
- `print_error(message)` - Red X prefix
- `print_info(message)` - Yellow info icon prefix
- `print_header(message)` - Blue header

**Usage:**
```bash
source "$(dirname "$0")/../../operations/utils/output-utils.sh"

print_header "Task 1: Update System"
print_info "Updating package lists..."
print_success "Task complete"
print_error "Failed to install package"
```

### 2. env-utils.sh
Environment variable validation functions.

**Functions:**
- `validate_required_vars(var_names...)` - Check variables are set and non-empty
- `validate_ip_address(ip_address)` - Validate IP address format
- `validate_email(email_address)` - Validate email address format
- `validate_domain(domain_name)` - Validate domain name format

**Usage:**
```bash
source "$(dirname "$0")/../../operations/utils/env-utils.sh"

# Validate required variables
validate_required_vars "SERVER_IP" "ADMIN_USER" "DOMAIN" || exit 3

# Validate formats
validate_ip_address "$SERVER_IP" || { print_error "Invalid IP"; exit 3; }
validate_email "$ADMIN_EMAIL" || { print_error "Invalid email"; exit 3; }
validate_domain "$DOMAIN" || { print_error "Invalid domain"; exit 3; }
```

### 3. password-utils.sh
Proton Pass integration for secret retrieval.

**Functions:**
- `fetch_secret(item_id, field, admin_user)` - Retrieve secret from Proton Pass

**Parameters:**
- `item_id` - Proton Pass item ID (required)
- `field` - Field to retrieve (default: "password")
- `admin_user` - User to run pass-cli as (default: $ADMIN_USER)

**Returns:**
- Secret value on stdout
- Exit code 0 on success, 1 on failure

**Prerequisites:**
- `HOMESERVER_PASS_SHARE_ID` environment variable must be set
- User must be logged into pass-cli

**Usage:**
```bash
source "$(dirname "$0")/../../operations/utils/password-utils.sh"

# Fetch password
SMTP_PASSWORD=$(fetch_secret "$SMTP2GO_PASS_ITEM_ID" "password" "$ADMIN_USER")
if [[ -z "$SMTP_PASSWORD" ]]; then
    print_error "Failed to fetch password"
    exit 1
fi
```

### 4. service-utils.sh
Service health check functions.

**Functions:**
- `check_docker_container(container_name)` - Verify container running
- `check_systemd_service(service_name)` - Verify service active
- `check_port_listening(port_number)` - Verify port in LISTEN state

**Returns:**
- Exit code 0 if healthy/running/listening
- Exit code 1 if unhealthy/stopped/not-listening

**Usage:**
```bash
source "$(dirname "$0")/../../operations/utils/service-utils.sh"

# Check Docker container
if check_docker_container "caddy"; then
    print_success "Caddy is running"
else
    print_error "Caddy is not running"
    exit 1
fi

# Check systemd service
if check_systemd_service "docker"; then
    print_success "Docker service is active"
fi

# Check port
if check_port_listening 443; then
    print_success "Port 443 is listening"
fi
```

### 5. validation-foundation-utils.sh
Reusable validation functions for Foundation Layer deployment verification.

**Functions:**
- `validate_ssh_hardening()` - Verify SSH hardening (password auth disabled, pubkey enabled, root login disabled)
- `validate_ufw_firewall()` - Verify UFW firewall active and rules configured
- `validate_fail2ban()` - Verify fail2ban service running and SSH jail active
- `validate_docker()` - Verify Docker and Docker Compose installed and running
- `validate_git_repository()` - Verify Git repository initialized with directory structure
- `validate_unattended_upgrades()` - Verify unattended-upgrades service running
- `validate_luks_encryption()` - Verify LUKS encryption, mount, and key file (requires DATA_DISK env var)
- `validate_docker_group()` - Verify admin user in docker group (requires ADMIN_USER env var)
- `validate_essential_tools()` - Verify essential tools installed (git, vim, curl, wget, htop)

**Required Environment Variables:**
- `validate_luks_encryption`: Requires `DATA_DISK` (e.g., "/dev/sdb")
- `validate_docker_group`: Requires `ADMIN_USER` (e.g., "admin")
- Other functions: No environment variables required

**Returns:**
- Exit code 0 if validation passes
- Exit code 1 if validation fails

**Usage:**
```bash
source scripts/operations/utils/validation-foundation-utils.sh

# Export required variables before calling validation functions
export DATA_DISK="/dev/sdb"
export ADMIN_USER="admin"

validate_ssh_hardening || exit 1
validate_luks_encryption || exit 1
validate_docker_group || exit 1
```

### 6. validation-infrastructure-utils.sh
Reusable validation functions for Infrastructure Layer deployment verification.

**Functions:**
- `validate_data_structure()` - Verify top-level data directories exist
- `validate_family_subdirectories()` - Verify family subdirectories exist
- `validate_backup_subdirectories()` - Verify backup subdirectories exist
- `validate_services_yaml()` - Verify services.yaml exists
- `validate_git_commit()` - Verify all changes committed to Git
- `validate_logrotate_caddy()` - Verify Caddy logrotate configured
- `validate_logrotate_pihole()` - Verify Pi-hole logrotate configured
- `validate_logrotate_msmtp()` - Verify msmtp logrotate configured
- `validate_dns_service()` - Verify Pi-hole container running
- `validate_dns_resolution()` - Verify DNS resolution working (requires INTERNAL_SUBDOMAIN, SERVER_IP env vars)
- `validate_external_dns()` - Verify external DNS resolution working
- `validate_caddy_service()` - Verify Caddy container running
- `validate_caddy_https()` - Verify Caddy HTTPS working (requires INTERNAL_SUBDOMAIN env var)
- `validate_certificate_trust()` - Verify root CA certificate exported
- `validate_smtp_service()` - Verify msmtp installed
- `validate_smtp_test()` - Verify msmtp configured (requires ADMIN_USER env var)
- `validate_netdata_service()` - Verify Netdata container running
- `validate_netdata_dashboard()` - Verify Netdata dashboard accessible (requires INTERNAL_SUBDOMAIN env var)

**Required Environment Variables:**
- `validate_dns_resolution`: Requires `INTERNAL_SUBDOMAIN`, `SERVER_IP`
- `validate_caddy_https`: Requires `INTERNAL_SUBDOMAIN`
- `validate_smtp_test`: Requires `ADMIN_USER`
- `validate_netdata_dashboard`: Requires `INTERNAL_SUBDOMAIN`
- Other functions: No environment variables required

**Returns:**
- Exit code 0 if validation passes
- Exit code 1 if validation fails

**Usage:**
```bash
source scripts/operations/utils/validation-infrastructure-utils.sh

# Export required variables before calling validation functions
export INTERNAL_SUBDOMAIN="home.mydomain.com"
export SERVER_IP="192.168.1.2"
export ADMIN_USER="admin"

validate_data_structure || exit 1
validate_dns_resolution || exit 1
validate_caddy_https || exit 1
```

### 7. validation-core-services-utils.sh
Reusable validation functions for Core Services Layer deployment verification.

**Functions:**
- `validate_samba_container()` - Verify Samba container running
- `validate_personal_folders()` - Verify user personal folders exist
- `validate_family_folders()` - Verify family shared folders exist
- `validate_media_folders()` - Verify media library folders exist
- `validate_personal_shares()` - Verify personal Samba shares accessible
- `validate_family_share()` - Verify Family share accessible
- `validate_media_share()` - Verify Media share accessible
- `validate_recycle_bin()` - Verify recycle bin enabled
- `validate_user_scripts()` - Verify user provisioning scripts exist
- `validate_jellyfin_container()` - Verify Jellyfin container running
- `validate_jellyfin_https()` - Verify Jellyfin HTTPS access
- `validate_jellyfin_media_access()` - Verify Jellyfin can read media
- `validate_jellyfin_dns()` - Verify Jellyfin DNS record
- `validate_git_commit()` - Verify Git working tree clean

**Required Environment Variables:**
- `validate_personal_folders`: Requires `DATA_MOUNT`, `ADMIN_USER`, `POWER_USER`, `STANDARD_USER`
- `validate_family_folders`: Requires `DATA_MOUNT`
- `validate_media_folders`: Requires `DATA_MOUNT`
- `validate_personal_shares`: Requires `SERVER_IP`, `ADMIN_USER`, `POWER_USER`, `STANDARD_USER`
- `validate_family_share`: Requires `SERVER_IP`
- `validate_media_share`: Requires `SERVER_IP`
- `validate_jellyfin_https`: Requires `INTERNAL_SUBDOMAIN`
- `validate_jellyfin_dns`: Requires `INTERNAL_SUBDOMAIN`, `SERVER_IP`
- Other functions: No environment variables required

**Returns:**
- Exit code 0 if validation passes
- Exit code 1 if validation fails

**Usage:**
```bash
source scripts/operations/utils/validation-core-services-utils.sh

# Export required variables before calling validation functions
export DATA_MOUNT="/mnt/data"
export INTERNAL_SUBDOMAIN="home.mydomain.com"
export SERVER_IP="192.168.1.2"
export ADMIN_USER="admin_user"
export POWER_USER="power_user"
export STANDARD_USER="standard_user"

validate_samba_container || exit 1
validate_jellyfin_container || exit 1
```

## Size Constraints

**Maximum 200 lines per utility library file** (including comments)

If a utility library exceeds this limit, split it into multiple focused libraries.

## Standard Library Structure

```bash
#!/bin/bash
# Utility: Brief description
# Functions: list_of_functions
# Usage: source this file, then call functions

# Function 1
function_name() {
    local param1="$1"
    local param2="${2:-default}"
    
    # Validate inputs
    [[ -z "$param1" ]] && { echo "Error: param1 required"; return 1; }
    
    # Execute
    # ...
    
    return 0
}

# Function 2
another_function() {
    # Implementation
}
```

## Key Principles

### 1. Reusability
Functions should be generic and reusable across multiple scripts. Avoid hardcoding values.

### 2. Clear Interfaces
Document function parameters, return values, and exit codes in comments.

### 3. Error Handling
Validate inputs and return meaningful error messages.

### 4. No Side Effects
Utility functions should not modify global state unless explicitly documented.

### 5. Sourcing Pattern
Libraries are sourced, not executed:
```bash
# Correct
source "$SCRIPT_DIR/../../operations/utils/output-utils.sh"

# Incorrect
./output-utils.sh
```

## Sourcing Utilities

From task modules:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../operations/utils/output-utils.sh"
source "$SCRIPT_DIR/../../operations/utils/env-utils.sh"
```

From deployment scripts:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../operations/utils/output-utils.sh"
```

## Testing

Each utility library should have corresponding unit tests validating:
- Function exists
- Correct behavior with valid inputs
- Correct error handling with invalid inputs
- Correct exit codes

## Creating New Utility Libraries

When creating a new utility library:

1. Name it descriptively: `{purpose}-utils.sh`
2. Keep under 200 lines
3. Document all functions with comments
4. Validate inputs before use
5. Return meaningful exit codes
6. Write corresponding unit tests
7. Update this README with the new library

## Common Patterns

### Pattern 1: Validation Function
```bash
validate_something() {
    local value="$1"
    
    # Validate input
    [[ -z "$value" ]] && { echo "Error: value required"; return 1; }
    
    # Check condition
    if [[ condition ]]; then
        return 0  # Valid
    else
        return 1  # Invalid
    fi
}
```

### Pattern 2: Fetch/Retrieve Function
```bash
fetch_something() {
    local id="$1"
    local field="${2:-default}"
    
    # Validate prerequisites
    [[ -z "$REQUIRED_VAR" ]] && { echo "Error: REQUIRED_VAR not set"; return 1; }
    
    # Fetch data
    local result=$(command_to_fetch "$id" "$field")
    
    # Return result
    echo "$result"
    return 0
}
```

### Pattern 3: Check Function
```bash
check_something() {
    local name="$1"
    
    # Check condition
    if command | grep -q "$name"; then
        return 0  # Healthy
    else
        return 1  # Unhealthy
    fi
}
```

## References

- Design Document: `.kiro/specs/refactor_fix_ph01-02/design.md`
- Requirements: `.kiro/specs/refactor_fix_ph01-02/requirements.md`
- Task Modules: `scripts/deploy/tasks/README.md`
