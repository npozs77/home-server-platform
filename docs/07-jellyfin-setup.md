# Jellyfin Setup Guide

**Document Type**: Low-Level Design (LLD) - AS-IS Configuration Reference

**Purpose**: Step-by-step guide for completing Jellyfin initial setup wizard and configuring media libraries.

**Audience**: Administrators performing Jellyfin deployment

---

## Prerequisites

Before starting Jellyfin setup, ensure:

1. **Jellyfin container deployed** (Task 6.2 complete)
2. **Caddy reverse proxy configured** (Task 6.3 complete)
3. **DNS record configured** (Task 6.4 complete)
4. **Root CA certificate installed** on admin workstation (from Phase 2)
5. **Media files present** in /mnt/data/media/ (optional, can add later)

---

## Initial Setup Wizard

### Step 1: Access Jellyfin Web Interface

1. Open web browser on admin workstation
2. Navigate to: `https://media.home.mydomain.com`
3. Accept the internal CA certificate (if prompted)
4. Jellyfin setup wizard should appear

**Troubleshooting**:
- If page doesn't load, verify DNS resolution: `nslookup media.home.mydomain.com`
- If certificate error, verify root CA installed on workstation
- If connection refused, verify Jellyfin container running: `docker ps | grep jellyfin`

### Step 2: Select Language

1. Select **English** (or preferred language)
2. Click **Next**

### Step 3: Create Administrator Account

1. **Username**: Enter admin username (e.g., `Admin_User`)
   - Recommendation: Use same username as Linux admin user for consistency
2. **Password**: Enter strong password (min 8 characters)
   - Store password securely (password manager recommended)
3. Click **Next**

**Important**: This is the Jellyfin administrator account (application-level), NOT the Linux user account. Jellyfin uses its own internal authentication system.

### Step 4: Configure Media Libraries

**Skip this step** - we'll configure libraries manually after setup for better control.

1. Click **Next** without adding libraries

### Step 5: Configure Metadata Language

1. **Preferred Metadata Language**: English
2. **Country**: United States (or your country)
3. Click **Next**

### Step 6: Configure Remote Access

1. **Enable Remote Access**: **Unchecked** (LAN-only access)
2. **Enable Automatic Port Mapping**: **Unchecked** (not needed for LAN-only)
3. Click **Next**

**Important**: Remote access is disabled for security. Future VPN access will be configured in a later phase.

### Step 7: Complete Setup

1. Review settings summary
2. Click **Finish**
3. Jellyfin will redirect to login page

### Step 8: Login as Administrator

1. Enter administrator username and password
2. Click **Sign In**
3. Jellyfin dashboard should appear

---

## Configure Media Libraries

After completing the setup wizard, configure media libraries manually:

### Library 1: Movies

1. Navigate to **Dashboard** → **Libraries**
2. Click **Add Media Library**
3. Configure:
   - **Content Type**: Movies
   - **Display Name**: Movies
   - **Folders**: Click **+** and add `/media/Movies`
   - **Preferred Language**: English
   - **Country**: United States
   - **Enable Real-Time Monitoring**: Checked (auto-detect new files)
4. Click **OK**

### Library 2: TV Shows

1. Click **Add Media Library**
2. Configure:
   - **Content Type**: Shows
   - **Display Name**: TV Shows
   - **Folders**: Click **+** and add `/media/TV Shows`
   - **Preferred Language**: English
   - **Country**: United States
   - **Enable Real-Time Monitoring**: Checked
3. Click **OK**

### Library 3: Music

1. Click **Add Media Library**
2. Configure:
   - **Content Type**: Music
   - **Display Name**: Music
   - **Folders**: Click **+** and add `/media/Music`
   - **Preferred Language**: English
   - **Enable Real-Time Monitoring**: Checked
3. Click **OK**

### Trigger Library Scan

1. Navigate to **Dashboard** → **Libraries**
2. For each library, click **Scan Library**
3. Wait for scan to complete (may take several minutes depending on media count)

---

## Configure Transcoding

Transcoding converts media to formats compatible with client devices.

### Step 1: Access Playback Settings

1. Navigate to **Dashboard** → **Playback**

### Step 2: Configure Transcoding

1. **Transcoding Thread Count**: Auto (or set to CPU core count)
2. **Hardware Acceleration**: Select **None** (software transcoding on headless server)
3. **Preferred Codec**: H.264 (broad compatibility)
4. **Allow Encoding in HEVC Format**: Checked (for 4K content)
5. Click **Save**

**Note**: Intel QuickSync hardware acceleration is available if server has Intel integrated GPU. Requires `/dev/dri` device mounted in Docker container.

---

---

## Configure Network Settings

### Step 1: Access Network Settings

1. Navigate to **Dashboard** → **Networking**

### Step 2: Configure Published Server URL

1. **Published Server URL**: `https://media.home.mydomain.com`
   - This should already be set via JELLYFIN_PublishedServerUrl environment variable
2. **LAN Networks**: `192.168.1.0/24`
3. **Enable Remote Access**: **Unchecked**
4. Click **Save**

---

## Create Jellyfin Users

**Important**: Jellyfin users are application-level accounts (NOT Linux users). See Task 6.6 for user creation instructions.

---

## Verify Setup

### Test Media Playback

1. Navigate to **Home** in Jellyfin
2. Browse to a movie or TV show
3. Click **Play**
4. Verify playback works

### Test from Mobile Device

1. Install Jellyfin app from App Store (iOS) or Google Play (Android)
2. Add server: `https://media.home.mydomain.com`
3. Login with administrator credentials
4. Verify media libraries appear
5. Test playback

### Test Transcoding

1. Play media file that requires transcoding (e.g., 4K video on mobile)
2. Navigate to **Dashboard** → **Activity**
3. Verify transcoding session appears
4. Check CPU usage (should be high if software transcoding, low if hardware acceleration)

---

## Troubleshooting

### Media Library Not Scanning

**Symptoms**: Library scan completes but no media appears

**Causes**:
- Media files not in correct directory structure
- Jellyfin container cannot read /mnt/data/media/ (permission issue)
- Media files have incorrect permissions

**Solutions**:
1. Verify media files exist: `ls -la /mnt/data/media/Movies/`
2. Verify Jellyfin container can read media:
   ```bash
   docker exec jellyfin ls -la /media/Movies/
   ```
3. Verify media group membership:
   ```bash
   docker exec jellyfin id
   # Should show: groups=1002(media)
   ```
4. Verify media directory permissions:
   ```bash
   ls -ld /mnt/data/media/
   # Should show: drwxr-xr-x root media
   ```

### Transcoding Not Working

**Symptoms**: Playback fails or stutters when transcoding required

**Causes**:
- Insufficient CPU resources
- Transcoding cache full
- Hardware acceleration not working

**Solutions**:
1. Check transcoding cache: `df -h /mnt/data/services/jellyfin/cache/`
2. Free up cache space if needed: `rm -rf /mnt/data/services/jellyfin/cache/transcoding/*`
3. Disable hardware acceleration and retry with software transcoding
4. Reduce transcoding quality in playback settings

### HTTPS Certificate Error

**Symptoms**: Browser shows certificate warning when accessing Jellyfin, or SSL/TLS errors in curl

**Causes**:
- Root CA certificate not installed on client device
- Caddy internal CA not working
- Caddy hasn't generated certificate for new domain yet

**Solutions**:
1. **Check if certificate exists for media.home.mydomain.com**:
   ```bash
   docker exec caddy ls -la /data/caddy/certificates/local/ | grep media
   ```

2. **If certificate missing, restart Caddy to trigger generation**:
   ```bash
   docker restart caddy
   sleep 5  # Wait for Caddy to start
   docker exec caddy ls -la /data/caddy/certificates/local/ | grep media
   ```

3. **Verify root CA certificate installed on client device** (see Phase 2 docs)

4. **Verify Caddy is running**: `docker ps | grep caddy`

5. **Check Caddy logs**: `docker logs caddy | grep -i "media\|certificate"`

**Important Lesson Learned**: After adding a new service to Caddyfile and configuring DNS, you MUST restart Caddy (not just reload) to trigger certificate generation for the new domain. The `caddy reload` command updates the configuration but doesn't always trigger certificate generation for new domains.

**Workflow for Adding New Services**:
1. Add service entry to Caddyfile
2. Add DNS record to Pi-hole
3. **Restart Caddy** (not reload): `docker restart caddy`
4. Verify certificate generated: `docker exec caddy ls -la /data/caddy/certificates/local/`

### Cannot Access from Mobile Device

**Symptoms**: Jellyfin app cannot connect to server

**Causes**:
- Mobile device not on same LAN
- DNS not resolving on mobile device
- Root CA certificate not installed on mobile device

**Solutions**:
1. Verify mobile device on same network (192.168.1.0/24)
2. Verify DNS resolution on mobile: Settings → Wi-Fi → DNS (should be 192.168.1.2)
3. Install root CA certificate on mobile device (see Phase 2 docs)
4. Try accessing via IP: `https://192.168.1.2:443` (should redirect to Jellyfin)

---

## Post-Setup Tasks

After completing initial setup:

1. **Create Jellyfin users** (Task 6.6) - application-level accounts for family members
2. **Add media files** - copy movies, TV shows, music to /mnt/data/media/
3. **Configure parental controls** (optional) - restrict content by rating
4. **Set up scheduled library scans** - Dashboard → Scheduled Tasks
5. **Configure notifications** (optional) - Dashboard → Notifications

---

## References

- **Jellyfin Documentation**: https://jellyfin.org/docs/
- **Docker Compose Configuration**: configs/docker-compose/jellyfin.yml
- **Caddy Configuration**: configs/caddy/Caddyfile
- **DNS Configuration**: configs/pihole/custom.list
- **Design Document**: .kiro/specs/03-core-services/design.md (Jellyfin architecture)
