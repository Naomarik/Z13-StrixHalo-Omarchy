#!/bin/bash
#
# Power Profile Status Script for Waybar
# Returns JSON with current power profile icon and tooltip
#

STATE_FILE="/var/lib/performance-plus/active"
PROFILE=$(powerprofilesctl get 2>/dev/null || echo "balanced")

# Ultra overrides everything
if [[ -f "$STATE_FILE" ]]; then
    ICON="<span color='#ffaa00'>⚡</span> (U)"
    TOOLTIP="Power profile: Ultra (Performance Plus)\nRyzenAdj OC active — survives suspend"
else
    case "$PROFILE" in
        performance)
            ICON="<span color='#ff6666'>󰓅</span> (P)"
            TOOLTIP="Power profile: performance"
            ;;
        balanced)
            ICON="󰾅 (B)"
            TOOLTIP="Power profile: balanced"
            ;;
        power-saver)
            ICON="<span color='#6699ff'>󰾆</span> (Q)"
            TOOLTIP="Power profile: power-saver"
            ;;
        *)
            ICON=""
            TOOLTIP="Power profile: unknown"
            ;;
    esac
fi

# Return JSON for Waybar
echo "{\"text\":\"$ICON\",\"tooltip\":\"$TOOLTIP\"}"
