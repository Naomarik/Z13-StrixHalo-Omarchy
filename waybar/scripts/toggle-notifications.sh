#!/bin/bash

# Get current mode
MODE=$(makoctl mode)

if [ "$MODE" = "do-not-disturb" ]; then
  # Switch to default (enable notifications)
  makoctl mode -s default
  notify-send "Notifications enabled" "You will now receive notifications"
else
  # Switch to do-not-disturb (mute notifications)
  makoctl mode -s do-not-disturb
  # This notification won't show because we're in DND, but that's intentional
fi

# Signal waybar to update (signal 12)
pkill -RTMIN+12 waybar
