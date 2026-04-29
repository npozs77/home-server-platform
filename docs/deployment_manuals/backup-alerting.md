# Backup & Alerting Deployment Manual

**Version**: 1.0
**Status**: Ready for Deployment
**Estimated Time**: 1-2 hours

## Overview

Deploy DAS LUKS backup target, backup orchestration (configs, Immich, Wiki+LLM), container health monitoring with email alerts, independent backup status watchdog, and cron scheduling.

## Prerequisites

**Phase 2 (Infrastructure Layer) Complete**:
- msmtp installed and configured (tasks 2.09–2.11) — required for email alerts
- Caddy, Pi-hole, Netdata containers running

**Phase 4 (Photo Management) Complete**:
- Immich fully deployed with `backup-immich.sh` functional

**Hardware**:
- DAS physically connected to server (`/dev/sdb2` partition available)
- LUKS passphrase ready (same as data partition)

**Reference Documents**:
- Requirements: `.kiro/specs/backup-alerting/requirements.md`
- Design: `.kiro/specs/backup-alerting/design.md`
- Tasks: `.kiro/specs/backup-alerting/tasks.md`

## Pre-Deployment Checklist

- [ ] DAS physically connected and `/dev/sdb2` visible (`lsblk`)
- [ ] LUKS passphrase available (same as data partition)
- [ ] msmtp configured and working (`echo "test" | msmtp admin@example.com`)
- [ ] Server accessible via SSH
- [ ] Docker running with critical containers (caddy, pihole, immich-server, immich-postgres, jellyfin)

```bash
# Verify prerequisites
ssh homeserver 'lsblk | grep sdb'
ssh homeserver 'command -v msmtp && echo "msmtp OK"'
ssh homeserver 'docker ps --format "{{.Names}}" | sort'
```

## Step 1: Deploy Shared Utilities

```bash
# Copy log-utils.sh to server
scp scripts/operations/utils/log-utils.sh homeserver:/opt/homeserver/scripts/operations/utils/log-utils.sh

# Verify syntax
ssh homeserver 'bash -n /opt/homeserver/scripts/operations/utils/log-utils.sh'
```

## Step 2: DAS LUKS Setup

Backup disk variables (`BACKUP_DISK`, `BACKUP_MOUNT`, `BACKUP_MAPPER`) are configured in `foundation.env` (set during Phase 1 config initialization, option 0). Verify they're set:

```bash
ssh homeserver 'grep BACKUP /opt/homeserver/configs/foundation.env'
# Expected: BACKUP_DISK="/dev/sdb2", BACKUP_MOUNT="/mnt/backup", BACKUP_MAPPER="backup_crypt"
```

```bash
# Copy setup script
scp scripts/backup/setup-das-luks.sh homeserver:/opt/homeserver/scripts/backup/setup-das-luks.sh

# Dry-run first
ssh homeserver 'sudo /opt/homeserver/scripts/backup/setup-das-luks.sh --dry-run'

# Review dry-run output, then execute live (interactive — prompts for LUKS passphrase)
ssh -t homeserver 'sudo /opt/homeserver/scripts/backup/setup-das-luks.sh'
```

**For non-LUKS setup** (skip encryption):
```bash
ssh homeserver 'sudo /opt/homeserver/scripts/backup/setup-das-luks.sh --no-luks'
```

**Post-setup verification**:
```bash
ssh homeserver 'sudo cryptsetup isLuks /dev/sdb2'           # LUKS header exists
ssh homeserver 'mountpoint -q /mnt/backup && echo MOUNTED'   # Mount active
ssh homeserver 'grep backup_crypt /etc/crypttab'             # crypttab entry
ssh homeserver 'grep /mnt/backup /etc/fstab'                 # fstab entry
ssh homeserver 'ls -la /root/luks-header-backup-*.img'       # Header backups
```

## Step 3: Deploy Backup Scripts

```bash
# Copy all backup scripts
scp scripts/backup/backup-configs.sh homeserver:/opt/homeserver/scripts/backup/
scp scripts/backup/backup-immich.sh homeserver:/opt/homeserver/scripts/backup/
scp scripts/backup/backup-wiki-llm.sh homeserver:/opt/homeserver/scripts/backup/
scp scripts/backup/backup-all.sh homeserver:/opt/homeserver/scripts/backup/

# Verify syntax
ssh homeserver 'for f in backup-configs.sh backup-immich.sh backup-wiki-llm.sh backup-all.sh; do bash -n /opt/homeserver/scripts/backup/$f && echo "$f: OK"; done'

# Dry-run orchestrator
ssh homeserver 'sudo /opt/homeserver/scripts/backup/backup-all.sh --dry-run'
```

## Step 4: Deploy Health Check

```bash
# Copy health check script and config
ssh homeserver 'mkdir -p /opt/homeserver/configs/monitoring'
scp scripts/operations/monitoring/check-container-health.sh homeserver:/opt/homeserver/scripts/operations/monitoring/
scp configs/monitoring/critical-containers.conf homeserver:/opt/homeserver/configs/monitoring/

# Verify
ssh homeserver 'bash -n /opt/homeserver/scripts/operations/monitoring/check-container-health.sh'
ssh homeserver 'sudo /opt/homeserver/scripts/operations/monitoring/check-container-health.sh --dry-run'
```

## Step 5: Deploy Backup Status Watchdog

Independent safety net that runs at 06:00 (after the 02:00 backup window). Catches failures that the backup script itself can't report — crashes during env sourcing, hung processes, or cron not firing at all.

**What it checks**:
- Today's backup log exists (`/var/log/homeserver/backup-YYYYMMDD.log`)
- Log contains "All backup jobs completed successfully"
- Sends email alert if either check fails

```bash
# Copy watchdog script
scp scripts/operations/monitoring/check-backup-status.sh homeserver:/opt/homeserver/scripts/operations/monitoring/
ssh homeserver 'sudo chmod 755 /opt/homeserver/scripts/operations/monitoring/check-backup-status.sh'

# Verify syntax
ssh homeserver 'bash -n /opt/homeserver/scripts/operations/monitoring/check-backup-status.sh'

# Test manually (should report OK if backup ran today, FAILED/MISSING otherwise)
ssh homeserver 'sudo /opt/homeserver/scripts/operations/monitoring/check-backup-status.sh'
```

The cron entry is included in `homeserver-cron` (installed in Step 6):
```
0 6 * * * root /opt/homeserver/scripts/operations/monitoring/check-backup-status.sh >> /var/log/homeserver/health-check.log 2>&1
```

## Step 6: Install Cron and Logrotate

```bash
# Copy configs
ssh homeserver 'mkdir -p /opt/homeserver/configs/cron /opt/homeserver/configs/logrotate'
scp configs/cron/homeserver-cron homeserver:/opt/homeserver/configs/cron/
scp configs/logrotate/homeserver-backups homeserver:/opt/homeserver/configs/logrotate/

# Install cron
ssh homeserver 'sudo cp /opt/homeserver/configs/cron/homeserver-cron /etc/cron.d/homeserver-cron && sudo chmod 644 /etc/cron.d/homeserver-cron'

# Install logrotate
ssh homeserver 'sudo cp /opt/homeserver/configs/logrotate/homeserver-backups /etc/logrotate.d/homeserver-backups && sudo chmod 644 /etc/logrotate.d/homeserver-backups'

# Create log directory
ssh homeserver 'sudo mkdir -p /var/log/homeserver && sudo chmod 750 /var/log/homeserver'
```

## Step 7: Deploy Documentation

```bash
scp docs/12-runbooks.md homeserver:/opt/homeserver/docs/12-runbooks.md
```

## Step 8: Git Commit on Server

```bash
ssh homeserver 'cd /opt/homeserver && git add scripts/ configs/ docs/ && git commit -m "feat(backup): deploy backup-alerting system"'
```

## Validation Checklist

Run these 16 checks to verify the deployment:

```bash
# 1. LUKS container (skip if --no-luks)
ssh homeserver 'sudo cryptsetup isLuks /dev/sdb2 && echo "PASS: LUKS"'

# 2. Backup partition mounted
ssh homeserver 'mountpoint -q /mnt/backup && echo "PASS: Mounted"'

# 3. crypttab entry (skip if --no-luks)
ssh homeserver 'grep -q "backup_crypt.*nofail,noauto" /etc/crypttab && echo "PASS: crypttab"'

# 4. fstab entry
ssh homeserver 'grep -q "/mnt/backup.*nofail" /etc/fstab && echo "PASS: fstab"'

# 5. Backup directory structure
ssh homeserver 'ls -d /mnt/backup/configs/ /mnt/backup/immich/ /mnt/backup/wiki-llm/ 2>/dev/null && echo "PASS: Dirs"'

# 6. Backup scripts exist
ssh homeserver 'ls /opt/homeserver/scripts/backup/backup-all.sh /opt/homeserver/scripts/backup/backup-configs.sh /opt/homeserver/scripts/backup/backup-wiki-llm.sh && echo "PASS: Scripts"'

# 7. Immich backup retrofitted
ssh homeserver 'grep -q "mountpoint -q" /opt/homeserver/scripts/backup/backup-immich.sh && echo "PASS: Immich retrofit"'

# 8. Health check reads from config
ssh homeserver 'grep -q "critical-containers.conf" /opt/homeserver/scripts/operations/monitoring/check-container-health.sh && echo "PASS: Health config"'

# 9. Cron jobs configured
ssh homeserver 'grep -q "0 2 \* \* \*" /etc/cron.d/homeserver-cron && grep -q "\*/15 \* \* \* \*" /etc/cron.d/homeserver-cron && grep -q "0 6 \* \* \*" /etc/cron.d/homeserver-cron && echo "PASS: Cron"'

# 10. Log directory
ssh homeserver 'test -d /var/log/homeserver && stat -c "%a" /var/log/homeserver | grep -q "750" && echo "PASS: Log dir"'

# 11. Logrotate config
ssh homeserver 'test -f /etc/logrotate.d/homeserver-backups && echo "PASS: Logrotate"'

# 12. Mount guard (test with unmounted — skip if DAS always mounted)
echo "SKIP: Mount guard test (requires unmounting DAS)"

# 13. Disk space check
ssh homeserver 'grep -q "df.*mnt/backup" /opt/homeserver/scripts/backup/backup-all.sh && echo "PASS: Disk check"'

# 14. LUKS header backups
ssh homeserver 'ls /root/luks-header-backup-sdb2.img /root/luks-header-backup-nvme0n1p3.img 2>/dev/null && echo "PASS: Headers"'

# 15. LUKS runbook
ssh homeserver 'grep -q "LUKS Disk Encryption Recovery" /opt/homeserver/docs/12-runbooks.md && echo "PASS: Runbook"'

# 16. Backup status watchdog
ssh homeserver 'test -x /opt/homeserver/scripts/operations/monitoring/check-backup-status.sh && echo "PASS: Watchdog"'
```

## Troubleshooting

### DAS Not Mounting

**Symptoms**: `/mnt/backup/` not mounted, backup scripts exit with code 2

**Solutions**:
1. Check DAS is physically connected: `lsblk | grep sdb`
2. Open LUKS manually: `sudo cryptsetup luksOpen /dev/sdb2 backup_crypt`
3. Mount: `sudo mount /dev/mapper/backup_crypt /mnt/backup`
4. If LUKS header corrupted: see `docs/12-runbooks.md` → LUKS Disk Encryption Recovery

### Alerts Not Sending

**Symptoms**: No email alerts received when expected

**Solutions**:
1. Check msmtp installed: `command -v msmtp`
2. Test msmtp directly: `echo "test" | msmtp $ADMIN_EMAIL`
3. Check ADMIN_EMAIL set: `grep ADMIN_EMAIL /opt/homeserver/configs/foundation.env`
4. Check script logs: `cat /var/log/homeserver/backup-$(date +%Y%m%d).log | grep -i "msmtp\|email\|alert"`
5. If msmtp not configured, alerts are logged locally (scripts don't fail)

### Cron Not Running

**Symptoms**: Backups not running at 02:00, health checks not running every 15 min

**Solutions**:
1. Check cron service: `systemctl status cron`
2. Check cron file installed: `ls -la /etc/cron.d/homeserver-cron`
3. Check cron file permissions: should be `644` and owned by `root:root`
4. Check cron syntax: `cat /etc/cron.d/homeserver-cron`
5. Check cron logs: `grep CRON /var/log/syslog | tail -20`
6. Reinstall: `sudo cp /opt/homeserver/configs/cron/homeserver-cron /etc/cron.d/homeserver-cron && sudo chmod 644 /etc/cron.d/homeserver-cron`

### Backup Failing with Exit Code 1

**Symptoms**: Orchestrator reports job failures

**Solutions**:
1. Check log: `cat /var/log/homeserver/backup-$(date +%Y%m%d).log`
2. Run individual script manually: `sudo /opt/homeserver/scripts/backup/backup-configs.sh`
3. Check disk space: `df -h /mnt/backup/`
4. Check mount writable: `sudo touch /mnt/backup/.test && sudo rm /mnt/backup/.test`

## Related Documentation

- Storage: docs/05-storage.md
- Infrastructure Layer: docs/02-infrastructure-layer.md
- Foundation Layer: docs/01-foundation-layer.md
- Runbooks (LUKS Recovery): docs/12-runbooks.md
