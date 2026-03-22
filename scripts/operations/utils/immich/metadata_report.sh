#!/bin/bash
set -euo pipefail

# Metadata Report Module — Photo Archive Audit
# Purpose: Analyze EXIF metadata completeness across a photo archive
# Location: scripts/operations/utils/immich/metadata_report.sh
# Requirements: 45.1-45.6, 47.1-47.4, 49.1-49.4, 51.1-51.2, 53.2, 53.5, 53.6
#
# Usage: metadata_report.sh <archive_directory> [--report]
#   archive_directory  Path to the photo archive (read-only access)
#   --report           Generate CSV metadata inventory file in current directory
#
# Safety: All operations are READ-ONLY. No files in the archive are modified.
# Dependencies: exiftool (required)
#
# Output patterns consumed by orchestrator (photo_audit.sh):
#   "Files with DateTimeOriginal: NNN"
#   "Files missing DateTimeOriginal: NNN"
#   "Files with metadata warnings: NNN"
#   Section "Camera/Device Sources" followed by count+model lines

# ─── Configuration ───────────────────────────────────────────────────────────

ARCHIVE_DIR="${1:?Usage: metadata_report.sh <archive_directory> [--report]}"
REPORT_FLAG="${2:-}"

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

# ─── Metadata Extraction (batch mode, read-only) ────────────────────────────

echo "--- Metadata Completeness ---"

# Use ExifTool batch mode for efficiency (read-only, -fast flag)
# Single pass: extract key fields as CSV for streaming processing
# Req 45.5: exiftool -fast (read-only fast mode)
# Req 52.4: batch mode (-csv -r) not per-file invocation
EXIF_OUTPUT=$(exiftool -fast -csv -r \
    -DateTimeOriginal -CreateDate -Model \
    "$ARCHIVE_DIR" 2>/dev/null || true)

# Extract data rows (skip CSV header line)
DATA_ROWS=$(echo "$EXIF_OUTPUT" | tail -n +2)

# Count total files processed
TOTAL=0
if [[ -n "$DATA_ROWS" ]]; then
    TOTAL=$(echo "$DATA_ROWS" | wc -l)
fi

# Req 45.1: Count files with valid DateTimeOriginal
HAS_DTO=0
if [[ "$TOTAL" -gt 0 ]]; then
    HAS_DTO=$(echo "$DATA_ROWS" | awk -F',' '$2 != ""' | wc -l)
fi

# Req 45.2: Count files missing DateTimeOriginal
MISSING_DTO=$((TOTAL - HAS_DTO))

# Req 45.3: Count files with valid CreateDate
HAS_CD=0
if [[ "$TOTAL" -gt 0 ]]; then
    HAS_CD=$(echo "$DATA_ROWS" | awk -F',' '$3 != ""' | wc -l)
fi

# Req 45.4: Count files with camera Model
HAS_MODEL=0
if [[ "$TOTAL" -gt 0 ]]; then
    HAS_MODEL=$(echo "$DATA_ROWS" | awk -F',' '$4 != ""' | wc -l)
fi

# Req 45.6: Files with no EXIF metadata at all (no DTO, no CreateDate, no Model)
NO_METADATA=0
if [[ "$TOTAL" -gt 0 ]]; then
    NO_METADATA=$(echo "$DATA_ROWS" | awk -F',' '$2 == "" && $3 == "" && $4 == ""' | wc -l)
fi

echo "Total files scanned: $TOTAL"
echo "Files with DateTimeOriginal: $HAS_DTO"
echo "Files missing DateTimeOriginal: $MISSING_DTO"
echo "Files with CreateDate: $HAS_CD"
echo "Files with Camera Model: $HAS_MODEL"
echo "Files with no metadata: $NO_METADATA"

# ─── Metadata Warnings/Errors Detection ─────────────────────────────────────
# Req 49.1-49.4: Detect files where ExifTool reports warnings or errors

echo ""
echo "--- Metadata Warnings ---"

# Capture stderr from the exiftool extraction for warnings/errors
# Run a separate pass to detect warnings (exiftool prints warnings to stderr)
WARN_OUTPUT=$(exiftool -fast -r -q -q "$ARCHIVE_DIR" 2>&1 1>/dev/null || true)

ERROR_COUNT=0
if [[ -n "$WARN_OUTPUT" ]]; then
    ERROR_COUNT=$(echo "$WARN_OUTPUT" | grep -ci "warning\|error" || true)
fi

echo "Files with metadata warnings: $ERROR_COUNT"

# Req 49.3: Report error types if any found
if [[ "$ERROR_COUNT" -gt 0 ]]; then
    echo ""
    echo "Warning/error types:"
    echo "$WARN_OUTPUT" \
        | grep -i "warning\|error" \
        | sed 's/.*Warning: //' \
        | sed 's/.*Error: //' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -10 \
        | while read -r count msg; do
            printf "  %5d  %s\n" "$count" "$msg"
        done
fi

# ─── Camera/Device Source Breakdown ──────────────────────────────────────────
# Req 47.1-47.4: Group by camera Model, sort by count descending

echo ""
echo "--- Camera/Device Sources ---"

if [[ "$TOTAL" -gt 0 ]]; then
    # Req 47.3: Files with no model → "Unknown"
    # Req 47.4: Sort by count descending
    echo "$DATA_ROWS" \
        | awk -F',' '{
            model = $4
            # Strip surrounding quotes if present
            gsub(/^"/, "", model)
            gsub(/"$/, "", model)
            # Trim whitespace
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", model)
            if (model == "") model = "Unknown"
            print model
        }' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -15 \
        | while read -r count model; do
            printf "  %5d  %s\n" "$count" "$model"
        done
else
    echo "  (no files found)"
fi

# ─── Optional CSV Report ────────────────────────────────────────────────────
# Req 51.1-51.2: Generate CSV metadata inventory when --report flag provided
# Columns: filepath, extension, DateTimeOriginal, CreateDate, CameraModel, FileSize

if [[ "$REPORT_FLAG" == "--report" ]]; then
    echo ""
    echo "--- Generating CSV Report ---"

    REPORT_FILE="./metadata_inventory.csv"

    # Full extraction with FileSize for the report (separate pass for complete data)
    # Req 51.2: Include filepath, extension, DateTimeOriginal, CreateDate, CameraModel, FileSize
    # Note: exiftool -csv always includes SourceFile as column 1 automatically
    REPORT_OUTPUT=$(exiftool -fast -csv -r \
        -FileTypeExtension -DateTimeOriginal -CreateDate -Model -FileSize \
        "$ARCHIVE_DIR" 2>/dev/null || true)

    if [[ -n "$REPORT_OUTPUT" ]]; then
        # Write header with standardized column names
        echo "filepath,extension,DateTimeOriginal,CreateDate,CameraModel,FileSize" > "$REPORT_FILE"
        # Write data rows (skip exiftool's own header)
        echo "$REPORT_OUTPUT" | tail -n +2 >> "$REPORT_FILE"
        REPORT_LINES=$(echo "$REPORT_OUTPUT" | tail -n +2 | wc -l)
        echo "CSV report written to: $REPORT_FILE ($REPORT_LINES files)"

        # Generate metadata_missing.csv — only files with missing DateTimeOriginal
        # Includes a FixDateTimeOriginal column for manual editing before running metadata_fix.sh
        # CSV columns: SourceFile(1),FileTypeExtension(2),DateTimeOriginal(3),CreateDate(4),Model(5),FileSize(6)
        MISSING_FILE="./metadata_missing.csv"
        echo "filepath,extension,DateTimeOriginal,CreateDate,CameraModel,FileSize,FixDateTimeOriginal" > "$MISSING_FILE"
        echo "$REPORT_OUTPUT" | tail -n +2 \
            | awk -F',' '{
                dto = $3
                gsub(/^"/, "", dto)
                gsub(/"$/, "", dto)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", dto)
                if (dto == "") print $0 ","
            }' >> "$MISSING_FILE"
        MISSING_LINES=$(tail -n +2 "$MISSING_FILE" | wc -l)
        echo "Missing metadata report written to: $MISSING_FILE ($MISSING_LINES files)"
        if [[ "$MISSING_LINES" -gt 0 ]]; then
            echo "  → Fill in the FixDateTimeOriginal column (format: YYYY:MM:DD HH:MM:SS)"
            echo "  → Then run: metadata_fix.sh $MISSING_FILE"
        fi
    else
        echo "filepath,extension,DateTimeOriginal,CreateDate,CameraModel,FileSize" > "$REPORT_FILE"
        echo "CSV report written to: $REPORT_FILE (0 files)"
    fi
fi

echo ""
echo "--- Metadata Report Complete ---"
