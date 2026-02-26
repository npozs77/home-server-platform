# Task Modules

This directory contains modular task scripts for deployment phases. Each task module performs a single, focused deployment operation following the single responsibility principle.

## Structure

Task modules follow a standardized naming convention:
```
task-{phase}-{number}-{description}.sh
```

Examples:
- `task-ph1-01-update-system.sh` - Phase 1, Task 1: Update system packages
- `task-ph2-05-deploy-caddy.sh` - Phase 2, Task 5: Deploy Caddy container

## Standard Task Module Structure

Every task module follows this structure:

```bash
#!/bin/bash
# Task: Brief description of what this task does
# Phase: N (Phase name)
# Number: NN
# Prerequisites:
#   - List of prerequisites (previous tasks, configuration, etc.)
# Parameters:
#   --dry-run: Validate without making changes
# Exit Codes:
#   0 = Success
#   1 = Failure
#   2 = Prerequisites not met
#   3 = Configuration error
# Environment Variables Required:
#   VAR1, VAR2, VAR3
# Environment Variables Optional:
#   OPTIONAL_VAR

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../operations/utils/output-utils.sh"
source "$SCRIPT_DIR/../../operations/utils/env-utils.sh"

# Parse parameters
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validate prerequisites
validate_required_vars "VAR1" "VAR2" || exit 3

# Check idempotency (if already completed, skip)
if [[ condition_already_met ]]; then
    print_info "Already completed - skip"
    exit 0
fi

# Execute task
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would perform action"
else
    # Actual implementation
    print_success "Task complete"
fi

exit 0
```

## Key Principles

### 1. Single Responsibility
Each task module performs exactly ONE deployment task. If a task grows beyond 150 lines, split it into multiple tasks.

### 2. Idempotency
Tasks must be safe to run multiple times. Check if the task is already completed before executing:
```bash
if command -v docker &> /dev/null; then
    print_info "Docker already installed - skip"
    exit 0
fi
```

### 3. Dry-Run Support
All tasks must support `--dry-run` flag for validation without making changes:
```bash
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would install Docker"
    exit 0
fi
```

### 4. Clear Exit Codes
- `0` = Success
- `1` = General failure
- `2` = Prerequisites not met
- `3` = Configuration error

### 5. Prerequisite Validation
Validate all prerequisites before execution:
```bash
# Check required environment variables
validate_required_vars "ADMIN_USER" "SERVER_IP" || exit 3

# Check previous tasks completed
if [[ ! -d /mnt/data ]]; then
    print_error "/mnt/data does not exist. Phase 1 incomplete?"
    exit 2
fi
```

### 6. Utility Library Usage
Source and use utility libraries for common operations:
```bash
source "$SCRIPT_DIR/../../operations/utils/output-utils.sh"
source "$SCRIPT_DIR/../../operations/utils/env-utils.sh"
source "$SCRIPT_DIR/../../operations/utils/password-utils.sh"
```

## Size Constraints

**Maximum 150 lines per task module** (including comments)

If a task exceeds this limit, split it into multiple focused tasks.

## Phase 1 Task Modules

| Task | Module | Description |
|------|--------|-------------|
| 1.01 | task-ph1-01-update-system.sh | Update packages, set timezone/hostname |
| 1.02 | task-ph1-02-setup-luks.sh | LUKS disk encryption setup |
| 1.03 | task-ph1-03-harden-ssh.sh | SSH configuration hardening |
| 1.04 | task-ph1-04-configure-firewall.sh | UFW firewall configuration |
| 1.05 | task-ph1-05-setup-fail2ban.sh | fail2ban installation and setup |
| 1.06 | task-ph1-06-install-docker.sh | Docker and Docker Compose installation |
| 1.07 | task-ph1-07-init-git-repo.sh | Git repository initialization |
| 1.08 | task-ph1-08-setup-auto-updates.sh | unattended-upgrades configuration |

## Phase 2 Task Modules

| Task | Module | Description |
|------|--------|-------------|
| 2.01 | task-ph2-01-create-data-dirs.sh | Create top-level data directories |
| 2.02 | task-ph2-02-create-family-dirs.sh | Create family subdirectories |
| 2.03 | task-ph2-03-create-backup-dirs.sh | Create backup subdirectories |
| 2.04 | task-ph2-04-create-services-yaml.sh | Generate services.yaml configuration |
| 2.05 | task-ph2-05-deploy-caddy.sh | Deploy Caddy reverse proxy |
| 2.06 | task-ph2-06-export-ca-cert.sh | Export Caddy root CA certificate |
| 2.07 | task-ph2-07-deploy-pihole.sh | Deploy Pi-hole DNS server |
| 2.08 | task-ph2-08-configure-dns.sh | Configure local DNS records |
| 2.09 | task-ph2-09-install-msmtp.sh | Install msmtp package |
| 2.10 | task-ph2-10-configure-msmtp.sh | Configure msmtp for SMTP2GO |
| 2.11 | task-ph2-11-test-email.sh | Test email delivery |
| 2.12 | task-ph2-12-deploy-netdata.sh | Deploy Netdata monitoring |
| 2.13 | task-ph2-13-configure-log-rotation.sh | Configure log rotation |

## Usage

Task modules are called by deployment scripts, not run directly:

```bash
# From deployment script
execute_update_system() {
    ./tasks/task-ph1-01-update-system.sh ${DRY_RUN:+--dry-run} || return 1
}
```

However, they can be run manually for testing:

```bash
# Dry-run mode
sudo ./task-ph1-01-update-system.sh --dry-run

# Actual execution
sudo ./task-ph1-01-update-system.sh
```

## Testing

Each task module should have corresponding unit tests in `tests/` directory validating:
- Script syntax (bash -n)
- Required functions exist
- Dry-run mode works
- Idempotency checks present
- Exit codes correct

## Creating New Task Modules

When creating a new task module:

1. Follow the naming convention: `task-{phase}-{number}-{description}.sh`
2. Copy the standard structure from this README
3. Keep under 150 lines
4. Implement idempotency checks
5. Support --dry-run flag
6. Use utility libraries for common operations
7. Document prerequisites and environment variables
8. Write corresponding unit tests

## References

- Design Document: `.kiro/specs/refactor_fix_ph01-02/design.md`
- Requirements: `.kiro/specs/refactor_fix_ph01-02/requirements.md`
- Utility Libraries: `scripts/operations/utils/README.md`
