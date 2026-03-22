#!/bin/bash
set -euo pipefail

# Year Distribution Module — Photo Archive Audit
# Purpose: Analyze year distribution of photos based on EXIF DateTimeOriginal
# Location: scripts/operations/utils/immich/year_distribution.sh
# Requirements: 46.1-46.5, 51.4, 53.4, 53.5, 53.6
#
# Usage: year_distribution.sh <archive_directory> [--report]
#   archive_directory  Path to the photo archive (read-only access)
#   --report           Generate year distribution CSV file in current directory
#
# Safety: All operations are READ-ONLY. No files in the archive are modified.
# Dependencies: exiftool (required)
#
# Output patterns consumed by orchestrator (photo_audit.sh):
#   "Year distribution:" followed by year/count lines
#   "  YYYY: NNN files" or "  YYYY: NNN files  ⚠ ANOMALY"
#   "  Unknown: NNN files"
#   "Anomalous years: NNN files (outside 1990–YYYY range)"

# ─── Configuration ───────────────────────────────────────────────────────────

ARCHIVE_DIR="${1:?Usage: year_distribution.sh <archive_directory> [--report]}"
REPORT_FLAG="${2:-}"
CURRENT_YEAR=$(date +%Y)

# ─── Dependency Check ────────────────────────────────────────────────────────

if ! command -v exiftool &>/dev/null; then
    echo "ERROR: exiftool is not installed (required)" >&2
    echo "  Install with: sudo apt install libimage-exiftool-perl" >&2
    exit 1
fi

# ─── Validation ──────────────────────────────────────────────────────────────

if [[ ! -d "$ARCHIVE_DIR" ]]; then
    echo "ERROR: Archive directory '$ARCHIVE_DIR' does not exist" >&2
    exit 1
fi

if [[ ! -r "$ARCHIVE_DIR" ]]; then
    echo "ERROR: Archive directory '$ARCHIVE_DIR' is not readable" >&2
    exit 1
fi

# ─── Year Extraction (batch mode, read-only) ────────────────────────────────
# Req 46.1: Extract year from DateTimeOriginal EXIF field
# Req 52.4: Use ExifTool batch mode (-fast -r) for efficiency

echo "--- Year Distribution ---"

# Count total files in archive (ground truth)
TOTAL_FILES=$(find "$ARCHIVE_DIR" -type f 2>/dev/null | wc -l)

# Single batch extraction: get DateTimeOriginal for all files
# -s3 outputs bare values (no tag names)
# Use -csv -r for reliable per-file output (one row per file, empty field if missing)
EXIF_CSV=$(exiftool -fast -csv -r -DateTimeOriginal "$ARCHIVE_DIR" 2>/dev/null || true)

# Extract years from CSV data rows (skip header), count per year, sort ascending
# CSV format: "SourceFile","DateTimeOriginal"
# DateTimeOriginal format: "YYYY:MM:DD HH:MM:SS" — first 4 chars = year
YEAR_COUNTS=""
DATED_FILE_COUNT=0
if [[ -n "$EXIF_CSV" ]]; then
    YEAR_COUNTS=$(echo "$EXIF_CSV" \
        | tail -n +2 \
        | awk -F',' '{
            dto = $2
            gsub(/^"/, "", dto)
            gsub(/"$/, "", dto)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", dto)
            if (dto != "") print substr(dto,1,4)
        }' \
        | sort \
        | uniq -c \
        | sort -k2 -n)
    if [[ -n "$YEAR_COUNTS" ]]; then
        DATED_FILE_COUNT=$(echo "$YEAR_COUNTS" | awk '{s+=$1} END {print s+0}')
    fi
fi

# Req 46.3: Files with no DateTimeOriginal = total files minus files with a valid year
NO_DATE=$((TOTAL_FILES - DATED_FILE_COUNT))

# ─── Display Year Distribution ───────────────────────────────────────────────
# Req 46.2: Report file counts grouped by year in ascending order
# Req 46.4: Flag years outside plausible range (before 1990 or after current year)

ANOMALY_COUNT=0

if [[ -n "$YEAR_COUNTS" ]]; then
    while read -r count year; do
        # Skip malformed entries (already excluded from DATED_FILE_COUNT)
        if [[ -z "$year" ]] || ! [[ "$year" =~ ^[0-9]{4}$ ]]; then
            continue
        fi

        if (( year < 1990 )) || (( year > CURRENT_YEAR )); then
            echo "  $year: $count files  ⚠ ANOMALY"
            ANOMALY_COUNT=$((ANOMALY_COUNT + count))
        else
            echo "  $year: $count files"
        fi
    done <<< "$YEAR_COUNTS"
fi

# Req 46.3: Report unknown category
if [[ "$NO_DATE" -gt 0 ]]; then
    echo "  Unknown: $NO_DATE files"
fi

# Req 46.5: Display warning with count of anomalous files
if [[ "$ANOMALY_COUNT" -gt 0 ]]; then
    echo ""
    echo "  ⚠ WARNING: Anomalous years: $ANOMALY_COUNT files (outside 1990–$CURRENT_YEAR range)"
fi

# ─── Optional CSV Report ────────────────────────────────────────────────────
# Req 51.4: Generate year distribution summary file when --report flag provided

if [[ "$REPORT_FLAG" == "--report" ]]; then
    echo ""
    echo "--- Generating Year Distribution Report ---"

    REPORT_FILE="./year_distribution.csv"
    echo "year,count" > "$REPORT_FILE"

    if [[ -n "$YEAR_COUNTS" ]]; then
        while read -r count year; do
            if [[ -n "$year" ]] && [[ "$year" =~ ^[0-9]{4}$ ]]; then
                echo "$year,$count" >> "$REPORT_FILE"
            fi
        done <<< "$YEAR_COUNTS"
    fi

    # Include Unknown row if any files lack DateTimeOriginal
    if [[ "$NO_DATE" -gt 0 ]]; then
        echo "Unknown,$NO_DATE" >> "$REPORT_FILE"
    fi

    REPORT_LINES=$(wc -l < "$REPORT_FILE")
    echo "Year distribution report written to: $REPORT_FILE ($((REPORT_LINES - 1)) entries)"
fi

echo ""
echo "--- Year Distribution Complete ---"
