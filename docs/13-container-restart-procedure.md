# Container Restart Procedure

Procedure for restarting Docker containers after network/DNS configuration changes.

---

## When to Restart Containers

Restart containers in these scenarios:

1. **After DNS configuration changes**:
   - Modified /etc/resolv.conf
   - Restarted Pi-hole container
   - Changed systemd-resolved configuration

2. **After network configuration changes**:
   - Modified UFW firewall rules
   - Changed iptables rules
   - Modified Docker network settings

3. **After container configuration changes**:
   - Updated environment variables
   - Modified volume mounts
   - Changed HEALTHCHECK settings

4. **When containers show unhealthy status**:
   - `docker ps` shows `(unhealthy)` or `(starting)`
   - Health checks failing repeatedly
   - Services unresponsive

---

## Restart Order

Always restart containers in this order to maintain service dependencies:

1. **Pi-hole** (DNS) - Must be first, other services depend on DNS
2. **Caddy** (Reverse Proxy) - Routes traffic to services
3. **Application Services** (Jellyfin, Immich, etc.) - Depend on DNS and proxy

---

## Restart Procedures

### Individual Container Restart

For single container restart (e.g., Pi-hole):

```bash
# Stop container
docker stop pihole

# Remove container (preserves volumes)
docker rm pihole

# Recreate container (use deployment script or docker run)
cd /opt/homeserver
sudo ./scripts/deploy/deploy-phase2-infrastructure.sh
# Select option 7 (Deploy Pi-hole)

# Verify health
docker ps | grep pihole
# Should show: (healthy) after 60 seconds
```

### Multiple Container Restart

For restarting multiple containers:

```bash
# Restart in dependency order
docker restart pihole
sleep 30  # Wait for Pi-hole to become healthy

docker restart caddy
sleep 10  # Wait for Caddy to become healthy

docker restart jellyfin
sleep 10  # Wait for Jellyfin to become healthy

# Verify all healthy
docker ps
# All should show (healthy)
```

### Full Docker Service Restart

Only use if Docker daemon itself has issues:

```bash
# Stop all containers gracefully
docker stop $(docker ps -q)

# Restart Docker daemon
sudo systemctl restart docker

# Wait for Docker to start
sleep 10

# Start containers in order
docker start pihole
sleep 30

docker start caddy
sleep 10

docker start jellyfin
sleep 10

# Verify all healthy
docker ps
```

---

## Validation After Restart

After restarting containers, validate functionality:

### 1. Check Container Health

```bash
docker ps
# All containers should show (healthy)
```

### 2. Check DNS Resolution

```bash
dig @127.0.0.1 google.com
# Should return IP address
```

### 3. Test Inbound Traffic from External Device

From laptop or phone on same network:

```bash
# Test ping
ping 192.168.1.2
# Should respond with <1ms latency

# Test SSH
time ssh user@192.168.1.2 'echo OK'
# Should connect in <2 seconds

# Test HTTPS services
curl -I https://pihole.home.mydomain.com
# Should return HTTP 200 OK

curl -I https://jellyfin.home.mydomain.com
# Should return HTTP 200 OK
```

### 4. Check Container Logs

If any service not working:

```bash
# Check Pi-hole logs
docker logs pihole | tail -50

# Check Caddy logs
docker logs caddy | tail -50

# Check Jellyfin logs
docker logs jellyfin | tail -50
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs for errors
docker logs <container>

# Check if port already in use
sudo netstat -tlnp | grep <port>

# Check if volume mounts exist
ls -la /opt/homeserver/configs/<service>/
```

### Container Starts But Unhealthy

```bash
# Check health check command
docker inspect <container> --format='{{.State.Health}}'

# Test health check manually
docker exec <container> <health-check-command>

# Example for Pi-hole:
docker exec pihole dig @127.0.0.1 google.com
```

### DNS Not Working After Restart

```bash
# Verify /etc/resolv.conf
cat /etc/resolv.conf
# Should show: nameserver 127.0.0.1

# Verify systemd-resolved disabled
systemctl status systemd-resolved
# Should show: inactive (dead)

# Restart Pi-hole
docker restart pihole
sleep 30

# Test DNS
dig @127.0.0.1 google.com
```

---

## Related Documentation

- docs/12-runbooks.md (Network Unreachability troubleshooting)
- docs/02-infrastructure-layer.md (Infrastructure architecture)
- scripts/operations/monitoring/check-container-health.sh (Health monitoring)
