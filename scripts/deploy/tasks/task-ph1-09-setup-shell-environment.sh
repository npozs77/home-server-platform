#!/bin/bash
# Task: Set up global Zsh + Oh-My-Zsh + Powerlevel10k shell environment
# Phase: 1 (Foundation)
# Number: 09
# Prerequisites: task-ph1-01 (zsh and modern CLI tools installed)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
# Environment Variables Required:
#   ADMIN_USER

set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utility libraries
source /opt/homeserver/scripts/operations/utils/output-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Idempotency check
if [[ -d /usr/share/oh-my-zsh ]] && [[ -d /usr/share/powerlevel10k ]] && \
   [[ -f /etc/zsh/.zshrc ]] && grep -q "ZDOTDIR=/etc/zsh" /etc/zsh/zshenv 2>/dev/null; then
    print_info "Shell environment already configured - skip"
    exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would install Oh-My-Zsh system-wide to /usr/share/oh-my-zsh"
    print_info "[DRY-RUN] Would install Powerlevel10k to /usr/share/powerlevel10k"
    print_info "[DRY-RUN] Would set ZDOTDIR=/etc/zsh in /etc/zsh/zshenv"
    print_info "[DRY-RUN] Would create global /etc/zsh/.zshrc"
    print_info "[DRY-RUN] Would set zsh as default shell for all users"
    exit 0
fi

print_header "Task 9: Set Up Global Shell Environment"
echo ""

# Step 1: Install Oh-My-Zsh system-wide
if [[ ! -d /usr/share/oh-my-zsh ]]; then
    print_info "Installing Oh-My-Zsh system-wide..."
    git clone https://github.com/ohmyzsh/ohmyzsh.git /usr/share/oh-my-zsh
else
    print_info "Oh-My-Zsh already installed"
fi

# Step 2: Install Powerlevel10k system-wide
if [[ ! -d /usr/share/powerlevel10k ]]; then
    print_info "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /usr/share/powerlevel10k
    ln -sf /usr/share/powerlevel10k /usr/share/oh-my-zsh/themes/powerlevel10k
else
    print_info "Powerlevel10k already installed"
fi

# Step 3: Symlink plugin directories
print_info "Setting up plugin symlinks..."
mkdir -p /usr/share/oh-my-zsh/custom/plugins
ln -sf /usr/share/zsh-autosuggestions /usr/share/oh-my-zsh/custom/plugins/zsh-autosuggestions
ln -sf /usr/share/zsh-syntax-highlighting /usr/share/oh-my-zsh/custom/plugins/zsh-syntax-highlighting

# Step 4: Set global ZDOTDIR
print_info "Configuring ZDOTDIR..."
if ! grep -q "ZDOTDIR=/etc/zsh" /etc/zsh/zshenv 2>/dev/null; then
    sed -i '1i export ZDOTDIR=/etc/zsh' /etc/zsh/zshenv
fi

# Step 5: Create global .zshrc
print_info "Creating global /etc/zsh/.zshrc..."
cat > /etc/zsh/.zshrc << 'ZSHRC'
skip_global_compinit=1
export ZSH="/usr/share/oh-my-zsh"

fpath=(
  /usr/share/oh-my-zsh/custom/plugins/zsh-autosuggestions
  /usr/share/oh-my-zsh/custom/plugins/zsh-syntax-highlighting
  $fpath
)

plugins=(git fzf)

ZSH_THEME="powerlevel10k/powerlevel10k"
source $ZSH/oh-my-zsh.sh

[[ -f /etc/zsh/p10k.zsh ]] && source /etc/zsh/p10k.zsh

alias bat="batcat"
alias fd="fdfind"

# fzf integration
if [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
  source /usr/share/doc/fzf/examples/key-bindings.zsh
fi

if [ -f /usr/share/doc/fzf/examples/completion.zsh ]; then
  source /usr/share/doc/fzf/examples/completion.zsh
fi

# Manual plugin loading (required for Ubuntu)
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSHRC

# Step 6: Set zsh as default shell for existing users and new users
print_info "Setting zsh as default shell..."
if id "$ADMIN_USER" &>/dev/null; then
    chsh -s /usr/bin/zsh "$ADMIN_USER"
fi
# Replace whatever default shell is set (could be /bin/sh or /bin/bash)
if grep -q "^SHELL=" /etc/default/useradd; then
    sed -i 's#^SHELL=.*#SHELL=/usr/bin/zsh#' /etc/default/useradd
else
    echo "SHELL=/usr/bin/zsh" >> /etc/default/useradd
fi

print_success "Task 9 complete"
print_info "NOTE: Run 'p10k configure' after first login to generate /etc/zsh/p10k.zsh"
exit 0
