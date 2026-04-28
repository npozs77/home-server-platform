# Home Media Server

Private infrastructure-as-code repository for a family home server. Manages the full lifecycle from OS hardening through service deployment using spec-driven development, phased deployment scripts, and property-based testing.

## What's Running

| Service | Purpose | URL Pattern |
|---------|---------|-------------|
| Caddy | Reverse proxy, automatic HTTPS | — |
| Pi-hole | Local DNS ad-blocking | `dns.home.mydomain.com` |
| Netdata | Real-time monitoring | `monitor.home.mydomain.com` |
| Jellyfin | Media streaming | `media.home.mydomain.com` |
| Samba | File sharing (SMB) | LAN shares |
| Immich | Photo management | `photos.home.mydomain.com` |

## Stack

- **OS**: Ubuntu Server LTS 24.04
- **Containers**: Docker / Docker Compose V2
- **Reverse Proxy**: Caddy (automatic HTTPS via internal CA)
- **DNS**: Pi-hole (local resolution + ad-blocking)
- **Monitoring**: Netdata + email alerts (msmtp/SMTP2Go)
- **File Sharing**: Samba (per-user + family shared + media library)
- **Backup**: LUKS-encrypted DAS, nightly cron (configs + Immich + Wiki.js stub)
- **Automation**: Bash scripts, phased deployment with interactive menus
- **Security**: LUKS disk encryption, SSH key-only, UFW firewall, fail2ban

## Deployment Phases

| Phase | Name | Status | Description |
|-------|------|--------|-------------|
| 01 | Foundation | ✅ Deployed | OS hardening, SSH, firewall, LUKS, Docker, Git, DAS backup target |
| 02 | Infrastructure | ✅ Deployed | Caddy, Pi-hole, Netdata, SMTP, data directories |
| 03 | Core Services | ✅ Deployed | Samba, Jellyfin, user provisioning, storage, backup orchestrator, container health checks |
| 04 | Photo Management | ✅ Deployed | Immich, external library, photo prep tooling |
| 05 | Family Wiki & AI | 📋 Planned | Wiki.js, local LLM, AI agent with RAG |
| 06 | Home Automation | 📋 Planned | Home Assistant, smart device control |
| 07 | Advanced Features | 📋 Planned | Zero-trust remote access, container lifecycle, optional services |

## Repository Structure

```
configs/                    # Configuration templates (*.example — secrets never committed)
  foundation.env.example    #   System-level config (hostname, IPs, disks)
  services.env.example      #   Service config (domains, SMTP, DNS)
  secrets.env.example       #   Sensitive data (passphrases, API keys)
  docker-compose/           #   Docker Compose files per service
  caddy/                    #   Caddyfile and error pages
  samba/                    #   Samba configuration
  monitoring/               #   Container health check config

scripts/
  deploy/                   # Phased deployment scripts with interactive menus
  deploy/tasks/             #   Modular task scripts (one per deployment step)
  backup/                   # Backup orchestrator + per-service backup scripts
  operations/utils/         # Shared utilities (logging, env loading, validation)
  operations/monitoring/    # Container health checks

docs/                       # Operational documentation (AS-IS reference)
  deployment_manuals/       #   Step-by-step deployment guides per phase
  00-architecture-overview  #   System architecture and design decisions
  12-runbooks               #   Troubleshooting and recovery procedures

tests/                      # Property-based tests and validation scripts (30 files)
```

`.kiro/` (specs, steering, hooks) is gitignored and lives only in the local dev environment.

## Getting Started

### Fresh Install

1. Install Ubuntu Server LTS 24.04 (minimal, with SSH enabled)
2. Clone the repo directly on the server:
   ```bash
   sudo mkdir -p /opt/homeserver && cd /opt/homeserver
   sudo git clone https://github.com/youruser/homeserver.git .
   ```
3. Copy example configs and customize:
   ```bash
   cp configs/foundation.env.example configs/foundation.env
   cp configs/services.env.example configs/services.env
   cp configs/secrets.env.example configs/secrets.env
   # Edit each file with your values
   ```
4. Run Phase 1 deployment (interactive menu):
   ```bash
   sudo scripts/deploy/deploy-phase1-foundation.sh
   ```
5. Continue with Phase 2, 3, 4 in order. Each deployment manual is in `docs/deployment_manuals/`.

Each deployment script provides an interactive menu:
- **Option 0**: Initialize/update configuration (prompts for all variables)
- **Option c**: Validate configuration
- **Options 1-N**: Execute individual deployment tasks
- **Option v**: Run full phase validation
- **Option q**: Quit

## Testing

30 test files with 800+ property-based assertions. Tests validate script structure, correctness properties, and governance compliance without requiring the server.

```bash
# Run all test suites
bash tests/run-all.sh

# Run specific test suite
bash tests/test_backup_alerting.sh        # Backup & alerting (192 assertions)
bash tests/test_phase1_scripts.sh         # Phase 1 foundation (76 assertions)
bash tests/test_phase3_scripts.sh         # Phase 3 core services
bash tests/test_phase4_scripts.sh         # Phase 4 photo management
```

## Configuration

Three logical config files (resolved at runtime on the server):

| File | Permissions | Purpose |
|------|-------------|---------|
| `foundation.env` | 644 | System-level: hostname, IPs, disks, backup DAS |
| `services.env` | 644 | Service-level: domains, SMTP, DNS settings |
| `secrets.env` | 600 (root) | Sensitive: LUKS passphrase, API keys |

Copy `*.example` files and customize. Real values are never committed to Git.

## Governance

Script size guidelines enforced by `scripts/operations/validate-governance.sh`:

| Script Type | Target LOC | Rationale |
|-------------|-----------|-----------|
| Deployment scripts | ~300 | AI context window + readability |
| Task modules | ~150 | Single responsibility |
| Utility libraries | ~200 | Reusable, focused |
| Backup/monitoring | ~150 | Operational simplicity |

## Key Design Decisions

- **DHCP reservation** (not static IP) — network resilient if server fails
- **Registered domain** with internal subdomain — proper HTTPS, no browser warnings
- **Application-level access control** — Linux permissions for ownership, apps for visibility
- **`group_add` for containers** — simple Linux group model, no UID remapping
- **Samba `force group`** — shared uploads get correct group ownership automatically
- **Config-driven** — `foundation.env` / `services.env` / `secrets.env`, no hardcoded values

## Access Model

| Role | SSH | Docker | Samba | Web Apps |
|------|-----|--------|-------|----------|
| Admin | ✅ All devices | ✅ | ✅ Full | ✅ Full |
| Power User | ✅ Personal device | ✅ | ✅ Limited | ✅ Full |
| Standard User | ❌ | ❌ | ✅ Personal + shared | ✅ Full |

## Notes

- **Private repo** — contains Kiro specs, steering files, and development artifacts
- Secrets (`.env`, keys, certs) are gitignored and never committed
- `input/` and `OLD/` directories are gitignored
- Companion public repo (published separately) holds generic operational documentation
