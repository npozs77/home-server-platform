# Samba File Sharing - Operational Reference

## Overview

Samba provides cross-platform file sharing for the home server, enabling Windows, macOS, Linux, iOS, and Android devices to access personal folders, family shared folders, and the media library. The service runs in a Docker container with role-based permissions, recycle bin functionality, and persistent user database.

## Architecture

- **Container**: samba
- **Image**: dperson/samba:latest
- **Network**: homeserver (Docker bridge network)
- **Ports**: 139 (NetBIOS), 445 (SMB)
- **Protocol**: SMB2/SMB3 (SMB1 disabled for security)
- **Access**: \\\\192.168.1.2 (Windows) or smb://192.168.1.2 (macOS/Linux)

## Share Structure

### Personal Shares (Per User)

Each user has a personal share with private folder structure:

- **Path**: /mnt/data/users/{username}/
- **Subdirectories**: Documents/, Photos/, Videos/, Music/
- **Ownership**: {username}:family
- **Permissions**: 770 (user and family group read/write)
- **Access**: Owner only (read/write)
- **Share Name**: {username}
- **Recycle Bin**: .recycle/{username}/ (per-user, 30-day retention)

**Example**:
```
\\192.168.1.2\admin
  ├── Documents/
  ├── Photos/
  ├── Videos/
  └── Music/
```

### Family Share

Shared folder for family collaboration:

- **Path**: /mnt/data/family/
- **Subdirectories**: Documents/, Photos/, Videos/, Projects/
- **Ownership**: root:family
- **Permissions**: 770 (family group read/write)
- **Access**: All family members (read/write)
- **Share Name**: Family
- **Force Group**: family (all files inherit family group)
- **Recycle Bin**: .recycle/{username}/ (per-user, 30-day retention)

**Example**:
```
\\192.168.1.2\Family
  ├── Documents/
  ├── Photos/
  ├── Videos/
  └── Projects/
```

### Media Share

Curated media library for streaming services:

- **Path**: /mnt/data/media/
- **Subdirectories**: Movies/, TV Shows/, Music/
- **Ownership**: media:media (all files and directories)
- **Permissions**: 2775 (setgid bit for group inheritance)
- **Access**: 
  - Admin/Power Users: Read/write (via media group membership)
  - Standard Users: Read-only
- **Share Name**: Media
- **Force User/Group**: media (ensures consistent ownership)
- **Recycle Bin**: .recycle/{username}/ (per-user, 30-day retention)

**Example**:
```
\\192.168.1.2\Media
  ├── Movies/
  ├── TV Shows/
  └── Music/
```

## Access Control

### Role-Based Permissions

| Role | Personal Share | Family Share | Media Share |
|------|---------------|--------------|-------------|
| Admin | RW (own only) | RW | RW (via media group) |
| Power User | RW (own only) | RW | RW (via media group) |
| Standard User | RW (own only) | RW | RO |

### Linux Group Membership

- **family**: All users (grants access to Family share)
- **media**: Admin and Power Users (grants write access to Media share)

### Samba Container Permissions

The Samba container runs with PGID matching the family group (GID 1001), allowing it to access personal directories with 770 permissions (user:family ownership).

**Critical Configuration**:
- `PGID: 1001` - Container runs with family group GID
- `/etc/passwd:/etc/passwd:ro` - Maps host users to container
- `/etc/group:/etc/group:ro` - Maps host groups to container

Without these mounts, Samba cannot resolve usernames, group memberships, or display names.

## Recycle Bin

### Configuration

- **Location**: .recycle/{username}/ in each share root
- **Retention**: 30 days (configurable)
- **Max Size**: 10% of share size (configurable)
- **Privacy**: Users can only see their own deleted files
- **Behavior**: Deleted files moved to recycle bin with original directory structure preserved

### File Naming

Deleted files are stored with timestamp suffix:
```
.recycle/admin/Documents/report.pdf
```

### Cleanup

Automatic cleanup runs daily via Samba's built-in recycle bin module:
- Files older than 30 days are permanently deleted
- If recycle bin exceeds 10% of share size, oldest files deleted first

### Manual Recovery

**Windows**:
1. Navigate to share: \\\\192.168.1.2\\{sharename}
2. Show hidden files: View → Hidden items
3. Open .recycle\\{username}\\
4. Copy files back to original location

**macOS/Linux**:
```bash
# Mount share
mount -t cifs //192.168.1.2/{sharename} /mnt/share -o username={user}

# Navigate to recycle bin
cd /mnt/share/.recycle/{username}/

# Copy files back
cp -r Documents/report.pdf /mnt/share/Documents/
```

## Configuration Files

### smb.conf

**Location**: /opt/homeserver/configs/samba/smb.conf

**Global Configuration**:
```ini
[global]
   workgroup = WORKGROUP
   server string = Home Media Server
   security = user
   
   # Protocol versions (SMB1 disabled)
   server min protocol = SMB2
   server max protocol = SMB3
   
   # Logging
   log level = 1
   max log size = 50
   
   # Performance tuning
   socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
   read raw = yes
   write raw = yes
   
   # Recycle bin (global)
   vfs objects = recycle
   recycle:repository = .recycle/%U
   recycle:keeptree = yes
   recycle:versions = yes
   recycle:touch = yes
   recycle:maxsize = 0
   recycle:exclude = *.tmp, *.temp, *.cache
```

**Share Definitions**:
- Personal shares: Added dynamically by user provisioning scripts
- Family share: Defined in smb.conf with force group = family
- Media share: Defined in smb.conf with force user/group = media

### docker-compose.yml

**Location**: /opt/homeserver/configs/docker-compose/samba.yml

**Key Configuration**:
```yaml
services:
  samba:
    image: dperson/samba:latest
    container_name: samba
    restart: unless-stopped
    ports:
      - "139:139"
      - "445:445"
    volumes:
      - /mnt/data:/mnt/data
      - /opt/homeserver/configs/samba/smb.conf:/etc/samba/smb.conf:ro
      - /mnt/data/services/samba/lib:/var/lib/samba:rw
      - /etc/passwd:/etc/passwd:ro
      - /etc/group:/etc/group:ro
    environment:
      TZ: "America/New_York"
      WORKGROUP: "WORKGROUP"
      RECYCLE: "true"
      PGID: "1001"
    networks:
      - homeserver
```

**Critical Mounts**:
- `/mnt/data/services/samba/lib:/var/lib/samba:rw` - Persists user database (survives container recreation)
- `/etc/passwd:/etc/passwd:ro` - Maps host users to container
- `/etc/group:/etc/group:ro` - Maps host groups to container

## Client Configuration

### Windows

**Connect to Share**:
1. Open File Explorer
2. Address bar: `\\192.168.1.2`
3. Enter username and Samba password
4. Select "Remember my credentials"

**Map Network Drive**:
1. Right-click "This PC" → Map network drive
2. Drive letter: Z: (or any available)
3. Folder: `\\192.168.1.2\{sharename}`
4. Check "Reconnect at sign-in"
5. Enter credentials

**Disconnect**:
```cmd
net use Z: /delete
```

### macOS

**Connect to Share**:
1. Finder → Go → Connect to Server (⌘K)
2. Server Address: `smb://192.168.1.2`
3. Click Connect
4. Enter username and Samba password
5. Select shares to mount

**Mount via Command Line**:
```bash
mkdir -p ~/mnt/share
mount -t smbfs //username@192.168.1.2/sharename ~/mnt/share
```

**Unmount**:
```bash
umount ~/mnt/share
```

### Linux

**Install CIFS utilities**:
```bash
sudo apt install cifs-utils
```

**Mount Share**:
```bash
sudo mkdir -p /mnt/share
sudo mount -t cifs //192.168.1.2/sharename /mnt/share -o username=user,uid=1000,gid=1000
```

**Permanent Mount** (add to /etc/fstab):
```
//192.168.1.2/sharename /mnt/share cifs username=user,password=pass,uid=1000,gid=1000 0 0
```

**Unmount**:
```bash
sudo umount /mnt/share
```

### Mobile (iOS/Android)

**iOS** (Files app):
1. Files → Browse → Connect to Server
2. Server: `smb://192.168.1.2`
3. Enter username and password
4. Select share

**Android** (File Manager apps):
- Use apps like "Solid Explorer", "FX File Explorer", or "CX File Explorer"
- Add network storage → SMB/CIFS
- Server: 192.168.1.2
- Username and password
- Select share

## Common Operations

### User Management

**Create Samba User** (via provisioning script):
```bash
cd /opt/homeserver/scripts/operations/user-management
sudo ./create-user.sh username role [ssh-key]
```

**Update Samba Password**:
```bash
docker exec -it samba smbpasswd username
```

**List Samba Users**:
```bash
docker exec samba pdbedit -L
```

**Delete Samba User**:
```bash
cd /opt/homeserver/scripts/operations/user-management
sudo ./delete-user.sh username [--keep-data]
```

### Share Management

**Add Personal Share** (automatic via create-user.sh):
```bash
# Share added to smb.conf automatically
# Reload configuration
docker exec samba smbcontrol all reload-config
```

**Reload Configuration** (after manual smb.conf edits):
```bash
docker exec samba smbcontrol all reload-config
```

**List Active Shares**:
```bash
docker exec samba smbclient -L localhost -N
```

**Test Share Access**:
```bash
smbclient //192.168.1.2/sharename -U username
```

### Container Management

**Check Container Status**:
```bash
docker ps | grep samba
```

**View Container Logs**:
```bash
docker logs samba --tail 50
docker logs samba -f  # follow mode
```

**Restart Container**:
```bash
docker restart samba
```

**Recreate Container** (preserves user database):
```bash
cd /opt/homeserver/configs/docker-compose
docker compose -f samba.yml down
docker compose -f samba.yml up -d
```

### Monitoring

**Check Active Connections**:
```bash
docker exec samba smbstatus
```

**Check Samba Version**:
```bash
docker exec samba smbd --version
```

**View Samba Logs**:
```bash
docker exec samba cat /var/log/samba/log.smbd
```

## Troubleshooting

### Cannot Connect to Share

**Check Samba container is running**:
```bash
docker ps | grep samba
```

**Check UFW allows Samba ports**:
```bash
sudo ufw status | grep -E "139|445"
```

Expected output:
```
139/tcp                    ALLOW       192.168.1.0/24             # Samba NetBIOS
445/tcp                    ALLOW       192.168.1.0/24             # Samba SMB
```

**Add UFW rules if missing**:
```bash
sudo ufw allow from 192.168.1.0/24 to any port 139 proto tcp comment 'Samba NetBIOS'
sudo ufw allow from 192.168.1.0/24 to any port 445 proto tcp comment 'Samba SMB'
```

**Test connectivity from client**:
```bash
# Windows
ping 192.168.1.2
telnet 192.168.1.2 445

# Linux/macOS
ping 192.168.1.2
nc -zv 192.168.1.2 445
```

### Authentication Failed

**Verify Samba user exists**:
```bash
docker exec samba pdbedit -L | grep username
```

**Reset Samba password**:
```bash
docker exec -it samba smbpasswd username
```

**Check Linux user exists**:
```bash
id username
```

**Verify container can see host users**:
```bash
docker exec samba getent passwd username
docker exec samba getent group family
```

If users/groups not visible, check `/etc/passwd` and `/etc/group` mounts in docker-compose.yml.

### Permission Denied

**Check file ownership and permissions**:
```bash
ls -la /mnt/data/users/username/
ls -la /mnt/data/family/
ls -la /mnt/data/media/
```

**Fix personal folder permissions**:
```bash
sudo chown -R username:family /mnt/data/users/username/
sudo chmod 770 /mnt/data/users/username/
sudo chmod 770 /mnt/data/users/username/*
```

**Fix family folder permissions**:
```bash
sudo chown -R root:family /mnt/data/family/
sudo chmod 770 /mnt/data/family/
sudo chmod 770 /mnt/data/family/*
```

**Fix media folder permissions**:
```bash
sudo chown -R media:media /mnt/data/media/
sudo chmod 2775 /mnt/data/media/
sudo chmod 2775 /mnt/data/media/*
```

**Verify user is in correct groups**:
```bash
groups username
```

Expected output:
- Admin: `username family sudo docker media`
- Power User: `username family docker media`
- Standard User: `username family`

**Add user to media group** (if missing):
```bash
sudo usermod -aG media username
# User must log out and back in for group membership to take effect
```

### Samba User Database Corrupted

**Symptoms**:
- Users created with UID 4294967295 (-1)
- Cannot authenticate
- pdbedit shows corrupted entries

**Cause**: Missing `/etc/passwd` or `/etc/group` mounts in container

**Fix**:
1. Stop container: `docker stop samba`
2. Verify mounts in docker-compose.yml:
   ```yaml
   volumes:
     - /etc/passwd:/etc/passwd:ro
     - /etc/group:/etc/group:ro
   ```
3. Recreate container: `docker compose -f samba.yml up -d`
4. Verify container can see host users: `docker exec samba getent passwd username`
5. Re-provision users if database corrupted: `sudo ./create-user.sh username role`

### Recycle Bin Not Working

**Check recycle bin directory exists**:
```bash
ls -la /mnt/data/users/username/.recycle/
ls -la /mnt/data/family/.recycle/
ls -la /mnt/data/media/.recycle/
```

**Create recycle bin directories**:
```bash
sudo mkdir -p /mnt/data/users/username/.recycle/username
sudo chown username:family /mnt/data/users/username/.recycle/username
sudo chmod 770 /mnt/data/users/username/.recycle/username
```

**Verify recycle bin configuration in smb.conf**:
```bash
grep -A 5 "vfs objects = recycle" /opt/homeserver/configs/samba/smb.conf
```

### Container Cannot Access Personal Folders

**Symptoms**:
- Permission denied when accessing personal shares
- Samba logs show "access denied" errors

**Cause**: Container not running with family group GID

**Fix**:
1. Check family group GID: `getent group family`
2. Verify PGID in docker-compose.yml matches family GID
3. Recreate container with correct PGID

**Verify container runs with correct GID**:
```bash
docker exec samba id
```

Expected output should include: `groups=1001(family)`

## Performance Tuning

### Network Performance

Current configuration optimized for gigabit LAN:
- Socket buffer sizes: 131072 bytes (128 KB)
- TCP_NODELAY: Reduces latency
- IPTOS_LOWDELAY: Prioritizes low latency over throughput
- Raw I/O: Direct disk access

**Expected Performance**: >100 MB/s on gigabit LAN

**Test Performance**:
```bash
# Copy large file to share and measure time
time cp /path/to/large-file.iso /mnt/share/
```

### Disk I/O

Samba accesses /mnt/data/ directly (no additional layers):
- No performance overhead from container
- Direct access to LUKS-encrypted volume
- Performance limited by disk speed and encryption overhead

## Security

### Protocol Security

- **SMB1 Disabled**: Prevents known vulnerabilities (WannaCry, EternalBlue)
- **SMB2/SMB3 Only**: Modern protocols with encryption support
- **User-Level Security**: No guest access, authentication required

### Network Security

- **Firewall**: UFW allows Samba ports only from LAN (192.168.1.0/24)
- **No Internet Exposure**: Samba not accessible from WAN
- **LAN-Only Access**: All clients must be on local network

### Authentication

- **Samba Passwords**: Separate from Linux passwords, stored in /var/lib/samba/private/passdb.tdb
- **Password Persistence**: User database persisted to /mnt/data/services/samba/lib
- **Password Complexity**: Minimum 8 characters (enforced by provisioning scripts)

### File Permissions

- **Personal Folders**: 770 (user and family group only)
- **Family Folders**: 770 (family group only)
- **Media Folders**: 2775 (media group write, others read)
- **Recycle Bin**: Per-user isolation (users cannot see others' deleted files)

## File Locations

- **Samba config**: /opt/homeserver/configs/samba/smb.conf
- **Docker Compose**: /opt/homeserver/configs/docker-compose/samba.yml
- **User database**: /mnt/data/services/samba/lib/private/passdb.tdb
- **Personal folders**: /mnt/data/users/{username}/
- **Family folders**: /mnt/data/family/
- **Media folders**: /mnt/data/media/
- **Provisioning scripts**: /opt/homeserver/scripts/operations/user-management/
- **Provisioning logs**: /var/log/user-provisioning.log

## Related Documentation

- Architecture Overview: docs/00-architecture-overview.md
- Foundation Layer: docs/01-foundation-layer.md
- Infrastructure Layer: docs/02-infrastructure-layer.md
- Storage Configuration: docs/05-storage.md
- Jellyfin Setup: docs/07-jellyfin-setup.md
- Deployment Manual: docs/deployment_manuals/phase3-core-services.md

## Lessons Learned

### User Database Persistence

**Problem**: Initial deployment did not persist Samba user database, causing users to be lost on container recreation.

**Solution**: Mount `/var/lib/samba` to `/mnt/data/services/samba/lib` on host filesystem.

**Verification**: Recreate container and verify users still exist: `docker exec samba pdbedit -L`

### Host User/Group Mapping

**Problem**: Samba users created with corrupted UIDs (4294967295) when `/etc/passwd` and `/etc/group` not mounted.

**Solution**: Mount `/etc/passwd` and `/etc/group` from host to container (read-only).

**Why Required**: Samba uses UID/GID from `/etc/passwd` to map Samba users to Unix users. GECOS field (5th field) used as display name. Group memberships determine share access.

### Container Group Permissions

**Problem**: Samba container could not access personal directories with 770 permissions (user:family).

**Solution**: Set `PGID` environment variable to family group GID (1001), allowing container to run with family group membership.

**Verification**: `docker exec samba id` should show `groups=1001(family)`

### Personal Folder Permissions

**Problem**: Original design used 700 permissions (user-only), preventing Samba container from accessing folders.

**Solution**: Changed to 770 permissions (user:family) and set PGID=family in container, allowing both user and Samba to access.

**Trade-off**: Family group members can technically access personal folders at filesystem level, but Samba share permissions restrict access to owner only.
