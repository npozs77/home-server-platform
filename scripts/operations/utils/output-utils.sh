#!/bin/bash
set -euo pipefail

# Utility Library: Output Formatting
# Purpose: Provide consistent colored output functions for deployment scripts
# Functions: print_success, print_error, print_info, print_header
# Usage: source this file, then call functions
#
# Example:
#   source scripts/operations/utils/output-utils.sh
#   print_success "Task completed successfully"
#   print_error "Task failed"
#   print_info "Processing..."
#   print_header "Phase 1: Foundation"

# Guard against multiple sourcing
[[ -n "${OUTPUT_UTILS_LOADED:-}" ]] && return 0
readonly OUTPUT_UTILS_LOADED=1

# Color codes
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

# Symbols
readonly SYMBOL_SUCCESS="✓"
readonly SYMBOL_ERROR="✗"
readonly SYMBOL_INFO="ℹ"

# Print success message with green checkmark
# Parameters:
#   $1: Message to print
# Returns: None
print_success() {
    local message="$1"
    echo -e "${COLOR_GREEN}${SYMBOL_SUCCESS}${COLOR_RESET} ${message}"
}

# Print error message with red X
# Parameters:
#   $1: Message to print
# Returns: None
print_error() {
    local message="$1"
    echo -e "${COLOR_RED}${SYMBOL_ERROR}${COLOR_RESET} ${message}" >&2
}

# Print info message with yellow info icon
# Parameters:
#   $1: Message to print
# Returns: None
print_info() {
    local message="$1"
    echo -e "${COLOR_YELLOW}${SYMBOL_INFO}${COLOR_RESET} ${message}"
}

# Print header message with blue color
# Parameters:
#   $1: Header text to print
# Returns: None
print_header() {
    local header="$1"
    echo ""
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
    echo -e "${COLOR_BLUE}${header}${COLOR_RESET}"
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
    echo ""
}
