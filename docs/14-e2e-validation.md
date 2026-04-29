# E2E Validation Script

## Location

`scripts/operations/validate-all.sh`

## Purpose

Single executable that runs all phase validations (1-4) without opening individual deployment scripts. Use cases:
- Post-deployment regression check
- Regular health check (cron or manual)
- Future alerting integration (JSON output)

## Usage

```bash
# Full validation (all phases)
sudo ./scripts/operations/validate-all.sh

# Single phase only
sudo ./scripts/operations/validate-all.sh --phase 2

# JSON output (for alerting/monitoring)
sudo ./scripts/operations/validate-all.sh --json

# Summary only (suppress per-check detail)
sudo ./scripts/operations/validate-all.sh --quiet

# Combine flags
sudo ./scripts/operations/validate-all.sh --phase 3 --quiet
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | One or more checks failed |
| 2 | Configuration/setup error (missing config files, not root) |

## Checks by Phase

| Phase | Name | Checks |
|-------|------|--------|
| 1 | Foundation | SSH, UFW, fail2ban, Docker, Git, Updates, LUKS, Docker Group, Tools, Shell |
| 2 | Infrastructure | Data dirs, Caddy, CA cert, Pi-hole, DNS, SMTP, Netdata, Logrotate |
| 3 | Core Services | Samba, Folders, Shares, Recycle bin, User scripts, Jellyfin, DNS, Git |
| 4 | Photo Management | Immich dirs, Containers, Caddy, DNS, HTTPS, Libraries, Backup, Version, Secrets |

Total: 55 checks across 4 phases.

## Parity with Deployment Scripts

Every check in each deployment script's `validate_all()` is included here. No automated check is omitted.

Excluded (with justification):

| Excluded | Reason |
|----------|--------|
| `validate_config()` per-phase | Config format validation is a pre-deployment gate. Config files don't change post-deploy; if corrupt, container checks catch it. |
| Manual validation checklists | Cannot automate from server (root CA on workstation, browser HTTPS trust, mobile app test). |
| `validate_prerequisites()` (Phase 4) | Redundant — Phase 1-3 checks already cover all prerequisites. |

## Architecture

Check arrays (`PHASE1_CHECKS`, `PHASE2_CHECKS`, etc.) live in each `validation-*-utils.sh` file — single source of truth. Both deployment scripts and `validate-all.sh` source them. No duplication.

```
validation-foundation-utils.sh       → PHASE1_CHECKS + check functions
validation-infrastructure-utils.sh   → PHASE2_CHECKS + check functions
validation-core-services-utils.sh    → PHASE3_CHECKS + check functions
validation-photo-management-utils.sh → PHASE4_CHECKS + check functions
         ↑                                    ↑
    deploy-phase{N}.sh                  validate-all.sh
    (sources for "option v")            (sources all)
```

## Adding a New Phase/Service

1. Create `scripts/operations/utils/validation-{name}-utils.sh` with check functions + `PHASEN_CHECKS` array
2. Add `source` line in `validate-all.sh`
3. Add `run_phase N "Name" "${PHASEN_CHECKS[@]}"` line
4. Deployment script sources same utils and uses same `PHASEN_CHECKS` array
5. Update this doc (checks table + total count)

## Dependencies

Sources these utility libraries (all in `scripts/operations/utils/`):
- `output-utils.sh` — colored output
- `env-utils.sh` — config loading (`load_env_files`)
- `validation-foundation-utils.sh` — Phase 1 checks
- `validation-infrastructure-utils.sh` — Phase 2 checks
- `validation-core-services-utils.sh` — Phase 3 checks
- `validation-photo-management-utils.sh` — Phase 4 checks

Config files loaded: `foundation.env`, `services.env`, `secrets.env`

## JSON Output Format

```json
{
  "timestamp": "2026-04-17T10:30:00Z",
  "server": "192.168.1.2",
  "total": 55,
  "passed": 53,
  "failed": 2,
  "checks": [
    {"phase": 1, "check": "SSH Hardening", "status": "pass"},
    {"phase": 2, "check": "msmtp Test", "status": "fail", "detail": "..."}
  ]
}
```

## Future: Alerting Integration

The `--json` flag produces machine-readable output. Planned integration:
- Pipe to email alert on failure: `validate-all.sh --json | alert-on-failure.sh`
- Cron health check: `0 6 * * * /opt/homeserver/scripts/operations/validate-all.sh --quiet || mail -s "Health check failed" admin@mydomain.com`
- Netdata custom chart (parse JSON, push metrics)

## Tests

```bash
bash tests/test_validate_all.sh
```

36 structural checks validating script integrity, all phase arrays, flags, and output format.

## Deploy to Server

```bash
scp scripts/operations/validate-all.sh user@192.168.1.2:/opt/homeserver/scripts/operations/
ssh user@192.168.1.2 'sudo chmod +x /opt/homeserver/scripts/operations/validate-all.sh'
```
