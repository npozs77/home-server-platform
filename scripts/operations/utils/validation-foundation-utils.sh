#!/bin/bash
set -euo pipefail

# Utility Library: Phase 1 Validation Functions
# Purpose: Reusable validation functions for Phase 1 deployment verification
# Functions: validate_ssh_hardening, validate_ufw_firewall, validate_fail2ban, 
#            validate_docker, validate_git_repository, validate_unattended_upgrades,
#            validate_luks_encryption, validate_docker_group, validate_essential_tools
# Usage: source this file, then call validation functions
#
# Example:
#   source scripts/operations/utils/validation-foundation-utils.sh
#   validate_ssh_hardening || exit 1
#   validate_docker || exit 1

# Source output utilities for messages
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/output-utils.sh"

# Phase 1 Validation Functions

validate_ssh_hardening() {
    local status="PASS"
    
    if grep -q "^Port 22" /etc/ssh/sshd_config; then
        print_success "Port 22 uncommented"
    else
        print_error "Port 22 NOT uncommented"
        status="FAIL"
    fi
    
    if grep -q "^UseDNS no" /etc/ssh/sshd_config; then
        print_success "UseDNS disabled (prevents DNS delays)"
    else
        print_error "UseDNS NOT disabled"
        status="FAIL"
    fi
    
    if grep -q "^GSSAPIAuthentication no" /etc/ssh/sshd_config; then
        print_success "GSSAPIAuthentication disabled (prevents auth delays)"
    else
        print_error "GSSAPIAuthentication NOT disabled"
        status="FAIL"
    fi
    
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
        print_success "Password authentication disabled"
    else
        print_error "Password authentication NOT disabled"
        status="FAIL"
    fi
    
    if grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config; then
        print_success "Public key authentication enabled"
    else
        print_error "Public key authentication NOT enabled"
        status="FAIL"
    fi
    
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
        print_success "Root login disabled"
    else
        print_error "Root login NOT disabled"
        status="FAIL"
    fi
    
    if grep -q "^ClientAliveInterval 300" /etc/ssh/sshd_config; then
        print_success "Idle timeout configured (1 hour)"
    else
        print_error "Idle timeout NOT configured"
        status="FAIL"
    fi
    
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
    
    if ufw status | grep -q "Status: active"; then
        print_success "UFW firewall active"
    else
        print_error "UFW firewall NOT active"
        status="FAIL"
    fi
    
    if ufw status | grep -q "22.*ALLOW.*192.168.1.0/24"; then
        print_success "SSH allowed from LAN"
    else
        print_error "SSH NOT allowed from LAN"
        status="FAIL"
    fi
    
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
    
    if systemctl is-active --quiet fail2ban; then
        print_success "fail2ban service running"
    else
        print_error "fail2ban service NOT running"
        status="FAIL"
    fi
    
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
    
    if command -v docker &> /dev/null; then
        print_success "Docker installed"
    else
        print_error "Docker NOT installed"
        status="FAIL"
    fi
    
    if docker compose version &>/dev/null; then
        print_success "Docker Compose installed"
    else
        print_error "Docker Compose NOT installed"
        status="FAIL"
    fi
    
    if systemctl is-active --quiet docker; then
        print_success "Docker service running"
    else
        print_error "Docker service NOT running"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_git_repository() {
    local status="PASS"
    
    if [[ -d /opt/homeserver/.git ]]; then
        print_success "Git repository initialized"
    else
        print_error "Git repository NOT initialized"
        status="FAIL"
    fi
    
    if [[ -d /opt/homeserver/docs ]] && [[ -d /opt/homeserver/scripts ]] && [[ -d /opt/homeserver/configs ]]; then
        print_success "Directory structure exists"
    else
        print_error "Directory structure incomplete"
        status="FAIL"
    fi
    
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
    
    if systemctl is-active --quiet unattended-upgrades; then
        print_success "unattended-upgrades service running"
    else
        print_error "unattended-upgrades service NOT running"
        status="FAIL"
    fi
    
    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
        print_success "Auto-upgrades configured"
    else
        print_error "Auto-upgrades NOT configured"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_luks_encryption() {
    # Required env vars: DATA_DISK (exported by calling script)
    local status="PASS"
    
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
    # Required env vars: ADMIN_USER (exported by calling script)
    local status="PASS"
    
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
    
    # Check modern CLI tools
    for tool in fzf rg jq zsh; do
        if command -v "$tool" &> /dev/null; then
            print_success "$tool installed"
        else
            print_error "$tool NOT installed"
            status="FAIL"
        fi
    done
    
    # Check symlinks
    if [[ -L /usr/local/bin/bat ]] || command -v bat &>/dev/null; then
        print_success "bat available"
    else
        print_error "bat NOT available (symlink missing?)"
        status="FAIL"
    fi
    
    if [[ -L /usr/local/bin/fd ]] || command -v fd &>/dev/null; then
        print_success "fd available"
    else
        print_error "fd NOT available (symlink missing?)"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}

validate_shell_environment() {
    local status="PASS"
    
    # Check Oh-My-Zsh installed
    if [[ -d /usr/share/oh-my-zsh ]]; then
        print_success "Oh-My-Zsh installed system-wide"
    else
        print_error "Oh-My-Zsh NOT installed"
        status="FAIL"
    fi
    
    # Check Powerlevel10k installed
    if [[ -d /usr/share/powerlevel10k ]]; then
        print_success "Powerlevel10k installed system-wide"
    else
        print_error "Powerlevel10k NOT installed"
        status="FAIL"
    fi
    
    # Check ZDOTDIR
    if grep -q "ZDOTDIR=/etc/zsh" /etc/zsh/zshenv 2>/dev/null; then
        print_success "ZDOTDIR set to /etc/zsh"
    else
        print_error "ZDOTDIR NOT configured"
        status="FAIL"
    fi
    
    # Check global .zshrc
    if [[ -f /etc/zsh/.zshrc ]]; then
        print_success "Global .zshrc exists"
    else
        print_error "Global .zshrc NOT found"
        status="FAIL"
    fi
    
    # Check default shell for new users
    if grep -q "/usr/bin/zsh" /etc/default/useradd 2>/dev/null; then
        print_success "Default shell set to zsh for new users"
    else
        print_error "Default shell NOT set to zsh"
        status="FAIL"
    fi
    
    [[ "$status" == "PASS" ]] && return 0 || return 1
}


# ── Checks Registry (single source of truth) ──
# Used by: deploy-phase1-foundation.sh validate_all(), validate-all.sh
PHASE1_CHECKS=(
    "SSH Hardening:validate_ssh_hardening"
    "UFW Firewall:validate_ufw_firewall"
    "fail2ban:validate_fail2ban"
    "Docker:validate_docker"
    "Git Repository:validate_git_repository"
    "Unattended-upgrades:validate_unattended_upgrades"
    "LUKS Encryption:validate_luks_encryption"
    "Docker Group:validate_docker_group"
    "Essential Tools:validate_essential_tools"
    "Shell Environment:validate_shell_environment"
)
