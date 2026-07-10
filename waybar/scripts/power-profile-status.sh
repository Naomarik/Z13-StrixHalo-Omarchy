#!/bin/bash
#
# Power Profile Status Script for Waybar
# Returns JSON with current power profile icon and tooltip
#

STATE_FILE="/var/lib/performance-plus/active"
PENDING="${XDG_RUNTIME_DIR:-/tmp}/power-profile-toggle/pending-profile"

power_profile_get() {
    python3.14 /usr/bin/powerprofilesctl get 2>/dev/null || powerprofilesctl get 2>/dev/null
}

PROFILE=""
ULTRA=false

# A pending click-selected profile takes precedence (ignore if stale >30s,
# e.g. leftover from a killed worker)
if [[ -s "$PENDING" ]] && (( $(date +%s) - $(stat -c %Y "$PENDING" 2>/dev/null || echo 0) < 30 )); then
    PROFILE=$(<"$PENDING")
    [[ "$PROFILE" == "ultra" ]] && ULTRA=true
else
    PROFILE=$(power_profile_get || echo "balanced")
    [[ -f "$STATE_FILE" ]] && ULTRA=true
fi

if $ULTRA; then
    ICON="<span color='#ffaa00'>⚡</span> (U)"
    TOOLTIP="Power profile: Ultra (Performance Plus)\nRyzenAdj OC active - survives suspend"
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
