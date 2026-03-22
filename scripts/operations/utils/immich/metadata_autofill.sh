#!/bin/bash
set -euo pipefail

# Metadata Autofill Script — Photo Archive Prep
# Purpose: Interactive line-by-line autofill of FixDateTimeOriginal in metadata_missing.csv
# Location: scripts/operations/utils/immich/metadata_autofill.sh
#
# Usage: metadata_autofill.sh <metadata_missing.csv>
#
# Workflow:
#   1. Run: photo_audit.sh <archive> --report   → generates metadata_missing.csv
#   2. Run: metadata_autofill.sh metadata_missing.csv  → interactive fill
#   3. Run: metadata_fix.sh metadata_missing.csv --dry-run
#   4. Run: metadata_fix.sh metadata_missing.csv
#
# For each row the script:
#   - Tries to guess a date from CreateDate, filename, or folder name
#   - Shows the file and suggested date
#   - Enter = accept suggestion, type a date = override, empty Enter (no suggestion) = skip
#
# Guess Priority (first match wins):
#   1. CreateDate from EXIF (if present in CSV row)
#   2. YYYYMMDD_HHMMSS from filename (e.g., 20210716_134557.mp4)
#   3. YYYYMMDD from filename with time 12:00:00 (e.g., IMG-20170801-WA0001.jpg)
#   4. YYYY_MM_DD or YYYY_MM from parent folder name (e.g., 2004_12_05/)
#   5. No guess — user enters manually or skips
#
# Safety: Does NOT modify any photo files. Only updates the CSV.

CSV_FILE="${1:?Usage: metadata_autofill.sh <metadata_missing.csv>}"

# Extensions that support EXIF date writing
EXIF_SUPPORTED="jpg jpeg tif tiff png heic heif dng cr2 cr3 nef arw orf rw2 pef srw raf mp4 mov avi m4v 3gp mts webp avif"

# ─── Validation ──────────────────────────────────────────────────────────────

if [[ ! -f "$CSV_FILE" ]]; then
    echo "ERROR: CSV file '$CSV_FILE' does not exist" >&2
    exit 1
fi

HEADER=$(head -1 "$CSV_FILE")
if ! echo "$HEADER" | grep -q "FixDateTimeOriginal"; then
    echo "ERROR: CSV missing 'FixDateTimeOriginal' column" >&2
    exit 1
fi

# ─── Guess Functions ─────────────────────────────────────────────────────────

is_plausible_date() {
    local dt="$1"
    # Use 10# prefix to force base-10 (avoids octal interpretation of 08, 09)
    local y=$((10#${dt:0:4})) m=$((10#${dt:5:2})) d=$((10#${dt:8:2}))
    [[ "$y" -ge 1990 && "$y" -le 2030 ]] && \
    [[ "$m" -ge 1 && "$m" -le 12 ]] && \
    [[ "$d" -ge 1 && "$d" -le 31 ]]
}

guess_date() {
    local filepath="$1" filename="$2" createdate="$3"
    local guess="" source=""

    # Strip quotes
    createdate=$(echo "$createdate" | sed 's/^"//;s/"$//')
    filepath=$(echo "$filepath" | sed 's/^"//;s/"$//')
    filename=$(echo "$filename" | sed 's/^"//;s/"$//')

    # Priority 1: CreateDate from EXIF
    if [[ -n "$createdate" ]] && [[ "$createdate" =~ ^[0-9]{4}:[0-9]{2}:[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        if is_plausible_date "$createdate"; then
            echo "$createdate|CreateDate"
            return 0
        fi
    fi

    # Priority 2: YYYYMMDD_HHMMSS in filename
    if [[ "$filename" =~ ([0-9]{4})([0-9]{2})([0-9]{2})[_-]([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
        guess="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
        if is_plausible_date "$guess"; then
            echo "$guess|filename_datetime"
            return 0
        fi
    fi

    # Priority 3: YYYYMMDD in filename (time defaults to 12:00:00)
    if [[ "$filename" =~ ([0-9]{4})([0-9]{2})([0-9]{2}) ]]; then
        guess="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]} 12:00:00"
        if is_plausible_date "$guess"; then
            echo "$guess|filename_date"
            return 0
        fi
    fi

    # Priority 4: Parent folder YYYY_MM_DD or YYYY-MM-DD
    local parent
    parent=$(basename "$(dirname "$filepath")")
    if [[ "$parent" =~ ^([0-9]{4})[_-]([0-9]{2})[_-]([0-9]{2}) ]]; then
        guess="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]} 12:00:00"
        if is_plausible_date "$guess"; then
            echo "$guess|folder_ymd"
            return 0
        fi
    fi

    # Priority 4b: Parent folder YYYY_MM or YYYY-MM
    if [[ "$parent" =~ ^([0-9]{4})[_-]([0-9]{2})$ ]]; then
        guess="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:01 12:00:00"
        if is_plausible_date "$guess"; then
            echo "$guess|folder_ym"
            return 0
        fi
    fi

    return 1
}

# ─── Interactive Processing ──────────────────────────────────────────────────

echo "=== METADATA AUTOFILL (interactive) ==="
echo "Input: $CSV_FILE"
echo ""
echo "For each file:"
echo "  Enter       = accept suggestion"
echo "  Type a date = override (YYYY:MM:DD HH:MM:SS or just YYYY:MM:DD)"
echo "  Empty Enter = skip (leave for later)"
echo "  q           = quit (saves progress so far)"
echo ""

# ─── Load all lines into array for safe quit handling ────────────────────────

mapfile -t DATA_LINES < <(tail -n +2 "$CSV_FILE")
LINE_COUNT=${#DATA_LINES[@]}

ROW=0
FILLED=0
SKIPPED=0
ALREADY=0
UNSUPPORTED=0
UNSUPPORTED_LIST=""
QUIT=false

TMP_FILE="${CSV_FILE}.tmp"
echo "$HEADER" > "$TMP_FILE"

for line in "${DATA_LINES[@]}"; do
    ROW=$((ROW + 1))

    # Parse fields — CSV: filepath,extension,DateTimeOriginal,CreateDate,CameraModel,FileSize,FixDateTimeOriginal
    filepath=$(echo "$line" | awk -F',' '{print $1}' | sed 's/^"//;s/"$//')
    filename=$(basename "$filepath")
    createdate=$(echo "$line" | awk -F',' '{print $4}')

    # Skip EXIF-unsupported formats silently
    file_ext="${filepath##*.}"
    file_ext_lower=$(echo "$file_ext" | tr '[:upper:]' '[:lower:]')
    if ! echo " $EXIF_SUPPORTED " | grep -qi " $file_ext_lower "; then
        echo "$line" >> "$TMP_FILE"
        UNSUPPORTED=$((UNSUPPORTED + 1))
        UNSUPPORTED_LIST="${UNSUPPORTED_LIST}  ${filepath} (.${file_ext})\n"
        continue
    fi

    # Skip already-filled rows silently (for multi-iteration use)
    existing=$(echo "$line" | awk -F',' '{print $7}' | sed 's/^"//;s/"$//;s/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -n "$existing" ]] && [[ "$existing" =~ ^[0-9]{4}: ]]; then
        echo "$line" >> "$TMP_FILE"
        ALREADY=$((ALREADY + 1))
        continue
    fi

    # Try to guess
    guess_result=$(guess_date "$filepath" "$filename" "$createdate" 2>/dev/null) || guess_result=""
    guess_val=""
    guess_src=""
    if [[ -n "$guess_result" ]]; then
        guess_val="${guess_result%%|*}"
        guess_src="${guess_result##*|}"
    fi

    # Show prompt
    short_path=$(echo "$filepath" | rev | cut -d'/' -f1-3 | rev)
    if [[ -n "$guess_val" ]]; then
        printf "\n[%d/%d] %s\n" "$ROW" "$LINE_COUNT" "$short_path"
        printf "  Suggest: %s (%s)\n" "$guess_val" "$guess_src"
        printf "  [Enter]=accept, type date=override, [s]=skip, [q]=quit: "
    else
        printf "\n[%d/%d] %s\n" "$ROW" "$LINE_COUNT" "$short_path"
        printf "  No guess available\n"
        printf "  Type date (YYYY:MM:DD HH:MM:SS or YYYY:MM:DD), [Enter]=skip, [q]=quit: "
    fi

    read -r user_input </dev/tty

    # Quit — write current + all remaining lines unchanged
    if [[ "$user_input" == "q" ]]; then
        echo "$line" >> "$TMP_FILE"
        SKIPPED=$((SKIPPED + 1))
        # Append remaining unprocessed lines
        local_idx=$ROW
        while [[ $local_idx -lt $LINE_COUNT ]]; do
            echo "${DATA_LINES[$local_idx]}" >> "$TMP_FILE"
            local_idx=$((local_idx + 1))
        done
        QUIT=true
        break
    fi

    # Skip explicitly
    if [[ "$user_input" == "s" ]]; then
        echo "$line" >> "$TMP_FILE"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if [[ -n "$guess_val" ]] && [[ -z "$user_input" ]]; then
        # Accept suggestion
        final_date="$guess_val"
    elif [[ -n "$user_input" ]]; then
        # User typed a date — accept full datetime or date-only (auto-appends 12:00:00)
        if [[ "$user_input" =~ ^[0-9]{4}:[0-9]{2}:[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
            final_date="$user_input"
        elif [[ "$user_input" =~ ^[0-9]{4}:[0-9]{2}:[0-9]{2}$ ]]; then
            final_date="$user_input 12:00:00"
        else
            echo "  Invalid format, skipping."
            echo "$line" >> "$TMP_FILE"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
    else
        # No guess + empty Enter = skip
        echo "$line" >> "$TMP_FILE"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Write line with FixDateTimeOriginal filled in
    # Rebuild: first 6 fields + final_date (column 7 = FixDateTimeOriginal)
    prefix=$(echo "$line" | awk -F',' '{OFS=","; NF=6; print}')
    echo "${prefix},${final_date}" >> "$TMP_FILE"
    FILLED=$((FILLED + 1))

done

mv "$TMP_FILE" "$CSV_FILE"

echo ""
echo "=== SUMMARY ==="
echo "Total:       $LINE_COUNT"
echo "Filled:      $FILLED"
echo "Skipped:     $SKIPPED (empty, for later)"
echo "Already:     $ALREADY (from previous run)"
echo "Unsupported: $UNSUPPORTED (format does not support EXIF write)"
if [[ "$QUIT" == "true" ]]; then
    echo "Quit early — progress saved. Run again to continue."
fi
if [[ "$UNSUPPORTED" -gt 0 ]]; then
    echo ""
    echo "Unsupported files (no EXIF write possible):"
    echo -e "$UNSUPPORTED_LIST"
fi
echo ""
if [[ "$FILLED" -gt 0 ]]; then
    echo "Next: metadata_fix.sh $CSV_FILE --dry-run"
fi
