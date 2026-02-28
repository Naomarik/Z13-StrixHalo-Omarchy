#!/bin/bash

# Get monitor name
MONITOR=$(hyprctl monitors -j | jq -r '.[0].name')

# Get current monitor settings
MONITOR_INFO=$(hyprctl monitors -j | jq -r '.[0]')
WIDTH=$(echo "$MONITOR_INFO" | jq -r '.width')
HEIGHT=$(echo "$MONITOR_INFO" | jq -r '.height')
POS_X=$(echo "$MONITOR_INFO" | jq -r '.x')
POS_Y=$(echo "$MONITOR_INFO" | jq -r '.y')
SCALE=$(echo "$MONITOR_INFO" | jq -r '.scale')
CURRENT_REFRESH=$(echo "$MONITOR_INFO" | jq -r '.refreshRate' | cut -d'.' -f1)
CURRENT_FORMAT=$(echo "$MONITOR_INFO" | jq -r '.currentFormat')

# Determine bit depth from current format
if [[ "$CURRENT_FORMAT" == *"2101010"* ]]; then
    BIT_DEPTH=10
else
    BIT_DEPTH=8
fi

# Determine target refresh rate
if [ "$CURRENT_REFRESH" -eq 180 ]; then
    TARGET_REFRESH=60
else
    TARGET_REFRESH=180
fi

# Toggle refresh rate using hyprctl, preserving resolution, position, scale, and bit depth
hyprctl keyword monitor "${MONITOR},${WIDTH}x${HEIGHT}@${TARGET_REFRESH},${POS_X}x${POS_Y},${SCALE},bitdepth,${BIT_DEPTH}"

# Send signal to waybar to update (signal 10 for custom/screen)
pkill -RTMIN+10 waybar
