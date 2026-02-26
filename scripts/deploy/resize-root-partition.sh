#!/bin/bash
set -euo pipefail

# Resize Root Partition Script
# Purpose: Shrink root partition to ~50GB and create new partition for LUKS encryption
# Use case: Single disk installations where entire disk was allocated to root during Ubuntu install

echo "=========================================="
echo "Root Partition Resize Script"
echo "=========================================="
echo ""
echo "This script will:"
echo "1. Shrink root partition to 50GB"
echo "2. Create new partition from freed space (~900GB)"
echo "3. Prepare new partition for LUKS encryption"
echo ""
echo "WARNING: This operation requires a reboot and can be risky!"
echo "BACKUP ANY IMPORTANT DATA BEFORE PROCEEDING"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Display current disk layout
echo "Current disk layout:"
lsblk
echo ""
df -h
echo ""

# Identify root partition
ROOT_PARTITION=$(findmnt -n -o SOURCE /)
ROOT_DISK=$(lsblk -no pkname "$ROOT_PARTITION")
echo "Root partition: $ROOT_PARTITION"
echo "Root disk: /dev/$ROOT_DISK"
echo ""

# Confirm with user
read -p "Do you want to proceed with resizing? (type 'yes' to continue): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted by user"
    exit 0
fi

# Install required tools
echo ""
echo "Installing required tools..."
apt update
apt install -y cloud-guest-utils parted

# Resize filesystem to 50GB
echo ""
echo "Step 1: Shrinking filesystem to 50GB..."
echo "This may take several minutes..."
resize2fs "$ROOT_PARTITION" 50G

# Get partition number
PART_NUM=$(echo "$ROOT_PARTITION" | grep -o '[0-9]*$')

# Resize partition
echo ""
echo "Step 2: Resizing partition..."
parted /dev/$ROOT_DISK resizepart $PART_NUM 50GB

# Create new partition
echo ""
echo "Step 3: Creating new partition from freed space..."
parted /dev/$ROOT_DISK mkpart primary ext4 50GB 100%

# Get new partition number (should be next number)
NEW_PART_NUM=$((PART_NUM + 1))
NEW_PARTITION="/dev/${ROOT_DISK}${NEW_PART_NUM}"

echo ""
echo "=========================================="
echo "Partition resize complete!"
echo "=========================================="
echo ""
echo "New disk layout:"
lsblk
echo ""
echo "Root partition: $ROOT_PARTITION (50GB)"
echo "New data partition: $NEW_PARTITION (~900GB)"
echo ""
echo "Next steps:"
echo "1. Reboot the server: sudo reboot"
echo "2. After reboot, run deployment script Task 2.2 to encrypt $NEW_PARTITION"
echo "3. Deployment script will format and encrypt the new partition with LUKS"
echo ""
echo "IMPORTANT: Note the new partition device: $NEW_PARTITION"
echo "You will need this for the deployment script configuration"
echo ""
