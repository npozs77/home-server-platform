# Services Layer

**Status**: Placeholder - To be created during Phase 03+

## Purpose

This document will describe the AS-IS services and applications configuration after Phase 03+ deployment.

## Planned Content

**Phase 03+ Components**:
- Media services (Jellyfin)
- Photo services (Immich, PhotoPrism)
- Home automation (Home Assistant)
- Wiki (Wiki.js)
- Shared services (SMTP relay, etc.)
- Service-specific configurations
- User access patterns
- Auto-start/idle-stop configuration

## When to Create

During Phase 03+ deployment, after application services are configured and validated.

## Related Documents

- `.kiro/specs/03-core-services/design.md` - Phase 03 design decisions
- `.kiro/specs/04-applications/design.md` - Phase 04 design decisions
- `docs/deployment_manuals/phase3-services.md` - Phase 03 deployment procedures
- `docs/02-infrastructure-layer.md` - Infrastructure layer (Phase 02)

---

**Last Updated**: 2025-02-02  
**Status**: Placeholder


## Health Monitoring

### Jellyfin Health Check

**Health command**: `curl -f http://localhost:8096/health`
- Tests: API health endpoint
- Interval: 30 seconds
- Timeout: 10 seconds
- Retries: 3
- Start period: 30 seconds

**Check Jellyfin health**:
```bash
docker ps | grep jellyfin
# Should show: (healthy)

docker inspect jellyfin --format='{{.State.Health.Status}}'
# Should return: healthy
```

**Manual health test**:
```bash
docker exec jellyfin curl -f http://localhost:8096/health
# Should return: HTTP 200 OK
```

### Automated Monitoring

Jellyfin is monitored by `/opt/homeserver/scripts/operations/monitoring/check-container-health.sh`:
- Runs every 15 minutes via `/etc/cron.d/homeserver-cron`
- Reads container list from `configs/monitoring/critical-containers.conf`
- Sends consolidated email alert if unhealthy or missing
- Reference: docs/02-infrastructure-layer.md for monitoring details
