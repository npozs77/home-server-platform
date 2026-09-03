# Phase 06 — Docker Service Helper Deployment Manual

**Version**: 1.0
**Status**: Deployed
**Estimated Time**: 30–45 minutes

## Overview

Deploy a reusable Docker service helper that turns a YAML service definition
into a fully wired service: Docker Compose file, Caddy reverse-proxy block,
Pi-hole DNS record, data directory, and backup registration — all following
established server conventions. After deployment, adding a new service is a
matter of editing `services.yml` and running `docker-service-helper.sh add <name>`.

## Prerequisites

**Phase 1 (Foundation) complete**: LUKS `/mnt/data/` mounted, UFW active, SSH hardened.
**Phase 2 (Infrastructure) complete**: Pi-hole DNS, Caddy reverse proxy, Netdata, SMTP relay.
**Phase 3–5 stable**: server load steady; not hard dependencies.

**Reference documents**:
- Requirements: `.kiro/specs/06-docker-service-helper/requirements.md`
- Design: `.kiro/specs/06-docker-service-helper/design.md`
- Tasks: `.kiro/specs/06-docker-service-helper/tasks.md`
- LLD reference: `docs/16-docker-service-helper.md`

## Quick Start

1. Pull on server: `ssh homeserver 'cd /opt/homeserver && bash scripts/operations/utils/deploy-update.sh main'`
2. Run the deployment script: `ssh homeserver 'sudo bash /opt/homeserver/scripts/deploy/deploy-phase6-docker-helper.sh'`
3. Menu: install yq → create `services.yml` → (optionally) deploy an example service → validate
4. Add your own service: edit `services.yml`, then `docker-service-helper.sh add <name>`

## Pre-Deployment Checklist

- [ ] Phase 2 validation passes (Caddy, Pi-hole, Netdata running)
- [ ] Server reachable via SSH, `/mnt/data/` mounted and writable
- [ ] Docker service running, `homeserver` Docker network exists
- [ ] Caddy and Pi-hole containers healthy

**Verification commands**:
```bash
ssh homeserver
docker ps        # expect caddy, pihole, netdata (+ existing services)
docker network ls | grep homeserver
df -h /mnt/data/
```

## Step 1 — Install yq

`yq` (Mike Farah's Go YAML processor) is required to read `services.yml`.

```bash
sudo bash /opt/homeserver/scripts/deploy/deploy-phase6-docker-helper.sh
# menu → "Install yq"   (or run task-ph6-01-install-yq.sh directly)
yq --version            # verify
```

Idempotent: skips if already installed at the correct version.

## Step 2 — Create the live services.yml

```bash
# menu → "Create services.yml"
# copies configs/helper-services/services.yml.example → services.yml if absent
sudo yq '.services | keys' /opt/homeserver/configs/helper-services/services.yml
```

The live `services.yml` is **gitignored** (it holds real domains/PII). Only the
`.example` is tracked. Edit the live file with your real service definitions.

## Step 3 — Add a service

Edit `services.yml`, then:

```bash
sudo bash /opt/homeserver/scripts/docker-helper/docker-service-helper.sh lint
sudo bash /opt/homeserver/scripts/docker-helper/docker-service-helper.sh add <name> --dry-run
sudo bash /opt/homeserver/scripts/docker-helper/docker-service-helper.sh add <name>
```

`add` performs: validate → create data dir → build (if `build:` block) →
generate compose → add DNS → add Caddy → start container → register backup →
validate → summary.

## Validation Checklist

Run the Phase 6 validation suite:

```bash
sudo bash /opt/homeserver/scripts/operations/validate-all.sh --phase 6
```

PHASE6_CHECKS covers: helper script present, `services.yml` present, `yq`
installed, `list` works, `lint` passes, example service running, DNS resolving,
HTTPS accessible, data dir exists, Netdata monitoring, backup script generated.

Per-service validation:
```bash
sudo bash /opt/homeserver/scripts/docker-helper/docker-service-helper.sh validate <name>
docker ps | grep <name>          # expect (healthy) after ~30s
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Container fails to start | `docker logs <name>` — image pull, env, or config error |
| DNS not resolving | Confirm Pi-hole record: `docker-service-helper.sh validate <name>`; check `# BEGIN helper:<name>` block in Pi-hole custom DNS |
| Caddy 502 | Backend not healthy yet, or `port` points at the wrong container (for multi-container, `port` is the frontend) |
| Healthcheck failing | App may not serve `/` — verify actual endpoint; default probe is `curl -f http://localhost:<port>/`, not `/health` |
| Port conflict (no_proxy) | Another service already publishes that host port — pick a free one |
| Build failure | Build-from-source needs a single Dockerfile; multi-container apps must use pre-built images + `extra_containers` |
| Permission denied on data dir | Set `run_as: "uid:gid"` in the definition (find with `docker exec <name> id`), then `update` |

## Rollback

```bash
# remove the service (keeps data)
sudo bash /opt/homeserver/scripts/docker-helper/docker-service-helper.sh remove <name>
# remove and purge data + backup registration
sudo bash /opt/homeserver/scripts/docker-helper/docker-service-helper.sh remove <name> --purge-data
```

`remove` reverses the `add` wiring: stop container → remove Caddy block →
remove DNS record → remove compose file → (with `--purge-data`) deregister
backup and delete the data directory.
