# Phase 01 - Foundation Layer Deployment Manual

**Version**: 1.0  
**Status**: Ready for Deployment  
**Last Updated**: 2025-02-01  
**Estimated Time**: 4-6 hours

## Overview

This manual provides step-by-step procedures for deploying the Phase 01 Foundation Layer. Follow these instructions to establish the secure, stable base operating system and essential infrastructure for the home media server platform.

**Prerequisites**:
- Domain registered (see `input_docs/domain.md`)
- Ubuntu Server LTS 24.04 ISO downloaded
- Bootable USB drive (8GB+)
- Server hardware ready (Windows Mini PC repurposed for Ubuntu)
- Admin laptop for SSH access

**Reference Documents**:
- Requirements: `.kiro/specs/01-foundation/requirements.md`
- Design: `.kiro/specs/01-foundation/design.md`
- Tasks: `.kiro/specs/01-foundation/tasks.md`
- Configuration Guide: `configs/CONFIG_GUIDE.md`

## Quick Start

1. Create bootable USB with Ubuntu Server LTS 24.04
2. Install Ubuntu Server on hardware (configure WiFi during install, enable OpenSSH)
3. Configure DHCP reservation on router using MAC address from install
4. SSH to server and run deploy-phase1-foundation.sh
5. Validate deployment with option 'v'

**Note**: bootstrap.sh is NOT needed - Ubuntu installer handles network configuration

## Task 1: Prepare Installation Media

**Objective**: Create bootable USB with Ubuntu Server and deployment scripts

**Prerequisites**: 
- Ubuntu Server LTS 24.04 ISO downloaded
- USB drive (8GB+)
- Task 0 complete (scripts exist and are validated)

**Steps**:

1. **Download Ubuntu Server ISO**
   ```bash
   # Download from https://ubuntu.com/download/server
   # Verify checksum
   sha256sum ubuntu-24.04-live-server-amd64.iso
   ```

2. **Create bootable USB** (Windows)
   - Use Rufus or balenaEtcher
   - Select Ubuntu ISO
   - Select USB drive
   - Write ISO to USB

3. **Create bootable USB** (Linux/Mac)
   ```bash
   # Find USB device
   lsblk
   
   # Write ISO to USB (replace /dev/sdX with your USB device)
   sudo dd if=ubuntu-24.04-live-server-amd64.iso of=/dev/sdX bs=4M status=progress
   sudo sync
   ```

4. **Copy deployment scripts to USB**
   ```bash
   # Mount USB data partition
   # Copy scripts from project
   cp scripts/deploy/bootstrap.sh /media/usb/
   cp scripts/deploy/deploy-phase1-foundation.sh /media/usb/
   cp configs/foundation.env.example /media/usb/
   cp configs/secrets.env.example /media/usb/
   ```

5. **Verify USB contents**
   ```bash
   ls -la /media/usb/
   # Should see: bootstrap.sh, deploy-phase1-foundation.sh, foundation.env.example, secrets.env.example
   ```

**Verification**:
- [ ] USB boots successfully
- [ ] Scripts are accessible on USB data partition
- [ ] Scripts have execute permissions

**Troubleshooting**:
- **USB won't boot**: Check BIOS boot order, try different USB port
- **Scripts not found**: Check USB partition mount point
- **Permission denied**: Make scripts executable: `chmod +x *.sh`


## Task 2: Install Ubuntu Server LTS 24.04

**Objective**: Install Ubuntu Server on hardware with minimal configuration

**Prerequisites**: 
- Bootable USB ready
- Server hardware powered on

**Steps**:

1. **Boot from USB**
   - Insert USB into server
   - Power on server
   - Press F12/F2/Del to enter boot menu (varies by hardware)
   - Select USB drive

2. **Start Ubuntu Server installation**
   - Select "Install Ubuntu Server"
   - Choose language: English
   - Choose keyboard layout: US (or your preference)

3. **Network configuration**
   - **IMPORTANT**: Use Ethernet with DHCP during installation
   - Reason: Need internet access to download packages (chicken-egg: can't install WiFi drivers without internet)
   - WiFi will be configured later via bootstrap script
   - Ethernet remains as backup interface (always available with DHCP)

4. **Storage configuration**
   - Select "Use an entire disk"
   - Select OS disk (usually smallest disk, e.g., 128GB SSD)
   - Do NOT select data disk (will encrypt later)
   - Confirm disk selection

5. **Profile setup**
   - Your name: Admin User
   - Server name: homeserver
   - Username: admin (or your preference)
   - Password: Strong password (will use SSH keys later)

6. **SSH setup**
   - Select "Install OpenSSH server"
   - Do NOT import SSH keys yet

7. **Featured server snaps**
   - Skip all (we'll install Docker manually)

8. **Installation**
   - Confirm and begin installation
   - Wait 10-15 minutes for installation to complete
   - Remove USB when prompted
   - Reboot

9. **First boot**
   - Wait for login prompt
   - Login with username and password

**Verification**:
```bash
# Check OS version
lsb_release -a
# Should show: Ubuntu 24.04 LTS

# Check network
ip addr
# Should show IP address assigned

# Check internet connectivity
ping -c 3 8.8.8.8
# Should succeed

# Check disk layout
lsblk
# Should show OS disk mounted, data disk unmounted
```

**Verification Checklist**:
- [ ] Ubuntu 24.04 LTS installed
- [ ] System boots to login prompt
- [ ] Login works with username/password
- [ ] Network interface has IP address
- [ ] Internet connectivity works
- [ ] Data disk is unmounted (for encryption later)

**Troubleshooting**:
- **No network**: Check cable, try different port, verify DHCP on router
- **Installation fails**: Check disk health, try different disk
- **Can't login**: Verify username/password, check caps lock


## Task 3: Run Bootstrap Script for Network Configuration

**Objective**: Configure network and obtain stable IP via DHCP reservation

**Prerequisites**: 
- Ubuntu Server installed
- USB with bootstrap.sh accessible

**Sub-task 3.1: Mount USB and copy bootstrap script**

**Steps**:
1. **Insert USB drive**
   ```bash
   # Wait for USB to be detected
   lsblk
   # Look for USB device (e.g., /dev/sdb1)
   ```

2. **Mount USB**
   ```bash
   sudo mkdir -p /mnt/usb
   sudo mount /dev/sdb1 /mnt/usb
   ```

3. **Copy bootstrap script**
   ```bash
   cp /mnt/usb/bootstrap.sh ~/
   chmod +x ~/bootstrap.sh
   ```

4. **Verify script**
   ```bash
   ls -la ~/bootstrap.sh
   # Should show executable permissions
   ```

**Sub-task 3.2: Run bootstrap script**

**Network Strategy**:
- **Ethernet**: Already configured during installation (DHCP), remains as backup
- **WiFi**: Optional, configure now for primary connectivity
- **Result**: Server accessible via WiFi (primary) or Ethernet (backup), both with DHCP reservation

**Steps**:
1. **Execute bootstrap script**
   ```bash
   sudo ~/bootstrap.sh
   ```

2. **Follow prompts**
   - **Option 1: WiFi Primary + Ethernet Backup** (recommended for headless)
     - Select WiFi interface
     - Enter SSID and password
     - Script configures WiFi
     - Ethernet remains available as backup (DHCP)
   
   - **Option 2: Ethernet Only** (simpler, wired connection)
     - Select Ethernet interface
     - Already configured during installation
     - Script confirms connectivity
   
   - Script tests connectivity
   - Script displays MAC address(es)

3. **Note MAC address**
   - Write down MAC address for primary interface
   - Example: `aa:bb:cc:dd:ee:ff`
   - Needed for DHCP reservation

**Expected Output**:
```
Network Configuration Bootstrap
================================
Detected interfaces:
1. enp0s3 (Ethernet) - Already configured
2. wlp2s0 (WiFi) - Not configured

Select primary interface [1-2]: 2

Configuring WiFi (wlp2s0)...
Enter SSID: MyHomeNetwork
Enter Password: ********

✓ WiFi configured
✓ Connectivity test passed
✓ Ethernet backup remains available

Primary Interface MAC Address: bb:cc:dd:ee:ff:00
Backup Interface MAC Address: aa:bb:cc:dd:ee:ff

Note the PRIMARY MAC address for DHCP reservation

Next steps:
1. Configure DHCP reservation on router (primary interface)
2. Reboot server to obtain reserved IP
```

**Sub-task 3.3: Configure DHCP reservation on router**

**Steps**:
1. **Access router admin panel**
   - Open browser on admin laptop
   - Navigate to http://192.168.1.1
   - Login with router credentials

2. **Add DHCP reservation**
   - Navigate to DHCP settings
   - Add new reservation:
     - MAC Address: `aa:bb:cc:dd:ee:ff` (from bootstrap script)
     - IP Address: `192.168.1.2`
     - Description: `homeserver`
   - Save changes

3. **Reboot server**
   ```bash
   sudo reboot
   ```

4. **Wait for reboot** (2-3 minutes)

**Sub-task 3.4: Verify stable IP and SSH access**

**Steps**:
1. **Check server IP** (on server console)
   ```bash
   ip addr show
   # Should show 192.168.1.2
   ```

2. **Test SSH from admin laptop**
   ```bash
   ssh admin@192.168.1.2
   # Should prompt for password
   # Login with password
   ```

3. **Verify network persists after reboot**
   ```bash
   # On server
   sudo reboot
   # Wait 2-3 minutes
   # SSH again
   ssh admin@192.168.1.2
   # Should work
   ```

**Verification Checklist**:
- [ ] Bootstrap script executed successfully
- [ ] MAC address noted
- [ ] DHCP reservation configured on router
- [ ] Server has IP 192.168.1.2
- [ ] SSH from admin laptop works
- [ ] Network persists after reboot

**Troubleshooting**:
- **WiFi not working**: Check SSID/password, verify WiFi hardware
- **DHCP reservation not working**: Verify MAC address, reboot router
- **Can't SSH**: Check firewall on admin laptop, verify IP address
- **Network lost after reboot**: Check netplan config, verify DHCP reservation


## Task 4: Copy Deployment Script and Initialize Configuration

**Objective**: Copy deployment script and initialize configuration

**Prerequisites**: 
- SSH access working
- USB with deploy-phase1-foundation.sh accessible

**Sub-task 4.1: Copy deployment script from USB**

**Steps**:
1. **Mount USB** (if not already mounted)
   ```bash
   sudo mkdir -p /mnt/usb
   sudo mount /dev/sdb1 /mnt/usb
   ```

2. **Copy deployment script**
   ```bash
   cp /mnt/usb/deploy-phase1-foundation.sh ~/
   chmod +x ~/deploy-phase1-foundation.sh
   ```

3. **Unmount and remove USB**
   ```bash
   sudo umount /mnt/usb
   # Remove USB drive
   ```

4. **Verify script**
   ```bash
   ls -la ~/deploy-phase1-foundation.sh
   # Should show executable permissions
   ```

**Sub-task 4.2: Initialize configuration**

**Steps**:
1. **Run deployment script**
   ```bash
   sudo ~/deploy-phase1-foundation.sh
   ```

2. **Select option 0: Initialize/Update configuration**
   ```
   Phase 01 - Foundation Layer Deployment
   =======================================
   0. Initialize/Update configuration
   c. Validate configuration
   1. Update system packages and set timezone/hostname
   2. Set up LUKS disk encryption
   3. Harden SSH access
   4. Configure firewall (UFW)
   5. Set up fail2ban
   6. Install Docker and Docker Compose
   7. Initialize infrastructure Git repository
   8. Set up automated security updates
   v. Validate all
   q. Quit

   Select option [0,c,1-8,v,q]: 0
   ```

3. **Enter configuration values**
   - Timezone: `Europe/Amsterdam` (or your timezone)
   - Hostname: `homeserver`
   - Server IP: `192.168.1.2`
   - Admin user: `admin` (current user)
   - Admin email: `admin@mydomain.com`
   - Data disk: `/dev/sdb` (verify with `lsblk`)
   - LUKS passphrase: Strong passphrase (20+ characters)
   - Git user name: `Admin User`
   - Git user email: `admin@home.mydomain.com`

4. **Configuration saved**
   ```
   ✓ Configuration saved to /opt/homeserver/configs/foundation.env and secrets.env
   ```

**Sub-task 4.3: Validate configuration**

**Steps**:
1. **Select option c: Validate configuration**
   ```
   Select option [0,c,1-8,v,q]: c
   ```

2. **Review validation results**
   ```
   Configuration Validation
   ========================
   ✓ Timezone is valid
   ✓ Hostname is valid
   ✓ Server IP is valid
   ✓ Admin user exists
   ✓ Admin email format is valid
   ✓ Data disk exists
   ✓ LUKS passphrase is strong
   ✓ Git user name is set
   ✓ Git user email is valid

   All checks passed!
   ```

3. **Fix any validation errors**
   - If validation fails, select option 0 to update configuration
   - Re-run validation (option c) until all checks pass

**Verification Checklist**:
- [ ] Deployment script copied to server
- [ ] Configuration initialized
- [ ] All configuration values entered
- [ ] Configuration saved to /opt/homeserver/configs/foundation.env and secrets.env
- [ ] Validation passes all checks

**Troubleshooting**:
- **Script not found**: Check USB mount point, verify copy command
- **Permission denied**: Run script with sudo
- **Validation fails**: Check values, verify disk exists, check email format
- **Can't save config**: Check /opt/homeserver/ directory exists


## Task 5: Set up LUKS Disk Encryption

**Objective**: Encrypt data partition with LUKS and configure auto-unlock

**Prerequisites**: 
- Configuration initialized
- Data disk identified (e.g., /dev/sdb)

**Sub-task 5.1: Create LUKS encrypted partition**

**Steps**:
1. **Identify data disk**
   ```bash
   lsblk
   # Verify data disk (e.g., /dev/sdb)
   # WARNING: This will erase all data on the disk!
   ```

2. **Format disk with LUKS encryption**
   ```bash
   sudo cryptsetup luksFormat /dev/sdb
   # Enter passphrase when prompted (use strong passphrase from config)
   # Confirm passphrase
   # Type 'YES' to confirm
   ```

3. **Verify LUKS encryption**
   ```bash
   sudo cryptsetup luksDump /dev/sdb
   # Should show LUKS header information
   ```

**Expected Output**:
```
WARNING!
========
This will overwrite data on /dev/sdb irrevocably.

Are you sure? (Type 'yes' in capital letters): YES
Enter passphrase for /dev/sdb: 
Verify passphrase: 
```

**Sub-task 5.2: Open encrypted partition and create filesystem**

**Steps**:
1. **Open LUKS partition**
   ```bash
   sudo cryptsetup luksOpen /dev/sdb data_crypt
   # Enter passphrase
   ```

2. **Create ext4 filesystem**
   ```bash
   sudo mkfs.ext4 /dev/mapper/data_crypt
   ```

3. **Verify filesystem**
   ```bash
   sudo blkid /dev/mapper/data_crypt
   # Should show TYPE="ext4"
   ```

**Sub-task 5.3: Configure auto-unlock**

**Steps**:
1. **Generate key file**
   ```bash
   sudo dd if=/dev/urandom of=/root/.luks-key bs=1024 count=4
   sudo chmod 600 /root/.luks-key
   sudo chown root:root /root/.luks-key
   ```

2. **Add key file to LUKS**
   ```bash
   sudo cryptsetup luksAddKey /dev/sdb /root/.luks-key
   # Enter existing passphrase
   ```

3. **Get UUID of encrypted partition**
   ```bash
   sudo blkid /dev/sdb
   # Note the UUID (e.g., UUID="12345678-1234-1234-1234-123456789abc")
   ```

4. **Configure /etc/crypttab**
   ```bash
   sudo nano /etc/crypttab
   # Add line:
   data_crypt UUID=12345678-1234-1234-1234-123456789abc /root/.luks-key luks
   ```

5. **Configure /etc/fstab**
   ```bash
   sudo nano /etc/fstab
   # Add line:
   /dev/mapper/data_crypt /mnt/data ext4 defaults 0 2
   ```

**Sub-task 5.4: Test auto-unlock**

**Steps**:
1. **Create mount point**
   ```bash
   sudo mkdir -p /mnt/data
   ```

2. **Test mount**
   ```bash
   sudo mount -a
   # Should mount without prompting for passphrase
   ```

3. **Verify mount**
   ```bash
   df -h | grep /mnt/data
   # Should show /mnt/data mounted
   ```

4. **Test reboot**
   ```bash
   sudo reboot
   # Wait 2-3 minutes
   # SSH back in
   df -h | grep /mnt/data
   # Should show /mnt/data mounted automatically
   ```

**Verification Checklist**:
- [ ] Data partition encrypted with LUKS
- [ ] Filesystem created on encrypted partition
- [ ] Key file generated with correct permissions (600, root-only)
- [ ] Key file added to LUKS
- [ ] /etc/crypttab configured
- [ ] /etc/fstab configured
- [ ] /mnt/data mounts automatically
- [ ] Auto-unlock works after reboot
- [ ] Manual unlock with passphrase still works

**Verification Commands**:
```bash
# Check LUKS encryption
sudo cryptsetup luksDump /dev/sdb | grep "Cipher:"
# Should show: Cipher: aes-xts-plain64

# Check key file permissions
ls -la /root/.luks-key
# Should show: -rw------- 1 root root

# Check mount
df -h | grep /mnt/data
# Should show /mnt/data mounted

# Test manual unlock (after reboot)
sudo cryptsetup luksOpen /dev/sdb test_unlock
# Enter passphrase - should work
sudo cryptsetup luksClose test_unlock
```

**Troubleshooting**:
- **LUKS format fails**: Check disk is not mounted, verify disk path
- **Auto-unlock fails**: Check key file permissions, verify /etc/crypttab
- **Mount fails**: Check /etc/fstab, verify filesystem created
- **Passphrase forgotten**: Use backup passphrase from password manager


## Task 6: Update System Packages and Basic Security

**Objective**: Update system packages and configure basic settings

**Prerequisites**: 
- Configuration initialized
- Network connectivity working

**Steps**:
1. **Update package lists**
   ```bash
   sudo apt update
   ```

2. **Upgrade all packages**
   ```bash
   sudo apt upgrade -y
   # Wait 5-10 minutes for updates
   ```

3. **Set timezone**
   ```bash
   sudo timedatectl set-timezone Europe/Amsterdam
   # Or your timezone from config
   ```

4. **Set hostname**
   ```bash
   sudo hostnamectl set-hostname homeserver
   ```

5. **Install essential tools**
   ```bash
   sudo apt install -y git vim curl wget htop net-tools
   ```

6. **Verify updates**
   ```bash
   apt list --upgradable
   # Should show: All packages are up to date
   ```

7. **Verify timezone**
   ```bash
   timedatectl
   # Should show correct timezone
   ```

8. **Verify hostname**
   ```bash
   hostnamectl
   # Should show: Static hostname: homeserver
   ```

**Verification Checklist**:
- [ ] All packages updated
- [ ] Timezone set correctly
- [ ] Hostname set to "homeserver"
- [ ] Essential tools installed

**Troubleshooting**:
- **Update fails**: Check internet connectivity, verify DNS
- **Timezone not found**: List timezones: `timedatectl list-timezones`
- **Hostname not changed**: Reboot server, check /etc/hostname


## Task 7: Harden SSH Access

**Objective**: Configure SSH key-based authentication and disable password auth

**Prerequisites**: 
- SSH access working with password
- Admin laptop ready

**Sub-task 7.1: Generate Ed25519 SSH keys (on admin laptop)**

**Steps**:
1. **Generate SSH key pair** (on admin laptop)
   ```bash
   ssh-keygen -t ed25519 -C "admin@homeserver"
   # Save to: ~/.ssh/id_ed25519_homeserver
   # Enter strong passphrase
   # Confirm passphrase
   ```

2. **Verify key generated**
   ```bash
   ls -la ~/.ssh/id_ed25519_homeserver*
   # Should show private and public key files
   ```

**Sub-task 7.2: Copy public key to server**

**Steps**:
1. **Copy public key** (from admin laptop)
   ```bash
   ssh-copy-id -i ~/.ssh/id_ed25519_homeserver.pub admin@192.168.1.2
   # Enter password
   ```

2. **Test SSH key authentication** (from admin laptop)
   ```bash
   ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2
   # Enter key passphrase
   # Should login without password
   ```

**Sub-task 7.3: Configure SSH server**

**Steps**:
1. **Backup SSH config** (on server)
   ```bash
   sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
   ```

2. **Edit SSH config**
   ```bash
   sudo nano /etc/ssh/sshd_config
   ```

3. **Update settings**
   ```
   # Find and update these lines:
   Port 22
   UseDNS no
   GSSAPIAuthentication no
   PasswordAuthentication no
   PubkeyAuthentication yes
   PermitRootLogin no
   ClientAliveInterval 300
   ClientAliveCountMax 2
   ```

   **Note**: 
   - `Port 22` must be uncommented (prevents SSH connection delays)
   - `UseDNS no` prevents DNS lookup delays on SSH connections
   - `GSSAPIAuthentication no` prevents GSSAPI authentication delays
   - `ClientAliveInterval 300` sets 5-minute keepalive (1 hour idle timeout with CountMax=2)

4. **Test config syntax**
   ```bash
   sudo sshd -t
   # Should show no errors
   ```

5. **Restart SSH service**
   ```bash
   sudo systemctl restart sshd
   ```

**Sub-task 7.4: Verify SSH hardening**

**Steps**:
1. **Keep current SSH session open** (important!)

2. **Test SSH key authentication** (from admin laptop, new terminal)
   ```bash
   ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2
   # Should work with key passphrase
   ```

3. **Test password authentication** (should fail)
   ```bash
   ssh admin@192.168.1.2
   # Should reject: Permission denied (publickey)
   ```

4. **Verify SSH config**
   ```bash
   grep PasswordAuthentication /etc/ssh/sshd_config
   # Should show: PasswordAuthentication no
   ```

**Verification Checklist**:

- [ ] SSH key generated with Ed25519 algorithm
- [ ] SSH key has passphrase protection
- [ ] Public key copied to server
- [ ] SSH key authentication works
- [ ] Password authentication disabled
- [ ] Root login disabled
- [ ] SSH service restarted
- [ ] Password authentication fails (as expected)

**Troubleshooting**:
- **Locked out**: Use original SSH session, revert config, restart sshd
- **Key not working**: Check key permissions (600), verify authorized_keys
- **Permission denied**: Check /etc/ssh/sshd_config, verify PubkeyAuthentication yes
- **Can't connect**: Verify firewall allows SSH, check SSH service running


## Task 8: Configure Firewall (UFW)

**Objective**: Configure UFW firewall to restrict unauthorized access

**Prerequisites**: 
- SSH key authentication working
- Network connectivity working

**Steps**:
1. **Install UFW** (if not already installed)
   ```bash
   sudo apt install -y ufw
   ```

2. **Set default policies**
   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   ```

3. **Allow SSH from LAN only**
   ```bash
   sudo ufw allow from 192.168.1.0/24 to any port 22
   ```

4. **Allow HTTP/HTTPS from LAN only**
   ```bash
   sudo ufw allow from 192.168.1.0/24 to any port 80
   sudo ufw allow from 192.168.1.0/24 to any port 443
   ```

5. **Allow Samba from LAN only**
   ```bash
   sudo ufw allow from 192.168.1.0/24 to any port 139
   sudo ufw allow from 192.168.1.0/24 to any port 445
   ```

6. **Enable UFW**
   ```bash
   sudo ufw enable
   # Type 'y' to confirm
   ```

7. **Verify firewall status**
   ```bash
   sudo ufw status verbose
   ```

**Expected Output**:
```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22                         ALLOW IN    192.168.1.0/24
80                         ALLOW IN    192.168.1.0/24
443                        ALLOW IN    192.168.1.0/24
139                        ALLOW IN    192.168.1.0/24
445                        ALLOW IN    192.168.1.0/24
```

8. **Test SSH from LAN** (from admin laptop)
   ```bash
   ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2
   # Should work
   ```

**Verification Checklist**:
- [ ] UFW installed
- [ ] Default policies set (deny incoming, allow outgoing)
- [ ] SSH allowed from LAN only
- [ ] HTTP/HTTPS allowed from LAN only
- [ ] Samba allowed from LAN only
- [ ] UFW enabled and active
- [ ] SSH from LAN works

**Verification Commands**:
```bash
# Check UFW status
sudo ufw status verbose
# Should show: Status: active

# Check UFW service
sudo systemctl status ufw
# Should show: active (running)

# Test SSH from LAN
ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2
# Should work
```

**Troubleshooting**:
- **Locked out**: Use console access, disable UFW: `sudo ufw disable`
- **SSH blocked**: Verify rule: `sudo ufw status | grep 22`
- **Can't enable UFW**: Check for conflicting firewall (iptables)
- **Rules not working**: Check rule order, verify IP ranges


## Task 9: Set up fail2ban

**Objective**: Configure fail2ban to prevent brute-force SSH attacks

**Prerequisites**: 
- SSH hardening complete
- UFW firewall active

**Steps**:
1. **Install fail2ban**
   ```bash
   sudo apt install -y fail2ban
   ```

2. **Create local configuration**
   ```bash
   sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
   ```

3. **Configure SSH jail**
   ```bash
   sudo nano /etc/fail2ban/jail.local
   ```

4. **Update SSH jail settings**
   ```
   [sshd]
   enabled = true
   port = 22
   filter = sshd
   logpath = /var/log/auth.log
   maxretry = 3
   findtime = 600
   bantime = 3600
   ```

5. **Start and enable fail2ban**
   ```bash
   sudo systemctl start fail2ban
   sudo systemctl enable fail2ban
   ```

6. **Verify fail2ban status**
   ```bash
   sudo systemctl status fail2ban
   # Should show: active (running)
   ```

7. **Check SSH jail status**
   ```bash
   sudo fail2ban-client status sshd
   ```

**Expected Output**:
```
Status for the jail: sshd
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     0
|  `- File list:        /var/log/auth.log
`- Actions
   |- Currently banned: 0
   |- Total banned:     0
   `- Banned IP list:
```

**Verification Checklist**:
- [ ] fail2ban installed
- [ ] SSH jail configured (3 attempts, 10 min window, 1 hour ban)
- [ ] fail2ban service active and running
- [ ] SSH jail active and monitoring

**Verification Commands**:
```bash
# Check fail2ban service
sudo systemctl status fail2ban
# Should show: active (running)

# Check fail2ban status
sudo fail2ban-client status
# Should show: fail2ban running

# Check SSH jail
sudo fail2ban-client status sshd
# Should show: SSH jail active
```

**Troubleshooting**:
- **Service won't start**: Check config syntax, verify log file exists
- **SSH jail not active**: Check jail.local, verify sshd enabled
- **Can't ban IPs**: Check UFW integration, verify iptables
- **Locked out**: Use console access, unban IP: `sudo fail2ban-client set sshd unbanip <IP>`


## Task 10: Install Docker and Docker Compose

**Objective**: Install Docker Engine and Docker Compose from official repository

**Prerequisites**: 
- System packages updated
- Network connectivity working

**Sub-task 10.1: Install Docker prerequisites**

**Steps**:
```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
```

**Sub-task 10.2: Add Docker repository**

**Steps**:
1. **Add Docker's official GPG key**
   ```bash
   sudo mkdir -p /etc/apt/keyrings
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
   ```

2. **Set up Docker repository**
   ```bash
   echo \
     "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
     $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
   ```

3. **Update package index**
   ```bash
   sudo apt update
   ```

**Sub-task 10.3: Install Docker Engine and Docker Compose**

**Steps**:
```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

**Sub-task 10.4: Configure Docker daemon**

**Steps**:
1. **Create daemon.json**
   ```bash
   sudo nano /etc/docker/daemon.json
   ```

2. **Add configuration**
   ```json
   {
     "log-driver": "json-file",
     "log-opts": {
       "max-size": "10m",
       "max-file": "3"
     },
     "storage-driver": "overlay2"
   }
   ```

3. **Restart Docker**
   ```bash
   sudo systemctl restart docker
   ```

**Sub-task 10.5: Add admin user to docker group**

**Steps**:
1. **Add user to docker group**
   ```bash
   sudo usermod -aG docker admin
   # Replace 'admin' with your username
   ```

2. **Log out and back in**
   ```bash
   exit
   # SSH back in
   ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2
   ```

**Sub-task 10.6: Test Docker installation**

**Steps**:
1. **Test Docker version**
   ```bash
   docker --version
   # Should show: Docker version 24.x.x
   ```

2. **Test Docker Compose version**
   ```bash
   docker compose version
   # Should show: Docker Compose version v2.x.x
   ```

3. **Run hello-world container**
   ```bash
   docker run hello-world
   # Should download and run successfully
   ```

**Expected Output**:
```
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

**Verification Checklist**:
- [ ] Docker prerequisites installed
- [ ] Docker repository added
- [ ] Docker Engine installed
- [ ] Docker Compose plugin installed
- [ ] Docker daemon configured (log rotation, overlay2)
- [ ] Admin user added to docker group
- [ ] Docker commands work without sudo
- [ ] hello-world container runs successfully

**Verification Commands**:
```bash
# Check Docker version
docker --version
# Should show: Docker version 24.x.x

# Check Docker Compose version
docker compose version
# Should show: Docker Compose version v2.x.x

# Check Docker service
sudo systemctl status docker
# Should show: active (running)

# Test Docker without sudo
docker run hello-world
# Should work without sudo
```

**Troubleshooting**:
- **Docker daemon won't start**: Check logs: `sudo journalctl -u docker`
- **Permission denied**: Log out and back in after adding to docker group
- **Docker Compose not found**: Verify plugin installation, check PATH
- **hello-world fails**: Check internet connectivity, verify Docker daemon running


## Task 11: Initialize Infrastructure Git Repository

**Objective**: Initialize Git repository for infrastructure as code

**Prerequisites**: 
- Git installed
- /opt/homeserver/ directory accessible

**Sub-task 11.1: Create infrastructure directory**

**Steps**:
```bash
sudo mkdir -p /opt/homeserver
sudo chown admin:admin /opt/homeserver
# Replace 'admin' with your username
```

**Sub-task 11.2: Initialize Git repository**

**Steps**:
1. **Navigate to directory**
   ```bash
   cd /opt/homeserver
   ```

2. **Initialize Git**
   ```bash
   git init
   ```

3. **Configure Git user**
   ```bash
   git config user.name "Admin User"
   git config user.email "admin@home.mydomain.com"
   ```

**Sub-task 11.3: Create directory structure**

**Steps**:
```bash
cd /opt/homeserver
mkdir -p docs
mkdir -p scripts/{backup,deploy,maintenance,monitoring,operations}
mkdir -p configs/{docker-compose,caddy,samba,wiki,foundation}
mkdir -p assets
mkdir -p templates
```

**Sub-task 11.4: Create initial files**

**Steps**:
1. **Create README.md**
   ```bash
   cat > README.md << 'EOF'
   # Home Media Server Infrastructure

   Infrastructure as Code for home media server platform.

   ## Structure

   - `docs/` - Documentation
   - `scripts/` - Automation scripts
   - `configs/` - Service configurations
   - `assets/` - Diagrams and screenshots
   - `templates/` - Reusable templates

   ## Phases

   - Phase 01: Foundation Layer
   - Phase 02: Infrastructure Services
   - Phase 03: Core Services
   - Phase 04: Applications

   ## Version

   Current version: 0.1
   EOF
   ```

2. **Create .gitignore**
   ```bash
   cat > .gitignore << 'EOF'
   # Sensitive files
   *.key
   *.pem
   *.env
   .env
   *.secret

   # Backup files
   *.backup
   *.bak
   *~

   # OS files
   .DS_Store
   Thumbs.db

   # Editor files
   .vscode/
   .idea/
   *.swp
   *.swo
   EOF
   ```

**Sub-task 11.5: Make initial commit**

**Steps**:
1. **Add all files**
   ```bash
   git add .
   ```

2. **Make initial commit**
   ```bash
   git commit -m "Initial infrastructure repository setup"
   ```

3. **Verify commit**
   ```bash
   git log
   # Should show initial commit
   ```

4. **Verify status**
   ```bash
   git status
   # Should show: nothing to commit, working tree clean
   ```

**Verification Checklist**:
- [ ] /opt/homeserver/ directory created
- [ ] Git repository initialized
- [ ] Git user configured
- [ ] Directory structure created (docs/, scripts/, configs/, assets/, templates/)
- [ ] Script subdirectories created
- [ ] Config subdirectories created
- [ ] README.md created
- [ ] .gitignore created
- [ ] Initial commit made
- [ ] Working tree clean

**Verification Commands**:
```bash
# Check Git repository
git -C /opt/homeserver/ status
# Should show: On branch main, nothing to commit

# Check directory structure
ls -la /opt/homeserver/
# Should show: docs/, scripts/, configs/, assets/, templates/

# Check Git log
git -C /opt/homeserver/ log
# Should show: Initial commit

# Check .gitignore
cat /opt/homeserver/.gitignore
# Should show: Sensitive files excluded
```

**Troubleshooting**:
- **Permission denied**: Check ownership of /opt/homeserver/
- **Git not initialized**: Run `git init` in /opt/homeserver/
- **Can't commit**: Configure Git user name and email
- **Files not tracked**: Check .gitignore, verify `git add .`


## Task 12: Set up Automated Security Updates

**Objective**: Configure unattended-upgrades for automatic security patching

**Prerequisites**: 
- System packages updated
- Network connectivity working

**Sub-task 12.1: Install unattended-upgrades**

**Steps**:
```bash
sudo apt install -y unattended-upgrades
```

**Sub-task 12.2: Configure automatic updates**

**Steps**:
1. **Edit unattended-upgrades config**
   ```bash
   sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
   ```

2. **Update configuration**
   ```
   # Enable security updates only
   Unattended-Upgrade::Allowed-Origins {
       "${distro_id}:${distro_codename}-security";
   };

   # Enable automatic reboot at 3:00 AM if required
   Unattended-Upgrade::Automatic-Reboot "true";
   Unattended-Upgrade::Automatic-Reboot-Time "03:00";

   # Remove unused dependencies
   Unattended-Upgrade::Remove-Unused-Dependencies "true";
   ```

**Sub-task 12.3: Enable automatic updates**

**Steps**:
1. **Edit auto-upgrades config**
   ```bash
   sudo nano /etc/apt/apt.conf.d/20auto-upgrades
   ```

2. **Update configuration**
   ```
   APT::Periodic::Update-Package-Lists "1";
   APT::Periodic::Unattended-Upgrade "1";
   APT::Periodic::AutocleanInterval "7";
   ```

**Sub-task 12.4: Test and verify configuration**

**Steps**:
1. **Test dry-run**
   ```bash
   sudo unattended-upgrades --dry-run --debug
   # Should show what would be upgraded
   ```

2. **Verify service enabled**
   ```bash
   sudo systemctl status unattended-upgrades
   # Should show: active (running)
   ```

3. **Check logs**
   ```bash
   sudo cat /var/log/unattended-upgrades/unattended-upgrades.log
   # Should show recent activity
   ```

**Verification Checklist**:
- [ ] unattended-upgrades installed
- [ ] Security updates enabled
- [ ] Automatic reboot at 3:00 AM configured
- [ ] Daily update checks enabled
- [ ] Weekly autoclean enabled
- [ ] Service active and running
- [ ] Dry-run test successful

**Verification Commands**:
```bash
# Check service status
sudo systemctl status unattended-upgrades
# Should show: active (running)

# Check configuration
cat /etc/apt/apt.conf.d/20auto-upgrades
# Should show: Update-Package-Lists "1", Unattended-Upgrade "1"

# Check logs
sudo tail -20 /var/log/unattended-upgrades/unattended-upgrades.log
# Should show recent activity
```

**Troubleshooting**:
- **Service won't start**: Check config syntax, verify package installed
- **Updates not running**: Check /etc/apt/apt.conf.d/20auto-upgrades
- **Reboot not working**: Verify Automatic-Reboot "true" in 50unattended-upgrades
- **No logs**: Wait 24 hours for first run, check systemd timer


## Task 13: Validate Phase 1 Completion

**Objective**: Verify all foundation components are working correctly

**Prerequisites**: 
- All previous tasks complete

**Sub-task 13.1: Run automated validation script**

**Steps**:
1. **Run deployment script**
   ```bash
   sudo ~/deploy-phase1-foundation.sh
   ```

2. **Select option v: Validate all**
   ```
   Select option [0,c,1-8,v,q]: v
   ```

3. **Review validation results**
   ```
   Phase 01 Foundation Validation
   ===============================
   1. SSH Hardening.................... ✓ PASS
   2. UFW Firewall..................... ✓ PASS
   3. fail2ban......................... ✓ PASS
   4. Docker........................... ✓ PASS
   5. Git Repository................... ✓ PASS
   6. Unattended-upgrades.............. ✓ PASS
   7. LUKS Encryption.................. ✓ PASS
   8. Docker Group..................... ✓ PASS
   9. Essential Tools.................. ✓ PASS

   All checks passed! ✓
   ```

**Sub-task 13.2: Manual validation checklist**

**Steps**:
1. **Test SSH key authentication**
   ```bash
   # From admin laptop
   ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2
   # Should work with key passphrase
   ```

2. **Test firewall blocks unauthorized access**
   ```bash
   # From admin laptop
   sudo ufw status verbose
   # Should show: Status: active
   ```

3. **Test fail2ban is monitoring**
   ```bash
   sudo fail2ban-client status sshd
   # Should show: SSH jail active
   ```

4. **Test Docker is functional**
   ```bash
   docker run hello-world
   # Should work without sudo
   ```

5. **Test Git repository initialized**
   ```bash
   git -C /opt/homeserver/ status
   # Should show: On branch main
   ```

6. **Test security updates configured**
   ```bash
   sudo systemctl status unattended-upgrades
   # Should show: active (running)
   ```

7. **Test data partition encrypted and auto-unlocks**
   ```bash
   df -h | grep /mnt/data
   # Should show /mnt/data mounted
   
   sudo cryptsetup luksDump /dev/sdb | grep "Cipher:"
   # Should show: Cipher: aes-xts-plain64
   ```

8. **Test server has stable IP**
   ```bash
   ip addr show | grep 192.168.1.2
   # Should show: inet 192.168.1.2
   ```

**Sub-task 13.3: Update network documentation**

**Steps**:
1. **Document server MAC address**
   ```bash
   ip link show | grep ether
   # Note MAC address
   ```

2. **Update docs/02-network.md** (if exists)
   ```bash
   # Add server MAC address and IP to network documentation
   ```

3. **Commit changes**
   ```bash
   cd /opt/homeserver
   git add docs/02-network.md
   git commit -m "Phase 01: Document server MAC address and IP"
   ```

**Sub-task 13.4: Create foundation snapshot**

**Steps**:
1. **Document current state**
   ```bash
   cd /opt/homeserver
   cat > docs/phase1-completion.md << 'EOF'
   # Phase 01 Foundation Completion

   **Date**: $(date +%Y-%m-%d)
   **Version**: 0.1

   ## Completed Tasks

   - Ubuntu Server LTS 24.04 installed
   - Network configured (192.168.1.2)
   - LUKS encryption configured
   - SSH hardened (key-based only)
   - UFW firewall active
   - fail2ban monitoring SSH
   - Docker and Docker Compose installed
   - Git repository initialized
   - Automated security updates enabled

   ## Validation Results

   All 9 validation checks passed.

   ## Next Steps

   Proceed to Phase 02: Infrastructure Services Layer
   EOF
   ```

2. **Commit snapshot**
   ```bash
   git add docs/phase1-completion.md
   git commit -m "Phase 01: Foundation layer complete"
   git tag phase1-complete
   ```

**Verification Checklist**:
- [ ] All 9 automated validation checks pass
- [ ] SSH key authentication works
- [ ] Firewall blocks unauthorized access
- [ ] fail2ban is monitoring
- [ ] Docker is functional
- [ ] Git repository initialized
- [ ] Security updates configured
- [ ] Data partition encrypted and auto-unlocks
- [ ] Server has stable IP (192.168.1.2)
- [ ] Network documentation updated
- [ ] Foundation snapshot created

**Final Verification**:
```bash
# Run full validation
sudo ~/deploy-phase1-foundation.sh
# Select option 'v'
# All checks should pass

# Verify system ready for Phase 02
git -C /opt/homeserver/ log --oneline
# Should show: Phase 01 commits

git -C /opt/homeserver/ tag
# Should show: phase1-complete
```

**Troubleshooting**:
- **Validation fails**: Review failed check, fix issue, re-run validation
- **SSH not working**: Check key permissions, verify SSH config
- **Docker not working**: Check service status, verify user in docker group
- **Git not initialized**: Check /opt/homeserver/, verify initial commit

## Next Steps

After Phase 01 completion:
1. Verify all validation checks pass
2. Create snapshot of current state
3. Proceed to Phase 02: Infrastructure Services Layer
4. See `.kiro/specs/02-infrastructure/` for Phase 02 spec

## Appendix A: Common Issues

### Issue: Locked out of SSH

**Symptoms**: Can't SSH into server after hardening

**Solution**:
1. Use console access (monitor + keyboard)
2. Login with username/password
3. Check SSH config: `sudo nano /etc/ssh/sshd_config`
4. Temporarily enable password auth: `PasswordAuthentication yes`
5. Restart SSH: `sudo systemctl restart sshd`
6. SSH in and fix key issue
7. Re-disable password auth

### Issue: LUKS auto-unlock fails

**Symptoms**: /mnt/data not mounted after reboot

**Solution**:
1. Check key file exists: `ls -la /root/.luks-key`
2. Check key file permissions: Should be 600, root-only
3. Check /etc/crypttab: Verify UUID and key file path
4. Check /etc/fstab: Verify /dev/mapper/data_crypt entry
5. Test manual unlock: `sudo cryptsetup luksOpen /dev/sdb test`
6. Fix issues and reboot

### Issue: Docker permission denied

**Symptoms**: Docker commands require sudo

**Solution**:
1. Check user in docker group: `groups`
2. Add user to docker group: `sudo usermod -aG docker $USER`
3. Log out and back in
4. Test: `docker run hello-world`

### Issue: Firewall blocks legitimate traffic

**Symptoms**: Can't access services from LAN

**Solution**:
1. Check UFW rules: `sudo ufw status verbose`
2. Verify IP range: Should be 192.168.1.0/24
3. Add specific rule if needed: `sudo ufw allow from 192.168.1.0/24 to any port <PORT>`
4. Reload UFW: `sudo ufw reload`

## Appendix B: Rollback Procedures

### Rollback SSH hardening

```bash
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication yes
sudo systemctl restart sshd
```

### Rollback firewall

```bash
sudo ufw disable
```

### Rollback fail2ban

```bash
sudo systemctl stop fail2ban
sudo systemctl disable fail2ban
```

### Rollback Docker

```bash
sudo apt remove -y docker-ce docker-ce-cli containerd.io
sudo rm -rf /var/lib/docker
```

## Appendix C: Reference Commands

### System Information

```bash
# OS version
lsb_release -a

# Hostname
hostnamectl

# Timezone
timedatectl

# Network interfaces
ip addr show

# Disk usage
df -h

# Memory usage
free -h

# CPU info
lscpu
```

### Service Status

```bash
# SSH
sudo systemctl status sshd

# UFW
sudo systemctl status ufw

# fail2ban
sudo systemctl status fail2ban

# Docker
sudo systemctl status docker

# Unattended-upgrades
sudo systemctl status unattended-upgrades
```

### Logs

```bash
# System logs
sudo journalctl -xe

# SSH logs
sudo tail -50 /var/log/auth.log

# fail2ban logs
sudo tail -50 /var/log/fail2ban.log

# Docker logs
sudo journalctl -u docker

# Unattended-upgrades logs
sudo tail -50 /var/log/unattended-upgrades/unattended-upgrades.log
```

---

**End of Phase 01 Foundation Layer Deployment Manual**
