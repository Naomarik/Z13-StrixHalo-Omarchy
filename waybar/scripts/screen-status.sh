#!/bin/bash

# Get brightness percentage
brightness=$(brightnessctl -m | cut -d',' -f4 | tr -d '%')

# Get current refresh rate from hyprctl
refresh_rate=$(hyprctl monitors -j | jq -r '.[0].refreshRate' | cut -d'.' -f1)

# Output in JSON format for waybar
echo "{\"text\":\"󰃠 ${brightness}% @ ${refresh_rate}Hz\", \"tooltip\":\"Brightness: ${brightness}%\\nRefresh Rate: ${refresh_rate}Hz\\n\\nClick to toggle refresh rate\"}"
