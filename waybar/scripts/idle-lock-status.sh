#!/bin/bash

# Check if hypridle is running
if pgrep -x hypridle >/dev/null; then
  # Idle lock is OFF (hypridle not running) - show caffeine icon
  echo '{"text": "", "tooltip": "Idle lock disabled (Caffeine mode)\n\nClick to enable", "class": "idle-lock-off"}'
else
  # Idle lock is ON (hypridle running) - show locked icon
  echo '{"text": "󰌾", "tooltip": "Idle lock enabled\n\nClick to disable", "class": "idle-lock-on"}'
fi
