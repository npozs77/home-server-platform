#!/bin/bash
# Task: Setup LUKS disk encryption
# Phase: 1 (Foundation)
# Number: 02
# Prerequisites: Task 1 complete (system updated)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   2 = Prerequisites not met
#   3 = Configuration error
# Environment Variables Required:
#   DATA_DISK, LUKS_PASSPHRASE
# Environment Variables Optional:
#   None

set -euo pipefail
# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utility libraries
source /opt/homeserver/scripts/operations/utils/output-utils.sh
source /opt/homeserver/scripts/operations/utils/env-utils.sh

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate required environment variables
validate_required_vars "DATA_DISK" "LUKS_PASSPHRASE" || exit 3

# Validate LUKS passphrase strength
if [[ ${#LUKS_PASSPHRASE} -lt 20 ]]; then
    print_error "LUKS passphrase must be at least 20 characters"
    exit 3
fi

# Check if already completed (idempotency)
if cryptsetup isLuks "$DATA_DISK" 2>/dev/null; then
    if [[ -e /dev/mapper/data_crypt ]] && df -h | grep -q "/mnt/data"; then
        if [[ -f /root/.luks-key ]]; then
            print_info "LUKS encryption already configured - skip"
            exit 0
        fi
    fi
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would format $DATA_DISK with LUKS encryption"
    print_info "[DRY-RUN] Would create ext4 filesystem"
    print_info "[DRY-RUN] Would generate key file at /root/.luks-key"
    print_info "[DRY-RUN] Would configure /etc/crypttab and /etc/fstab"
    print_info "[DRY-RUN] Would create mount point /mnt/data"
    exit 0
fi

print_header "Task 2: Setup LUKS Disk Encryption"
echo ""

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
exit 0
