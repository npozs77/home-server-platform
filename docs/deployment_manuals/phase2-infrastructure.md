# Phase 02 - Infrastructure Services Layer Deployment Manual

**Version**: 1.0  
**Status**: Ready for Deployment  
**Last Updated**: 2025-02-21  
**Estimated Time**: 7-9 hours

## Overview

This manual provides step-by-step procedures for deploying the Phase 02 Infrastructure Services Layer. Follow these instructions to establish DNS resolution, reverse proxy routing, certificate management, email notifications, organized data storage, and real-time monitoring.

## Prerequisites

- Phase 01 (Foundation Layer) complete
- Ubuntu Server LTS 24.04 installed and updated
- SSH hardening configured (key-based auth only)
- UFW firewall active (LAN-only access)
- fail2ban monitoring SSH attempts
- LUKS encryption with /mnt/data/ mounted and auto-unlocking
- Docker and Docker Compose installed
- Git repository at /opt/homeserver/ initialized
- Registered domain (e.g., mydomain.com)
- External SMTP relay credentials (Gmail, SendGrid, or Mailgun)
- Admin email address for receiving notifications
- Router admin access (to configure DNS server advertisement)

**Reference Documents**:
- Requirements: `.kiro/specs/02-infrastructure/requirements.md`
- Design: `.kiro/specs/02-infrastructure/design.md`
- Tasks: `.kiro/specs/02-infrastructure/tasks.md`
- Phase 1 Manual: `docs/deployment_manuals/phase1-foundation.md`

## Quick Start

1. Copy deployment script to server: `scp scripts/deploy/deploy-phase2-infrastructure.sh user@192.168.1.2:/opt/homeserver/scripts/deploy/`
2. SSH to server and run script: `sudo ./deploy-phase2-infrastructure.sh`
3. Initialize configuration (option 0)
4. Execute tasks sequentially (2.1 → 2.2 → 2.3 → 3.1 → 4.1 → ...)
5. Validate deployment (option v)
6. Install root CA certificate on admin workstation
7. Configure router DHCP to advertise DNS server

## Pre-Deployment Checklist

Before starting Phase 02 deployment, verify:

- [ ] Phase 01 validation passes all checks
- [ ] Server accessible via SSH (192.168.1.2)
- [ ] /mnt/data/ mounted and writable
- [ ] Docker service running
- [ ] Git repository at /opt/homeserver/ initialized
- [ ] Domain registered and accessible
- [ ] SMTP relay credentials available (Gmail app password, SendGrid API key, etc.)
- [ ] Admin email address confirmed
- [ ] Router admin credentials available

**Verification Commands**:
```bash
# SSH to server
ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2

# Check Phase 01 status
sudo ~/deploy-phase1-foundation.sh
# Select option 'v' - all checks should pass

# Check /mnt/data/ mounted
df -h | grep /mnt/data
# Should show mounted partition

# Check Docker running
docker ps
# Should show no errors

# Check Git repository
git -C /opt/homeserver/ status
# Should show clean working tree
```

## Task 0: Copy Deployment Script to Server

**Objective**: Copy Phase 2 deployment script and manual to server

**Prerequisites**: 
- Phase 2 deployment artifacts created locally
- SSH access to server working

**Steps**:

1. **Copy deployment script** (from admin laptop)
   ```bash
   scp scripts/deploy/deploy-phase2-infrastructure.sh admin@192.168.1.2:/opt/homeserver/scripts/deploy/
   ```

2. **Copy deployment manual** (from admin laptop)
   ```bash
   scp docs/deployment_manuals/phase2-infrastructure.md admin@192.168.1.2:/opt/homeserver/docs/deployment_manuals/
   ```

3. **SSH to server**
   ```bash
   ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2
   ```

4. **Make script executable**
   ```bash
   chmod +x /opt/homeserver/scripts/deploy/deploy-phase2-infrastructure.sh
   ```

5. **Verify files copied**
   ```bash
   ls -la /opt/homeserver/scripts/deploy/deploy-phase2-infrastructure.sh
   ls -la /opt/homeserver/docs/deployment_manuals/phase2-infrastructure.md
   # Both should exist
   ```

**Verification Checklist**:
- [ ] Deployment script copied to server
- [ ] Deployment manual copied to server
- [ ] Script has execute permissions
- [ ] Files accessible from /opt/homeserver/

## Task 1: Initialize Phase 2 Configuration

**Objective**: Initialize configuration file with domain, SMTP, and Pi-hole settings

**Prerequisites**: 
- Deployment script copied to server
- SMTP relay credentials available
- Domain registered

**Steps**:

1. **Navigate to deployment scripts**
   ```bash
   cd /opt/homeserver/scripts/deploy/
   ```

2. **Run deployment script**
   ```bash
   sudo ./deploy-phase2-infrastructure.sh
   ```

3. **Select option 0: Initialize/Update configuration**
   ```
   Phase 02 - Infrastructure Services Layer Deployment
   ====================================================
   0. Initialize/Update configuration
   c. Validate configuration
   ...
   
   Select option [0,c,2.1-2.3,3.1,4.1,v,q]: 0
   ```

4. **Enter configuration values**
   
   **Domain Configuration**:
   - Domain: `mydomain.com` (your registered domain)
   - Internal subdomain: `home.mydomain.com`
   - Server IP: `192.168.1.2`
   
   **Admin Configuration**:
   - Admin email: `admin@mydomain.com` (your email for notifications)
   
   **SMTP Configuration**:
   - SMTP relay host: `smtp.gmail.com` (or your SMTP provider)
   - SMTP relay port: `587` (standard for TLS)
   - SMTP username: Your Gmail address or SMTP username
   - SMTP password: Gmail app password or SMTP password
   
   **Pi-hole Configuration**:
   - Pi-hole password: Strong password for web interface (8+ characters)

5. **Configuration saved**
   ```
   ✓ Configuration saved to /opt/homeserver/configs/services.env
   ```

**Expected Output**:
```
Configuration Initialization
============================

Domain [mydomain.com]: mydomain.com
Internal subdomain [home.mydomain.com]: home.mydomain.com
Server IP [192.168.1.2]: 192.168.1.2
Admin email [admin@mydomain.com]: admin@mydomain.com

SMTP Relay Configuration (for email notifications)
SMTP relay host [smtp.gmail.com]: smtp.gmail.com
SMTP relay port [587]: 587
SMTP username []: myemail@gmail.com
SMTP password: ********

Pi-hole web interface password: ********

✓ Configuration saved to /opt/homeserver/configs/services.env
```

**Verification Checklist**:
- [ ] Configuration file created at /opt/homeserver/configs/services.env
- [ ] All required values entered
- [ ] SMTP credentials correct
- [ ] Pi-hole password strong (8+ characters)

**Troubleshooting**:
- **Permission denied**: Run script with sudo
- **Can't save config**: Check /opt/homeserver/configs/ directory exists
- **Invalid domain**: Verify domain format (e.g., mydomain.com)

## Task 1.1: Validate Configuration

**Objective**: Verify configuration values are valid

**Prerequisites**: 
- Configuration initialized

**Steps**:

1. **Select option c: Validate configuration**
   ```
   Select option [0,c,2.1-2.3,3.1,4.1,v,q]: c
   ```

2. **Review validation results**
   ```
   Configuration Validation
   ========================
   ✓ Domain is valid: mydomain.com
   ✓ Internal subdomain is valid: home.mydomain.com
   ✓ Server IP is valid: 192.168.1.2
   ✓ Admin email format is valid: admin@mydomain.com
   ✓ SMTP relay host is set: smtp.gmail.com
   ✓ SMTP relay port is valid: 587
   ✓ SMTP username is set
   ✓ SMTP password is set
   ✓ Pi-hole password is strong (8+ characters)

   All checks passed!
   ```

3. **Fix any validation errors**
   - If validation fails, select option 0 to update configuration
   - Re-run validation (option c) until all checks pass

**Verification Checklist**:
- [ ] All validation checks pass
- [ ] Domain format valid
- [ ] Email format valid
- [ ] SMTP configuration complete
- [ ] Pi-hole password strong

**Troubleshooting**:
- **Domain invalid**: Check format (e.g., mydomain.com, not http://mydomain.com)
- **Email invalid**: Check format (e.g., user@domain.com)
- **SMTP port invalid**: Use numeric port (e.g., 587, not "587")
- **Password too weak**: Use 8+ characters for Pi-hole password

## Task 2: Data Storage Structure

**Objective**: Create organized directory structure for user data, media, and service data

### Task 2.1: Create Top-Level Data Directories

**Prerequisites**: 
- /mnt/data/ mounted and writable
- LUKS encryption active

**Steps**:

1. **Execute task 2.1**
   ```
   Select option [0,c,2.1-2.3,3.1,4.1,v,q]: 2.1
   ```

2. **Review output**
   ```
   Task 2.1: Create Top-Level Data Directories
   ============================================
   ℹ Creating top-level directories...
   ℹ Setting permissions...
   ℹ Setting ownership...
   ✓ Task 2.1 complete
   ```

3. **Verify directories created**
   ```bash
   ls -la /mnt/data/
   # Should show: media/, family/, users/, backups/, services/
   ```

4. **Verify permissions**
   ```bash
   ls -ld /mnt/data/{media,family,users,backups,services}
   # media: drwxr-xr-x (755) root:root
   # family: drwxr-xr-x (755) root:root
   # users: drwxr-xr-x (755) root:root
   # backups: drwx------ (700) root:root
   # services: drwxr-xr-x (755) root:root
   ```

**Verification Checklist**:
- [ ] /mnt/data/media/ exists (755, root:root)
- [ ] /mnt/data/family/ exists (755, root:root)
- [ ] /mnt/data/users/ exists (755, root:root)
- [ ] /mnt/data/backups/ exists (700, root:root)
- [ ] /mnt/data/services/ exists (755, root:root)

### Task 2.2: Create Family Subdirectories

**Prerequisites**: 
- /mnt/data/family/ exists

**Steps**:

1. **Execute task 2.2**
   ```
   Select option [0,c,2.1-2.3,3.1,4.1,v,q]: 2.2
   ```

2. **Verify subdirectories created**
   ```bash
   ls -la /mnt/data/family/
   # Should show: Documents/, Photos/, Videos/, Projects/
   ```

3. **Verify permissions**
   ```bash
   ls -ld /mnt/data/family/{Documents,Photos,Videos,Projects}
   # Documents: drwxrwsr-x (2775) root:family (setgid bit)
   # Photos: drwxrws--- (2770) root:family (setgid bit)
   # Videos: drwxrws--- (2770) root:family (setgid bit)
   # Projects: drwxrwsr-x (2775) root:family (setgid bit)
   ```

**Verification Checklist**:
- [ ] /mnt/data/family/Documents/ exists (2775, root:family, setgid)
- [ ] /mnt/data/family/Photos/ exists (2770, root:family, setgid)
- [ ] /mnt/data/family/Videos/ exists (2770, root:family, setgid)
- [ ] /mnt/data/family/Projects/ exists (2775, root:family, setgid)

**Note**: The setgid bit (2xxx) ensures all files created in these directories inherit the family group ownership, enabling proper Samba force group functionality.

### Task 2.3: Create Backup Subdirectories

**Prerequisites**: 
- /mnt/data/backups/ exists

**Steps**:

1. **Execute task 2.3**
   ```
   Select option [0,c,2.1-2.3,3.1,4.1,v,q]: 2.3
   ```

2. **Verify subdirectories created**
   ```bash
   ls -la /mnt/data/backups/
   # Should show: snapshots/, incremental/, offsite-sync/
   ```

3. **Verify permissions**
   ```bash
   ls -ld /mnt/data/backups/{snapshots,incremental,offsite-sync}
   # All: drwx------ (700) root:root
   ```

**Verification Checklist**:
- [ ] /mnt/data/backups/snapshots/ exists (700, root:root)
- [ ] /mnt/data/backups/incremental/ exists (700, root:root)
- [ ] /mnt/data/backups/offsite-sync/ exists (700, root:root)

## Task 3: Service Configuration Management

**Note**: Tasks 3.1 onwards are placeholders in the deployment script. These will be implemented during actual deployment when the full infrastructure services are ready.

### Task 3.1: Create services.yaml

**Objective**: Create single source of truth for service definitions

**Prerequisites**: 
- /opt/homeserver/configs/ directory exists

**Steps** (Manual - to be automated later):

1. **Create services.yaml**
   ```bash
   nano /opt/homeserver/configs/services.yaml
   ```

2. **Add infrastructure service definitions**
   ```yaml
   services:
     pihole:
       name: pihole
       image: pihole/pihole:latest
       ports:
         - "53:53/tcp"
         - "53:53/udp"
         - "8080:80/tcp"
       volumes:
         - /opt/homeserver/configs/pihole/etc-pihole:/etc/pihole
         - /opt/homeserver/configs/pihole/etc-dnsmasq.d:/etc/dnsmasq.d
       environment:
         TZ: America/New_York
         WEBPASSWORD: ${PIHOLE_PASSWORD}
       hostname: pihole.home.mydomain.com
       dns_record: true
       caddy_proxy: true
   ```

3. **Validate YAML syntax**
   ```bash
   # Install yamllint if not available
   sudo apt install -y yamllint
   
   # Validate syntax
   yamllint /opt/homeserver/configs/services.yaml
   ```

4. **Commit to Git**
   ```bash
   cd /opt/homeserver
   git add configs/services.yaml
   git commit -m "Phase 02: Add services.yaml"
   ```

**Verification Checklist**:
- [ ] services.yaml created
- [ ] YAML syntax valid
- [ ] Service definitions complete
- [ ] Committed to Git

## Post-Deployment Tasks

### Install Root CA Certificate on Admin Workstation

**Objective**: Install Caddy root CA certificate so browsers trust internal HTTPS certificates

**Prerequisites**: 
- Caddy deployed and root CA certificate exported
- Root CA certificate at /opt/homeserver/configs/caddy/root-ca.crt

**Steps**:

1. **Copy root CA certificate to admin workstation**
   ```bash
   # From admin laptop
   scp admin@192.168.1.2:/opt/homeserver/configs/caddy/root-ca.crt ~/
   ```

2. **Install on Windows**:
   - Double-click root-ca.crt
   - Click "Install Certificate"
   - Select "Local Machine"
   - Select "Place all certificates in the following store"
   - Browse → "Trusted Root Certification Authorities"
   - Click "Next" → "Finish"
   - Restart browser

3. **Install on macOS**:
   - Double-click root-ca.crt (opens Keychain Access)
   - Enter admin password
   - Find certificate in Keychain Access
   - Double-click certificate
   - Expand "Trust" section
   - Set "When using this certificate" to "Always Trust"
   - Close window and enter password
   - Restart browser

4. **Install on Linux**:
   ```bash
   sudo cp root-ca.crt /usr/local/share/ca-certificates/homeserver-ca.crt
   sudo update-ca-certificates
   # Restart browser
   ```

5. **Test certificate trust**
   - Open browser
   - Navigate to https://test.home.mydomain.com
   - Verify: Browser shows "Secure" (no certificate warnings)

**Verification Checklist**:
- [ ] Root CA certificate copied to workstation
- [ ] Certificate installed in system trust store
- [ ] Browser restarted
- [ ] HTTPS sites show "Secure" (no warnings)

### Configure Router DHCP to Advertise DNS Server

**Objective**: Configure router to advertise home server as primary DNS

**Prerequisites**: 
- Pi-hole deployed and running
- Router admin access

**Steps**:

1. **Access router admin panel**
   - Open browser
   - Navigate to http://192.168.1.1
   - Login with router credentials

2. **Navigate to DHCP settings**
   - Find DHCP server configuration
   - Locate DNS server settings

3. **Configure DNS servers**
   - Primary DNS: `192.168.1.2` (home server)
   - Secondary DNS: `192.168.1.1` (router fallback)
   - Save changes

4. **Reconnect client device**
   - Disconnect from WiFi
   - Reconnect to WiFi
   - Or: Release/renew DHCP lease

5. **Verify DNS server received**
   ```bash
   # Windows
   ipconfig /all
   # Look for: DNS Servers: 192.168.1.2, 192.168.1.1
   
   # Linux/Mac
   cat /etc/resolv.conf
   # Look for: nameserver 192.168.1.2
   ```

6. **Test DNS resolution**
   ```bash
   nslookup test.home.mydomain.com
   # Should return: 192.168.1.2
   ```

**Verification Checklist**:
- [ ] Router DHCP configured with DNS servers
- [ ] Client device receives DNS server (192.168.1.2)
- [ ] DNS resolution works for internal domains
- [ ] External DNS resolution still works

## Validation

### Automated Validation

**Objective**: Run automated validation checks

**Steps**:

1. **Run deployment script**
   ```bash
   sudo /opt/homeserver/scripts/deploy/deploy-phase2-infrastructure.sh
   ```

2. **Select option v: Validate all**
   ```
   Select option [0,c,2.1-2.3,3.1,4.1,v,q]: v
   ```

3. **Review validation results**
   ```
   Phase 02 Infrastructure Validation
   ===================================
   1. DNS Service...................... ✓ PASS
   2. DNS Resolution................... ✓ PASS
   3. External DNS..................... ✓ PASS
   4. Caddy Service.................... ✓ PASS
   5. Caddy HTTPS...................... ✓ PASS
   6. Certificate Trust................ ✓ PASS
   7. SMTP Service..................... ✓ PASS
   8. SMTP Test........................ ✓ PASS
   9. Netdata Service.................. ✓ PASS
   10. Netdata Dashboard............... ✓ PASS
   11. Data Structure.................. ✓ PASS
   12. Family Subdirectories........... ✓ PASS
   13. Backup Subdirectories........... ✓ PASS
   14. services.yaml................... ✓ PASS
   15. Git Commit...................... ✓ PASS

   ========================================
   Results: 15/15 checks passed
   ========================================
   ✓ All checks passed! Phase 02 complete.
   ```

**Verification Checklist**:
- [ ] All 15 automated checks pass
- [ ] No errors in validation output

### Manual Validation

**Objective**: Verify infrastructure services work from client devices

**Steps**:

1. **Test DNS resolution**
   ```bash
   # From admin laptop
   nslookup test.home.mydomain.com
   # Should return: 192.168.1.2
   ```

2. **Test HTTPS access**
   - Open browser
   - Navigate to https://test.home.mydomain.com
   - Verify: Browser shows "Secure" (no warnings)

3. **Test email delivery**
   ```bash
   # On server
   echo "Test email from home server" | mail -s "Test Email" admin@mydomain.com
   # Check admin inbox for email (within 5 minutes)
   ```

4. **Test Netdata dashboard**
   - Open browser
   - Navigate to https://monitor.home.mydomain.com
   - Verify: Dashboard loads with real-time metrics

5. **Test from mobile device**
   - Connect mobile to home WiFi
   - Open browser
   - Navigate to https://test.home.mydomain.com
   - Verify: Works (may need to install root CA on mobile)

**Verification Checklist**:
- [ ] DNS resolves internal hostnames
- [ ] HTTPS shows "Secure" (no warnings)
- [ ] Test email received
- [ ] Netdata dashboard accessible
- [ ] Mobile access works

## Troubleshooting

### Issue: DNS not resolving internal domains

**Symptoms**: nslookup test.home.mydomain.com fails

**Solution**:
1. Check Pi-hole container running: `docker ps | grep pihole`
2. Check DNS records: `docker exec pihole cat /etc/pihole/custom.list`
3. Restart Pi-hole DNS: `docker exec pihole pihole reloaddns`
4. Test DNS directly: `nslookup test.home.mydomain.com 192.168.1.2`

### Issue: systemd-resolved interfering with DNS

**Symptoms**: 
- /etc/resolv.conf points to 127.0.0.53 instead of 127.0.0.1
- DNS queries fail or timeout
- Pi-hole not receiving DNS queries

**Solution**:
1. Stop and disable systemd-resolved:
   ```bash
   sudo systemctl stop systemd-resolved
   sudo systemctl disable systemd-resolved
   ```

2. Remove symlink and create static resolv.conf:
   ```bash
   sudo rm /etc/resolv.conf
   echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
   ```

3. Make resolv.conf immutable:
   ```bash
   sudo chattr +i /etc/resolv.conf
   ```

4. Verify configuration:
   ```bash
   cat /etc/resolv.conf
   # Should show: nameserver 127.0.0.1
   
   systemctl status systemd-resolved
   # Should show: inactive (dead)
   ```

5. Restart containers after DNS changes:
   ```bash
   docker restart pihole
   sleep 30
   docker restart caddy
   docker restart jellyfin
   ```

6. Test DNS resolution:
   ```bash
   dig @127.0.0.1 google.com
   # Should return IP address
   ```

**Reference**: See docs/13-container-restart-procedure.md for detailed container restart procedures.

### Issue: Network unreachability after DNS changes

**Symptoms**:
- Ping to server fails or has high latency
- SSH connection takes 30+ seconds
- HTTPS services unresponsive

**Solution**:
1. Verify /etc/resolv.conf configuration (see above)
2. Restart Pi-hole container
3. Restart dependent containers (Caddy, Jellyfin)
4. Test external access from laptop/phone

**Reference**: See docs/12-runbooks.md for complete network unreachability troubleshooting.

### Issue: Browser shows certificate warning

**Symptoms**: "Your connection is not private" or "NET::ERR_CERT_AUTHORITY_INVALID"

**Solution**:
1. Verify root CA certificate installed on client device
2. Restart browser after installing certificate
3. Check certificate issued by Caddy: `curl -vk https://test.home.mydomain.com 2>&1 | grep issuer`
4. Re-export and re-install root CA if needed

### Issue: Email not sending

**Symptoms**: Test email not received

**Solution**:
1. Check SMTP container running: `docker ps | grep smtp`
2. Check SMTP logs: `docker logs smtp`
3. Verify SMTP credentials in services.env
4. Test SMTP relay: `telnet smtp.gmail.com 587`
5. Check Gmail app password (not regular password)

### Issue: Netdata dashboard not accessible

**Symptoms**: https://monitor.home.mydomain.com fails to load

**Solution**:
1. Check Netdata container running: `docker ps | grep netdata`
2. Check Caddy routing: `docker exec caddy caddy list-routes`
3. Check DNS record: `nslookup monitor.home.mydomain.com 192.168.1.2`
4. Test direct access: `curl http://localhost:19999`

## Next Steps

After Phase 02 completion:
1. Verify all 15 validation checks pass
2. Install root CA on all family devices
3. Configure router DHCP to advertise DNS server
4. Test from multiple devices (laptop, mobile, tablet)
5. Create snapshot of current state
6. Proceed to Phase 03: Core Services Layer
7. See `.kiro/specs/03-core-services/` for Phase 03 spec (when available)

## Appendix A: SMTP Relay Configuration

### Gmail SMTP

**Requirements**:
- Gmail account
- 2-factor authentication enabled
- App password generated

**Configuration**:
- SMTP host: smtp.gmail.com
- SMTP port: 587
- Username: your-email@gmail.com
- Password: 16-character app password (not regular password)

**Generate App Password**:
1. Go to https://myaccount.google.com/security
2. Enable 2-Step Verification
3. Go to App passwords
4. Select "Mail" and "Other (Custom name)"
5. Enter "Home Server"
6. Copy 16-character password

### SendGrid SMTP

**Requirements**:
- SendGrid account (free tier: 100 emails/day)
- API key generated

**Configuration**:
- SMTP host: smtp.sendgrid.net
- SMTP port: 587
- Username: apikey
- Password: Your SendGrid API key

### Mailgun SMTP

**Requirements**:
- Mailgun account (free tier: 5000 emails/month)
- SMTP credentials generated

**Configuration**:
- SMTP host: smtp.mailgun.org
- SMTP port: 587
- Username: Your Mailgun SMTP username
- Password: Your Mailgun SMTP password

## Appendix B: Reference Commands

### Service Status

```bash
# Pi-hole
docker ps | grep pihole
docker logs pihole

# Caddy
docker ps | grep caddy
docker logs caddy

# SMTP
docker ps | grep smtp
docker logs smtp

# Netdata
docker ps | grep netdata
docker logs netdata
```

### DNS Testing

```bash
# Test internal DNS
nslookup test.home.mydomain.com 192.168.1.2

# Test external DNS
nslookup google.com 192.168.1.2

# Check DNS records
docker exec pihole cat /etc/pihole/custom.list

# Restart DNS
docker exec pihole pihole restartdns
```

### Certificate Management

```bash
# Export root CA
docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > /opt/homeserver/configs/caddy/root-ca.crt

# Check certificate
openssl x509 -in /opt/homeserver/configs/caddy/root-ca.crt -text -noout

# Test HTTPS
curl -vk https://test.home.mydomain.com
```

### Email Testing

```bash
# Send test email
echo "Test email" | mail -s "Test" admin@mydomain.com

# Check SMTP logs
docker logs smtp

# Test SMTP relay
telnet smtp.gmail.com 587
```

---

**End of Phase 02 Infrastructure Services Layer Deployment Manual**
