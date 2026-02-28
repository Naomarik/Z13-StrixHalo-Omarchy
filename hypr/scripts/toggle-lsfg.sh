#!/bin/bash
CONFIG="$HOME/.config/lsfg-vk/conf.toml"
LOCKFILE="/tmp/lsfg-toggle.lock"

# Prevent multiple simultaneous executions (debounce)
if [ -f "$LOCKFILE" ]; then
    # Check if lock is stale (older than 2 seconds)
    if [ $(($(date +%s) - $(stat -c %Y "$LOCKFILE" 2>/dev/null || echo 0))) -lt 2 ]; then
        exit 0  # Exit silently if lock is fresh
    fi
fi

# Create lock file
touch "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT

# Get current multiplier from Elden Ring section
CURRENT=$(awk '/exe = "eldenring.exe"/{flag=1; next} flag && /^multiplier/{print $3; exit}' "$CONFIG")

# If no multiplier found, assume 1 (OFF)
if [ -z "$CURRENT" ]; then
    CURRENT=1
fi

# Cycle: 1 (OFF) -> 2 -> 3 -> 4 -> 1
case $CURRENT in
    1)
        NEW=2
        MSG="Frame Gen: 2x (Enabled)"
        ;;
    2)
        NEW=3
        MSG="Frame Gen: 3x (High)"
        ;;
    3)
        NEW=4
        MSG="Frame Gen: 4x (Maximum)"
        ;;
    *)
        NEW=1
        MSG="Frame Gen: OFF (Disabled)"
        ;;
esac

# Update ONLY Elden Ring's multiplier using awk
awk -v new="$NEW" '
    /exe = "eldenring.exe"/ { flag=1 }
    flag && /^multiplier = / { 
        sub(/multiplier = [0-9]+/, "multiplier = " new)
        flag=0
    }
    { print }
' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"

# Send notification
notify-send -t 2000 -u normal "LSFG" "$MSG"

# Optional: Log for debugging
echo "$(date '+%Y-%m-%d %H:%M:%S'): Elden Ring: $CURRENT -> $NEW" >> "$HOME/.config/lsfg-vk/toggle.log"
