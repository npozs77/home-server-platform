# Architecture Overview

## System Architecture

Single Ubuntu Server LTS 24.04 host running Docker containers, accessible via LAN only (192.168.1.0/24).

### Service Stack

| Layer | Service | Container(s) | URL | Purpose |
|-------|---------|-------------|-----|---------|
| Infrastructure | Caddy | caddy | — | Reverse proxy, automatic HTTPS (internal CA) |
| Infrastructure | Pi-hole | pihole | dns.home.mydomain.com | Local DNS, ad-blocking |
| Infrastructure | Netdata | netdata | monitor.home.mydomain.com | Real-time monitoring |
| Core Services | Samba | samba | LAN shares | File sharing (SMB) |
| Core Services | Jellyfin | jellyfin | media.home.mydomain.com | Media streaming |
| Photo Management | Immich | immich-server, immich-ml, immich-redis, immich-postgres | photos.home.mydomain.com | Photo management |
| Wiki + LLM | Wiki.js | wiki-server, wiki-db | wiki.home.mydomain.com | Family wiki |
| Wiki + LLM | Ollama | ollama | (internal only) | Local LLM runtime |
| Wiki + LLM | Open WebUI | open-webui | chat.home.mydomain.com | AI chat interface with RAG |

### Network Architecture

- All services on Docker `homeserver` network (bridge)
- Caddy terminates HTTPS (internal CA) and routes to containers
- Pi-hole resolves *.home.mydomain.com → server LAN IP
- Ollama API internal-only (port 11434 not published to host)
- UFW firewall: LAN-only, default deny incoming

### Data Architecture

- `/mnt/data/` — LUKS-encrypted NVMe partition (user data, media, service data)
- `/mnt/backup/` — LUKS-encrypted DAS partition (nightly backups)
- All service persistent data under `/mnt/data/services/{service-name}/`
- Database backups via pg_dump (Immich, Wiki.js) — never filesystem copy

### Access Control

Two-layer model applied consistently across all services:
- **Linux/OS-level**: File ownership and permissions (protect data at rest)
- **Application-level**: Native user accounts and roles (control visibility and experience)

All user-facing services use application-native accounts (NOT Linux users).

### Deployment Architecture

Three-layer modular scripts:
1. **Orchestration** (~300 LOC): Interactive menu, config management, task delegation
2. **Task modules** (~150 LOC each): Single deployment step per script
3. **Utility libraries** (~200 LOC each): Shared functions across phases

### Container Dependencies

```
Pi-hole (DNS) → Caddy (HTTPS) → Application Services

Wiki.js:    wiki-db → wiki-server
Immich:     immich-postgres → immich-redis → immich-server → immich-ml
LLM:        ollama → open-webui
```

## Deployment Phases

| Phase | Name | Status | Key Services |
|-------|------|--------|-------------|
| 01 | Foundation | ✅ Deployed | OS hardening, SSH, firewall, LUKS, Docker |
| 02 | Infrastructure | ✅ Deployed | Caddy, Pi-hole, Netdata, SMTP |
| 03 | Core Services | ✅ Deployed | Samba, Jellyfin, user provisioning |
| 04 | Photo Management | ✅ Deployed | Immich |
| 05 | Wiki + LLM | 🚧 In Progress | Wiki.js, Ollama, Open WebUI |
| 06 | Home Automation | 📋 Planned | Home Assistant |
| 07 | Advanced Features | 📋 Planned | Zero-trust remote access |

## Related Documents

- `docs/01-foundation-layer.md` — Phase 01 foundation layer
- `docs/02-infrastructure-layer.md` — Phase 02 infrastructure layer
- `docs/03-services-layer.md` — Phase 03 services layer
- `docs/05-storage.md` — Data storage structure
- `docs/09-immich-setup.md` — Immich setup
- `docs/10-wiki-setup.md` — Wiki.js setup
- `docs/11-llm-setup.md` — LLM setup
- `docs/12-runbooks.md` — Troubleshooting and recovery
- `docs/13-container-restart-procedure.md` — Container restart/upgrade procedures

---

**Last Updated**: 2026-04-29
**Status**: Active
