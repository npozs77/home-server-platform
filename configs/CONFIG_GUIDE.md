# Configuration Management Guide

## Overview

This guide documents all configuration files used in the home media server infrastructure deployment. Configuration files use `.env` format (key=value pairs) for simplicity and compatibility with shell scripts and Docker Compose.

## Configuration Strategy

**Logical Grouping Approach**: Configuration is organized by purpose, not deployment phase. This eliminates duplication and provides clear ownership of variables.

## Configuration Files

| File | Purpose | Used By |
|------|---------|---------|
| `configs/foundation.env` | System-level configuration (timezone, hostname, network) | All phases |
| `configs/services.env` | Service-specific configuration (domains, SMTP, DNS) | Phase 02+ |
| `configs/secrets.env` | Sensitive data (passphrases, API keys) | All phases |

**Benefits of Logical Grouping**:
- No duplication (each variable in exactly one file)
- Clear ownership (network config in foundation.env, SMTP in services.env)
- Logical grouping (related variables together)
- Reusable across phases (foundation.env used by all phases)

**Anti-Pattern**: Phase-based configuration (phase1-config.env, phase2-config.env) causes duplication and unclear ownership. See `.kiro/specs/refactor_fix_ph01-02/design.md` for details.

## Foundation Configuration (foundation.env)

System-level configuration used by all phases.

### Server Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TIMEZONE` | No | `Europe/Amsterdam` | Server timezone (see: `timedatectl list-timezones`) |
| `HOSTNAME` | No | `homeserver` | Server hostname |
| `SERVER_IP` | No | `192.168.1.2` | Static IP via DHCP reservation |

### User Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ADMIN_USER` | Yes | Current user | Admin username (created during Ubuntu install) |
| `ADMIN_EMAIL` | Yes | - | Admin email for notifications |

### Git Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GIT_USER_NAME` | Yes | - | Git user name for commits |
| `GIT_USER_EMAIL` | Yes | - | Git user email |

### Network Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NETWORK_INTERFACE` | No | Auto-detected | Network interface (e.g., `enp0s3`, `wlp2s0`) |

## Services Configuration (services.env)

Service-specific configuration used by Phase 02+.

### Domain Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BASE_DOMAIN` | Yes | - | Registered public domain (e.g., `mydomain.com`) |
| `INTERNAL_SUBDOMAIN` | No | `home` | Internal subdomain (e.g., `home.mydomain.com`) |

### SMTP Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SMTP_HOST` | Yes | - | SMTP server hostname |
| `SMTP_PORT` | No | `587` | SMTP server port |
| `SMTP_USER` | Yes | - | SMTP username |
| `SMTP_FROM` | Yes | - | Email "From" address |

### Phase 3: Core Services Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POWER_USER` | Yes | `power_user` | Power user username |
| `STANDARD_USER` | Yes | `standard_user` | Standard user username |
| `SAMBA_WORKGROUP` | No | `WORKGROUP` | Samba workgroup name |
| `SAMBA_SERVER_STRING` | No | `Home Media Server` | Samba server description |
| `JELLYFIN_SERVER_NAME` | No | `Home Media Server` | Jellyfin server display name |

### DNS Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DNS_PROVIDER` | No | `cloudflare` | DNS provider (cloudflare, route53, etc.) |

## Secrets Configuration (secrets.env)

Sensitive data used by all phases. **NEVER commit to Git**.

### Security Secrets

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATA_DISK` | Yes | - | Data disk for LUKS encryption (e.g., `/dev/sdb`) |
| `LUKS_PASSPHRASE` | Yes | - | LUKS encryption passphrase (20+ characters) |

### Service Secrets

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SMTP_PASSWORD` | Yes | - | SMTP password |
| `DNS_API_TOKEN` | No | - | DNS provider API token (if using automated DNS) |

## Configuration Workflow

### 1. Initialize Configuration

Run the deployment script and select option 0:

```bash
sudo ./deploy-phase1-foundation.sh
# Select option 0: Initialize/Update configuration
```

The script will prompt for all required values and save to:
- `/opt/homeserver/configs/foundation.env`
- `/opt/homeserver/configs/secrets.env`

### 2. Validate Configuration

Select option c to validate configuration:

```bash
# Select option c: Validate configuration
```

Validation checks:
- Timezone is valid (exists in system timezone list)
- Hostname is valid (alphanumeric and hyphens only)
- Server IP is valid (IPv4 format)
- Admin user exists on system
- Admin email format is valid
- Data disk exists (block device)
- LUKS passphrase is strong (20+ characters)
- Git user name is set
- Git user email is valid

### 3. Update Configuration

To update configuration values, run option 0 again:

```bash
# Select option 0: Initialize/Update configuration
# Existing values will be shown as defaults
# Press Enter to keep existing value or enter new value
```

### 4. Execute Tasks

After configuration is validated, execute tasks:

```bash
# Select task number (1-8) to execute
# Configuration will be loaded automatically
```

## Example Configuration

### foundation.env

```bash
# /opt/homeserver/configs/foundation.env
# Generated: 2025-02-01

# Server Configuration
TIMEZONE="Europe/Amsterdam"
HOSTNAME="homeserver"
SERVER_IP="192.168.1.2"

# User Configuration
ADMIN_USER="admin"
ADMIN_EMAIL="admin@example.com"

# Git Configuration
GIT_USER_NAME="Admin User"
GIT_USER_EMAIL="admin@home.mydomain.com"

# Network Configuration
NETWORK_INTERFACE="enp0s3"
```

### secrets.env

```bash
# /opt/homeserver/configs/secrets.env
# Generated: 2025-02-01
# WARNING: NEVER COMMIT TO GIT

# Security Configuration
DATA_DISK="/dev/sdb"
LUKS_PASSPHRASE="<your-strong-passphrase-20-chars-min>"

# Service Secrets (Phase 02+)
SMTP_PASSWORD="<your-smtp-password>"
DNS_API_TOKEN="<your-dns-api-token>"
```

### services.env

```bash
# /opt/homeserver/configs/services.env
# Generated: 2025-02-01

# Domain Configuration
BASE_DOMAIN="mydomain.com"
INTERNAL_SUBDOMAIN="home"

# SMTP Configuration
SMTP_HOST="smtp.gmail.com"
SMTP_PORT="587"
SMTP_USER="admin@mydomain.com"
SMTP_FROM="homeserver@mydomain.com"

# DNS Configuration
DNS_PROVIDER="cloudflare"

# Phase 3: Core Services Configuration
POWER_USER="power_user"
STANDARD_USER="standard_user"
SAMBA_WORKGROUP="WORKGROUP"
SAMBA_SERVER_STRING="Home Media Server"
JELLYFIN_SERVER_NAME="Home Media Server"
```

## Security Best Practices

### Configuration File Security

1. **Never commit secrets.env to Git**: Contains sensitive data (LUKS passphrase, passwords)
2. **Restrict permissions**: 
   ```bash
   chmod 600 /opt/homeserver/configs/foundation.env
   chmod 600 /opt/homeserver/configs/secrets.env
   chmod 600 /opt/homeserver/configs/services.env
   ```
3. **Backup securely**: Store backup in password manager or encrypted storage
4. **Use strong passphrases**: LUKS passphrase should be 20+ characters

### .gitignore Configuration

Ensure `.gitignore` excludes configuration files:

```
# Sensitive files
*.key
*.pem
*.env
.env
*.secret
```

## Troubleshooting

### Configuration Not Found

**Symptom**: Script reports "Configuration file not found"

**Solution**: Run option 0 to initialize configuration

```bash
sudo ./deploy-phase1-foundation.sh
# Select option 0
```

### Validation Errors

**Symptom**: Validation fails with specific errors

**Solution**: 
1. Review error messages
2. Run option 0 to update incorrect values
3. Re-run option c to validate
4. Repeat until all checks pass

### Values Not Used by Tasks

**Symptom**: Tasks don't use configuration values

**Solution**: Ensure task calls `load_config()` at start. All tasks in deployment script automatically load configuration.

### Reset Configuration

**Symptom**: Need to start over with fresh configuration

**Solution**: Remove configuration files and re-initialize

```bash
sudo rm /opt/homeserver/configs/foundation.env
sudo rm /opt/homeserver/configs/secrets.env
sudo ./deploy-phase1-foundation.sh
# Select option 0
```

## Configuration Format

### Why .env Format?

The project uses `.env` format (key=value pairs) instead of YAML for several reasons:

1. **Simplicity**: No indentation issues, straightforward key=value syntax
2. **Shell-friendly**: Easy to source in bash scripts: `source config.env`
3. **Docker-native**: Docker Compose natively supports .env files
4. **Widely supported**: Most tools understand .env format
5. **Less error-prone**: No YAML parsing issues

### .env Format Rules

- One variable per line
- Format: `KEY="value"`
- Comments start with `#`
- No spaces around `=`
- Quote values with spaces
- No trailing whitespace

**Good**:
```bash
TIMEZONE="Europe/Amsterdam"
HOSTNAME="homeserver"
SERVER_IP="192.168.1.2"
```

**Bad**:
```bash
TIMEZONE = "Europe/Amsterdam"  # Spaces around =
HOSTNAME=home server           # Unquoted value with space
SERVER_IP="192.168.1.2"        # Trailing whitespace
```

## Advanced Configuration

### Dry-Run Mode

Test deployment without making changes:

```bash
sudo ./deploy-phase1-foundation.sh --dry-run
# All tasks will show what would be done without executing
```

### Manual Configuration Editing

While not recommended, you can manually edit the configuration files:

```bash
sudo nano /opt/homeserver/configs/foundation.env
sudo nano /opt/homeserver/configs/secrets.env
# Make changes
# Save and exit
# Run option c to validate
```

### Configuration Backup

Backup configuration before major changes:

```bash
sudo cp /opt/homeserver/configs/foundation.env \
        /opt/homeserver/configs/foundation.env.backup
sudo cp /opt/homeserver/configs/secrets.env \
        /opt/homeserver/configs/secrets.env.backup
```

## Migration from Phase-Based Configuration

If you have existing phase-based configuration files (phase1-config.env, phase2-config.env), see `.kiro/specs/refactor_fix_ph01-02/design.md` for migration guidance.

**Quick Migration**:
1. Extract system-level variables from phase1-config.env → foundation.env
2. Extract service-specific variables from phase2-config.env → services.env
3. Extract sensitive variables from both → secrets.env
4. Remove old phase-based config files
5. Update deployment scripts to source new config files

## Related Documentation

- Deployment Manual: `docs/deployment_manuals/phase1-foundation.md`
- Requirements: `.kiro/specs/01-foundation/requirements.md`
- Design: `.kiro/specs/01-foundation/design.md`
- Tasks: `.kiro/specs/01-foundation/tasks.md`
- Migration Guide: `.kiro/specs/refactor_fix_ph01-02/design.md`

---

**Last Updated**: 2025-02-01  
**Version**: 2.0 (Logical Grouping)
