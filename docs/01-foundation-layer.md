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

**Encrypted Partition**:
- **Device**: [DATA_DISK from config, e.g., /dev/sdb]
- **Type**: LUKS (Linux Unified Key Setup)
- **Filesystem**: ext4
- **Mount Point**: /mnt/data

**Auto-Unlock Configuration**:
- **Key File**: /root/.luks-key
- **Permissions**: 600 (root-only)
- **Crypttab**: `/etc/crypttab` (auto-unlock on boot)
- **Fstab**: `/etc/fstab` (auto-mount after unlock)

**Manual Unlock** (emergency):
```bash
sudo cryptsetup luksOpen /dev/sdb data_crypt
# Enter passphrase when prompted
sudo mount /dev/mapper/data_crypt /mnt/data
```

**Passphrase Storage**:
- Password manager (primary)
- Printed copy (secure location, backup)

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

**9 Validation Checks**:
1. **SSH Hardening**: Password auth disabled, key auth enabled
2. **UFW Firewall**: Active with LAN-only rules
3. **fail2ban**: Running and monitoring SSH
4. **Docker**: Installed and functional (hello-world test)
5. **Git Repository**: Initialized with proper structure
6. **Unattended-upgrades**: Enabled and configured
7. **LUKS Encryption**: Data partition encrypted and auto-unlocks
8. **Docker Group**: Admin user in docker group
9. **Essential Tools**: git, vim, curl, wget, htop installed

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

**Symptoms**: /mnt/data not mounted after reboot

**Solutions**:
1. Check crypttab: `cat /etc/crypttab`
2. Check fstab: `cat /etc/fstab`
3. Verify key file: `ls -l /root/.luks-key` (should be 600)
4. Manual unlock: `sudo cryptsetup luksOpen /dev/sdb data_crypt`
5. Manual mount: `sudo mount /dev/mapper/data_crypt /mnt/data`

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

**Configuration**:
```bash
crontab -l
# Should show:
*/5 * * * * /opt/homeserver/scripts/operations/monitoring/check-container-health.sh
```

**Add cron job** (if not present):
```bash
crontab -e
# Add line:
*/5 * * * * /opt/homeserver/scripts/operations/monitoring/check-container-health.sh
```

**What it monitors**:
- Pi-hole container health
- Caddy container health
- Jellyfin container health

**Alert behavior**:
- Sends email to ADMIN_EMAIL if any container unhealthy
- Uses msmtp for email delivery
- No output if all containers healthy

**Manual test**:
```bash
/opt/homeserver/scripts/operations/monitoring/check-container-health.sh
# No output = all healthy
# Email sent = container unhealthy
```

**Verify cron is running**:
```bash
systemctl status cron
# Should show: active (running)

# Check cron logs
grep CRON /var/log/syslog | tail -20
```

**Reference**: See docs/02-infrastructure-layer.md for health monitoring details.
