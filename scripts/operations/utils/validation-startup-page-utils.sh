#!/bin/bash
set -euo pipefail
# Utility: Caddy Startup Page Validation (unit tests + property-based tests)
# Usage: source this file, then call functions with file paths as arguments

if ! command -v print_success &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/output-utils.sh"
fi

# ── Unit Tests ──

# Validate startup page: exists, non-empty, <10KB, required elements
validate_startup_page_file() {
    local file="${1:?Usage: validate_startup_page_file <path>}" status="PASS"
    [[ -f "$file" ]] || { print_error "Startup page not found: $file"; return 1; }
    print_success "Startup page exists: $file"
    local size; size=$(wc -c < "$file")
    if [[ "$size" -eq 0 ]]; then print_error "Startup page is empty"; status="FAIL"
    elif [[ "$size" -gt 10240 ]]; then print_error "Startup page exceeds 10KB ($size bytes)"; status="FAIL"
    else print_success "Startup page size OK ($size bytes, limit 10240)"; fi
    local checks=('name="viewport":viewport meta tag' 'http-equiv="refresh":meta refresh tag'
        '@keyframes:spinner CSS animation' 'id="status":status element' '<script>:inline JavaScript')
    for c in "${checks[@]}"; do
        local pat="${c%%:*}" lbl="${c#*:}"
        if grep -q "$pat" "$file"; then print_success "Contains $lbl"
        else print_error "Missing $lbl ($pat)"; status="FAIL"; fi
    done
    [[ "$status" == "PASS" ]]
}

# Validate Caddy /srv/pages volume mounted read-only (server-side, skips gracefully)
validate_caddy_pages_volume() {
    if ! command -v docker &>/dev/null || ! docker ps &>/dev/null 2>&1; then
        print_info "Docker not available — skipping volume check"; return 0; fi
    if ! docker ps | grep -q caddy; then
        print_info "Caddy container not running — skipping volume check"; return 0; fi
    local mi; mi=$(docker inspect caddy \
        --format='{{range .Mounts}}{{if eq .Destination "/srv/pages"}}{{.Source}}->{{.Destination}}({{.Mode}}){{end}}{{end}}' 2>/dev/null)
    [[ -z "$mi" ]] && { print_error "Caddy missing /srv/pages volume mount"; return 1; }
    [[ "$mi" == *"(ro)"* ]] && { print_success "Caddy /srv/pages volume mounted read-only"; return 0; }
    print_error "Caddy /srv/pages volume NOT read-only: $mi"; return 1
}

# Validate pages directory exists (server-side, skips gracefully)
validate_pages_directory() {
    local dir="${1:-/opt/homeserver/configs/caddy/pages}"
    [[ -d "$dir" ]] && { print_success "Pages directory exists: $dir"; return 0; }
    print_info "Pages directory not found: $dir (expected on server)"; return 1
}

# ── Property-Based Tests ──

# Helper: detect site block start (non-indented domain line with {)
_is_site_start() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9.\-]*\.[a-zA-Z] ]] && [[ "$1" == *"{"* ]]; }
_site_name() { echo "$1" | sed 's/[[:space:]]*{.*//'; }

# Feature: caddy-startup-page, Property 1: No external resource references
validate_startup_page_no_external_refs() {
    local file="${1:?Usage: validate_startup_page_no_external_refs <path>}"
    [[ -f "$file" ]] || { print_error "File not found: $file"; return 1; }
    local v; v=$(grep -nEi '(src|href|url\s*\().*https?://|//[a-zA-Z]' "$file" || true)
    if [[ -n "$v" ]]; then
        print_error "Property 1 FAILED: External references in $file"; echo "$v" >&2; return 1; fi
    print_success "Property 1 PASSED: No external resource references in $(basename "$file")"
}

# Feature: caddy-startup-page, Property 2: Handle_errors block completeness
validate_caddyfile_handle_errors_complete() {
    local file="${1:?Usage: validate_caddyfile_handle_errors_complete <path>}"
    [[ -f "$file" ]] || { print_error "File not found: $file"; return 1; }
    local status="PASS" bc=0 ib=0 d=0 hr=0 hrt=0 hfs=0
    while IFS= read -r line; do
        if [[ $ib -eq 0 ]] && [[ "$line" =~ handle_errors ]]; then
            ib=1; d=0; bc=$((bc+1)); hr=0; hrt=0; hfs=0; fi
        if [[ $ib -eq 1 ]]; then
            [[ "$line" == *"{"* ]] && d=$((d+1))
            [[ "$line" == *"}"* ]] && d=$((d-1))
            [[ "$line" =~ rewrite.*starting\.html ]] && hr=1
            [[ "$line" =~ root.*\/srv\/pages ]] && hrt=1
            [[ "$line" =~ file_server ]] && hfs=1
            if [[ $d -eq 0 ]]; then
                ib=0; local m=""
                [[ $hr -eq 0 ]] && m+="rewrite "; [[ $hrt -eq 0 ]] && m+="root "; [[ $hfs -eq 0 ]] && m+="file_server "
                [[ -n "$m" ]] && { print_error "handle_errors #$bc incomplete — missing: $m"; status="FAIL"; }
            fi
        fi
    done < "$file"
    [[ $bc -eq 0 ]] && { print_error "Property 2 FAILED: No handle_errors blocks in $(basename "$file")"; return 1; }
    [[ "$status" == "PASS" ]] && { print_success "Property 2 PASSED: All $bc handle_errors blocks complete in $(basename "$file")"; return 0; }
    print_error "Property 2 FAILED: Incomplete handle_errors in $(basename "$file")"; return 1
}

# Feature: caddy-startup-page, Property 3: Universal handle_errors coverage
validate_caddyfile_handle_errors_coverage() {
    local file="${1:?Usage: validate_caddyfile_handle_errors_coverage <path>}"
    [[ -f "$file" ]] || { print_error "File not found: $file"; return 1; }
    local status="PASS" sc=0 is=0 d=0 he=0 sn=""
    while IFS= read -r line; do
        if [[ $is -eq 0 ]] && _is_site_start "$line"; then
            is=1; d=0; he=0; sn=$(_site_name "$line"); sc=$((sc+1)); fi
        if [[ $is -eq 1 ]]; then
            [[ "$line" == *"{"* ]] && d=$((d+1))
            [[ "$line" == *"}"* ]] && d=$((d-1))
            [[ "$line" =~ handle_errors ]] && he=1
            if [[ $d -eq 0 ]]; then
                is=0; [[ $he -eq 0 ]] && { print_error "Site '$sn' missing handle_errors"; status="FAIL"; }
            fi
        fi
    done < "$file"
    [[ $sc -eq 0 ]] && { print_error "Property 3 FAILED: No site blocks in $(basename "$file")"; return 1; }
    [[ "$status" == "PASS" ]] && { print_success "Property 3 PASSED: All $sc site blocks have handle_errors in $(basename "$file")"; return 0; }
    print_error "Property 3 FAILED: Missing handle_errors in $(basename "$file")"; return 1
}

# Feature: caddy-startup-page, Property 4: Handle_errors placement ordering
validate_caddyfile_handle_errors_ordering() {
    local file="${1:?Usage: validate_caddyfile_handle_errors_ordering <path>}"
    [[ -f "$file" ]] || { print_error "File not found: $file"; return 1; }
    local status="PASS" sc=0 is=0 d=0 sl=0 shbl=0 sn=""
    while IFS= read -r line; do
        if [[ $is -eq 0 ]] && _is_site_start "$line"; then
            is=1; d=0; sl=0; shbl=0; sn=$(_site_name "$line"); sc=$((sc+1)); fi
        if [[ $is -eq 1 ]]; then
            [[ "$line" == *"{"* ]] && d=$((d+1))
            [[ "$line" == *"}"* ]] && d=$((d-1))
            if [[ $d -le 1 ]]; then
                [[ "$line" =~ ^[[:space:]]*log([[:space:]]|$) ]] && sl=1
                [[ "$line" =~ ^[[:space:]]*handle_errors ]] && [[ $sl -eq 0 ]] && shbl=1
            fi
            if [[ $d -eq 0 ]]; then
                is=0; [[ $shbl -eq 1 ]] && { print_error "Site '$sn': handle_errors before log"; status="FAIL"; }
            fi
        fi
    done < "$file"
    [[ $sc -eq 0 ]] && { print_error "Property 4 FAILED: No site blocks in $(basename "$file")"; return 1; }
    [[ "$status" == "PASS" ]] && { print_success "Property 4 PASSED: handle_errors after log in all $sc site blocks in $(basename "$file")"; return 0; }
    print_error "Property 4 FAILED: Ordering violation in $(basename "$file")"; return 1
}

# ── Checks Registry ──
STARTUP_PAGE_CHECKS=(
    "Startup Page File:validate_startup_page_file"
    "Pages Volume Mount:validate_caddy_pages_volume"
    "Pages Directory:validate_pages_directory"
    "P1 No External Refs:validate_startup_page_no_external_refs"
    "P2 Handle_errors Complete:validate_caddyfile_handle_errors_complete"
    "P3 Handle_errors Coverage:validate_caddyfile_handle_errors_coverage"
    "P4 Handle_errors Ordering:validate_caddyfile_handle_errors_ordering"
)
