# Docker Data-Root Migration (Existing Server)

One-time runbook for relocating Docker's `data-root` from the default
`/var/lib/docker` (small OS/root partition) to `/mnt/data/docker` (large
LUKS-encrypted data volume).

**When to use**: An existing server where Docker was installed before the
data-root relocation was adopted. Fresh installs get the correct data-root from
`task-ph1-06-install-docker.sh` and do NOT need this procedure.

**Why**: The OS/root partition (~50GB) fills with Docker image layers
(overlay2), while `/mnt/data` has hundreds of GB free. Relocating data-root
fixes the root cause of recurring "disk almost full" alarms.

---

## Impact and Prerequisites

- **Service interruption**: ALL containers stop during the copy. Expect a few
  minutes of downtime. Pi-hole going down briefly means a DNS blip on the LAN.
  Schedule when the family is not actively using services.
- **Reversible**: The original `/var/lib/docker` is kept (renamed) until you
  confirm success, so you can roll back.
- **Disk space**: Ensure `/mnt/data` has free space greater than the current
  Docker footprint.

**Pre-flight checks** (read-only):

```bash
# Current Docker footprint and data-root
docker system df
docker info --format '{{.DockerRootDir}}'          # expect /var/lib/docker
sudo du -xsh /var/lib/docker                        # size to copy

# Target volume mounted and has room
mountpoint -q /mnt/data && echo "mnt-data mounted" || echo "NOT MOUNTED — abort"
df -h /mnt/data                                     # confirm free > footprint

# Note running containers so you can compare afterward
docker ps --format '{{.Names}}' | sort > /tmp/containers-before.txt
wc -l /tmp/containers-before.txt
```

Do not proceed if `/mnt/data` is not mounted, or free space is insufficient.

---

## Migration Procedure

Run as root (or via `sudo`). Values resolve from
`/opt/homeserver/configs/foundation.env` (`DOCKER_DATA_ROOT`, default
`/mnt/data/docker`).

### 1. Stop Docker completely

```bash
sudo systemctl stop docker docker.socket
# Confirm the daemon is down
systemctl is-active docker || echo "docker stopped"
```

### 2. Copy data to the new location

`rsync` preserves permissions, ownership, timestamps, and hardlinks (important
for overlay2 layers). The trailing slashes matter.

```bash
sudo mkdir -p /mnt/data/docker
sudo rsync -aP /var/lib/docker/ /mnt/data/docker/
```

Re-run the same `rsync` once more to catch anything missed — it should complete
almost instantly if the first pass succeeded.

### 3. Apply daemon config and boot-ordering drop-in

The live files are generated from the committed templates
(`configs/docker/daemon.json.example`,
`configs/docker/docker-service-dropin.conf.example`).

```bash
# daemon.json with data-root
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak 2>/dev/null || true
sudo tee /etc/docker/daemon.json >/dev/null << 'EOF'
{
  "data-root": "/mnt/data/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

# systemd drop-in: start dockerd only after /mnt/data is mounted
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/10-data-root-mount.conf >/dev/null << 'EOF'
[Unit]
RequiresMountsFor=/mnt/data
EOF
```

### 4. Reload systemd and start Docker

```bash
sudo systemctl daemon-reload
sudo systemctl start docker
```

### 5. Verify

```bash
# data-root now points at the encrypted volume
docker info --format '{{.DockerRootDir}}'           # expect /mnt/data/docker

# all containers came back
docker ps --format '{{.Names}}' | sort > /tmp/containers-after.txt
diff /tmp/containers-before.txt /tmp/containers-after.txt && echo "all containers present"

# spot-check health after they settle (~60s)
sleep 60 && docker ps
```

If any service is unhealthy, follow the restart order in
`docs/13-container-restart-procedure.md`.

---

## Reclaim the Old Directory

Only after confirming everything works. Rename first (cheap, reversible), then
delete once you are confident.

```bash
# Rename (keeps data as a safety net)
sudo mv /var/lib/docker /var/lib/docker.old

# Confirm Docker still works with the renamed old dir gone from its path
docker ps

# Reclaim space once satisfied (irreversible)
sudo rm -rf /var/lib/docker.old
df -h /                                             # root usage should drop sharply
```

---

## Verify Boot Ordering (recommended)

The drop-in is only proven at the next boot. Either wait for a scheduled reboot
or, if you can afford it, reboot now and confirm Docker starts after the
encrypted mount:

```bash
sudo reboot
# After reconnecting:
systemctl show docker.service -p After | tr ' ' '\n' | grep -i mnt-data
docker info --format '{{.DockerRootDir}}'           # expect /mnt/data/docker
docker ps                                           # all services up
```

---

## Rollback

If verification fails and you have not yet deleted `/var/lib/docker`:

```bash
sudo systemctl stop docker docker.socket
sudo rm -f /etc/docker/daemon.json
sudo mv /etc/docker/daemon.json.bak /etc/docker/daemon.json 2>/dev/null || true
sudo rm -f /etc/systemd/system/docker.service.d/10-data-root-mount.conf
sudo systemctl daemon-reload
sudo systemctl start docker
docker info --format '{{.DockerRootDir}}'           # back to /var/lib/docker
```

The original `/var/lib/docker` (or `/var/lib/docker.old`, if renamed) still
holds the untouched data.

---

## Related Documentation

- docs/05-storage.md (storage layout and /mnt/data structure)
- docs/13-container-restart-procedure.md (restart order after Docker restart)
- docs/01-foundation-layer.md (foundation configuration)
- .kiro/specs/01-foundation/design.md (data-root design rationale)
- configs/docker/daemon.json.example, configs/docker/docker-service-dropin.conf.example
