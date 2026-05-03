#!/bin/bash
# Task: Commit all Phase 6 artifacts to Git
# Phase: 6 (Docker Service Helper)
# Number: 07
# Prerequisites: All Phase 6 tasks complete
# Parameters:
#   --dry-run: Show what would be committed without committing
# Exit Codes: 0 = Success, 1 = Failure
# Requirements: 12.3

set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Error: Must run as root (use sudo)" >&2; exit 1; }

source /opt/homeserver/scripts/operations/utils/output-utils.sh

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

REPO_ROOT="/opt/homeserver"

print_header "Task ph6-07: Git commit Phase 6 artifacts"

cd "$REPO_ROOT"

# Stage Phase 6 files (excludes gitignored: services.yml, per-service dirs)
STAGE_PATHS=(
    "scripts/docker-helper/"
    "scripts/deploy/deploy-phase6-docker-helper.sh"
    "scripts/deploy/tasks/task-ph6-*.sh"
    "scripts/operations/utils/validation-docker-helper-utils.sh"
    "configs/helper-services/services.yml.example"
    "configs/helper-services/.gitkeep"
    ".gitignore"
)

if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY-RUN] Would stage and commit:"
    for p in "${STAGE_PATHS[@]}"; do
        # shellcheck disable=SC2086
        ls -1 $p 2>/dev/null | sed 's/^/  /' || true
    done
    exit 0
fi

for p in "${STAGE_PATHS[@]}"; do
    # shellcheck disable=SC2086
    git add $p 2>/dev/null || true
done

if git diff --cached --quiet; then
    print_info "Nothing to commit — working tree clean"
    exit 0
fi

git commit -m "feat(phase6): docker service helper — scripts, config, docs, tests"
print_success "Committed Phase 6 artifacts"
exit 0
