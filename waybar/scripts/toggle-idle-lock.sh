#!/bin/bash

# Wrapper around omarchy-toggle-idle to fix a race condition:
# omarchy-toggle-idle starts/stops hypridle asynchronously and signals
# waybar immediately, before the process state has settled. The module
# then reads a stale `pgrep hypridle` result and draws the wrong icon.
# We re-signal waybar after a short settle delay so it reflects reality.

omarchy-toggle-idle

# Wait for hypridle to actually appear/disappear (up to ~1s), then refresh.
for _ in $(seq 1 10); do
  sleep 0.1
done
pkill -RTMIN+9 waybar
