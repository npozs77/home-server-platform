# Local LLM Setup Guide (Ollama + Open WebUI)

## Architecture

- **Ollama**: Local LLM runtime — runs models, serves inference API on internal Docker network only
- **Open WebUI**: Chat interface — web UI with RAG, web search, per-user chat history
- Ollama API (port 11434) is NOT published to the host — only accessible via Docker internal network

## Initial Setup

### First Login (Admin Account)

The admin account is created automatically by the provisioning script (task-ph5-11). After provisioning:

1. Access https://chat.home.mydomain.com
2. Log in with admin credentials from secrets.env
3. Verify Ollama models appear in the model selector dropdown

### Generate API Token

Required for wiki-to-RAG sync and future automation:

1. Log in as admin
2. Settings → Account → API Keys section
3. Click "Create New API Key"
4. Copy the key immediately (cannot be viewed again)
5. Store in secrets.env:
   ```bash
   echo 'OPENWEBUI_API_TOKEN="your-token-here"' >> /opt/homeserver/configs/secrets.env
   chmod 600 /opt/homeserver/configs/secrets.env
   ```

**Note**: API keys are enabled via ENABLE_API_KEY=true in ollama.yml (no manual admin toggle needed).

## User Accounts

Users are provisioned automatically by the deployment script:
```bash
sudo ./scripts/deploy/tasks/task-ph5-11-provision-openwebui-users.sh
```

| Family Role | Open WebUI Role | Access |
|---|---|---|
| Admin (ADMIN_USER) | admin | Full access, model management, user management |
| Power User (POWER_USERS) | user | Chat, RAG, web search, model selection |
| Standard User (STANDARD_USERS) | user | Chat, RAG, web search, model selection |

- Self-registration is disabled after provisioning (ENABLE_SIGNUP=false)
- Each user has isolated chat history and document uploads
- Passwords are stored in secrets.env as OPENWEBUI_PASSWORD_{username}

## Model Management

### Default Models

Pulled during deployment (task-ph5-08):
- **llama3.2:3b** — Default model (lightweight, fast, good for general use)
- **mistral:7b** — Additional model (better reasoning, more resource-intensive)

### Pull Additional Models

Via Open WebUI (preferred):
1. Admin → Settings → Models → Pull a model
2. Enter model name (e.g., `codellama:7b`)

Via CLI:
```bash
docker exec ollama ollama pull codellama:7b
docker exec ollama ollama list  # Verify
```

### Remove Models

```bash
docker exec ollama ollama rm codellama:7b
```

### Model Storage

Models are stored at `/mnt/data/services/ollama/models/` on the host. They persist across container recreations. Models can be large (2-8GB each) — monitor disk usage.

### Resource Impact

| Model Size | RAM Usage (approx.) | Notes |
|---|---|---|
| 3B params | ~2-3 GB | Fast responses, good for simple tasks |
| 7B params | ~4-5 GB | Better quality, slower on CPU-only |
| 13B+ params | ~8+ GB | Not recommended for this server |

Ollama automatically unloads models from memory after idle period (default: 5 minutes).

## RAG (Retrieval-Augmented Generation)

### Manual Document Upload

1. In any chat, click the "+" icon or drag-and-drop a file
2. Supported formats: PDF, TXT, Markdown, DOCX
3. Ask questions about the uploaded document
4. Documents are per-user (isolated) unless explicitly shared

### Automated Wiki-to-RAG Sync

Wiki.js content is automatically synced to Open WebUI RAG nightly:

- Script: `/opt/homeserver/scripts/operations/wiki-rag-sync.sh`
- Schedule: Nightly at 03:00 (cron)
- Source: `/mnt/data/services/wiki/content/` (Wiki.js disk storage)
- Method: Checksum comparison — only uploads changed/new pages
- Removes documents when wiki pages are deleted

All processing is local (no external service or network exposure).

**Verify sync**:
```bash
# Check checksum file
cat /mnt/data/services/openwebui/data/.wiki-rag-checksums

# Run sync manually
sudo /opt/homeserver/scripts/operations/wiki-rag-sync.sh
```

## Web Search

### Default Configuration

DuckDuckGo is enabled by default — no API key required.

### How to Use

In any chat, the LLM can search the internet when asked questions requiring current information (e.g., "What's the phone number for XYZ insurance?"). Source URLs are displayed alongside the response.

### Alternative Search Backends

Edit services.env to switch:
```bash
# DuckDuckGo (default, no API key)
WEB_SEARCH_ENGINE="duckduckgo"

# SearXNG (self-hosted, requires separate container)
WEB_SEARCH_ENGINE="searxng"

# Google (requires API key in secrets.env)
WEB_SEARCH_ENGINE="google"
```

Recreate the container after changing:
```bash
docker compose -f /opt/homeserver/configs/docker-compose/ollama.yml up -d
```

## External LLM Providers (Optional)

Open WebUI can connect to external LLM providers alongside local Ollama models. This is disabled by default (local-only mode).

### Opt-In Configuration

1. Uncomment the relevant variables in services.env:
   ```bash
   # Anthropic
   ANTHROPIC_API_KEY="your-key-here"

   # AWS Bedrock
   # AWS_BEDROCK_REGION="us-east-1"
   # AWS_BEDROCK_ACCESS_KEY="your-key"
   # AWS_BEDROCK_SECRET_KEY="your-secret"

   # OpenAI-compatible
   # OPENAI_API_KEY="your-key-here"
   # OPENAI_API_BASE_URL="https://api.openai.com/v1"
   ```

2. Add API keys to secrets.env (never commit)

3. Configure in Open WebUI: Admin → Settings → Connections → Add Connection

4. External models appear alongside local models in the model selector

### Security Note

When using external providers, prompts and responses are sent to third-party servers. Local Ollama models keep all data on the home network.

## Backup and Recovery

### What Gets Backed Up

- **Open WebUI data** (rsync): Chat history, uploaded documents, RAG embeddings, user accounts
  - Location: `/mnt/data/services/openwebui/data/`
- **Ollama models** are NOT backed up by default (large, can be re-pulled from registry)

### Backup Script

```bash
sudo /opt/homeserver/scripts/backup/backup-wiki-llm.sh
```

### Restore Procedure

1. Stop open-webui: `docker stop open-webui`
2. Restore data:
   ```bash
   rsync -a /mnt/backup/wiki-llm/openwebui-data/ /mnt/data/services/openwebui/data/
   ```
3. Start open-webui: `docker start open-webui`
4. Re-pull models if needed:
   ```bash
   docker exec ollama ollama pull llama3.2:3b
   docker exec ollama ollama pull mistral:7b
   ```
5. Verify: access https://chat.home.mydomain.com, check chat history and models

## Related Documentation

- Wiki setup: docs/10-wiki-setup.md
- Deployment manual: docs/deployment_manuals/phase5-wiki-llm.md
- Storage structure: docs/05-storage.md
- Container restart/upgrade: docs/13-container-restart-procedure.md
