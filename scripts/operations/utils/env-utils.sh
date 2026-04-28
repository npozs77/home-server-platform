#!/bin/bash
set -euo pipefail

# Utility Library: Environment Variable Validation and Loading
# Purpose: Load and validate environment variables and configuration values
# Functions: load_env_files, validate_required_vars, validate_ip_address, validate_email, validate_domain
# Usage: source this file, then call functions
#
# Example:
#   source scripts/operations/utils/env-utils.sh
#   load_env_files
#   validate_required_vars "SERVER_IP" "ADMIN_USER" || exit 1
#   validate_ip_address "$SERVER_IP" || exit 1

# Source output utilities for error messages (if not already loaded)
if ! command -v print_success &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/output-utils.sh"
fi

# Load environment variables from configuration files
# Sources foundation.env and services.env if they exist
# Returns:
#   0 if at least one config file was loaded
#   1 if no config files found
# Example:
#   load_env_files
load_env_files() {
    local loaded=0
    
    if [[ -f /opt/homeserver/configs/foundation.env ]]; then
        source /opt/homeserver/configs/foundation.env
        loaded=1
    fi
    
    if [[ -f /opt/homeserver/configs/services.env ]]; then
        source /opt/homeserver/configs/services.env
        loaded=1
    fi
    
    if [[ -f /opt/homeserver/configs/secrets.env ]]; then
        source /opt/homeserver/configs/secrets.env
        loaded=1
    fi
    
    if [[ $loaded -eq 0 ]]; then
        return 1
    fi
    
    return 0
}

# Validate that required environment variables are set and non-empty
# Parameters:
#   $@: Variable names to check
# Returns:
#   0 if all variables are set and non-empty
#   1 if any variable is missing or empty
# Example:
#   validate_required_vars "VAR1" "VAR2" "VAR3"
validate_required_vars() {
    local missing_vars=()
    local var_name
    
    for var_name in "$@"; do
        if [[ -z "${!var_name:-}" ]]; then
            missing_vars+=("$var_name")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required environment variables:"
        for var_name in "${missing_vars[@]}"; do
            echo "  - $var_name"
        done
        return 1
    fi
    
    return 0
}

# Validate IP address format (IPv4)
# Parameters:
#   $1: IP address to validate
# Returns:
#   0 if valid IP address
#   1 if invalid IP address
# Example:
#   validate_ip_address "192.168.1.1"
validate_ip_address() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        print_error "IP address is empty"
        return 1
    fi
    
    # Check IPv4 format: four octets separated by dots
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "Invalid IP address format: $ip"
        return 1
    fi
    
    # Check each octet is 0-255
    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if ((octet > 255)); then
            print_error "Invalid IP address (octet > 255): $ip"
            return 1
        fi
    done
    
    return 0
}

# Validate email address format
# Parameters:
#   $1: Email address to validate
# Returns:
#   0 if valid email address
#   1 if invalid email address
# Example:
#   validate_email "user@mydomain.com"
validate_email() {
    local email="$1"
    
    if [[ -z "$email" ]]; then
        print_error "Email address is empty"
        return 1
    fi
    
    # Basic email format: user@domain.tld
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid email address format: $email"
        return 1
    fi
    
    return 0
}

# Validate domain name format
# Parameters:
#   $1: Domain name to validate
# Returns:
#   0 if valid domain name
#   1 if invalid domain name
# Example:
#   validate_domain "mydomain.com"
validate_domain() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        print_error "Domain name is empty"
        return 1
    fi
    
    # Basic domain format: alphanumeric with dots and hyphens
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        print_error "Invalid domain name format: $domain"
        return 1
    fi
    
    return 0
}
