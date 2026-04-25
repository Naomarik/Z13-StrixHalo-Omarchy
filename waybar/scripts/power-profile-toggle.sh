#!/bin/bash
#
# power-profile-toggle.sh
#
# Cycles: power-saver -> balanced -> performance -> ultra -> power-saver
#
STATE_FILE="/var/lib/performance-plus/active"
WAYBAR_SIGNAL=13
PENDING_FILE="/tmp/power-profile-pending"
DEBOUNCE_PID_FILE="/tmp/power-profile-debounce.pid"
DEBOUNCE_MS=500

# Function to apply Ultra settings
apply_ultra_settings() {
    "$HOME/.local/bin/ryzenadj" \
        --stapm-limit=120000 \
        --fast-limit=120000 \
        --slow-limit=85000 \
        --apu-slow-limit=85000 \
        --tctl-temp=95 \
        --set-coall=0x0fffd8
}

# Function to apply undervolt
apply_undervolt() {
    "$HOME/.local/bin/ryzenadj" --set-coall=0x0fffd8
}

# Debounce: kill existing timer and update pending mode
if [[ -f "$DEBOUNCE_PID_FILE" ]]; then
    OLD_PID=$(cat "$DEBOUNCE_PID_FILE" 2>/dev/null)
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
    fi
fi

# Calculate next mode based on CURRENT state (read fresh each time)
CURRENT_PROFILE=$(powerprofilesctl get 2>/dev/null || echo "balanced")
ULTRA_ACTIVE=false
[[ -f "$STATE_FILE" ]] && ULTRA_ACTIVE=true

if $ULTRA_ACTIVE; then
    NEXT="power-saver"
elif [[ "$CURRENT_PROFILE" == "performance" ]]; then
    NEXT="ultra"
elif [[ "$CURRENT_PROFILE" == "balanced" ]]; then
    NEXT="performance"
elif [[ "$CURRENT_PROFILE" == "power-saver" ]]; then
    NEXT="balanced"
else
    NEXT="balanced"
fi

# Write the desired mode to pending file
echo "$NEXT" > "$PENDING_FILE"

# Start debounce timer in background
(
    sleep 0.$DEBOUNCE_MS
    
    # Read the final desired mode
    FINAL_MODE=$(cat "$PENDING_FILE" 2>/dev/null || echo "balanced")
    rm -f "$PENDING_FILE"
    rm -f "$DEBOUNCE_PID_FILE"
    
    # Apply the mode
    if [[ "$FINAL_MODE" == "ultra" ]]; then
        powerprofilesctl set performance
        sudo mkdir -p /var/lib/performance-plus
        sudo touch "$STATE_FILE"
        apply_ultra_settings
        (sleep 3 && apply_ultra_settings) &
        (sleep 9 && apply_ultra_settings) &
    else
        if [[ -f "$STATE_FILE" ]]; then
            sudo rm -f "$STATE_FILE"
        fi
        powerprofilesctl set "$FINAL_MODE"
        if [[ "$FINAL_MODE" == "power-saver" || "$FINAL_MODE" == "balanced" ]]; then
            apply_undervolt
            (sleep 3 && apply_undervolt) &
        fi
    fi
    
    pkill -RTMIN+$WAYBAR_SIGNAL waybar 2>/dev/null || true
) &

# Save the PID of the background process
echo $! > "$DEBOUNCE_PID_FILE"
