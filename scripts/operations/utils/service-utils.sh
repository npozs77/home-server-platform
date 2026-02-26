#!/bin/bash
set -euo pipefail

# Utility Library: Service Health Checks
# Purpose: Check if services are running and healthy
# Functions: check_docker_container, check_systemd_service, check_port_listening
# Usage: source this file, then call functions
#
# Example:
#   source scripts/operations/utils/service-utils.sh
#   check_docker_container "caddy" || exit 1
#   check_systemd_service "docker" || exit 1
#   check_port_listening 443 || exit 1

# Source output utilities for error messages
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/output-utils.sh"

# Check if Docker container exists and is running
# Parameters:
#   $1: container_name - Name of the Docker container
# Returns:
#   0 if container is running
#   1 if container is not running or doesn't exist
# Example:
#   check_docker_container "caddy"
check_docker_container() {
    local container_name="$1"
    
    if [[ -z "$container_name" ]]; then
        print_error "check_docker_container: container_name parameter is required"
        return 1
    fi
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        print_error "check_docker_container: docker command not found"
        return 1
    fi
    
    # Check if container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return 1
    fi
    
    return 0
}

# Check if systemd service is active
# Parameters:
#   $1: service_name - Name of the systemd service
# Returns:
#   0 if service is active
#   1 if service is not active or doesn't exist
# Example:
#   check_systemd_service "docker"
check_systemd_service() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        print_error "check_systemd_service: service_name parameter is required"
        return 1
    fi
    
    # Check if systemctl is available
    if ! command -v systemctl &> /dev/null; then
        print_error "check_systemd_service: systemctl command not found"
        return 1
    fi
    
    # Check if service is active
    if ! systemctl is-active --quiet "$service_name"; then
        return 1
    fi
    
    return 0
}

# Check if port is in LISTEN state
# Parameters:
#   $1: port_number - Port number to check
# Returns:
#   0 if port is listening
#   1 if port is not listening
# Example:
#   check_port_listening 443
check_port_listening() {
    local port_number="$1"
    
    if [[ -z "$port_number" ]]; then
        print_error "check_port_listening: port_number parameter is required"
        return 1
    fi
    
    # Validate port number is numeric
    if ! [[ "$port_number" =~ ^[0-9]+$ ]]; then
        print_error "check_port_listening: port_number must be numeric"
        return 1
    fi
    
    # Check if ss command is available (preferred)
    if command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":${port_number} "; then
            return 0
        fi
    # Fallback to netstat if ss not available
    elif command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":${port_number} "; then
            return 0
        fi
    else
        print_error "check_port_listening: neither ss nor netstat command found"
        return 1
    fi
    
    return 1
}
