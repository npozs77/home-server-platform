# Runbooks

Operational procedures for troubleshooting and resolving common issues.

---

## Network Unreachability

**Symptoms**:
- Ping to server fails or has high latency
- SSH connection takes 30+ seconds to establish
- HTTPS services unresponsive or timeout
- DNS queries fail or timeout

**Root Causes**:
- Pi-hole DNS container down or unhealthy
- systemd-resolved interfering with DNS
- Incorrect /etc/resolv.conf configuration
- iptables blocking traffic
- Container networking issues

**Diagnosis**:

1. Check DNS configuration:
   ```bash
   cat /etc/resolv.conf
   # Should show: nameserver 127.0.0.1
   ```

2. Check systemd-resolved status:
   ```bash
   systemctl status systemd-resolved
   # Should be: inactive (dead)
   ```

3. Check Pi-hole container health:
   ```bash
   docker ps | grep pihole
   # Should show: (healthy)
   ```

4. Check container health status:
   ```bash
   docker inspect pihole --format='{{.State.Health.Status}}'
   # Should return: healthy
   ```

5. Test DNS resolution:
   ```bash
   dig @127.0.0.1 google.com
   # Should return IP address
   ```

6. Check iptables rules:
   ```bash
   sudo iptables -L -n
   # Verify no DROP rules blocking traffic
   ```

**Resolution**:

1. If systemd-resolved is active:
   ```bash
   sudo systemctl stop systemd-resolved
   sudo systemctl disable systemd-resolved
   sudo rm /etc/resolv.conf
   echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
   sudo chattr +i /etc/resolv.conf
   ```

2. If Pi-hole container unhealthy:
   ```bash
   docker restart pihole
   sleep 30
   docker ps | grep pihole  # Verify (healthy)
   ```

3. If DNS still not working:
   ```bash
   docker stop pihole
   docker rm pihole
   # Re-run Phase 2 Task 7: Deploy Pi-hole
   cd /opt/homeserver
   sudo ./scripts/deploy/deploy-phase2-infrastructure.sh
   # Select option 7
   ```

4. Restart dependent containers:
   ```bash
   docker restart caddy
   docker restart jellyfin
   # Wait 30 seconds for health checks
   docker ps  # Verify all show (healthy)
   ```

5. Test external access:
   ```bash
   # From external device (laptop/phone):
   ping 192.168.1.2
   ssh user@192.168.1.2
   curl -I https://pihole.home.mydomain.com
   ```

**Prevention**:
- Monitor container health with cron job (check-container-health.sh runs every 15 minutes via /etc/cron.d/homeserver-cron)
- Ensure /etc/resolv.conf is immutable: `sudo chattr +i /etc/resolv.conf`
- Verify systemd-resolved stays disabled after system updates
- Add HEALTHCHECK to all critical containers (Pi-hole, Caddy, Jellyfin)

**Related Documentation**:
- docs/02-infrastructure-layer.md (DNS configuration)
- docs/13-container-restart-procedure.md (Container restart procedure)
- scripts/operations/monitoring/check-container-health.sh (Health monitoring)

---

## LUKS Disk Encryption Recovery

Reference procedures for LUKS-encrypted partitions on this server. Commands with brief context — not a tutorial.

### Key Slot Inventory

| Partition | Device | Mapper Name | Slot 0 | Slot 1 |
|-----------|--------|-------------|--------|--------|
| Data | `/dev/nvme0n1p3` | `data_crypt` | Passphrase | `/root/.luks-key` |
| Backup (DAS) | `/dev/sdb2` | `backup_crypt` | Passphrase | `/root/.luks-key` |

Both partitions use the same passphrase and the same key file.

### Verify Key Slots

```bash
sudo cryptsetup luksDump /dev/nvme0n1p3 | grep -A1 "Key Slot"
sudo cryptsetup luksDump /dev/sdb2 | grep -A1 "Key Slot"
```

Expect slot 0 (passphrase) and slot 1 (key file) to show `ENABLED`.

### Manual Unlock (Auto-Unlock Failed)

Data partition:
```bash
sudo cryptsetup luksOpen /dev/nvme0n1p3 data_crypt
sudo mount /dev/mapper/data_crypt /mnt/data
```

Backup partition (DAS):
```bash
sudo cryptsetup luksOpen /dev/sdb2 backup_crypt
sudo mount /dev/mapper/backup_crypt /mnt/backup
```

### Key File Lost or Corrupted

Unlock with passphrase (slot 0), then regenerate the key file and re-add to both partitions:

```bash
# Unlock with passphrase
sudo cryptsetup luksOpen /dev/nvme0n1p3 data_crypt

# Regenerate key file
sudo dd if=/dev/urandom of=/root/.luks-key bs=1024 count=4
sudo chmod 600 /root/.luks-key

# Remove old key slot 1 and add new key file to both partitions
sudo cryptsetup luksRemoveKey /dev/nvme0n1p3 --key-slot 1
sudo cryptsetup luksAddKey /dev/nvme0n1p3 /root/.luks-key
sudo cryptsetup luksRemoveKey /dev/sdb2 --key-slot 1
sudo cryptsetup luksAddKey /dev/sdb2 /root/.luks-key
```

Verify both partitions have the new key file:
```bash
sudo cryptsetup luksDump /dev/nvme0n1p3 | grep "Key Slot 1"
sudo cryptsetup luksDump /dev/sdb2 | grep "Key Slot 1"
```

### Passphrase Forgotten

Unlock with key file (slot 1), then add a new passphrase:

```bash
# Unlock with key file
sudo cryptsetup luksOpen --key-file /root/.luks-key /dev/nvme0n1p3 data_crypt

# Add new passphrase to both partitions
sudo cryptsetup luksAddKey --key-file /root/.luks-key /dev/nvme0n1p3
sudo cryptsetup luksAddKey --key-file /root/.luks-key /dev/sdb2
```

### LUKS Header Corrupted

Restore from header backup:

```bash
# Data partition
sudo cryptsetup luksHeaderRestore /dev/nvme0n1p3 \
    --header-backup-file /root/luks-header-backup-nvme0n1p3.img

# Backup partition (DAS)
sudo cryptsetup luksHeaderRestore /dev/sdb2 \
    --header-backup-file /root/luks-header-backup-sdb2.img
```

Header backups are also stored on the DAS at `/mnt/backup/configs/system/`.

### Create / Refresh Header Backups

```bash
sudo cryptsetup luksHeaderBackup /dev/nvme0n1p3 \
    --header-backup-file /root/luks-header-backup-nvme0n1p3.img
sudo cryptsetup luksHeaderBackup /dev/sdb2 \
    --header-backup-file /root/luks-header-backup-sdb2.img
sudo chmod 600 /root/luks-header-backup-*.img
```

Copy header backups to a USB drive and store offline.

### DAS Not Opening at Boot

The DAS is configured with `nofail,noauto` in crypttab, so it is intentionally not auto-opened at boot. To open and mount manually:

```bash
sudo cryptsetup luksOpen /dev/sdb2 backup_crypt
sudo mount /dev/mapper/backup_crypt /mnt/backup
```

To verify it's mounted:
```bash
mountpoint -q /mnt/backup && echo "MOUNTED" || echo "NOT MOUNTED"
```

### Both Keys Lost (Passphrase + Key File)

If both the passphrase and key file are lost, the encrypted data is **unrecoverable**. There is no backdoor.

This is why you must:
1. Store the LUKS passphrase in a password manager
2. Keep header backups on a USB drive stored offline
3. Run `backup-configs.sh` regularly (copies header backups to DAS)

**Related Documentation**:
- scripts/backup/setup-das-luks.sh (DAS LUKS setup script)
- scripts/backup/backup-configs.sh (backs up header files to DAS)

---
