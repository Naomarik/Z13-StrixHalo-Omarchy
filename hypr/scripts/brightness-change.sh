#!/bin/bash

# Change brightness by a percentage and show OSD
# Usage: brightness-change.sh +5 or brightness-change.sh -5

change="$1"

# Format for brightnessctl (e.g., +5 becomes 5%+, -5 becomes 5%-)
if [[ "$change" == +* ]]; then
    formatted="${change#+}%+"
elif [[ "$change" == -* ]]; then
    formatted="${change#-}%-"
else
    formatted="${change}%"
fi

# Change brightness using brightnessctl
brightnessctl set "$formatted"

# Get the new brightness percentage
brightness=$(brightnessctl -m | cut -d',' -f4 | tr -d '%')

# Calculate progress for swayosd (0.0 to 1.0)
progress=$(awk "BEGIN {printf \"%.2f\", $brightness / 100}")

# Show OSD notification (use default brightness icon by using brightness command with absolute value)
swayosd-client --brightness "$brightness"

# Send signal to waybar to update
pkill -RTMIN+10 waybar
