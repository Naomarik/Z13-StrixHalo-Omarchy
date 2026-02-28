#!/bin/bash
# 3-way toggle: tiling -> floating -> sticky -> tiling

# Get active window info
window_info=$(hyprctl activewindow -j)
is_floating=$(echo "$window_info" | jq -r '.floating')
is_pinned=$(echo "$window_info" | jq -r '.pinned')

if [ "$is_floating" = "false" ]; then
    # Currently tiling -> make floating
    hyprctl dispatch togglefloating
elif [ "$is_pinned" = "false" ]; then
    # Currently floating (not sticky) -> make sticky
    hyprctl dispatch pin
else
    # Currently sticky -> back to tiling
    hyprctl dispatch pin  # unpin first
    hyprctl dispatch togglefloating  # then tile
fi
