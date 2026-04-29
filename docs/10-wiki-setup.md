# Wiki.js Setup Guide

## Initial Setup Wizard

1. Access https://wiki.home.mydomain.com from browser
2. Complete setup wizard (first-time only):
   - Admin email: use ADMIN_EMAIL from foundation.env
   - Admin password: choose a strong password (Wiki.js-specific, not Linux)
   - Site URL: https://wiki.home.mydomain.com
3. Generate API token: Administration → API Access → Create API Key
4. Store token in secrets.env:
   ```bash
   echo 'WIKI_API_TOKEN="your-token-here"' >> /opt/homeserver/configs/secrets.env
   chmod 600 /opt/homeserver/configs/secrets.env
   ```

**Note**: The API token is required before running the user provisioning script (task-ph5-05).

## User Account Creation

Users are provisioned automatically by the deployment script:
```bash
sudo ./scripts/deploy/tasks/task-ph5-05-provision-wiki-users.sh
```

The script:
- Reads ADMIN_USER, POWER_USERS, STANDARD_USERS from services.env
- Creates Wiki.js accounts via GraphQL API
- Maps roles to Wiki.js groups:

| Family Role | Wiki.js Group | Permissions |
|---|---|---|
| Admin (ADMIN_USER) | Administrators | Full access, admin panel |
| Power User (POWER_USERS) | Editors | Read + write all spaces |
| Standard User (STANDARD_USERS) | Readers | Read all spaces, limited editing |

- Admin uses ADMIN_EMAIL from foundation.env
- Other users use {username}@homeserver as email
- Idempotent: skips users that already exist

## Wiki Spaces

Create these spaces after initial setup:

| Space | Purpose | Access |
|---|---|---|
| Family | General family information, contacts, procedures | All users |
| Recipes | Family recipes and cooking guides | All users |
| Infrastructure | Server documentation, network setup, runbooks | Admin + Power Users |
| Projects | Ongoing projects, plans, research | All users |

**To create a space**: Navigate to the desired path (e.g., `/family/`) and create the first page. Wiki.js auto-creates the space hierarchy.

## Local File System Storage Module

Wiki.js can export all page content as markdown files to disk. This serves two purposes:
1. Content recovery independent of the database
2. Source for wiki-to-RAG sync (Open WebUI can search wiki content)

### Configuration

1. Administration → Storage → Local File System
2. Set path: `/wiki/data/content`
   - This maps to `/mnt/data/services/wiki/content/` on the host via Docker volume mount
3. Set sync direction: **Wiki.js → Disk** (push mode)
4. Schedule: Daily (Wiki.js internal scheduler)
5. Click **"Dump all content to disk"** to export existing pages

### Verification

```bash
# Check content directory on host
ls -la /mnt/data/services/wiki/content/

# After creating a test page, verify sync
ls -la /mnt/data/services/wiki/content/
# Should contain .md files matching wiki pages
```

### Important Notes

- This is NOT the homeserver infrastructure Git repo — wiki content is user data
- The Local File System module replaces the originally planned Git storage module
  (Git module requires a remote URI, not compatible with local bare repo path)
- Content is organized by page path (e.g., `family/contacts.md`, `recipes/pasta.md`)
- Sync is one-way: Wiki.js → Disk (edits happen in Wiki.js, not on disk)

## Editors

Wiki.js v2 provides two editors:

| Editor | Best For | Features |
|---|---|---|
| Visual Editor | Non-technical users | WYSIWYG, toolbar, drag-and-drop images |
| Markdown Editor | Technical users | Raw markdown, preview pane, keyboard shortcuts |

The editor is selected per-page when creating. Existing pages use the editor they were created with.

## API Token Management

### When You Need a Token

- **WIKI_API_TOKEN**: Required for automated user provisioning (task-ph5-05)
- **WIKI_AGENT_API_TOKEN**: Required only for Sub-phase C (custom agent, optional/future)

### Generating a Token

1. Log in as admin
2. Administration → API Access
3. Click "Create API Key"
4. Copy the token immediately
5. Store in secrets.env (never commit to Git)

### Token Permissions

The API token inherits the permissions of the user who created it. Admin tokens have full access to all GraphQL mutations (user creation, page management).

## Backup and Recovery

### What Gets Backed Up

- **Wiki database** (pg_dump): All page content, user accounts, configuration, revision history
- **Wiki disk storage** (rsync): Markdown page exports at /mnt/data/services/wiki/content/

### Backup Script

```bash
sudo /opt/homeserver/scripts/backup/backup-wiki-llm.sh
```

### Restore Procedure

1. Stop wiki-server: `docker stop wiki-server`
2. Restore database:
   ```bash
   docker exec -i wiki-db psql -U wikijs -d wikijs < /mnt/backup/wiki-llm/wiki-db-YYYYMMDD_HHMMSS.sql
   ```
3. Restore disk storage (optional):
   ```bash
   rsync -a /mnt/backup/wiki-llm/wiki-content/ /mnt/data/services/wiki/content/
   ```
4. Start wiki-server: `docker start wiki-server`
5. Verify: access https://wiki.home.mydomain.com, check user accounts and pages

## Related Documentation

- Deployment manual: docs/deployment_manuals/phase5-wiki-llm.md
- LLM setup: docs/11-llm-setup.md
- Storage structure: docs/05-storage.md
- Container restart/upgrade: docs/13-container-restart-procedure.md
