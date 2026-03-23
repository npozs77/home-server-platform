# Phase 04 - Photo Management Deployment Manual

**Version**: 1.0  
**Status**: Ready for Deployment  
**Estimated Time**: 4-6 hours

## Overview

Deploy Immich as the primary photo management service with mobile-first backup, AI-powered face recognition, and integration with existing photo directories. Implementation follows the three-layer modular architecture with orchestration script, task modules, and reusable utility libraries.

## Prerequisites

**Phase 1 (Foundation Layer) Complete**:
- LUKS encrypted /mnt/data/ mounted and auto-unlocking
- UFW firewall active (LAN-only, HTTPS allowed)
- SSH hardening configured

**Phase 2 (Infrastructure Layer) Complete**:
- Pi-hole DNS running (internal domain resolution)
- Caddy reverse proxy running (HTTPS routing)
- Netdata monitoring running
- SMTP relay configured (email alerts)

**Phase 3 (Core Services Layer) Complete**:
- Samba file sharing running with role-based permissions
- User provisioning complete (Linux users, Samba users)
- Media system user and group created (media:media, GID known)
- /mnt/data/media/Photos/ and /mnt/data/family/Photos/ exist

**Reference Documents**:
- Requirements: `.kiro/specs/04-photo-management/requirements.md`
- Design: `.kiro/specs/04-photo-management/design.md`
- Tasks: `.kiro/specs/04-photo-management/tasks.md`
- Phase 3 Manual: `docs/deployment_manuals/phase3-core-services.md`

## Quick Start

1. Copy scripts to server: `scp -r scripts/ admin@192.168.1.2:/opt/homeserver/`
2. Copy configs to server: `scp -r configs/ admin@192.168.1.2:/opt/homeserver/`
3. SSH to server: `ssh admin@192.168.1.2`
4. Run: `sudo ./scripts/deploy/deploy-phase4-photo-management.sh`
5. Execute tasks sequentially
6. Complete Immich setup wizard via browser
7. Install mobile apps

## Pre-Deployment Checklist

- [ ] Phase 3 validation passes all checks
- [ ] Server accessible via SSH (192.168.1.2)
- [ ] /mnt/data/ mounted and writable
- [ ] Docker service running
- [ ] Caddy reverse proxy running
- [ ] Pi-hole DNS running
- [ ] media group exists (GID known)
- [ ] /mnt/data/media/Photos/ exists
- [ ] /mnt/data/family/Photos/ exists

**Verification Commands**:
```bash
ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2

# Check Phase 3 status
docker ps  # Should show caddy, pihole, netdata, samba, jellyfin

# Check media group
getent group media  # Should return media:x:1002:...

# Check photo directories
ls -la /mnt/data/media/Photos/
ls -la /mnt/data/family/Photos/
```

## Task 0: Copy Deployment Artifacts to Server

**Objective**: Copy Phase 4 scripts, configs, and documentation to server

```bash
# From admin laptop
scp scripts/deploy/deploy-phase4-photo-management.sh admin@192.168.1.2:/opt/homeserver/scripts/deploy/
scp -r scripts/deploy/tasks/task-ph4-*.sh admin@192.168.1.2:/opt/homeserver/scripts/deploy/tasks/
scp configs/docker-compose/immich.yml.example admin@192.168.1.2:/opt/homeserver/configs/docker-compose/
scp configs/services.env.example admin@192.168.1.2:/opt/homeserver/configs/
scp configs/secrets.env.example admin@192.168.1.2:/opt/homeserver/configs/
scp -r scripts/operations/utils/immich/ admin@192.168.1.2:/opt/homeserver/scripts/operations/utils/
scp -r scripts/backup/backup-immich.sh admin@192.168.1.2:/opt/homeserver/scripts/backup/

# SSH to server
ssh -i ~/.ssh/id_ed25519_homeserver admin@192.168.1.2
```

## Task 1: Create Immich Directories

```bash
sudo ./scripts/deploy/tasks/task-ph4-01-create-immich-directories.sh
```

Creates:
- /mnt/data/services/immich/postgres (PostgreSQL data)
- /mnt/data/services/immich/upload (mobile uploads)

**Verify**:
```bash
ls -la /mnt/data/services/immich/
```

## Task 2: Deploy Immich Docker Compose Stack

```bash
sudo ./scripts/deploy/tasks/task-ph4-02-deploy-immich-stack.sh
```

Starts all Immich containers: immich-server, immich-ml, immich-redis, immich-postgres.

**Verify**:
```bash
docker ps | grep immich
# All 4 containers should show (healthy) after ~2 minutes
```

## Task 3: Configure Caddy Reverse Proxy

```bash
sudo ./scripts/deploy/tasks/task-ph4-03-configure-caddy.sh
```

Adds photos.home.mydomain.com → immich-server:2283 routing with TLS internal.

**Verify**:
```bash
curl -k https://photos.home.mydomain.com
# Should return HTTP 200
```

## Task 4: Configure Pi-hole DNS

```bash
sudo ./scripts/deploy/tasks/task-ph4-04-configure-dns.sh
```

Adds DNS record: 192.168.1.2 photos.home.mydomain.com

**Verify**:
```bash
dig @127.0.0.1 photos.home.mydomain.com
# Should return 192.168.1.2
```

## Task 5: Complete Immich Setup Wizard (Manual)

1. Open https://photos.home.mydomain.com in browser
2. Complete setup wizard — first user becomes administrator
3. Set admin password (Immich-specific, NOT Linux password)
4. Generate API key: User Settings → API Keys → New API Key
5. Store API key:
   ```bash
   echo 'IMMICH_API_KEY="your-api-key-here"' >> /opt/homeserver/configs/secrets.env
   chmod 600 /opt/homeserver/configs/secrets.env
   ```

## Task 6: Provision Immich Users

```bash
sudo ./scripts/deploy/tasks/task-ph4-05-provision-immich-users.sh
```

Creates Immich accounts for all family users via REST API. Captures UUIDs to services.env.

**Verify**:
```bash
grep IMMICH_UUID /opt/homeserver/configs/services.env
# Should show UUID for each user
```

## Task 7: Configure Samba Upload Shares

```bash
sudo ./scripts/deploy/tasks/task-ph4-06-configure-samba-uploads.sh
```

Creates:
- `[all-uploads]` — admin + power users read-only share covering all users' upload libraries (for consolidated curation)
- `[{username}-uploads]` — per-user read-only shares for individual upload browsing (all users)

**Verify**:
```bash
grep "\-uploads\]\|all-uploads" /opt/homeserver/configs/samba/smb.conf
# Should show [all-uploads] and [username-uploads] entries
```

## Task 8: Deploy Backup Script

```bash
sudo ./scripts/deploy/tasks/task-ph4-07-deploy-backup-script.sh
```

Installs backup-immich.sh with pg_dump (database) and rsync (files).

**Verify**:
```bash
ls -la /opt/homeserver/scripts/backup/backup-immich.sh
# Should exist and be executable
```

## Task 9: Verify Documentation

All Phase 4 documentation is in the Git repo and was scp'd to the server. Verify files are present:
```bash
ls -la /opt/homeserver/docs/deployment_manuals/phase4-photo-management.md
ls -la /opt/homeserver/docs/09-immich-setup.md
ls -la /opt/homeserver/docs/05-storage.md
ls -la /opt/homeserver/docs/13-container-restart-procedure.md
```

## Task 10: Configure External Libraries (Manual)

1. Access https://photos.home.mydomain.com → Administration
2. External Libraries → Create Library (Owner: admin)
3. Add import paths (container-internal paths):
   - `/mnt/media/Photos` (maps to host /mnt/data/media/Photos, read-only)
   - `/mnt/family/Photos` (maps to host /mnt/data/family/Photos, read-only)
4. Scan schedule: `0 0 * * *` (daily at midnight)
5. Trigger initial manual scan
6. Verify existing photos appear in timeline

**Verify mounts**:
```bash
docker inspect immich-server --format \
  '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Mode}}){{println}}{{end}}'
```

## Task 11: Validate Phase 4

```bash
sudo ./scripts/deploy/deploy-phase4-photo-management.sh
# Select option: v (Validate all)
```

**Expected Output**:
```
Phase 04 Photo Management Validation
=====================================
Immich Directories             ✓ PASS
Docker Compose File            ✓ PASS
Immich Containers Running      ✓ PASS
Caddy Routing                  ✓ PASS
DNS Resolution                 ✓ PASS
HTTPS Access                   ✓ PASS
External Library Mounts        ✓ PASS
Upload Directory Writable      ✓ PASS
Samba Upload Shares            ✓ PASS
Backup Script                  ✓ PASS
Version Pinned                 ✓ PASS
Secrets Not in Git             ✓ PASS

Results: 12/12 checks passed
```

## Task 12: Git Commit

```bash
cd /opt/homeserver
git add configs/docker-compose/immich.yml configs/caddy/Caddyfile \
  scripts/deploy/ docs/ tests/
# Verify secrets.env is NOT staged
git diff --cached --name-only | grep -v secrets
git commit -m "Complete Phase 4: Photo Management with Immich"
git tag v1.0-phase4
```

## Post-Deployment Tasks

### Test Mobile App

1. Install Immich app (iOS App Store / Google Play)
2. Server URL: https://photos.home.mydomain.com
3. Log in with Immich credentials
4. Enable automatic backup (WiFi only)
5. Verify photos upload when on home WiFi

### Configure Backup Cron (When DAS HDD Available)

```bash
# Add to /etc/cron.d/immich-backup
0 2 * * * root /opt/homeserver/scripts/backup/backup-immich.sh /mnt/backup/immich >> /var/log/immich-backup.log 2>&1
```

## Troubleshooting

### Containers Not Starting

```bash
docker compose -f /opt/homeserver/configs/docker-compose/immich.yml logs
docker ps -a | grep immich
```

### Database Connection Errors

```bash
docker exec immich-postgres pg_isready -U postgres -d immich
docker logs immich-postgres | tail -20
```

### ML Model Download Slow

First startup downloads ~1.7GB of ML models. Allow 5-10 minutes.
```bash
docker logs immich-ml | tail -20
```

### HTTPS Not Working

```bash
dig @127.0.0.1 photos.home.mydomain.com
curl -k https://photos.home.mydomain.com
docker logs caddy | grep photos
```

### Face Recognition Not Working

- Verify immich-ml is healthy: `docker ps | grep immich-ml`
- Check ML logs: `docker logs immich-ml`
- Face recognition runs in background after upload; allow time for processing

### Samba Upload Shares Not Visible

```bash
# Check Samba config
grep -A 5 "uploads" /opt/homeserver/configs/samba/smb.conf
# Check Samba container has upload volume mounted
docker inspect samba --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
```

### Backup Fails

```bash
# Test pg_dump manually
docker exec immich-postgres pg_dump -U postgres -d immich > /dev/null
echo $?  # Should be 0

# Check backup destination
ls -la /mnt/backup/immich/
df -h /mnt/backup/
```

## Next Steps

- Test Samba upload share access from all client devices
- Test mobile app backup from iOS and Android
- Add media files to external library directories
- Configure nightly backup cron when DAS HDD available
- Proceed to Phase 5 (if planned)
