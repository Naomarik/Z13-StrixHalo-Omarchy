#!/usr/bin/env bash
# Toggle between Double (both monitors) and External (only DP-1) configurations

# State file to track current mode
STATE_FILE="/tmp/hypr-monitor-mode"

# Read current state (defaults to "external" if file doesn't exist)
CURRENT_MODE=$(cat "$STATE_FILE" 2>/dev/null || echo "external")

if [ "$CURRENT_MODE" = "external" ]; then
    # Switch to Double mode
    hyprctl keyword monitor eDP-1,2560x1600@180.00,384x1152,2.00
    hyprctl keyword monitor DP-1,2560x1440@239.96,0x0,1.25
    echo "double" > "$STATE_FILE"
    notify-send -t 2000 "Monitor Mode" "Double: Internal + External"
else
    # Switch to External mode
    hyprctl keyword monitor eDP-1,disable
    hyprctl keyword monitor DP-1,2560x1440@239.96,0x0,1.25
    echo "external" > "$STATE_FILE"
    notify-send -t 2000 "Monitor Mode" "External Only"
fi
