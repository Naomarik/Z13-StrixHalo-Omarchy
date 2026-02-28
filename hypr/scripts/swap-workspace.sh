#!/bin/bash

# Get current workspace info
current_ws=$(hyprctl activeworkspace -j)
current_id=$(echo "$current_ws" | jq '.id')
current_name=$(echo "$current_ws" | jq -r '.name')

# Extract display name (part after colon, or empty if no custom name)
if [[ "$current_name" == *":"* ]]; then
  current_display="${current_name#*:}"
else
  current_display=""
fi

# Get all workspaces
all_workspaces=$(hyprctl workspaces -j)

# Build menu options for positions 1-10, excluding current
menu_options=""
for i in {1..10}; do
  if [[ $i -ne $current_id ]]; then
    # Check if workspace exists and get its name
    ws_info=$(echo "$all_workspaces" | jq -r ".[] | select(.id == $i)")
    if [[ -n "$ws_info" ]]; then
      ws_name=$(echo "$ws_info" | jq -r '.name')
      if [[ "$ws_name" == *":"* ]]; then
        display_name="${ws_name#*:}"
        menu_options+="$i: $display_name\n"
      else
        menu_options+="$i: (empty)\n"
      fi
    else
      menu_options+="$i: (unused)\n"
    fi
  fi
done

# Show menu
selected=$(echo -e "$menu_options" | omarchy-launch-walker --dmenu --width 295 --minheight 1 --maxheight 400 -p "Swap workspace $current_id to position...")

# Exit if nothing selected
[[ -z "$selected" ]] && exit 0

# Extract target ID from selection
target_id=$(echo "$selected" | cut -d: -f1)

# Get target workspace info
target_ws=$(echo "$all_workspaces" | jq -r ".[] | select(.id == $target_id)")
if [[ -n "$target_ws" ]]; then
  target_name=$(echo "$target_ws" | jq -r '.name')
  if [[ "$target_name" == *":"* ]]; then
    target_display="${target_name#*:}"
  else
    target_display=""
  fi
else
  target_display=""
fi

# Use a temporary workspace for the swap (use a high number unlikely to be used)
temp_ws=99

# Get windows from current workspace
current_windows=$(hyprctl clients -j | jq -r ".[] | select(.workspace.id == $current_id) | .address")

# Get windows from target workspace
target_windows=$(hyprctl clients -j | jq -r ".[] | select(.workspace.id == $target_id) | .address")

# Move current workspace windows to temp
for addr in $current_windows; do
  hyprctl dispatch movetoworkspacesilent "$temp_ws,address:$addr"
done

# Move target workspace windows to current position
for addr in $target_windows; do
  hyprctl dispatch movetoworkspacesilent "$current_id,address:$addr"
done

# Move temp windows to target position
for addr in $current_windows; do
  hyprctl dispatch movetoworkspacesilent "$target_id,address:$addr"
done

# Swap the names - apply current's name to target position and vice versa
if [[ -n "$current_display" ]]; then
  hyprctl dispatch renameworkspace "$target_id" "$target_id:$current_display"
else
  hyprctl dispatch renameworkspace "$target_id" "$target_id"
fi

if [[ -n "$target_display" ]]; then
  hyprctl dispatch renameworkspace "$current_id" "$current_id:$target_display"
else
  hyprctl dispatch renameworkspace "$current_id" "$current_id"
fi

# Switch to the target workspace (where our original windows now are)
hyprctl dispatch workspace "$target_id"
