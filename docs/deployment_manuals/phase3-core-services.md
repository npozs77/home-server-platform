# Phase 03 - Core Services Layer Deployment Manual

**Version**: 1.1  
**Status**: Ready for Deployment  
**Last Updated**: 2025-03-02  
**Estimated Time**: 8-10 hours

## Overview

This manual provides step-by-step procedures for deploying the Phase 03 Core Services Layer. Follow these instructions to establish Samba file sharing with role-based permissions, automated user provisioning scripts, organized folder structures, and Jellyfin media streaming that enable family members to access and manage their files and media securely.

## Prerequisites

**Phase 1 and 2 Complete**:
- Ubuntu Server LTS 24.04 installed and updated
- SSH hardening configured (key-based auth only)
- UFW firewall active (LAN-only access)
- fail2ban monitoring SSH attempts
- LUKS encryption with /mnt/data/ mounted and auto-unlocking
- Docker and Docker Compose installed
- Git repository at /opt/homeserver/ initialized
- Internal CA (Caddy) deployed and root certificate exported
- Caddy reverse proxy running with HTTPS
- Pi-hole DNS running with internal domain resolution
- SMTP relay configured for email notifications
- Data storage structure created (/mnt/data/media, /mnt/data/family, /mnt/data/users)
- Netdata monitoring running

**User Accounts Prepared**:
- Admin user SSH keys generated (Ed25519 with passphrase)
- Power user SSH keys generated (Ed25519 with passphrase)
- Samba passwords chosen (min 8 characters)

**Network Configuration**:
- Router DHCP reservation for server (192.168.1.2)
- Client devices configured to use Pi-hole DNS (192.168.1.2)
- Root CA certificate installed on admin workstation

**Reference Documents**:
- Requirements: `.kiro/specs/03-core-services/requirements.md`
- Design: `.kiro/specs/03-core-services/design.md`
- Tasks: `.kiro/specs/03-core-services/tasks.md`
- Phase 2 Manual: `docs/deployment_manuals/phase2-infrastructure.md`

## Quick Start

1. Copy deployment script to server: `scp scripts/deploy/deploy-phase3-core-services.sh user@192.168.1.2:/opt/homeserver/scripts/deploy/`
2. SSH to server and run script: `sudo ./deploy-phase3-core-services.sh`
3. Initialize configuration (option 0)
4. Execute tasks sequentially (2.1 → 2.2 → 3.1 → ...)
5. Validate deployment (option v)
6. Complete Jellyfin initial setup via web interface
7. Configure client devices for Samba and Jellyfin access

## Pre-Deployment Checklist

Before starting Phase 03 deployment, verify:

- [ ] Phase 02 validation passes all checks
- [ ] Server accessible via SSH (192.168.1.2)
- [ ] /mnt/data/ mounted and writable
- [ ] Docker service running
- [ ] Caddy reverse proxy running
- [ ] Pi-hole DNS running
- [ ] Admin SSH key available (Ed25519 with passphrase)
- [ ] Power user SSH key available (Ed25519 with passphrase)
- [ ] Samba passwords chosen for all users (min 8 characters)

**Verification Commands**:
```bash
# SSH to server
ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2

# Check Phase 02 status
sudo /opt/homeserver/scripts/deploy/deploy-phase2-infrastructure.sh
# Select option 'v' - all checks should pass

# Check /mnt/data/ mounted
df -h | grep /mnt/data
# Should show mounted partition

# Check Docker running
docker ps
# Should show caddy, pihole, netdata containers

# Check Caddy running
curl -k https://monitor.home.mydomain.com
# Should return Netdata web interface
```

## Task 0: Copy Deployment Script to Server

**Objective**: Copy Phase 3 deployment script and manual to server

**Prerequisites**: 
- Phase 3 deployment artifacts created locally
- SSH access to server working

**Steps**:

1. **Copy deployment script** (from admin laptop)
   ```bash
   scp scripts/deploy/deploy-phase3-core-services.sh admin@192.168.1.2:/opt/homeserver/scripts/deploy/
   ```

2. **Copy deployment manual** (from admin laptop)
   ```bash
   scp docs/deployment_manuals/phase3-core-services.md admin@192.168.1.2:/opt/homeserver/docs/deployment_manuals/
   ```

3. **SSH to server**
   ```bash
   ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2
   ```

4. **Verify files copied**
   ```bash
   ls -la /opt/homeserver/scripts/deploy/deploy-phase3-core-services.sh
   ls -la /opt/homeserver/docs/deployment_manuals/phase3-core-services.md
   # Both should exist
   ```

**Verification Checklist**:
- [ ] Deployment script copied to server
- [ ] Deployment manual copied to server
- [ ] Files accessible from /opt/homeserver/

## Task 1: Initialize Phase 3 Configuration

**Objective**: Initialize configuration file with user, Samba, and Jellyfin settings

**Prerequisites**: 
- Deployment script copied to server
- User names decided

**Steps**:

1. **Navigate to deployment scripts**
   ```bash
   cd /opt/homeserver/scripts/deploy/
   ```

2. **Run deployment script**
   ```bash
   sudo ./deploy-phase3-core-services.sh
   ```

3. **Select option 0: Initialize/Update configuration**
   ```
   Phase 03 - Core Services Layer
   ==============================
   0. Initialize/Update configuration
   c. Validate configuration
   ...
   
   Select option: 0
   ```

4. **Enter configuration values**
   
   **User Configuration**:
   - Admin username: `admin_user` (lowercase, alphanumeric, underscore)
   - Power user username: `power_user`
   - Standard user username: `standard_user`
   
   **Samba Configuration**:
   - Samba workgroup: `WORKGROUP` (default)
   - Samba server description: `Home Media Server`
   
   **Jellyfin Configuration**:
   - Jellyfin server name: `Home Media Server`

5. **Configuration saved**
   ```
   ✓ Configuration saved to /opt/homeserver/configs/services.env
   ```

**Expected Output**:
```
Configuration Initialization
============================

User Configuration
Admin username [admin_user]: admin_user
Power user username [power_user]: power_user
Standard user username [standard_user]: standard_user

Samba Configuration
Samba workgroup [WORKGROUP]: WORKGROUP
Samba server description [Home Media Server]: Home Media Server

Jellyfin Configuration
Jellyfin server name [Home Media Server]: Home Media Server

✓ Configuration saved to /opt/homeserver/configs/services.env
```

**Verification Checklist**:
- [ ] Configuration file updated at /opt/homeserver/configs/services.env
- [ ] All usernames valid (lowercase, alphanumeric, underscore)

## Task 2: Create Data Storage Structure

**Objective**: Create media library and Jellyfin service directories

**Prerequisites**: 
- Configuration initialized
- /mnt/data/ mounted

**Steps**:

1. **Create media library subdirectories (Task 2.1)**
   ```
   Select option: 2.1
   ```
   - Creates /mnt/data/media/Movies/
   - Creates /mnt/data/media/TV Shows/
   - Creates /mnt/data/media/Music/
   - Sets permissions: 755 (root:media)

2. **Create Jellyfin service directories (Task 2.2)**
   ```
   Select option: 2.2
   ```
   - Creates /mnt/data/services/jellyfin/config/
   - Creates /mnt/data/services/jellyfin/cache/
   - Sets permissions: 755 (root:root)

**Verification Checklist**:
- [ ] Media subdirectories exist
- [ ] Jellyfin service directories exist
- [ ] Permissions correct (755)

## Task 3: Deploy Samba File Sharing Service

**Objective**: Configure and deploy Samba container for cross-platform file sharing

**Prerequisites**: 
- Data storage structure created
- Docker running

**Steps**:

1. **Create Samba configuration files (Task 3.1)**
   ```
   Select option: 3.1
   ```
   - Creates /opt/homeserver/configs/samba/smb.conf
   - Configures global settings (workgroup, protocols, recycle bin)
   - Configures Family share with force group = family (ensures consistent group ownership)
   - Configures Media share with force user/group = media
   - Personal shares added dynamically during user provisioning

2. **Deploy Samba container (Task 3.2)**
   ```
   Select option: 3.2
   ```
   - Creates Docker Compose file
   - Starts Samba container
   - Exposes ports 139 (NetBIOS) and 445 (SMB)
   - Mounts /mnt/data and smb.conf

3. **Verify Samba shares accessible (Task 3.3)**
   ```
   Select option: 3.3
   ```
   - Tests Samba connectivity
   - Lists available shares

**Verification Checklist**:
- [ ] Samba container running
- [ ] Ports 139 and 445 accessible
- [ ] Family and Media shares listed

## Task 4: Create User Provisioning Scripts

**Objective**: Create automated scripts for user management

**Prerequisites**: 
- Samba deployed

**Steps**:

1. **Create user provisioning scripts (Task 4.1)**
   ```
   Select option: 4.1
   ```
   - Creates create-user.sh
   - Creates update-user.sh
   - Creates delete-user.sh
   - Creates list-users.sh
   - All scripts in /opt/homeserver/scripts/operations/user-management/

**Verification Checklist**:
- [ ] All four scripts created
- [ ] Scripts have execute permissions
- [ ] Scripts pass syntax validation

## Task 5: Provision Actual Users

**Objective**: Create admin, power, and standard users with proper permissions

**Prerequisites**: 
- User provisioning scripts created
- SSH keys prepared for admin and power users
- Samba passwords chosen

**Steps**:

1. **Provision Admin_User (Task 5.1)**
   ```
   Select option: 5.1
   ```
   - Prompts for SSH public key path
   - Prompts for Samba password
   - Creates Linux user with admin role
   - Creates Samba user
   - Creates personal folder structure
   - Configures SSH access

2. **Provision Power_User (Task 5.2)**
   ```
   Select option: 5.2
   ```
   - Prompts for SSH public key path
   - Prompts for Samba password
   - Creates Linux user with power role
   - Creates Samba user
   - Creates personal folder structure
   - Configures SSH access

3. **Provision Standard_User (Task 5.3)**
   ```
   Select option: 5.3
   ```
   - Prompts for Samba password
   - Creates Linux user with standard role
   - Creates Samba user
   - Creates personal folder structure
   - NO SSH access configured

**Verification Checklist**:
- [ ] All three users created
- [ ] Personal folders exist for each user
- [ ] Samba shares configured for each user
- [ ] SSH access configured for admin and power users only

## Task 6: Deploy Jellyfin Media Streaming Service

**Objective**: Configure and deploy Jellyfin container for media streaming

**Prerequisites**: 
- Media library structure created
- Jellyfin service directories created
- Docker running

**Steps**:

1. **Create Jellyfin Docker Compose configuration (Task 6.1)**
   ```
   Select option: 6.1
   ```
   - Creates Docker Compose file
   - Configures volumes (config, cache, media read-only)
   - Configures group_add for media group access (GID 1002)
   - Enables hardware acceleration (Intel Quick Sync) if available

2. **Deploy Jellyfin container (Task 6.2)**
   ```
   Select option: 6.2
   ```
   - Starts Jellyfin container
   - Exposes port 8096 (HTTP, internal only)
   - Waits for initialization

3. **Configure Caddy reverse proxy for Jellyfin (Task 6.3)**
   ```
   Select option: 6.3
   ```
   - Adds media.home.mydomain.com to Caddyfile
   - Configures reverse proxy to jellyfin:8096
   - Reloads Caddy

4. **Configure DNS record for Jellyfin (Task 6.4)**
   ```
   Select option: 6.4
   ```
   - Adds media.home.mydomain.com to Pi-hole custom.list
   - Restarts Pi-hole DNS

**Verification Checklist**:
- [ ] Jellyfin container running
- [ ] HTTPS access works (https://media.home.mydomain.com)
- [ ] DNS resolves correctly

## Task 7: Complete Jellyfin Initial Setup (Manual)

**Objective**: Complete Jellyfin setup wizard via web interface

**Prerequisites**: 
- Jellyfin accessible via HTTPS
- Root CA certificate installed on admin workstation

**Steps**:

1. **Access Jellyfin web interface**
   - Open browser: https://media.home.mydomain.com
   - Setup wizard appears

2. **Complete setup wizard**
   - Language: English
   - Create admin user: Admin_User (matches Linux username)
   - Set admin password (min 8 characters, separate from Linux password)

3. **Add media libraries**
   - Movies: /media/Movies (Content type: Movies)
   - TV Shows: /media/TV Shows (Content type: TV Shows)
   - Music: /media/Music (Content type: Music)

4. **Configure transcoding**
   - Dashboard → Playback → Transcoding
   - Hardware acceleration: Intel Quick Sync Video (if available) or None
   - Transcoding thread count: Auto

5. **Configure DLNA**
   - Dashboard → DLNA
   - Enable DLNA server: Yes

6. **Create Jellyfin users**
   - Dashboard → Users → Add User
   - Create Power_User (regular user, all libraries)
   - Create Standard_User (regular user, all libraries)
   - Note: Jellyfin users are application-level (NOT Linux users)

**Verification Checklist**:
- [ ] Jellyfin admin user created
- [ ] Media libraries configured
- [ ] All Jellyfin users created
- [ ] Users can log in with Jellyfin passwords

## Task 8: Validate Phase 3 Deployment

**Objective**: Run automated validation to verify all components working

**Prerequisites**: 
- All previous tasks completed

**Steps**:

1. **Run validation (option v)**
   ```
   Select option: v
   ```

2. **Verify all checks pass**
   - Samba Container: ✓ PASS
   - Personal Folders: ✓ PASS
   - Family Folders: ✓ PASS
   - Media Folders: ✓ PASS
   - Personal Shares: ✓ PASS
   - Family Share: ✓ PASS
   - Media Share: ✓ PASS
   - Recycle Bin: ✓ PASS
   - User Scripts: ✓ PASS
   - Jellyfin Container: ✓ PASS
   - Jellyfin HTTPS: ✓ PASS
   - Jellyfin Media Access: ✓ PASS
   - DNS Record (Jellyfin): ✓ PASS
   - Git Commit: ✓ PASS

**Expected Output**:
```
Phase 03 Core Services Validation
==================================

Samba Container                ✓ PASS
Personal Folders               ✓ PASS
Family Folders                 ✓ PASS
Media Folders                  ✓ PASS
Personal Shares                ✓ PASS
Family Share                   ✓ PASS
Media Share                    ✓ PASS
Recycle Bin                    ✓ PASS
User Scripts                   ✓ PASS
Jellyfin Container             ✓ PASS
Jellyfin HTTPS                 ✓ PASS
Jellyfin Media Access          ✓ PASS
DNS Record (Jellyfin)          ✓ PASS
Git Commit                     ✓ PASS

========================================
Results: 14/14 checks passed
========================================
✓ All checks passed!
```

**Verification Checklist**:
- [ ] All automated checks pass
- [ ] No errors in validation output

## Post-Deployment Tasks

### Configure Client Devices for Samba

**Windows**:
1. Open File Explorer
2. Enter \\192.168.1.2 in address bar
3. Enter Samba username and password
4. Map network drive (right-click share → Map network drive)

**macOS**:
1. Open Finder
2. Go → Connect to Server (Cmd+K)
3. Enter smb://192.168.1.2
4. Enter Samba username and password
5. Add to login items (System Preferences → Users & Groups → Login Items)

**Linux**:
1. Install cifs-utils: `sudo apt install cifs-utils`
2. Mount: `sudo mount -t cifs //192.168.1.2/{share} /mnt/{share} -o username={user}`

**Mobile (iOS/Android)**:
1. Install file manager app with SMB support (FE File Explorer, Solid Explorer)
2. Add SMB connection: Server 192.168.1.2, username, password

### Configure Client Devices for Jellyfin

**Web Browser**:
- Navigate to https://media.home.mydomain.com
- Log in with Jellyfin username and password

**iOS/Android**:
- Install Jellyfin app from App Store/Google Play
- Add server: https://media.home.mydomain.com
- Log in with Jellyfin username and password

**TV Apps** (Roku, Fire TV, Apple TV, Android TV):
- Install Jellyfin app from device app store
- Add server: https://media.home.mydomain.com
- Log in with Jellyfin username and password

## Troubleshooting

### Samba Issues

**Cannot connect to \\\\192.168.1.2**:
- Check Samba container: `docker ps | grep samba`
- Check firewall: `sudo ufw status | grep -E '139|445'`
- Check connectivity: `ping 192.168.1.2`
- Check logs: `docker logs samba`

**Authentication failed**:
- Verify user exists: `sudo pdbedit -L`
- Reset password: `sudo smbpasswd username`

**Permission denied**:
- Check user in family group: `groups username`
- Check folder permissions: `ls -la /mnt/data/path/to/share`

### Jellyfin Issues

**Cannot access https://media.home.mydomain.com**:
- Check Jellyfin container: `docker ps | grep jellyfin`
- Check container health: `docker inspect jellyfin --format='{{.State.Health.Status}}'` (should show "healthy")
- Check Caddy routing: `grep -A 5 "media.home.mydomain.com" /opt/homeserver/configs/caddy/Caddyfile`
- Check DNS: `nslookup media.home.mydomain.com 192.168.1.2`
- Check logs: `docker logs jellyfin`

**Container shows unhealthy status**:
- Check health check: `docker inspect jellyfin --format='{{.State.Health}}'`
- Test health check manually: `docker exec jellyfin curl -f http://localhost:8096/health || echo "Health check failed"`
- Restart container: `docker restart jellyfin` (wait 30 seconds for health check)
- Check logs for errors: `docker logs jellyfin | grep -i error`

**Libraries empty**:
- Check media mounted: `docker exec jellyfin ls -la /media`
- Trigger scan: Dashboard → Libraries → Scan All Libraries
- Check logs: `docker logs jellyfin | grep ERROR`

**Playback error**:
- Check media file format supported
- Try lower quality setting
- Check transcoding enabled: Dashboard → Playback → Transcoding
- Check disk space: `df -h /mnt/data/services/jellyfin/cache`

### Container Health Monitoring

All critical containers (Pi-hole, Caddy, Jellyfin) have HEALTHCHECK configured:

**Check container health status**:
```bash
docker ps
# Look for (healthy) status next to container name
```

**View detailed health information**:
```bash
docker inspect <container> --format='{{json .State.Health}}' | jq
```

**Automated health monitoring**:
- Script: `/opt/homeserver/scripts/operations/monitoring/check-container-health.sh`
- Runs every 15 minutes via `/etc/cron.d/homeserver-cron`
- Reads container list from `configs/monitoring/critical-containers.conf`
- Sends consolidated email alert if any container unhealthy or missing
- Reference: docs/12-runbooks.md for troubleshooting

**HEALTHCHECK configuration**:
- Pi-hole: `dig @127.0.0.1 google.com` (tests DNS resolution)
- Caddy: `curl -f http://localhost:80` (tests HTTP response)
- Jellyfin: `curl -f http://localhost:8096/health` (tests API health endpoint)
- Interval: 30 seconds
- Timeout: 10 seconds
- Retries: 3
- Start period: 30-60 seconds (allows container initialization)

## Next Steps

After Phase 3 deployment complete:
- Test Samba access from all client devices
- Test Jellyfin playback from multiple devices
- Add media files to /mnt/data/media/
- Configure automated backups for user data
- Proceed to Phase 4 (if planned)

## Appendix

### Samba Share Structure

```
/mnt/data/
├── users/
│   ├── admin_user/       (770, admin_user:family)
│   │   ├── Documents/
│   │   ├── Photos/
│   │   ├── Videos/
│   │   └── Music/
│   ├── power_user/       (770, power_user:family)
│   └── standard_user/    (770, standard_user:family)
├── family/               (2770/2775, root:family, setgid)
│   ├── Documents/        (2775, setgid)
│   ├── Photos/           (2770, setgid)
│   ├── Videos/           (2770, setgid)
│   └── Projects/         (2775, setgid)
└── media/                (2775, media:media, setgid)
    ├── Movies/
    ├── TV Shows/
    └── Music/
```

**Key Permission Changes**:
- Personal folders: 770 (user:family) - allows Samba container access via PGID
- Family folders: 2770/2775 (root:family, setgid) - ensures group inheritance
- Media folders: 2775 (media:media, setgid) - ensures consistent ownership
- Samba force group = family for Family share
- Samba force user/group = media for Media share

### Jellyfin Library Structure

```
/mnt/data/media/
├── Movies/
│   └── Movie Title (Year)/
│       ├── Movie Title (Year).mkv
│       └── poster.jpg
├── TV Shows/
│   └── Show Title/
│       ├── Season 01/
│       │   └── Show Title - S01E01 - Episode Title.mkv
│       └── Season 02/
└── Music/
    └── Artist Name/
        └── Album Name/
            └── 01 - Track Title.mp3
```

### User Roles and Permissions

| Role     | Linux Groups        | SSH Access | Samba Access | Jellyfin Role |
|----------|---------------------|------------|--------------|---------------|
| Admin    | family, sudo, docker| Yes        | RW all       | Administrator |
| Power    | family, docker      | Yes        | RW all       | User          |
| Standard | family              | No         | RW personal  | User          |
