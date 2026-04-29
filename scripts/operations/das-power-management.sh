#!/bin/bash
# DAS Power Management — configure disk spindown for TerraMaster D4-320
# Usage: das-power-management.sh [status|apply|help]
# Exit: 0=success, 1=failure
#
# Disks spin down after 10 minutes idle to reduce energy use and disk wear.
# Config persisted in /etc/hdparm.conf (survives reboot).
#
# DAS disks:
#   sdb (usb-TerraMas_TDAS_WKPSM2W8) — 1TB backup, LUKS, /mnt/backup
#   sdc (usb-TerraMas_TDAS_WSC30NR9) — 8TB, unmounted (future use)
#
# What wakes the disks:
#   - Daily backup at 02:00 (backup-all.sh writes to /mnt/backup)
#   - Any manual access to /mnt/backup
# What does NOT wake the disks:
#   - Container health check (only runs docker inspect, no disk I/O)
#   - mountpoint -q check (kernel-level, no disk I/O on ext4)
#
# Fan note: D4-320 fan is hardware-controlled (always on when powered).
#   hdparm only controls disk spindown, not the enclosure fan.

set -euo pipefail

SCRIPT_NAME="das-power-management"
SPINDOWN_VALUE=120  # 120 = 10 minutes (value * 5 seconds)
APM_VALUE=127       # 1-127 allows spindown, 128-254 prevents it

# Stable disk IDs (won't change across reboots)
DISK_BACKUP="usb-TerraMas_TDAS_WKPSM2W8-0:0"
DISK_FUTURE="usb-TerraMas_TDAS_WSC30NR9-0:0"

resolve_dev() {
    local id="$1"
    local path="/dev/disk/by-id/${id}"
    if [[ -L "$path" ]]; then
        readlink -f "$path"
    else
        echo ""
    fi
}

show_status() {
    echo "=== DAS Disk Power Status ==="
    for id in "$DISK_BACKUP" "$DISK_FUTURE"; do
        local dev
        dev=$(resolve_dev "$id")
        if [[ -z "$dev" ]]; then
            echo "  ${id}: NOT CONNECTED"
            continue
        fi
        local state
        state=$(hdparm -C "$dev" 2>/dev/null | grep "drive state" | awk -F: '{print $2}' | xargs)
        local apm
        apm=$(hdparm -B "$dev" 2>/dev/null | grep "APM_level" | awk -F= '{print $2}' | xargs)
        echo "  ${dev} (${id}):"
        echo "    State: ${state:-unknown}"
        echo "    APM:   ${apm:-not supported}"
    done
}

apply_settings() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: must be run as root (sudo)"
        exit 1
    fi

    for id in "$DISK_BACKUP" "$DISK_FUTURE"; do
        local dev
        dev=$(resolve_dev "$id")
        if [[ -z "$dev" ]]; then
            echo "  ${id}: NOT CONNECTED — skipping"
            continue
        fi
        echo "  Setting spindown=${SPINDOWN_VALUE} on ${dev}..."
        hdparm -S "$SPINDOWN_VALUE" "$dev"
        # APM only if supported
        if hdparm -B "$dev" 2>/dev/null | grep -q "APM_level"; then
            echo "  Setting APM=${APM_VALUE} on ${dev}..."
            hdparm -B "$APM_VALUE" "$dev"
        fi
    done
    echo ""
    echo "Settings applied. Disks will spin down after 10 min idle."
    echo "Persistent config: /etc/hdparm.conf"
}

show_help() {
    echo "Usage: $0 [status|apply|help]"
    echo ""
    echo "  status  Show current disk power state (default)"
    echo "  apply   Apply spindown settings (requires root)"
    echo "  help    Show this help"
}

case "${1:-status}" in
    status) show_status ;;
    apply)  apply_settings ;;
    help)   show_help ;;
    *)      show_help; exit 1 ;;
esac
