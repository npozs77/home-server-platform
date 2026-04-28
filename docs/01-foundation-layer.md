# Foundation Services

**See also**:
- `.kiro/specs/01-foundation/design.md` - High-level architecture and WHY decisions
- `docs/deployment_manuals/phase1-foundation.md` - Step-by-step deployment procedures (HOW)
- `configs/CONFIG_GUIDE.md` - Configuration reference

## Overview

This document describes the AS-IS foundation layer configuration after Phase 01 deployment. It documents the actual deployed state of security, Docker, Git repository, and automated updates.

## System Configuration

### Operating System

**Distribution**: Ubuntu Server LTS 24.04
**Hostname**: homeserver
**Timezone**: [Configured during deployment]
**IP Address**: 192.168.1.2 (DHCP reservation)
**Network Interface**: [Ethernet or WiFi, configured during bootstrap]

### Essential Tools

**Installed packages**:
- git - Version control
- vim - Text editor
- curl - HTTP client
- wget - File downloader
- htop - Process monitor
- net-tools - Network utilities
- fzf - Fuzzy finder (Ctrl+R history search)
- ripgrep (rg) - Fast recursive grep
- bat (batcat) - cat with syntax highlighting
- fd-find (fd) - Fast file finder
- jq - JSON processor

**Ubuntu symlinks** (Ubuntu renames some packages):
- `/usr/local/bin/bat` → `/usr/bin/batcat`
- `/usr/local/bin/fd` → `/usr/bin/fdfind`

## Shell Environment

### Global Zsh Configuration

**Default shell**: Zsh (for all SSH users)
**Framework**: Oh-My-Zsh (system-wide at `/usr/share/oh-my-zsh`)
**Theme**: Powerlevel10k (system-wide at `/usr/share/powerlevel10k`)

**Global config location**: `/etc/zsh/`
- `/etc/zsh/zshenv` — sets `ZDOTDIR=/etc/zsh`
- `/etc/zsh/.zshrc` — global shell config (plugins, theme, aliases)
- `/etc/zsh/p10k.zsh` — Powerlevel10k theme config

**Plugins**:
- zsh-autosuggestions (gray inline suggestions)
- zsh-syntax-highlighting (command coloring)
- fzf (Ctrl+R fuzzy history search)
- git (aliases and completions)

**Key behavior**:
- No per-user `.zshrc` required — global config applies to all users
- New users default to zsh via `/etc/default/useradd`
- Powerlevel10k prompt with git status, exit codes, execution time

**Verification**:
```bash
# Check default shell
echo $SHELL
# Should show: /usr/bin/zsh

# Check ZDOTDIR
echo $ZDOTDIR
# Should show: /etc/zsh

# Check Oh-My-Zsh
ls /usr/share/oh-my-zsh/
# Should exist

# Check Powerlevel10k
ls /usr/share/powerlevel10k/
# Should exist
```

**Reconfigure Powerlevel10k prompt**:
```bash
p10k configure
# Then copy to global:
sudo cp ~/.p10k.zsh /etc/zsh/p10k.zsh
```

## Security Configuration

### SSH Hardening

**SSH Server Configuration** (`/etc/ssh/sshd_config`):
```
Port 22
UseDNS no
GSSAPIAuthentication no
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
ClientAliveInterval 300
ClientAliveCountMax 2
```

**Configuration Notes**:
- `Port 22` uncommented (prevents SSH connection delays)
- `UseDNS no` prevents DNS lookup delays on SSH connections
- `GSSAPIAuthentication no` prevents GSSAPI authentication delays
- `ClientAliveInterval 300` sets 5-minute keepalive (1 hour idle timeout with CountMax=2)

**SSH Keys**:
- **Type**: Ed25519
- **Location** (admin laptop): `~/.ssh/id_ed25519_homeserver`
- **Authorized keys** (server): `~/.ssh/authorized_keys`
- **Passphrase**: Required (stored in password manager)

**Access**:
- Admin user: SSH key authentication only
- Root user: Disabled (no direct root login)
- Password authentication: Disabled globally

### Firewall (UFW)

**Default Policy**:
- Incoming: DENY
- Outgoing: ALLOW
- Routed: DENY

**Active Rules**:
```
22/tcp (SSH)         - ALLOW from 192.168.1.0/24
80/tcp (HTTP)        - ALLOW from 192.168.1.0/24
443/tcp (HTTPS)      - ALLOW from 192.168.1.0/24
139,445/tcp (Samba)  - ALLOW from 192.168.1.0/24
```

**Status**: Active and enabled on boot

**Verification**:
```bash
sudo ufw status verbose
```

### Intrusion Prevention (fail2ban)

**Service**: fail2ban
**Status**: Active and enabled on boot

**SSH Jail Configuration**:
- **Max attempts**: 3
- **Find time**: 10 minutes
- **Ban time**: 1 hour
- **Action**: iptables ban + email notification (optional)

**Monitored Services**:
- SSH (sshd jail)

**Verification**:
```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

### Disk Encryption (LUKS)

**Data Partition**:
- **Device**: /dev/nvme0n1p3
- **LUKS mapper**: `data_crypt`
- **Type**: LUKS (Linux Unified Key Setup)
- **Filesystem**: ext4
- **Mount Point**: /mnt/data
- **Key slots**: Slot 0 = passphrase, Slot 1 = `/root/.luks-key`

**Backup Partition (DAS)**:
- **Device**: /dev/sdb2 (~900GB)
- **LUKS mapper**: `backup_crypt`
- **Type**: LUKS
- **Filesystem**: ext4
- **Mount Point**: /mnt/backup
- **Key slots**: Slot 0 = passphrase (same as data partition), Slot 1 = `/root/.luks-key`
- **crypttab**: `backup_crypt UUID=<uuid> /root/.luks-key luks,nofail,noauto`
- **fstab**: `/dev/mapper/backup_crypt /mnt/backup ext4 defaults,nofail 0 2`
- **Boot behavior**: Not auto-opened (`noauto`). Server boots cleanly without DAS.

**Key Slot Inventory**:

| Partition | Device | Mapper | Slot 0 | Slot 1 |
|-----------|--------|--------|--------|--------|
| Data | /dev/nvme0n1p3 | data_crypt | Passphrase | /root/.luks-key |
| Backup | /dev/sdb2 | backup_crypt | Passphrase | /root/.luks-key |

**Auto-Unlock Configuration** (data partition only):
- **Key File**: /root/.luks-key
- **Permissions**: 600 (root-only)
- **Crypttab**: `/etc/crypttab` (auto-unlock on boot)
- **Fstab**: `/etc/fstab` (auto-mount after unlock)

**LUKS Header Backups**:
- `/root/luks-header-backup-nvme0n1p3.img` (data partition, 600 permissions)
- `/root/luks-header-backup-sdb2.img` (backup partition, 600 permissions)
- Also copied to `/mnt/backup/configs/system/` by `backup-configs.sh`

**Manual Unlock** (data partition — emergency):
```bash
sudo cryptsetup luksOpen /dev/nvme0n1p3 data_crypt
sudo mount /dev/mapper/data_crypt /mnt/data
```

**Manual Unlock** (backup partition):
```bash
sudo cryptsetup luksOpen /dev/sdb2 backup_crypt
sudo mount /dev/mapper/backup_crypt /mnt/backup
```

**Passphrase Storage**:
- Password manager (primary)
- Printed copy (secure location, backup)

**Recovery**: See `docs/12-runbooks.md` → LUKS Disk Encryption Recovery for full recovery procedures (key file lost, passphrase forgotten, header corrupted, both keys lost).

## Docker Configuration

### Docker Engine

**Version**: Docker Engine (latest from official repository)
**Installation Method**: Official Docker repository (not Ubuntu package)

**Installed Components**:
- docker-ce (Docker Engine)
- docker-ce-cli (Docker CLI)
- containerd.io (Container runtime)
- docker-buildx-plugin (Build plugin)
- docker-compose-plugin (Docker Compose V2)

### Docker Daemon Configuration

**Configuration File**: `/etc/docker/daemon.json`

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

**Log Rotation**:
- Max size per log file: 10 MB
- Max log files: 3
- Total max logs per container: 30 MB

**Storage Driver**: overlay2 (recommended for Ubuntu)

### Docker Group

**Group**: docker
**Members**: [ADMIN_USER from config]

**Purpose**: Allows admin user to run Docker commands without sudo

**Verification**:
```bash
groups $USER
docker run hello-world
```

### Docker Compose

**Version**: Docker Compose V2 (plugin)
**Command**: `docker compose` (not `docker-compose`)

**Verification**:
```bash
docker compose version
```

## Git Repository

### Infrastructure Repository

**Location**: /opt/homeserver/
**Owner**: [ADMIN_USER from config]
**Permissions**: 755 (owner: rwx, group: r-x, others: r-x)

**Git Configuration**:
- **User Name**: [GIT_USER_NAME from config]
- **User Email**: [GIT_USER_EMAIL from config]

**Directory Structure**:
```
/opt/homeserver/
├── .git/                      # Git repository
├── .gitignore                 # Ignore sensitive files
├── README.md                  # Project overview
├── docs/                      # Documentation
├── scripts/                   # Automation scripts
│   ├── backup/
│   ├── deploy/
│   ├── maintenance/
│   ├── monitoring/
│   └── operations/
├── configs/                   # Configuration files
│   ├── docker-compose/
│   ├── caddy/
│   ├── samba/
│   ├── wiki/
│   └── foundation/
├── assets/                    # Static assets
└── templates/                 # Configuration templates
```

**Initial Commit**: "Initial infrastructure repository setup"

**Verification**:
```bash
git -C /opt/homeserver/ status
git -C /opt/homeserver/ log
```

## Automated Updates

### Unattended Upgrades

**Service**: unattended-upgrades
**Status**: Active and enabled on boot

**Configuration** (`/etc/apt/apt.conf.d/50unattended-upgrades`):
- **Security updates**: Enabled (Ubuntu security repository)
- **Automatic reboot**: Enabled at 3:00 AM if required
- **Email notifications**: Optional (configure if needed)

**Update Schedule** (`/etc/apt/apt.conf.d/20auto-upgrades`):
- **Update package lists**: Daily
- **Unattended upgrades**: Daily
- **Autoclean**: Weekly

**Logs**: `/var/log/unattended-upgrades/`

**Verification**:
```bash
sudo systemctl status unattended-upgrades
sudo unattended-upgrades --dry-run --debug
```

## Network Configuration

### Network Interface

**Interface**: [NETWORK_INTERFACE from config, e.g., eth0 or wlan0]
**Configuration Method**: DHCP with reservation
**IP Address**: 192.168.1.2 (reserved by router)
**Gateway**: 192.168.1.1 (router)
**DNS**: 192.168.1.1 (router, will change to 192.168.1.2 in Phase 02)

**MAC Address**: 4c:23:38:b6:fd:87 (WiFi interface)

### IP Allocation Plan

**Network**: 192.168.1.0/24 (255.255.255.0)

**Reserved Ranges**:
- 192.168.1.1: Router (Zyxel EX5601-T1)
- 192.168.1.2: Home server (DHCP reservation)
- 192.168.1.3-50: Reserved for future servers/critical devices
- 192.168.1.100-200: DHCP pool for dynamic devices (laptops, phones, tablets)
- 192.168.1.201-254: Available for manual assignment

**Rationale**:
- Router as DHCP server (not home server) ensures network resilience if server fails
- DHCP reservation by MAC address provides stable IP without static configuration
- Reserved range (3-50) allows future expansion without reconfiguring DHCP pool
- Large DHCP pool (100-200) accommodates family devices and guests

**Netplan Configuration** (if using Netplan):
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    [interface]:
      dhcp4: true
```

**WiFi Configuration** (if using WiFi):
```yaml
network:
  version: 2
  renderer: networkd
  wifis:
    [interface]:
      dhcp4: true
      access-points:
        "[SSID]":
          password: "[password]"
```

### DHCP Reservation

**Router**: Internet router (192.168.1.1)
**Reservation**:
- MAC Address: 4c:23:38:b6:fd:87
- IP Address: 192.168.1.2
- Hostname: homeserver

**Configuration Location**: Router admin panel → DHCP settings → Static/Reserved DHCP

## Validation Checks

### Automated Validation

**Script**: `deploy-phase1-foundation.sh` (option v)

**10 Validation Checks**:
1. **SSH Hardening**: Password auth disabled, key auth enabled
2. **UFW Firewall**: Active with LAN-only rules
3. **fail2ban**: Running and monitoring SSH
4. **Docker**: Installed and functional (hello-world test)
5. **Git Repository**: Initialized with proper structure
6. **Unattended-upgrades**: Enabled and configured
7. **LUKS Encryption**: Data partition encrypted and auto-unlocks
8. **Docker Group**: Admin user in docker group
9. **Essential Tools**: git, vim, curl, wget, htop, fzf, rg, bat, fd, jq installed
10. **Shell Environment**: Zsh default, Oh-My-Zsh + Powerlevel10k global config

**Run Validation**:
```bash
cd ~/
./deploy-phase1-foundation.sh
# Select option: v (Validate all)
```

### Manual Validation

**SSH Key Authentication**:
```bash
# From admin laptop
ssh [ADMIN_USER]@192.168.1.2
# Should connect without password prompt
```

**Firewall Status**:
```bash
sudo ufw status verbose
# Should show: Status: active
```

**fail2ban Status**:
```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
# Should show: SSH jail active
```

**Docker Functionality**:
```bash
docker run hello-world
# Should run without sudo
```

**Git Repository**:
```bash
git -C /opt/homeserver/ status
# Should show: On branch main, nothing to commit, working tree clean
```

**LUKS Encryption**:
```bash
lsblk -f
# Should show: crypto_LUKS for data disk
df -h | grep /mnt/data
# Should show: /mnt/data mounted
```

**Automated Updates**:
```bash
sudo systemctl status unattended-upgrades
# Should show: active (running)
```

## Service Status

### Active Services

**System Services**:
- sshd (SSH server)
- ufw (Firewall)
- fail2ban (Intrusion prevention)
- docker (Docker Engine)
- containerd (Container runtime)
- unattended-upgrades (Automated updates)

**Verification**:
```bash
sudo systemctl status sshd
sudo systemctl status ufw
sudo systemctl status fail2ban
sudo systemctl status docker
sudo systemctl status unattended-upgrades
```

### Service Dependencies

**Docker depends on**:
- containerd.io (container runtime)
- Network connectivity

**fail2ban depends on**:
- iptables (firewall rules)
- sshd (SSH server logs)

**unattended-upgrades depends on**:
- apt (package manager)
- Network connectivity

## Configuration Files

### Key Configuration Files

**SSH**:
- `/etc/ssh/sshd_config` - SSH server configuration
- `~/.ssh/authorized_keys` - Authorized SSH keys

**Firewall**:
- `/etc/ufw/ufw.conf` - UFW configuration
- `/etc/ufw/user.rules` - User-defined firewall rules

**fail2ban**:
- `/etc/fail2ban/jail.local` - Jail configuration
- `/var/log/fail2ban.log` - fail2ban logs

**Docker**:
- `/etc/docker/daemon.json` - Docker daemon configuration
- `/var/lib/docker/` - Docker data directory

**LUKS**:
- `/etc/crypttab` - Encrypted partition auto-unlock
- `/etc/fstab` - Filesystem auto-mount
- `/root/.luks-key` - LUKS key file (600 permissions)

**Automated Updates**:
- `/etc/apt/apt.conf.d/50unattended-upgrades` - Unattended upgrades configuration
- `/etc/apt/apt.conf.d/20auto-upgrades` - Update schedule

**Git**:
- `/opt/homeserver/.git/config` - Git repository configuration

## Troubleshooting

### SSH Connection Issues

**Symptoms**: Cannot connect via SSH

**Solutions**:
1. Verify server IP: `ip addr show`
2. Verify SSH service: `sudo systemctl status sshd`
3. Check firewall: `sudo ufw status`
4. Verify SSH key: `ssh-add -l` (on admin laptop)
5. Check fail2ban: `sudo fail2ban-client status sshd`

### Docker Permission Denied

**Symptoms**: "permission denied" when running docker commands

**Solutions**:
1. Verify user in docker group: `groups $USER`
2. Log out and back in (group changes require new session)
3. Verify Docker service: `sudo systemctl status docker`

### LUKS Partition Not Mounting

**Symptoms**: /mnt/data or /mnt/backup not mounted after reboot

**Solutions (data partition)**:
1. Check crypttab: `cat /etc/crypttab`
2. Check fstab: `cat /etc/fstab`
3. Verify key file: `ls -l /root/.luks-key` (should be 600)
4. Manual unlock: `sudo cryptsetup luksOpen /dev/nvme0n1p3 data_crypt`
5. Manual mount: `sudo mount /dev/mapper/data_crypt /mnt/data`

**Solutions (backup partition / DAS)**:
1. Check DAS is connected: `lsblk | grep sdb`
2. Manual unlock: `sudo cryptsetup luksOpen /dev/sdb2 backup_crypt`
3. Manual mount: `sudo mount /dev/mapper/backup_crypt /mnt/backup`
4. Note: DAS uses `nofail,noauto` — it is NOT auto-opened at boot by design

**Full recovery procedures**: See `docs/12-runbooks.md` → LUKS Disk Encryption Recovery

### Firewall Blocking Services

**Symptoms**: Cannot access services from LAN

**Solutions**:
1. Check UFW status: `sudo ufw status verbose`
2. Verify rules allow LAN: `192.168.1.0/24`
3. Add missing rule: `sudo ufw allow from 192.168.1.0/24 to any port [port]`
4. Reload firewall: `sudo ufw reload`

## Related Documentation

- **01-architecture.md**: Overall system architecture
- **02-network.md**: Network configuration and DNS
- **03-reverse-proxy.md**: Caddy configuration (Phase 02)
- **05-storage.md**: Samba and storage configuration (Phase 02)
- **12-runbooks.md**: Operational procedures

## Change Log

| Date | Change | Author |
|------|--------|--------|
| [Date] | Initial foundation layer deployment | [Admin] |
| [Date] | Updated after Phase 01 completion | [Admin] |

---

**Last Updated**: [Date]
**Status**: Deployed (Phase 01 Complete)
**Next Steps**: Proceed to Phase 02 (Infrastructure Services Layer)


## Automated Monitoring

### Container Health Monitoring

**Cron job**: Monitors Docker container health every 5 minutes

**Configuration** (via `/etc/cron.d/homeserver-cron`):
```bash
cat /etc/cron.d/homeserver-cron
# Should show:
*/15 * * * * root /opt/homeserver/scripts/operations/monitoring/check-container-health.sh >> /var/log/homeserver/health-check.log 2>&1
```

**Install cron** (if not present):
```bash
sudo cp /opt/homeserver/configs/cron/homeserver-cron /etc/cron.d/homeserver-cron
sudo chmod 644 /etc/cron.d/homeserver-cron
```

**What it monitors**:
- Critical containers listed in `configs/monitoring/critical-containers.conf`
- Default: caddy, pihole, immich-server, immich-postgres, jellyfin

**Alert behavior**:
- Sends single consolidated email to ADMIN_EMAIL if any container unhealthy or missing
- Uses msmtp for email delivery (graceful fallback if unavailable)
- No email if all containers healthy
- Logs structured output to `/var/log/homeserver/health-check.log`

**Manual test**:
```bash
sudo /opt/homeserver/scripts/operations/monitoring/check-container-health.sh --dry-run
# Shows container statuses without sending email
sudo /opt/homeserver/scripts/operations/monitoring/check-container-health.sh
# Sends email if any unhealthy
```

**Verify cron is running**:
```bash
systemctl status cron
# Should show: active (running)

# Check cron logs
grep CRON /var/log/syslog | tail -20
```

**Reference**: See docs/02-infrastructure-layer.md for health monitoring details.
