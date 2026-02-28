#!/bin/bash
id=$(hyprctl activeworkspace -j | jq '.id')
name=$(omarchy-launch-walker --dmenu --inputonly --width 350 -p "Rename (empty for default)…")
if [[ -n "$name" ]]; then
  hyprctl dispatch renameworkspace "$id" "$id:$name"
else
  hyprctl dispatch renameworkspace "$id" "$id"
fi
