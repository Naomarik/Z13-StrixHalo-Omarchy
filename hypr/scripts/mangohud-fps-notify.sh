#!/bin/bash
# MangoHud FPS Limiter Notification Script
# Cycles through FPS limits: 0 (unlimited) → 60 → 120 → 0
# Shows current limit with system notification

CONFIG_FILE="$HOME/.config/MangoHud/MangoHud.conf"
STATE_FILE="/tmp/mangohud_fps_state"

# Get current FPS limit from state file
get_current_fps_limit() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "0"
    fi
}

# Show notification for given FPS limit
show_notification() {
    local limit=$1
    
    if [ "$limit" -eq 0 ]; then
        notify-send -t 2000 -u normal "FPS Limit" "Unlimited (No limit)"
    else
        notify-send -t 2000 -u normal "FPS Limit" "${limit} FPS"
    fi
}

# Cycle through FPS limits
cycle_fps_limit() {
    local current=$(get_current_fps_limit)
    local limits=(0 60 120)
    local next_index=0
    
    # Find current index and move to next
    for i in "${!limits[@]}"; do
        if [[ "${limits[$i]}" == "$current" ]]; then
            next_index=$(( (i + 1) % ${#limits[@]} ))
            break
        fi
    done
    
    local new_limit="${limits[$next_index]}"
    echo "$new_limit" > "$STATE_FILE"
    
    # Show notification
    show_notification "$new_limit"
}

# Show current FPS limit
show_current() {
    local current=$(get_current_fps_limit)
    show_notification "$current"
}

# Main
case "${1:-cycle}" in
    cycle)
        cycle_fps_limit
        ;;
    show|current)
        show_current
        ;;
    reset)
        echo "0" > "$STATE_FILE"
        show_notification 0
        ;;
    *)
        echo "Usage: $0 [cycle|show|reset]"
        exit 1
        ;;
esac
