#!/bin/bash
set -euo pipefail
# Core Service Updater — pull + recreate + validate a compose-based CORE
# platform service, with a pre-update backup for stateful ones.
#
# Usage: update-core-service.sh <service> [--dry-run] [--no-backup]
#   <service>     one of: wiki | immich | ollama | jellyfin
#   --dry-run     show what would happen, change nothing
#   --no-backup   skip the pre-update backup (NOT recommended for stateful svcs)
#
# Scope: compose-based core services only. Helper-managed services use
# docker-service-helper.sh; docker-run infra (caddy/pihole/netdata) is a
# different mechanism and is intentionally NOT handled here.
#
# Most core images float on a moving tag (wiki :2, jellyfin/ollama/openwebui
# :latest), so "update" = pull the newer image + recreate. Immich is pinned via
# IMMICH_VERSION in services.env — bump that first, then run this to apply.
#
# Exit Codes: 0=success, 1=update/validate failed, 2=bad args, 3=prereq not met

SCRIPT_NAME="update-core-service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/utils"
# shellcheck source=/dev/null
source "${UTILS_DIR}/log-utils.sh"
# shellcheck source=/dev/null
source "${UTILS_DIR}/core-service-utils.sh"

REPO_DIR="${CSU_REPO_DIR:-/opt/homeserver}"
BACKUP_DIR="${REPO_DIR}/scripts/backup"

SERVICE=""
DRY_RUN=false
NO_BACKUP=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --no-backup) NO_BACKUP=true ;;
        -*) log_msg "ERROR" "$SCRIPT_NAME" "Unknown flag: $arg"; exit 2 ;;
        *) SERVICE="$arg" ;;
    esac
done

if [[ -z "$SERVICE" ]]; then
    echo "Usage: update-core-service.sh <wiki|immich|ollama|jellyfin> [--dry-run] [--no-backup]" >&2
    exit 2
fi

# Known compose-based core services:
#   compose basename | space-separated containers to health-check | backup script (""=none)
COMPOSE_NAME="" ; HEALTH_CONTAINERS="" ; BACKUP_SCRIPT=""
case "$SERVICE" in
    wiki)
        COMPOSE_NAME="wiki";     HEALTH_CONTAINERS="wiki-server wiki-db"
        BACKUP_SCRIPT="${BACKUP_DIR}/backup-wiki-llm.sh" ;;
    immich)
        COMPOSE_NAME="immich";   HEALTH_CONTAINERS="immich-server immich-postgres immich-redis immich-ml"
        BACKUP_SCRIPT="${BACKUP_DIR}/backup-immich.sh" ;;
    ollama)
        COMPOSE_NAME="ollama";   HEALTH_CONTAINERS="ollama open-webui"
        BACKUP_SCRIPT="${BACKUP_DIR}/backup-wiki-llm.sh" ;;   # captures openwebui data
    jellyfin)
        COMPOSE_NAME="jellyfin"; HEALTH_CONTAINERS="jellyfin"
        BACKUP_SCRIPT="" ;;                                   # no DB / stateless config
    caddy|pihole|netdata)
        log_msg "ERROR" "$SCRIPT_NAME" "'${SERVICE}' is docker-run infra, not compose-managed — update it via its Phase 2 task, not this script"
        exit 2 ;;
    *)
        log_msg "ERROR" "$SCRIPT_NAME" "Unknown core service '${SERVICE}'. Known: wiki, immich, ollama, jellyfin"
        exit 2 ;;
esac

# Prereqs
if ! command -v docker &>/dev/null; then
    log_msg "ERROR" "$SCRIPT_NAME" "docker not found"; exit 3
fi
COMPOSE_FILE="$(csu_compose_file "$COMPOSE_NAME")" || exit 3

DRY_LABEL=""; $DRY_RUN && DRY_LABEL=" (dry-run)"
log_msg "INFO" "$SCRIPT_NAME" "Updating core service '${SERVICE}'${DRY_LABEL}"

# Record current image(s) for the summary.
for c in $HEALTH_CONTAINERS; do
    cur=$(docker inspect --format='{{.Config.Image}}' "$c" 2>/dev/null || echo "absent")
    log_msg "INFO" "$SCRIPT_NAME" "  ${c}: ${cur}"
done

# 1. Pre-update backup (stateful services), unless skipped.
if $NO_BACKUP; then
    log_msg "WARN" "$SCRIPT_NAME" "${SERVICE}: --no-backup set — skipping pre-update backup"
else
    csu_run_backup "$SERVICE" "$BACKUP_SCRIPT" "$DRY_RUN" || exit 1
fi

# 2. Pull newer image(s).
csu_pull "$COMPOSE_FILE" "$DRY_RUN" || { log_msg "ERROR" "$SCRIPT_NAME" "pull failed"; exit 1; }

# 3. Recreate changed containers.
csu_recreate "$COMPOSE_FILE" "$DRY_RUN" || { log_msg "ERROR" "$SCRIPT_NAME" "recreate failed"; exit 1; }

if $DRY_RUN; then
    log_msg "INFO" "$SCRIPT_NAME" "dry-run complete — no changes made"
    exit 0
fi

# 4. Validate: each container reaches healthy/running.
FAILED=0
for c in $HEALTH_CONTAINERS; do
    csu_wait_healthy "$c" 120 || FAILED=$(( FAILED + 1 ))
done

if [[ $FAILED -gt 0 ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "${SERVICE}: ${FAILED} container(s) not healthy after update — investigate: docker logs <container>"
    exit 1
fi

# Report resulting image(s).
for c in $HEALTH_CONTAINERS; do
    now=$(docker inspect --format='{{.Config.Image}}' "$c" 2>/dev/null || echo "absent")
    log_msg "INFO" "$SCRIPT_NAME" "  ${c} now: ${now}"
done
log_msg "INFO" "$SCRIPT_NAME" "${SERVICE}: update complete — all containers healthy"
