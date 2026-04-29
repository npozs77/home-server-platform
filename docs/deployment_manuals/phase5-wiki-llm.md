# Phase 05 - Wiki + Local LLM Platform Deployment Manual

**Version**: 1.0
**Status**: Ready for Deployment
**Estimated Time**: 3-5 hours (excluding model download time)

## Overview

Deploy Wiki.js v2 as a family wiki (Sub-phase A) and Ollama + Open WebUI as a local LLM chat interface with RAG (Sub-phase B). Implementation follows the three-layer modular architecture with orchestration script, task modules, and reusable utility libraries.

## Prerequisites

**Phase 1 (Foundation Layer) Complete**:
- LUKS encrypted /mnt/data/ mounted and auto-unlocking
- UFW firewall active (LAN-only, HTTPS allowed)
- SSH hardening configured

**Phase 2 (Infrastructure Layer) Complete**:
- Pi-hole DNS running (internal domain resolution)
- Caddy reverse proxy running (HTTPS routing)
- Netdata monitoring running
- SMTP relay configured (email alerts via msmtp)

**Phase 3 (Core Services Layer) Complete**:
- Samba file sharing running with role-based permissions
- User provisioning complete (Linux users exist)

**Phase 4 (Photo Management) Stable**:
- Immich running and healthy (not a hard dependency, but server load should be stable)

**Reference Documents**:
- Requirements: `.kiro/specs/05-wiki-llm-platform/requirements.md`
- Design: `.kiro/specs/05-wiki-llm-platform/design.md`
- Tasks: `.kiro/specs/05-wiki-llm-platform/tasks.md`
- Phase 4 Manual: `docs/deployment_manuals/phase4-photo-management.md`

## Quick Start

1. Copy scripts to server: `scp -r scripts/ configs/ docs/ homeserver:/opt/homeserver/`
2. SSH to server: `ssh homeserver`
3. Run: `sudo ./scripts/deploy/deploy-phase5-wiki-llm.sh`
4. Execute tasks sequentially via interactive menu
5. Complete Wiki.js setup wizard via browser (Task 5.5 prerequisite)
6. Complete Open WebUI first login via browser (Task 5.11 prerequisite)

## Pre-Deployment Checklist

- [ ] Phase 4 validation passes all checks
- [ ] Server accessible via SSH
- [ ] /mnt/data/ mounted and writable
- [ ] Docker service running
- [ ] Caddy reverse proxy running
- [ ] Pi-hole DNS running
- [ ] WIKI_DB_PASSWORD set in secrets.env

**Verification Commands**:
```bash
ssh homeserver

# Check Phase 4 status
docker ps  # Should show caddy, pihole, netdata, samba, jellyfin, immich-*

# Check data mount
df -h /mnt/data/

# Check secrets
sudo grep WIKI_DB_PASSWORD /opt/homeserver/configs/secrets.env
```

## Task 0: Copy Deployment Artifacts to Server

```bash
# From admin laptop
scp -r scripts/ homeserver:/opt/homeserver/
scp -r configs/ homeserver:/opt/homeserver/
scp -r docs/ homeserver:/opt/homeserver/

# SSH to server
ssh homeserver
```

## Sub-phase A: Wiki.js

### Task 5.1: Create Wiki.js Data Directories

```bash
sudo ./scripts/deploy/deploy-phase5-wiki-llm.sh
# Select option 5.1
```

Creates:
- /mnt/data/services/wiki/postgres (PostgreSQL data)
- /mnt/data/services/wiki/content (disk storage for markdown exports)

### Task 5.2: Deploy Wiki.js Docker Compose Stack

```bash
# Select option 5.2
```

Starts wiki-db (PostgreSQL) and wiki-server (Wiki.js v2).

**Verify**:
```bash
docker ps | grep wiki
# Both containers should show (healthy) after ~2 minutes
```

### Task 5.3: Configure Caddy Reverse Proxy

```bash
# Select option 5.3
```

Adds wiki.home.mydomain.com → wiki-server:3000 routing with TLS internal.

### Task 5.4: Configure Pi-hole DNS

```bash
# Select option 5.4
```

Adds DNS record for wiki.home.mydomain.com.

**Verify**:
```bash
curl -k https://wiki.home.mydomain.com
# Should return HTTP 200
```

### Task 5.5: Wiki.js Initial Setup (Manual)

1. Open https://wiki.home.mydomain.com in browser
2. Complete setup wizard: set admin email, password, site URL
3. Navigate to Administration → API Access → Generate API Token
4. Store token:
   ```bash
   echo 'WIKI_API_TOKEN="your-token-here"' >> /opt/homeserver/configs/secrets.env
   chmod 600 /opt/homeserver/configs/secrets.env
   ```

### Task 5.5b: Provision Wiki.js Users

```bash
# Select option 5.5
```

Creates Wiki.js accounts for family members via GraphQL API.

### Task 5.5c: Configure Wiki Spaces and Storage (Manual)

1. Log in to Wiki.js as admin
2. Create Wiki Spaces: Family, Recipes, Infrastructure, Projects
3. Administration → Storage → Local File System
4. Set path: `/wiki/data/content`
5. Set sync direction: Wiki.js → Disk
6. Click "Dump all content to disk"

See `docs/10-wiki-setup.md` for detailed configuration.

## Sub-phase B: Ollama + Open WebUI

### Task 5.6: Create LLM Data Directories

```bash
# Select option 5.6
```

Creates:
- /mnt/data/services/ollama/models
- /mnt/data/services/openwebui/data

### Task 5.7: Deploy LLM Docker Compose Stack

```bash
# Select option 5.7
```

Starts ollama and open-webui containers.

**Verify**:
```bash
docker ps | grep -E "ollama|open-webui"
# Both containers should show (healthy) after ~2 minutes
```

### Task 5.8: Pull Default LLM Model

```bash
# Select option 5.8
```

Downloads the default model (llama3.2:3b) and additional models. This may take 10-30 minutes depending on internet speed.

**Verify**:
```bash
docker exec ollama ollama list
# Should show downloaded models
```

### Task 5.9: Configure Caddy Reverse Proxy

```bash
# Select option 5.9
```

Adds chat.home.mydomain.com → open-webui:8080 routing.

### Task 5.10: Configure Pi-hole DNS

```bash
# Select option 5.10
```

Adds DNS record for chat.home.mydomain.com.

**Verify**:
```bash
curl -k https://chat.home.mydomain.com
# Should return HTTP 200
```

### Task 5.11: Provision Open WebUI Users

```bash
# Select option 5.11
```

Creates admin account (first user), then family user accounts via REST API. Disables self-registration after provisioning.

### Task 5.11b: Generate Open WebUI API Token (Manual)

1. Access https://chat.home.mydomain.com, log in as admin
2. Settings → Account → API Keys → Create New API Key
3. Copy the key immediately (cannot be viewed again)
4. Store token:
   ```bash
   echo 'OPENWEBUI_API_TOKEN="your-token-here"' >> /opt/homeserver/configs/secrets.env
   chmod 600 /opt/homeserver/configs/secrets.env
   ```

See `docs/11-llm-setup.md` for detailed configuration.

## Shared Components

### Task 5.12: Deploy Backup Script

```bash
# Select option 5.12
```

Installs backup-wiki-llm.sh with pg_dump (Wiki database) and rsync (wiki content, Open WebUI data).

### Task 5.13: Verify Documentation

All Phase 5 documentation is in the Git repo and was scp'd to the server. Verify files are present:
```bash
ls -la /opt/homeserver/docs/deployment_manuals/phase5-wiki-llm.md
ls -la /opt/homeserver/docs/10-wiki-setup.md
ls -la /opt/homeserver/docs/11-llm-setup.md
```

### Task 5.14: Deploy Wiki-to-RAG Sync

```bash
# Select option 5.14
```

Installs wiki-rag-sync.sh and configures nightly cron job to sync wiki content into Open WebUI RAG.

**Prerequisite**: OPENWEBUI_API_TOKEN must be set in secrets.env.

## Validate Phase 5

```bash
sudo ./scripts/deploy/deploy-phase5-wiki-llm.sh
# Select option: v (Validate all)
```

**Expected Output**:
```
Phase 05 Wiki + LLM Platform Validation
========================================
Wiki Directories               ✓ PASS
Wiki Containers Running        ✓ PASS
Wiki Caddy Routing             ✓ PASS
Wiki DNS Resolution            ✓ PASS
Wiki HTTPS Access              ✓ PASS
LLM Directories                ✓ PASS
LLM Containers Running         ✓ PASS
Ollama Internal Only           ✓ PASS
Chat Caddy Routing             ✓ PASS
Chat DNS Resolution            ✓ PASS
Chat HTTPS Access              ✓ PASS
LLM Models Available           ✓ PASS
Backup Script                  ✓ PASS
Secrets Not in Git             ✓ PASS

Results: 14/14 checks passed
```

## Git Commit

```bash
cd /opt/homeserver
git add configs/ scripts/ docs/
# Verify secrets.env is NOT staged
git diff --cached --name-only | grep -v secrets
git commit -m "Complete Phase 5: Wiki + LLM Platform"
git tag v1.0-phase5
```

## Troubleshooting

### Wiki.js Containers Not Starting

```bash
docker compose -f /opt/homeserver/configs/docker-compose/wiki.yml logs
docker ps -a | grep wiki
```

### Wiki Database Connection Errors

```bash
docker exec wiki-db pg_isready -U wikijs -d wikijs
docker logs wiki-db | tail -20
```

### Ollama Model Download Slow/Failing

Model downloads can be large (2-5GB). Allow time and check connectivity.
```bash
docker logs ollama | tail -20
docker exec ollama ollama list
```

### Open WebUI Can't Connect to Ollama

```bash
# Verify Ollama is healthy
docker exec ollama curl -sf http://localhost:11434/
# Verify internal network connectivity
docker exec open-webui curl -sf http://ollama:11434/
```

### HTTPS Not Working

```bash
dig @127.0.0.1 wiki.home.mydomain.com
dig @127.0.0.1 chat.home.mydomain.com
curl -k https://wiki.home.mydomain.com
curl -k https://chat.home.mydomain.com
docker logs caddy | grep -E "wiki|chat"
```

### Backup Fails

```bash
# Test pg_dump manually
docker exec wiki-db pg_dump -U wikijs wikijs > /dev/null
echo $?  # Should be 0

# Check backup destination
ls -la /mnt/backup/wiki-llm/
df -h /mnt/backup/
```

## Next Steps

- Configure Wiki Spaces and content structure
- Test web search in Open WebUI (DuckDuckGo default)
- Test RAG: upload a document and ask questions about it
- Verify wiki-to-RAG sync runs nightly
- Configure nightly backup cron when DAS HDD available
- Optionally configure external LLM providers (see docs/11-llm-setup.md)
