#!/bin/bash
set -euo pipefail

# Photo Archive Audit — Orchestrator Script
# Purpose: Run all inspection modules against a photo archive and print a console summary
# Location: scripts/operations/utils/immich/photo_audit.sh
# Requirements: 43.1, 43.3, 43.4, 44.1-44.5, 50.1-50.7, 52.2, 53.1, 53.7
#
# Usage: photo_audit.sh <archive_directory> [--report]
#   archive_directory  Path to the photo archive (read-only access)
#   --report           Generate CSV/detailed report files in current directory
#
# Safety: All operations are READ-ONLY. No files in the archive are modified.
# Dependencies: exiftool (required), jdupes (optional)

# ─── Configuration ───────────────────────────────────────────────────────────

ARCHIVE_DIR="${1:?Usage: photo_audit.sh <archive_directory> [--report]}"
REPORT_FLAG="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Validation Functions ────────────────────────────────────────────────────

validate_archive_directory() {
    if [[ ! -d "$ARCHIVE_DIR" ]]; then
        echo "ERROR: Archive directory '$ARCHIVE_DIR' does not exist" >&2
        exit 1
    fi
    if [[ ! -r "$ARCHIVE_DIR" ]]; then
        echo "ERROR: Archive directory '$ARCHIVE_DIR' is not readable" >&2
        exit 1
    fi
}

validate_dependencies() {
    local missing=0

    # exiftool is REQUIRED
    if ! command -v exiftool &>/dev/null; then
        echo "ERROR: exiftool is not installed (required)" >&2
        echo "  Install with: sudo apt install libimage-exiftool-perl" >&2
        missing=1
    fi

    # jdupes is OPTIONAL — warn but continue
    if ! command -v jdupes &>/dev/null; then
        echo "WARNING: jdupes is not installed — duplicate detection will be skipped" >&2
        echo "  Install with: sudo apt install jdupes" >&2
    fi

    if [[ "$missing" -eq 1 ]]; then
        exit 1
    fi
}

# ─── File Inventory (inline — lightweight) ───────────────────────────────────

run_file_inventory() {
    echo "--- File Inventory ---"

    TOTAL_FILES=$(find "$ARCHIVE_DIR" -type f 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)

    echo "Total files: $TOTAL_FILES"
    echo "Total size:  $TOTAL_SIZE"
    echo ""

    # Extension breakdown (case-insensitive matching)
    echo "Extension breakdown (top 20):"
    if [[ "$TOTAL_FILES" -gt 0 ]]; then
        find "$ARCHIVE_DIR" -type f 2>/dev/null \
            | sed 's/.*\.//' \
            | tr '[:upper:]' '[:lower:]' \
            | sort \
            | uniq -c \
            | sort -rn \
            | head -20 \
            | while read -r count ext; do
                printf "  %-12s %s files\n" ".$ext" "$count"
            done
    else
        echo "  (no files found)"
    fi
    echo ""

    # Immich compatibility check
    # Supported extensions from https://immich.app/docs/features/supported-formats
    local IMMICH_IMAGE_EXTS="avif bmp gif heic heif jp2 jpeg jpg jpe insp jxl png psd raw rw2 svg tif tiff webp"
    local IMMICH_VIDEO_EXTS="3gp 3gpp avi flv m4v mkv mts m2ts m2t mp4 insv mpg mpe mpeg mov webm wmv"
    local ALL_SUPPORTED="$IMMICH_IMAGE_EXTS $IMMICH_VIDEO_EXTS"

    echo "--- Immich Compatibility ---"
    local supported_count=0
    local unsupported_count=0
    local unsupported_list=""

    if [[ "$TOTAL_FILES" -gt 0 ]]; then
        while read -r count ext; do
            local lower_ext
            lower_ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
            local found=false
            for supported in $ALL_SUPPORTED; do
                if [[ "$lower_ext" == "$supported" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == "true" ]]; then
                supported_count=$((supported_count + count))
            else
                unsupported_count=$((unsupported_count + count))
                unsupported_list="${unsupported_list}  .$lower_ext  $count files (not supported by Immich)\n"
            fi
        done < <(find "$ARCHIVE_DIR" -type f 2>/dev/null \
            | sed 's/.*\.//' \
            | tr '[:upper:]' '[:lower:]' \
            | sort \
            | uniq -c \
            | sort -rn)

        echo "Immich-supported files: $supported_count"
        echo "Unsupported files:      $unsupported_count"
        if [[ -n "$unsupported_list" ]]; then
            echo ""
            echo "Unsupported extensions:"
            echo -e "$unsupported_list"
        fi
    fi
    echo ""
}

# ─── Module Invocation ───────────────────────────────────────────────────────

run_module() {
    local module_name="$1"
    local module_path="$SCRIPT_DIR/$module_name"

    if [[ ! -f "$module_path" ]]; then
        echo "WARNING: Module '$module_name' not found at $module_path — skipping" >&2
        return 0
    fi
    if [[ ! -x "$module_path" ]]; then
        # Try running via bash if not executable
        bash "$module_path" "$ARCHIVE_DIR" $REPORT_FLAG
    else
        "$module_path" "$ARCHIVE_DIR" $REPORT_FLAG
    fi
}

# ─── Console Summary ─────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   AUDIT SUMMARY                            ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║  %-58s ║\n" "Total files:  $TOTAL_FILES"
    printf "║  %-58s ║\n" "Total size:   $TOTAL_SIZE"

    # File type count (unique extensions)
    local type_count
    type_count=$(find "$ARCHIVE_DIR" -type f 2>/dev/null \
        | sed 's/.*\.//' \
        | tr '[:upper:]' '[:lower:]' \
        | sort -u \
        | wc -l)
    printf "║  %-58s ║\n" "File types:   $type_count unique extensions"

    # Metadata completeness (from metadata_report.sh output captured earlier)
    if [[ -n "${META_HAS_DTO:-}" ]]; then
        printf "║  %-58s ║\n" "With DateTimeOriginal: $META_HAS_DTO"
        printf "║  %-58s ║\n" "Missing DateTimeOriginal: $META_MISSING_DTO"
    fi

    # Top cameras (from metadata_report.sh output captured earlier)
    if [[ -n "${META_TOP_CAMERAS:-}" ]]; then
        printf "║  %-58s ║\n" "Top cameras: $META_TOP_CAMERAS"
    fi

    # Duplicates (from duplicate_scan.sh output captured earlier)
    if [[ -n "${DUP_GROUPS:-}" ]]; then
        printf "║  %-58s ║\n" "Duplicate groups: $DUP_GROUPS"
        printf "║  %-58s ║\n" "Wasted space: ${DUP_WASTED:-unknown}"
    fi

    # Errors (from metadata_report.sh output captured earlier)
    if [[ -n "${META_ERRORS:-}" ]]; then
        printf "║  %-58s ║\n" "Metadata warnings: $META_ERRORS"
    fi

    echo "╚══════════════════════════════════════════════════════════════╝"
}

# ─── Output Capture Helpers ──────────────────────────────────────────────────

# Capture key metrics from module output for the summary
capture_metadata_metrics() {
    local output="$1"
    META_HAS_DTO=$(echo "$output" | grep -oP 'Files with DateTimeOriginal: \K\d+' || echo "")
    META_MISSING_DTO=$(echo "$output" | grep -oP 'Files missing DateTimeOriginal: \K\d+' || echo "")
    META_ERRORS=$(echo "$output" | grep -oP 'Files with metadata warnings: \K\d+' || echo "")
    META_TOP_CAMERAS=$(echo "$output" | sed -n '/Camera\/Device Sources/,/^$/p' \
        | grep -v "^$" | grep -v "Camera/Device" | grep -v "^---" \
        | head -3 | awk '{$1=$1; print}' | paste -sd ", " || echo "")
}

capture_duplicate_metrics() {
    local output="$1"
    DUP_GROUPS=$(echo "$output" | grep -oP 'Duplicate file groups: \K\S+' || echo "")
    DUP_WASTED=$(echo "$output" | grep -oP 'Estimated wasted space: \K.*' || echo "")
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    # Validate inputs and dependencies
    validate_archive_directory
    validate_dependencies

    echo "=== PHOTO ARCHIVE AUDIT ==="
    echo "Archive: $ARCHIVE_DIR"
    echo "Date:    $(date)"
    if [[ "$REPORT_FLAG" == "--report" ]]; then
        echo "Mode:    Full report (CSV files will be generated)"
    else
        echo "Mode:    Console summary only"
    fi
    echo ""

    # Initialize summary variables
    META_HAS_DTO=""
    META_MISSING_DTO=""
    META_ERRORS=""
    META_TOP_CAMERAS=""
    DUP_GROUPS=""
    DUP_WASTED=""

    # 1. File inventory (inline)
    run_file_inventory

    # 2. Metadata completeness report
    local meta_output
    meta_output=$(run_module "metadata_report.sh" 2>&1) || true
    echo "$meta_output"
    capture_metadata_metrics "$meta_output"

    # 3. Year distribution
    run_module "year_distribution.sh" || true

    # 4. Duplicate scan
    local dup_output
    dup_output=$(run_module "duplicate_scan.sh" 2>&1) || true
    echo "$dup_output"
    capture_duplicate_metrics "$dup_output"

    # Print consolidated summary
    print_summary

    echo ""
    echo "=== AUDIT COMPLETE ==="
}

main "$@"
