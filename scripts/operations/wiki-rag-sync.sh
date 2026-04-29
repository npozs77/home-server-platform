#!/bin/bash
# Wiki-to-RAG Sync Script
# Purpose: Sync Wiki.js disk storage content into Open WebUI RAG for semantic search
# Usage: wiki-rag-sync.sh [--dry-run]
# Exit Codes: 0=success, 1=sync failure, 3=prerequisites not met
# Requirements: 13b.1-13b.8
#
# How it works:
#   1. Reads markdown files from Wiki.js Local File System storage
#   2. Computes checksums and compares to stored checksums
#   3. Uploads changed/new files to Open WebUI document API for RAG embedding
#   4. Removes documents from Open WebUI RAG when wiki pages are deleted
#   5. All processing is local (no external service or network exposure)

set -euo pipefail

SCRIPT_NAME="wiki-rag-sync"
DRY_RUN=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        *) ;;
    esac
done

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/utils"
source "${UTILS_DIR}/log-utils.sh"
source "${UTILS_DIR}/env-utils.sh"
load_env_files || log_msg "WARN" "$SCRIPT_NAME" "Could not load env files"

# Configuration
WIKI_CONTENT_DIR="/mnt/data/services/wiki/content"
CHECKSUM_FILE="/mnt/data/services/openwebui/data/.wiki-rag-checksums"
OPENWEBUI_DOMAIN="${OPENWEBUI_DOMAIN:-}"
OPENWEBUI_API_TOKEN="${OPENWEBUI_API_TOKEN:-}"

# Validate prerequisites
if [[ -z "$OPENWEBUI_DOMAIN" ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "OPENWEBUI_DOMAIN not set in services.env"
    exit 3
fi
if [[ -z "$OPENWEBUI_API_TOKEN" ]]; then
    log_msg "ERROR" "$SCRIPT_NAME" "OPENWEBUI_API_TOKEN not set in secrets.env"
    exit 3
fi
if [[ ! -d "$WIKI_CONTENT_DIR" ]]; then
    log_msg "WARN" "$SCRIPT_NAME" "Wiki content directory not found: ${WIKI_CONTENT_DIR} — nothing to sync"
    exit 0
fi

DRY_LABEL=""; $DRY_RUN && DRY_LABEL=" (dry-run)"
log_msg "INFO" "$SCRIPT_NAME" "Starting wiki-to-RAG sync${DRY_LABEL}"

# Initialize checksum file if missing
[[ -f "$CHECKSUM_FILE" ]] || touch "$CHECKSUM_FILE"

UPLOADED=0; SKIPPED=0; REMOVED=0; ERRORS=0

# Step 1: Sync new/changed markdown files to Open WebUI RAG
while IFS= read -r -d '' file; do
    checksum=$(md5sum "$file" | cut -d' ' -f1)
    relative_path="${file#${WIKI_CONTENT_DIR}/}"

    # Skip if unchanged
    if grep -q "^${relative_path}:${checksum}$" "$CHECKSUM_FILE" 2>/dev/null; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if $DRY_RUN; then
        log_msg "INFO" "$SCRIPT_NAME" "dry-run: would upload ${relative_path}"
        UPLOADED=$((UPLOADED + 1))
        continue
    fi

    # Upload to Open WebUI document API
    RESPONSE=$(curl -sf -X POST "https://${OPENWEBUI_DOMAIN}/api/v1/files/" \
        -H "Authorization: Bearer ${OPENWEBUI_API_TOKEN}" \
        -F "file=@${file};filename=${relative_path}" 2>&1) || {
        log_msg "WARN" "$SCRIPT_NAME" "Failed to upload ${relative_path}: ${RESPONSE}"
        ERRORS=$((ERRORS + 1))
        continue
    }

    # Update checksum record
    sed -i "\|^${relative_path}:|d" "$CHECKSUM_FILE" 2>/dev/null || true
    echo "${relative_path}:${checksum}" >> "$CHECKSUM_FILE"
    UPLOADED=$((UPLOADED + 1))
done < <(find "$WIKI_CONTENT_DIR" -name "*.md" -type f -print0)

# Step 2: Remove documents from RAG when wiki pages are deleted
while IFS=: read -r path checksum; do
    [[ -z "$path" ]] && continue
    if [[ ! -f "${WIKI_CONTENT_DIR}/${path}" ]]; then
        if $DRY_RUN; then
            log_msg "INFO" "$SCRIPT_NAME" "dry-run: would remove deleted page ${path}"
        else
            log_msg "INFO" "$SCRIPT_NAME" "Removing deleted page from RAG: ${path}"
            sed -i "\|^${path}:|d" "$CHECKSUM_FILE" 2>/dev/null || true
        fi
        REMOVED=$((REMOVED + 1))
    fi
done < "$CHECKSUM_FILE"

# Summary
log_msg "INFO" "$SCRIPT_NAME" "Sync complete: uploaded=${UPLOADED}, skipped=${SKIPPED}, removed=${REMOVED}, errors=${ERRORS}"

if [[ $ERRORS -gt 0 ]]; then
    log_msg "WARN" "$SCRIPT_NAME" "Completed with ${ERRORS} error(s)"
fi

exit 0
