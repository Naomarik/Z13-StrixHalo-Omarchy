#!/bin/bash

# Check current mako mode
MODE=$(makoctl mode)

if [ "$MODE" = "do-not-disturb" ]; then
  # DND is ON - notifications are muted
  echo '{"text": "󰂛", "tooltip": "Notifications muted (DND)\n\nClick to enable", "class": "notifications-muted"}'
else
  # DND is OFF - notifications are enabled
  echo '{"text": "󰂚", "tooltip": "Notifications enabled\n\nClick to mute", "class": "notifications-enabled"}'
fi
