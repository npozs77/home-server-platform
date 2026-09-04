# Core Service Updates — Reference

Update a **core platform** container (Wiki.js, Immich, Ollama/Open WebUI,
Jellyfin) to a newer image: back up (if stateful) → pull → recreate → validate.

- **Script:** `scripts/operations/update-core-service.sh`
- **Lib:** `scripts/operations/utils/core-service-utils.sh`
- **Make:** `make update-core SERVICE=<name> [ARGS=--dry-run]`

> Core services ≠ helper-managed services. Apps deployed via the docker service
> helper (e.g. vocabgen, musivault) are updated with
> `docker-service-helper.sh update <name>` — see `docs/16-docker-service-helper.md`.
> This script is only for the compose-based core platform services.

## Usage

```bash
# from the dev machine (ssh) or on the server (local) — same command:
make update-core SERVICE=wiki                 # back up, pull, recreate, validate
make update-core SERVICE=wiki ARGS=--dry-run  # show what would happen, no changes
make update-core SERVICE=immich ARGS=--no-backup   # skip pre-update backup (rarely)

# or call the script directly on the server:
sudo bash /opt/homeserver/scripts/operations/update-core-service.sh wiki
```

## Supported services

| SERVICE | Compose file | Containers | Pre-update backup | Image pin |
|---------|--------------|------------|-------------------|-----------|
| `wiki` | `wiki.yml` | wiki-server, wiki-db | `backup-wiki-llm.sh` (pg_dump) | floating `ghcr.io/requarks/wiki:2` |
| `immich` | `immich.yml` | immich-server, -postgres, -redis, -ml | `backup-immich.sh` (pg_dump) | `IMMICH_VERSION` in `services.env` |
| `ollama` | `ollama.yml` | ollama, open-webui | `backup-wiki-llm.sh` (Open WebUI data) | `*_VERSION` (default `latest`) |
| `jellyfin` | `jellyfin.yml` | jellyfin | none (no DB) | `jellyfin/jellyfin:latest` |

## How "update" works per pin style

- **Floating tag** (wiki `:2`, jellyfin/ollama/openwebui `:latest`): there is no
  version to edit — `update` **pulls the newer image and recreates**. This is the
  common case (e.g. Wiki.js 2.5.313 → 2.5.314 is just a pull + recreate).
- **Explicit pin** (Immich `IMMICH_VERSION=v2.5.6` in `services.env`): bump the
  version in `services.env` **first**, then run `make update-core SERVICE=immich`
  to pull that tag and recreate. Reproducible; you control exactly which version.

`docker compose up -d` only recreates containers whose image/config changed, so
sidecars (e.g. `wiki-db`, `immich-postgres`) are left running untouched. Their
data persists via bind mounts under `/mnt/data/services/<svc>/` regardless.

## What it does (order)

1. **Record** current image(s) for the service's containers (for the summary).
2. **Backup** — runs the service's backup script (pg_dump + rsync to DAS) unless
   `--no-backup`. If the backup **fails, the update aborts** (safety first).
3. **Pull** newer image(s): `docker compose ... pull`.
4. **Recreate**: `docker compose ... up -d` (changed containers only).
5. **Validate**: waits (≤120s each) for every container to report `healthy`
   (or `running` if it has no healthcheck). Non-zero exit if any don't.
6. **Report** the resulting image(s).

## NOT handled (by design)

- **docker-run infra**: `caddy`, `pihole`, `netdata` are started with `docker run`
  in their Phase 2 task scripts, not compose. Update them by re-running their
  Phase 2 deploy task. The script rejects these names with a clear message.
- **Helper-managed services**: use `docker-service-helper.sh update`.

## Rollback

- **Explicit pin** (Immich): set the previous `IMMICH_VERSION` in `services.env`
  and re-run `make update-core SERVICE=immich`.
- **Floating tag** (wiki/jellyfin/ollama/openwebui): pin the compose `image:` line
  to the previous known-good tag temporarily, recreate, then investigate. The
  pre-update backup on the DAS is the recovery point for stateful data.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Update aborts before pull | Pre-update backup failed — check DAS mount / `backup-*.log`; fix, or re-run with `--no-backup` if you accept the risk |
| Container not healthy after update | `docker logs <container>` — new image may need a migration or config change; app DBs migrate on startup (give it time) |
| `unauthorized` on pull | Private image — the pulling context (root) must be logged into the registry (`sudo docker login <registry>`) |
| Wrong service name | Only `wiki`, `immich`, `ollama`, `jellyfin` are supported; infra (caddy/pihole/netdata) is updated via its Phase 2 task |
