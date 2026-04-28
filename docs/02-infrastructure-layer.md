# Infrastructure Layer - Operational Reference

## Overview

Infrastructure services layer providing DNS (Pi-hole), reverse proxy (Caddy), and monitoring (Netdata) for the home server platform.

## Network Architecture

- **Custom Docker Network**: `homeserver` - all infrastructure containers communicate via this network
- **Server IP**: 192.168.1.2 (DHCP reservation on router)
- **Internal Domain**: home.mydomain.com
- **DNS Server**: Pi-hole on 192.168.1.2:53 (advertised via router DHCP)

## Services

### Pi-hole (DNS)
- **Container**: pihole
- **Image**: pihole/pihole:latest
- **Network**: host networking (port 53 UDP/TCP, port 8888 HTTP)
- **Web Interface**: https://pihole.home.mydomain.com (proxied via Caddy)
- **Direct Access**: http://192.168.1.2:8888/admin
- **Config**: /opt/homeserver/configs/pihole/
- **Note**: Pi-hole v6 uses `FTLCONF_webserver_port` environment variable (not `WEB_PORT`)

### Caddy (Reverse Proxy)
- **Container**: caddy
- **Image**: caddy:alpine
- **Network**: homeserver
- **Ports**: 80 (HTTP), 443 (HTTPS)
- **Config**: /opt/homeserver/configs/caddy/Caddyfile
- **Root CA**: /opt/homeserver/configs/caddy/root-ca.crt

### Netdata (Monitoring)
- **Container**: netdata
- **Image**: netdata/netdata:latest
- **Network**: homeserver
- **Port**: 19999
- **Dashboard**: https://monitor.home.mydomain.com
- **Config**: /opt/homeserver/configs/netdata/

## Common Operations

### DNS Management

**Add DNS record**:
```bash
# Get current records
docker exec pihole pihole-FTL --config dns.hosts

# Add new record (replace entire list)
docker exec pihole pihole-FTL --config dns.hosts '["192.168.1.2 home.mydomain.com", "192.168.1.2 pihole.home.mydomain.com", "192.168.1.2 monitor.home.mydomain.com", "192.168.1.2 newservice.home.mydomain.com"]'
```

**Test DNS resolution**:
```bash
nslookup service.home.mydomain.com 192.168.1.2
```

**Check Pi-hole logs**:
```bash
docker logs pihole --tail 50
```

### Caddy Management

**Reload Caddyfile** (after in-place edit with `nano` or `sed`):
```bash
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

**Caddyfile update procedure** (when replacing the file via `cp` or `scp`):

The Caddyfile is bind-mounted as a single file. Docker holds a reference to the original inode. If you replace the file (via `cp`, `scp`, or redirect `>`), the container keeps reading the old inode and `caddy reload` silently uses stale config.

```bash
# WRONG — creates new inode, container won't see changes:
cp /tmp/new-Caddyfile /opt/homeserver/configs/caddy/Caddyfile
scp local-Caddyfile homeserver:/opt/homeserver/configs/caddy/Caddyfile

# RIGHT — edit in-place (preserves inode):
nano /opt/homeserver/configs/caddy/Caddyfile
sed -i 's/old/new/' /opt/homeserver/configs/caddy/Caddyfile

# OR — restart container after replacing file (picks up new inode):
cp /tmp/new-Caddyfile /opt/homeserver/configs/caddy/Caddyfile
docker restart caddy
```

Same applies to `starting.html` and any other single-file bind mount. Directory mounts (`/srv/pages`, `/data`, `/config`) are NOT affected — new files in a mounted directory are visible immediately.

**Check Caddy logs**:
```bash
docker logs caddy --tail 50
```

**Export root CA certificate**:
```bash
docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > /opt/homeserver/configs/caddy/root-ca.crt
chmod 644 /opt/homeserver/configs/caddy/root-ca.crt
```

**Add new service to Caddyfile**:
```bash
sudo nano /opt/homeserver/configs/caddy/Caddyfile
```
Add block (for container on homeserver network):
```
service.home.mydomain.com {
    reverse_proxy container-name:port
    tls internal
    log {
        output file /var/log/caddy/service-access.log
    }
    handle_errors {
        root * /srv/pages
        rewrite * /starting.html
        file_server
    }
}
```
Or for host networking service (e.g., Pi-hole):
```
service.home.mydomain.com {
    reverse_proxy DOCKER_GATEWAY_IP:port {
        header_up Host expected-hostname
    }
    tls internal
    log {
        output file /var/log/caddy/service-access.log
    }
    handle_errors {
        root * /srv/pages
        rewrite * /starting.html
        file_server
    }
}
```
Note: Host networking services can't be reached by container name from Caddy's bridge network.
Use the Docker gateway IP (`docker inspect caddy --format='{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'`).
UFW must allow traffic from Docker's bridge subnet (172.18.0.0/16) to the service port.
Then reload: `docker exec caddy caddy reload --config /etc/caddy/Caddyfile`

**handle_errors block**: Every site block must include the `handle_errors` block above. When a backend container is down, Caddy serves `/srv/pages/starting.html` (a friendly "starting up" page with auto-retry) instead of a raw 502/503 error. The page auto-refreshes every 5 seconds until the service is back.

**Startup page location**: `/opt/homeserver/configs/caddy/pages/starting.html` (mounted read-only at `/srv/pages` in the Caddy container).

### Container Management

**Check running containers**:
```bash
docker ps
# Look for (healthy) status
```

**Check container health**:
```bash
docker inspect <container> --format='{{.State.Health.Status}}'
# Should return: healthy
```

**Restart a service**:
```bash
docker restart <container-name>
# Wait 30 seconds for health check
docker ps | grep <container-name>  # Verify (healthy)
```

**View container logs**:
```bash
docker logs <container-name> --tail 50
docker logs <container-name> -f  # follow mode
```

**Remove and redeploy container**:
```bash
docker stop <container-name>
docker rm <container-name>
# Then run docker run command from deployment script
```

**Pi-hole deployment command** (for reference):
```bash
docker run -d \
    --name pihole \
    --restart unless-stopped \
    --network host \
    -e TZ="America/New_York" \
    -e WEBPASSWORD="$PIHOLE_PASSWORD" \
    -e DNSMASQ_LISTENING="all" \
    -e DNS1="8.8.8.8" \
    -e DNS2="1.1.1.1" \
    -e FTLCONF_webserver_api=1 \
    -e FTLCONF_webserver_port=8888 \
    -v /opt/homeserver/configs/pihole/etc-pihole:/etc/pihole \
    -v /opt/homeserver/configs/pihole/etc-dnsmasq.d:/etc/dnsmasq.d \
    --health-cmd "dig @127.0.0.1 google.com || exit 1" \
    --health-interval 30s \
    --health-timeout 10s \
    --health-retries 3 \
    --health-start-period 60s \
    pihole/pihole:latest
```

**Caddy deployment command** (for reference):
```bash
docker run -d \
    --name caddy \
    --restart unless-stopped \
    --network homeserver \
    -p 80:80 \
    -p 443:443 \
    -v /opt/homeserver/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
    -v /opt/homeserver/configs/caddy/data:/data \
    -v /opt/homeserver/configs/caddy/config:/config \
    -v /var/log/caddy:/var/log/caddy \
    -v /opt/homeserver/configs/caddy/pages:/srv/pages:ro \
    --health-cmd "curl -f http://localhost:80 || exit 1" \
    --health-interval 30s \
    --health-timeout 10s \
    --health-retries 3 \
    --health-start-period 30s \
    caddy:alpine
```

### Network Management

**List Docker networks**:
```bash
docker network ls
```

**Inspect homeserver network**:
```bash
docker network inspect homeserver
```

**Connect container to homeserver network**:
```bash
docker network connect homeserver <container-name>
```

### Firewall Management

**Check UFW status**:
```bash
sudo ufw status numbered
```

**Allow service from LAN**:
```bash
sudo ufw allow from 192.168.1.0/24 to any port <port> proto tcp
sudo ufw allow from 192.168.1.0/24 to any port <port> proto udp
```

**Required ports for Phase 2**:
```bash
# DNS (Pi-hole)
sudo ufw allow from 192.168.1.0/24 to any port 53 proto udp
sudo ufw allow from 192.168.1.0/24 to any port 53 proto tcp

# Pi-hole web interface
sudo ufw allow from 192.168.1.0/24 to any port 8888 proto tcp

# Pi-hole web interface from Docker bridge (for Caddy reverse proxy)
sudo ufw allow from 172.18.0.0/16 to any port 8888 proto tcp
```

## Client Configuration

### Install Root CA Certificate

**Windows**:
1. Copy root-ca.crt from server: `scp user@192.168.1.2:/opt/homeserver/configs/caddy/root-ca.crt %USERPROFILE%\Downloads\`
2. Double-click root-ca.crt
3. Install Certificate → Local Machine → Trusted Root Certification Authorities
4. Restart browser

**Linux**:
```bash
scp user@192.168.1.2:/opt/homeserver/configs/caddy/root-ca.crt ~/
sudo cp root-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

**macOS**:
1. Copy root-ca.crt from server (requires sudo on server since file is root-owned):
   ```bash
   # On server first: copy to readable location
   sudo cp /opt/homeserver/configs/caddy/data/caddy/pki/authorities/local/root.crt /tmp/caddy-root-ca.crt
   sudo chmod 644 /tmp/caddy-root-ca.crt
   # From laptop:
   scp user@192.168.1.2:/tmp/caddy-root-ca.crt ~/Downloads/
   ```
2. Install to system keychain:
   ```bash
   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/caddy-root-ca.crt
   ```
3. Firefox uses its own cert store — either import via Settings → Privacy & Security → Certificates → Import, or set `security.enterprise_roots.enabled = true` in `about:config`

### Configure DNS

**Router** (recommended):
- Set DHCP DNS server to 192.168.1.2
- Clients automatically receive DNS configuration

**Manual** (Windows):
```cmd
# Flush DNS cache
ipconfig /flushdns

# Renew DHCP lease
ipconfig /release
ipconfig /renew

# Verify DNS server
ipconfig /all | findstr "DNS Servers"
```

## Troubleshooting

### Startup page not showing (raw 502 instead)

**Check pages volume is mounted**:
```bash
docker inspect caddy --format='{{range .Mounts}}{{if eq .Destination "/srv/pages"}}{{.Source}} -> {{.Destination}} ({{.Mode}}){{end}}{{end}}'
```
If empty, redeploy Caddy with `-v /opt/homeserver/configs/caddy/pages:/srv/pages:ro`.

**Check starting.html exists inside container**:
```bash
docker exec caddy ls -la /srv/pages/starting.html
```

**Check handle_errors block in Caddyfile**:
```bash
docker exec caddy grep -A 4 "handle_errors" /etc/caddy/Caddyfile
```
If missing, the container may be reading a stale Caddyfile (see "Caddyfile update procedure" above). Fix: `docker restart caddy`.

**Check Caddyfile inode matches** (single-file bind mount gotcha):
```bash
# If these differ, container is reading stale config — restart required
stat -c %i /opt/homeserver/configs/caddy/Caddyfile
docker exec caddy stat -c %i /etc/caddy/Caddyfile
```

### DNS not resolving

**Check Pi-hole is running**:
```bash
docker ps | grep pihole
```

**Check DNS port is listening**:
```bash
sudo ss -tulpn | grep :53
```

**Check UFW allows DNS**:
```bash
sudo ufw status | grep 53
```

**Test DNS locally on server**:
```bash
nslookup service.home.mydomain.com 127.0.0.1
```

### HTTPS certificate warnings

**Check root CA is installed** on client device

**Verify Caddy is using internal CA**:
```bash
docker exec caddy cat /etc/caddy/Caddyfile | grep local_certs
```

**Check certificate was issued**:
```bash
docker exec caddy ls -la /data/caddy/certificates/
```

### Container can't reach another container

**Check both containers are on homeserver network**:
```bash
docker inspect <container1> | grep -A 5 Networks
docker inspect <container2> | grep -A 5 Networks
```

**Test connectivity**:
```bash
docker exec <container1> ping <container2>
```

### Service not accessible from browser

**Check DNS resolves correctly**:
```bash
nslookup service.home.mydomain.com
```

**Check Caddy is routing**:
```bash
curl -k https://service.home.mydomain.com
```

**Check Caddy logs for errors**:
```bash
docker logs caddy | grep error
```

## File Locations

- **Caddy config**: /opt/homeserver/configs/caddy/Caddyfile
- **Caddy data**: /opt/homeserver/configs/caddy/data/
- **Caddy logs**: /var/log/caddy/
- **Caddy pages**: /opt/homeserver/configs/caddy/pages/ (startup page, mounted at /srv/pages in container)
- **Pi-hole config**: /opt/homeserver/configs/pihole/
- **Netdata config**: /opt/homeserver/configs/netdata/
- **Root CA certificate**: /opt/homeserver/configs/caddy/root-ca.crt
- **Services config**: /opt/homeserver/configs/services.env

## Related Documentation

- Architecture Overview: docs/00-architecture-overview.md
- Foundation Layer: docs/01-foundation-layer.md
- Services Layer: docs/03-services-layer.md
- Deployment Manual: docs/deployment_manuals/phase2-infrastructure.md


### Pi-hole Management

**Set/reset web interface password**:
```bash
docker exec -it pihole pihole setpassword
```

**Check Pi-hole version**:
```bash
docker exec pihole pihole -v
```

**View Pi-hole statistics**:
```bash
docker exec pihole pihole -c
```

**Restart Pi-hole DNS**:
```bash
docker exec pihole pihole restartdns
```

**Update gravity (blocklists)**:
```bash
docker exec pihole pihole -g
```

## Lessons Learned

### Pi-hole v6 Changes
- Environment variable `WEB_PORT` renamed to `FTLCONF_webserver_port` in v6
- `WEBPASSWORD` environment variable doesn't set password on first run - use `pihole setpassword` command
- Web server requires explicit port configuration when using host networking
- Pi-hole v6 `webserver.domain` setting (default: `pi.hole`) controls which Host header the web UI responds to. Caddy must send `header_up Host pi.hole` or requests get rejected/redirected.
- Reference: https://discourse.pi-hole.net/t/web-port-setting-seems-to-be-ignored-in-v6/77564

### Caddy Proxying to Host Networking Services
- Caddy runs on Docker bridge network (`homeserver`) and cannot resolve host networking container names
- Use Docker gateway IP instead of container name or host IP: `docker inspect caddy --format='{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'`
- Host IP (192.168.1.2) times out from Docker bridge due to UFW blocking Docker subnet traffic
- UFW must allow Docker bridge subnet (172.18.0.0/16) to reach the service port: `ufw allow from 172.18.0.0/16 to any port 8888 proto tcp`

### Docker Networking
- Custom `homeserver` network required for container-to-container communication
- Caddy must be on same network as services it proxies (except host networking services)
- Pi-hole requires host networking for DNS (port 53) but web interface can use custom port
- Port conflicts avoided by: Caddy on 80/443, Pi-hole web on 8888, Netdata on 19999 (all proxied via Caddy)

### UFW Firewall
- Phase 1 deployment must include DNS port 53 rules (missing from original deployment)
- Each service port must be explicitly allowed from LAN subnet
- Host networking services need UFW rules for their ports


## Health Monitoring

### Container Health Checks

All critical containers have HEALTHCHECK configured:

**Pi-hole**:
- Health command: `dig @127.0.0.1 google.com`
- Tests: DNS resolution functionality
- Interval: 30 seconds
- Timeout: 10 seconds
- Retries: 3
- Start period: 60 seconds

**Caddy**:
- Health command: `curl -f http://localhost:80`
- Tests: HTTP response on port 80
- Interval: 30 seconds
- Timeout: 10 seconds
- Retries: 3
- Start period: 30 seconds

**Check container health status**:
```bash
docker ps
# Look for (healthy) status

docker inspect <container> --format='{{.State.Health.Status}}'
# Returns: healthy, unhealthy, or starting
```

### Automated Health Monitoring

**Monitoring script**: `/opt/homeserver/scripts/operations/monitoring/check-container-health.sh`

**What it does**:
- Reads critical container list from `configs/monitoring/critical-containers.conf`
- Checks health status of each container via `docker inspect`
- Sends single consolidated email alert if any container unhealthy or missing
- No email if all healthy (no noise on success)
- Supports `--dry-run` mode
- Logs to `/var/log/homeserver/health-check.log` using structured format

**Monitored containers** (default):
- caddy, pihole, immich-server, immich-postgres, jellyfin
- Edit `configs/monitoring/critical-containers.conf` to add/remove

**Cron configuration** (via `/etc/cron.d/homeserver-cron`):
```bash
# Runs every 15 minutes as root
*/15 * * * * root /opt/homeserver/scripts/operations/monitoring/check-container-health.sh >> /var/log/homeserver/health-check.log 2>&1
```

**Manual test**:
```bash
sudo /opt/homeserver/scripts/operations/monitoring/check-container-health.sh --dry-run
# Shows container statuses, reports what alerts would be sent
sudo /opt/homeserver/scripts/operations/monitoring/check-container-health.sh
# Sends email if any unhealthy, logs structured output
```

**Email alerts**:
- Recipient: ADMIN_EMAIL from foundation.env
- Subject: `[HOMESERVER] Container Alert - YYYY-MM-DD HH:MM`
- Body: hostname, timestamp, unhealthy/missing containers, healthy containers
- Delivery: via msmtp (graceful fallback if unavailable)

### Troubleshooting Unhealthy Containers

**If container shows unhealthy**:

1. Check detailed health status:
   ```bash
   docker inspect <container> --format='{{json .State.Health}}' | jq
   ```

2. Check container logs:
   ```bash
   docker logs <container> --tail 50
   ```

3. Test health check manually:
   ```bash
   # Pi-hole
   docker exec pihole dig @127.0.0.1 google.com
   
   # Caddy
   docker exec caddy curl -f http://localhost:80
   
   # Jellyfin
   docker exec jellyfin curl -f http://localhost:8096/health
   ```

4. Restart container if needed:
   ```bash
   docker restart <container>
   # Wait 30-60 seconds for health check
   docker ps | grep <container>  # Verify (healthy)
   ```

**Reference**: See docs/12-runbooks.md for detailed troubleshooting procedures.
