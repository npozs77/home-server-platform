# Docker Service Helper — Reference

Deploy any containerized service from a YAML definition. The helper generates
the Docker Compose file, Caddy block, Pi-hole DNS record, data directory, and
backup registration following server conventions.

- **Helper**: `scripts/docker-helper/docker-service-helper.sh`
- **Config**: `configs/helper-services/services.yml` (gitignored; `.example` is tracked)
- **Data**: `/mnt/data/services/{service-name}/`
- **Deployment manual**: `docs/deployment_manuals/phase6-docker-helper.md`

## Subcommands

| Command | Purpose |
|---------|---------|
| `add <name> [--dry-run] [--verbose]` | Deploy a new service (data dir, build, compose, DNS, Caddy, start, backup, validate) |
| `remove <name> [--dry-run] [--purge-data]` | Remove a service; `--purge-data` also deletes data dir + backup registration |
| `update <name> [--dry-run] [--verbose]` | Re-read definition, regenerate compose, rebuild if needed, force-recreate |
| `list [--json]` | List all services with status (running/stopped/not deployed/disabled) |
| `validate <name>` | Run all checks, output "X / Y checks passed" |
| `logs <name> [--follow] [--tail N]` | View container logs |
| `stop <name>` / `start <name>` | Stop/start container(s), preserving config |
| `lint` | Validate `services.yml` syntax + schema |
| `backup <name>` | Run the generated backup script for a service |

```bash
docker-service-helper.sh add vocabgen --dry-run
docker-service-helper.sh list --json
docker-service-helper.sh logs vocabgen --tail 50
```

## Service definition schema

`services.yml` under `services:`. Only `name`, `image` (or `build`), and `port`
(unless `no_proxy`) are required; everything else has convention defaults.

| Field | Required | Default | Notes |
|-------|----------|---------|-------|
| `name` | yes | — | lowercase, alphanumeric + hyphens; matches container name |
| `image` | yes* | — | *`image` OR `build` required (both allowed: build then tag) |
| `build` | yes* | — | `context` (git URL or path) + `dockerfile`; single Dockerfile only |
| `port` | yes† | — | †required unless `no_proxy: true`; container port Caddy proxies to |
| `visibility` | no | `private` | `public` or `private` (LAN/VPN vs exposed intent) |
| `subdomain` | no | `name` | → `{subdomain}.home.<domain>` |
| `no_proxy` | no | `false` | `true` = publish host port, no Caddy block (background/non-HTTP) |
| `environment` | no | — | env vars; reference secrets as `${VAR}` from `secrets.env` |
| `volumes` | no | auto data dir | extra bind mounts beyond the auto `/mnt/data/services/{name}` |
| `memory_limit` | no | `512M` | container memory cap |
| `cpu_limit` | no | `1.0` | container CPU cap |
| `healthcheck` | no | `curl -f http://localhost:{port}/` | verify the app's real endpoint |
| `run_as` | no | data dir `chmod 777` | `"uid:gid"` — container user + data dir ownership (find via `docker exec <name> id`) |
| `depends_on` | no | — | start ordering for multi-container |
| `extra_containers` | no | — | sidecars (db, backend) on the shared network; each takes image/env/volumes/healthcheck |
| `enabled` | no | `true` | `false` → `add`/`validate` skip, `list` shows "disabled" |
| `backup.pre_command` | no | — | app-aware snapshot (e.g. `docker exec <c> pg_dump …`) run before rsync |
| `backup.pre_command_output` | no | — | file (inside data dir) the pre_command writes to |
| `backup.paths` | no | data dir only | additional host paths to rsync |

Convention defaults always applied to generated compose: `restart: unless-stopped`,
`container_name`, TZ from `foundation.env`, `homeserver` network, resource limits,
and a data volume at `/mnt/data/services/{name}`.

## Example workflow — "I found a cool project on GitHub, how do I deploy it?"

1. **Decide image vs build.** Pre-built image on a registry → use `image:`.
   Source-only with a single Dockerfile → use `build.context` (git URL).
   Multi-container app → pre-built images + `extra_containers` (build-from-source
   is single-Dockerfile only).
2. **Add secrets** (if any) to `/opt/homeserver/configs/secrets.env`, reference
   as `${VAR}` in the definition.
3. **Add the block** to `services.yml` (copy the closest example).
4. **Lint + dry-run**: `docker-service-helper.sh lint` then `add <name> --dry-run`.
5. **Deploy**: `add <name>`.
6. **Validate**: `validate <name>`, then open `https://<subdomain>.home.<domain>`.

## Operations quick-reference

```bash
# add / update / remove
docker-service-helper.sh add <name>
docker-service-helper.sh update <name>            # after editing services.yml or new image tag
docker-service-helper.sh remove <name>            # keep data
docker-service-helper.sh remove <name> --purge-data

# inspect
docker-service-helper.sh list
docker-service-helper.sh validate <name>
docker-service-helper.sh logs <name> --tail 50

# lifecycle without config change
docker-service-helper.sh stop <name>
docker-service-helper.sh start <name>

# backup
docker-service-helper.sh backup <name>            # runs scripts/backup/backup-<name>.sh
```

## Limitations & Workarounds

Learned from the VocabGen and MusiVault deployments
(see `input/musivault-deployment-runbook.md`):

1. **Healthcheck defaults to `/`, not `/health`.** Always verify the app's actual
   endpoint before relying on the default `curl -f http://localhost:{port}/`.
2. **Build-from-source requires a single Dockerfile.** Multi-container apps with
   separate Dockerfiles per service must use pre-built images + `extra_containers`,
   not `build:`.
3. **All containers join the `homeserver` network.** The helper does not create
   per-service networks; containers reach each other by name on the shared network.
4. **`port` is the frontend/proxy port.** For multi-container apps, `port` is what
   Caddy proxies to (the frontend), not a backend/API port.
5. **Secrets are managed via `secrets.env`, not the helper.** Add them on the
   server and reference as `${VAR_NAME}` in `services.yml`.
