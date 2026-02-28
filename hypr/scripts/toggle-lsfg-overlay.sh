#!/bin/bash
# Toggle LSFG overlay - open if closed, close if open

# Check if lsfg-overlay window exists
if hyprctl clients | grep -q "class: lsfg-overlay"; then
    # Overlay is open, close all instances by PID
    pkill -f "alacritty.*lsfg-overlay"
else
    # Overlay is closed, open it
    alacritty --class=lsfg-overlay -e ~/github/omarchy-lsfg/configure.sh &
fi
