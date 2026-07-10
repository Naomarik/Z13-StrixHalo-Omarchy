#!/bin/bash

# Check if hypridle is running
if pgrep -x hypridle >/dev/null; then
  # hypridle running = idle lock ON - show locked icon
  echo '{"text": "󰌾", "tooltip": "Idle lock enabled\n\nClick to disable", "class": "idle-lock-on"}'
else
  # hypridle not running = idle lock OFF (Caffeine mode) - show caffeine icon
  echo '{"text": "", "tooltip": "Idle lock disabled (Caffeine mode)\n\nClick to enable", "class": "idle-lock-off"}'
fi
