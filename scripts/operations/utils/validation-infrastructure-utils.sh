#!/bin/bash
set -euo pipefail

# Utility Library: Phase 2 Validation Functions
# Purpose: Reusable validation functions for Phase 2 deployment verification
# Functions: validate_data_structure, validate_family_subdirectories, validate_backup_subdirectories,
#            validate_services_yaml, validate_logrotate_caddy, validate_logrotate_pihole,
#            validate_logrotate_msmtp, validate_dns_service, validate_dns_resolution, validate_external_dns,
#            validate_caddy_service, validate_caddy_https, validate_certificate_trust, validate_smtp_service,
#            validate_smtp_test, validate_netdata_service, validate_netdata_dashboard
# Usage: source this file, then call validation functions
#
# Example:
#   source scripts/operations/utils/validation-infrastructure-utils.sh
#   validate_data_structure || exit 1
#   validate_dns_service || exit 1

# Source output utilities for messages (if not already loaded)
if ! command -v print_success &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/output-utils.sh"
fi

# Phase 2 Validation Functions

validate_data_structure() {
    local status="PASS"
    
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
    # services.yaml was originally planned for Ansible-based config generation
    # but was dropped in favor of direct Docker Compose files per service (simpler)
    # Check that at least one Docker Compose service file exists instead
    local count=0
    for f in /opt/homeserver/configs/docker-compose/*.yml; do
        [[ -f "$f" ]] && count=$((count + 1))
    done
    if [[ $count -gt 0 ]]; then
        print_success "Docker Compose service files found ($count)"
        return 0
    else
        print_info "No Docker Compose service files found in configs/docker-compose/"
        return 1
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
        
        # Check health status
        HEALTH_STATUS=$(docker inspect pihole --format='{{.State.Health.Status}}' 2>/dev/null || echo "no healthcheck")
        if [[ "$HEALTH_STATUS" == "healthy" ]]; then
            print_success "Pi-hole is healthy"
        elif [[ "$HEALTH_STATUS" == "starting" ]]; then
            print_info "Pi-hole health check is starting"
        elif [[ "$HEALTH_STATUS" == "no healthcheck" ]]; then
            print_warning "Pi-hole has no HEALTHCHECK configured"
        else
            print_warning "Pi-hole health status: $HEALTH_STATUS"
        fi
        
        return 0
    else
        print_info "Pi-hole not yet deployed (will be deployed in Task 5.1)"
        return 1
    fi
}

validate_dns_resolution() {
    # Required env vars: INTERNAL_SUBDOMAIN, SERVER_IP (exported by calling script)
    
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
        
        # Check health status
        HEALTH_STATUS=$(docker inspect caddy --format='{{.State.Health.Status}}' 2>/dev/null || echo "no healthcheck")
        if [[ "$HEALTH_STATUS" == "healthy" ]]; then
            print_success "Caddy is healthy"
        elif [[ "$HEALTH_STATUS" == "starting" ]]; then
            print_info "Caddy health check is starting"
        elif [[ "$HEALTH_STATUS" == "no healthcheck" ]]; then
            print_warning "Caddy has no HEALTHCHECK configured"
        else
            print_warning "Caddy health status: $HEALTH_STATUS"
        fi
        
        return 0
    else
        print_info "Caddy not yet deployed (will be deployed in Task 4.1)"
        return 1
    fi
}

validate_caddy_https() {
    # Required env vars: INTERNAL_SUBDOMAIN, SERVER_IP (exported by calling script)
    
    if docker ps | grep -q caddy; then
        local http_code
        http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "monitor.${INTERNAL_SUBDOMAIN}:443:${SERVER_IP}" "https://monitor.${INTERNAL_SUBDOMAIN}" 2>/dev/null) || true
        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]; then
            print_success "Caddy HTTPS working (HTTP $http_code)"
            return 0
        else
            print_info "Caddy HTTPS not yet configured (HTTP $http_code)"
            return 1
        fi
    else
        print_info "Caddy not yet deployed"
        return 1
    fi
}

validate_certificate_trust() {
    if docker ps --filter "name=caddy" --filter "status=running" --format "{{.Names}}" | grep -q caddy; then
        # Check both: exported copy and original in Caddy data volume
        if [[ -f "/opt/homeserver/configs/caddy/root-ca.crt" ]]; then
            print_success "Root CA certificate exported"
            return 0
        elif [[ -f "/opt/homeserver/configs/caddy/data/caddy/pki/authorities/local/root.crt" ]]; then
            print_success "Root CA certificate exists in Caddy data volume"
            return 0
        else
            print_info "Root CA certificate not found"
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
    # Required env vars: ADMIN_USER (exported by calling script)
    
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
    # Required env vars: INTERNAL_SUBDOMAIN, SERVER_IP (exported by calling script)
    
    if docker ps | grep -q netdata; then
        local http_code
        http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "monitor.${INTERNAL_SUBDOMAIN}:443:${SERVER_IP}" "https://monitor.${INTERNAL_SUBDOMAIN}" 2>/dev/null) || true
        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]; then
            print_success "Netdata dashboard accessible (HTTP $http_code)"
            return 0
        else
            print_info "Netdata dashboard not yet configured (HTTP $http_code)"
            return 1
        fi
    else
        print_info "Netdata not yet deployed"
        return 1
    fi
}


# Wrapper functions for orchestration script compatibility
validate_data_directories() { validate_data_structure; }
validate_caddy_container() { validate_caddy_service; }
validate_ca_certificate() { validate_certificate_trust; }
validate_pihole_container() { validate_dns_service; }
validate_pihole_web_ui() {
    # Validates Pi-hole web interface is accessible via Caddy reverse proxy
    # Required env vars: INTERNAL_SUBDOMAIN, SERVER_IP
    if ! docker ps | grep -q pihole; then
        print_info "Pi-hole not yet deployed"
        return 1
    fi
    local http_code
    http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "pihole.${INTERNAL_SUBDOMAIN}:443:${SERVER_IP}" "https://pihole.${INTERNAL_SUBDOMAIN}/admin/" 2>/dev/null) || true
    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]; then
        print_success "Pi-hole web UI accessible via Caddy (HTTP $http_code)"
        return 0
    else
        print_error "Pi-hole web UI NOT accessible via Caddy (HTTP $http_code)"
        return 1
    fi
}
validate_dns_records() { validate_dns_resolution; }
validate_msmtp() { validate_smtp_service; }
validate_netdata_container() { validate_netdata_service; }
validate_log_rotation() {
    validate_logrotate_caddy && validate_logrotate_pihole && validate_logrotate_msmtp
}


# ── Checks Registry (single source of truth) ──
# Used by: deploy-phase2-infrastructure.sh validate_all(), validate-all.sh
PHASE2_CHECKS=(
    "Data Structure:validate_data_structure"
    "Family Directories:validate_family_subdirectories"
    "Backup Directories:validate_backup_subdirectories"
    "Compose Files:validate_services_yaml"
    "Caddy Service:validate_caddy_service"
    "Caddy HTTPS:validate_caddy_https"
    "CA Certificate:validate_certificate_trust"
    "Pi-hole Service:validate_dns_service"
    "Pi-hole Web UI:validate_pihole_web_ui"
    "DNS Resolution:validate_dns_resolution"
    "External DNS:validate_external_dns"
    "msmtp Service:validate_smtp_service"
    "msmtp Test:validate_smtp_test"
    "Netdata Service:validate_netdata_service"
    "Netdata Dashboard:validate_netdata_dashboard"
    "Logrotate Caddy:validate_logrotate_caddy"
    "Logrotate Pi-hole:validate_logrotate_pihole"
    "Logrotate msmtp:validate_logrotate_msmtp"
)
