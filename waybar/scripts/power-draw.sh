#!/bin/bash

# Read STAPM value + limit from ryzenadj -i
# Format: 13/86W (current draw / package limit)
info=$("$HOME/.local/bin/ryzenadj" -i 2>/dev/null)

value=$(echo "$info" | awk -F'|' '/STAPM VALUE/{gsub(/ /,"",$3); printf "%.0f", $3}')
limit=$(echo "$info" | awk -F'|' '/STAPM LIMIT/{gsub(/ /,"",$3); printf "%.0f", $3}')

if [[ -n "$value" && -n "$limit" ]]; then
    echo "{\"text\":\" ${value}/${limit}W\",\"tooltip\":\"CPU Power: ${value}W of ${limit}W STAPM limit\"}"
else
    echo "{\"text\":\" N/A\",\"tooltip\":\"Power data unavailable\"}"
fi
