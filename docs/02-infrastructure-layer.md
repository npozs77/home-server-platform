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

**Reload Caddyfile** (after editing):
```bash
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

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
}
```
Or for host networking service:
```
service.home.mydomain.com {
    reverse_proxy 192.168.1.2:port
    tls internal
    log {
        output file /var/log/caddy/service-access.log
    }
}
```
Then reload: `docker exec caddy caddy reload --config /etc/caddy/Caddyfile`

### Container Management

**Check running containers**:
```bash
docker ps
```

**Restart a service**:
```bash
docker restart <container-name>
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
1. Copy root-ca.crt from server
2. Double-click to open Keychain Access
3. Set trust to "Always Trust"

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
- Reference: https://discourse.pi-hole.net/t/web-port-setting-seems-to-be-ignored-in-v6/77564

### Docker Networking
- Custom `homeserver` network required for container-to-container communication
- Caddy must be on same network as services it proxies (except host networking services)
- Pi-hole requires host networking for DNS (port 53) but web interface can use custom port
- Port conflicts avoided by: Caddy on 80/443, Pi-hole web on 8888, Netdata on 19999 (all proxied via Caddy)

### UFW Firewall
- Phase 1 deployment must include DNS port 53 rules (missing from original deployment)
- Each service port must be explicitly allowed from LAN subnet
- Host networking services need UFW rules for their ports
