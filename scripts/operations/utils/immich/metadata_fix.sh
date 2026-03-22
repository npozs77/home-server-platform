#!/bin/bash
set -euo pipefail

# Metadata Fix Script — Photo Archive Prep
# Purpose: Write DateTimeOriginal EXIF field to files listed in metadata_missing.csv
# Location: scripts/operations/utils/immich/metadata_fix.sh
#
# Usage: metadata_fix.sh <metadata_missing.csv> [--dry-run]
#
# Workflow:
#   1. Run: photo_audit.sh <archive> --report
#   2. Edit: metadata_missing.csv — fill in FixDateTimeOriginal column
#      Format: YYYY:MM:DD HH:MM:SS (e.g., 2005:07:15 12:00:00)
#   3. Run: metadata_fix.sh metadata_missing.csv
#
# Safety:
#   - exiftool creates .jpg_original backup files by default
#   - Use --dry-run to preview changes without writing
#   - Only writes DateTimeOriginal (and CreateDate) to files with a non-empty FixDateTimeOriginal value
#
# Dependencies: exiftool (required)

CSV_FILE="${1:?Usage: metadata_fix.sh <metadata_missing.csv> [--dry-run]}"
DRY_RUN="${2:-}"

# ─── Dependency Check ────────────────────────────────────────────────────────

if ! command -v exiftool &>/dev/null; then
    echo "ERROR: exiftool is not installed (required)" >&2
    echo "  Install with: sudo apt install libimage-exiftool-perl" >&2
    exit 1
fi

# ─── Validation ──────────────────────────────────────────────────────────────

if [[ ! -f "$CSV_FILE" ]]; then
    echo "ERROR: CSV file '$CSV_FILE' does not exist" >&2
    exit 1
fi

if [[ ! -r "$CSV_FILE" ]]; then
    echo "ERROR: CSV file '$CSV_FILE' is not readable" >&2
    exit 1
fi

# Verify CSV has the expected header
HEADER=$(head -1 "$CSV_FILE")
if ! echo "$HEADER" | grep -q "FixDateTimeOriginal"; then
    echo "ERROR: CSV file missing 'FixDateTimeOriginal' column" >&2
    echo "  Expected header: filepath,extension,DateTimeOriginal,CreateDate,CameraModel,FileSize,FixDateTimeOriginal" >&2
    exit 1
fi

# ─── Process CSV ─────────────────────────────────────────────────────────────

echo "=== METADATA FIX ==="
echo "Input: $CSV_FILE"
if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "Mode:  DRY RUN (no changes will be made)"
else
    echo "Mode:  LIVE (exiftool will write EXIF data, originals backed up as .jpg_original)"
fi
echo ""

TOTAL=0
FIXED=0
SKIPPED=0
ERRORS=0
UNSUPPORTED=0
UNSUPPORTED_LIST=""

# Extensions that support EXIF date writing
EXIF_SUPPORTED="jpg jpeg tif tiff png heic heif dng cr2 cr3 nef arw orf rw2 pef srw raf mp4 mov avi m4v 3gp mts webp avif"

# Skip header line, process each row
# CSV: filepath,extension,DateTimeOriginal,CreateDate,CameraModel,FileSize,FixDateTimeOriginal
while IFS=',' read -r filepath ext dto createdate model filesize fix_dto; do
    TOTAL=$((TOTAL + 1))

    # Strip quotes and whitespace from fix_dto
    fix_dto=$(echo "$fix_dto" | sed 's/^"//;s/"$//;s/^[[:space:]]*//;s/[[:space:]]*$//')

    # Skip rows where FixDateTimeOriginal is empty
    if [[ -z "$fix_dto" ]]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Validate date format (YYYY:MM:DD HH:MM:SS)
    if ! [[ "$fix_dto" =~ ^[0-9]{4}:[0-9]{2}:[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        echo "  SKIP: $filepath — invalid date format: '$fix_dto' (expected YYYY:MM:DD HH:MM:SS)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Strip quotes from filepath
    filepath=$(echo "$filepath" | sed 's/^"//;s/"$//')

    # Check extension is EXIF-writable (silently skip unsupported)
    file_ext="${filepath##*.}"
    file_ext_lower=$(echo "$file_ext" | tr '[:upper:]' '[:lower:]')
    if ! echo " $EXIF_SUPPORTED " | grep -qi " $file_ext_lower "; then
        UNSUPPORTED=$((UNSUPPORTED + 1))
        UNSUPPORTED_LIST="${UNSUPPORTED_LIST}  ${filepath} (.${file_ext})\n"
        continue
    fi

    # Verify file exists
    if [[ ! -f "$filepath" ]]; then
        echo "  ERROR: File not found: $filepath"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        echo "  [DRY-RUN] Would set DateTimeOriginal='$fix_dto' on: $filepath"
        FIXED=$((FIXED + 1))
    else
        # Write DateTimeOriginal and CreateDate using exiftool
        if exiftool -DateTimeOriginal="$fix_dto" -CreateDate="$fix_dto" "$filepath" 2>/dev/null; then
            echo "  FIXED: $filepath → $fix_dto"
            FIXED=$((FIXED + 1))
        else
            echo "  ERROR: Failed to write EXIF to: $filepath"
            ERRORS=$((ERRORS + 1))
        fi
    fi
done < <(tail -n +2 "$CSV_FILE")

echo ""
echo "=== SUMMARY ==="
echo "Total rows:   $TOTAL"
echo "Fixed:        $FIXED"
echo "Skipped:      $SKIPPED (empty FixDateTimeOriginal)"
echo "Unsupported:  $UNSUPPORTED (format does not support EXIF write)"
echo "Errors:       $ERRORS"

if [[ "$UNSUPPORTED" -gt 0 ]]; then
    echo ""
    echo "Unsupported files (no EXIF write possible):"
    echo -e "$UNSUPPORTED_LIST"
fi

if [[ "$DRY_RUN" == "--dry-run" && "$FIXED" -gt 0 ]]; then
    echo ""
    echo "Hint: Remove --dry-run to apply changes."
fi

if [[ "$ERRORS" -gt 0 ]]; then
    exit 1
fi
