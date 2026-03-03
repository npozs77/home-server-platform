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
- Monitor container health with cron job (check-container-health.sh runs every 5 minutes)
- Ensure /etc/resolv.conf is immutable: `sudo chattr +i /etc/resolv.conf`
- Verify systemd-resolved stays disabled after system updates
- Add HEALTHCHECK to all critical containers (Pi-hole, Caddy, Jellyfin)

**Related Documentation**:
- docs/02-infrastructure-layer.md (DNS configuration)
- docs/13-container-restart-procedure.md (Container restart procedure)
- scripts/operations/monitoring/check-container-health.sh (Health monitoring)

---
