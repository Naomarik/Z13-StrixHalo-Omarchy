#!/bin/bash
#
# power-profile-toggle.sh
#
# Cycles: power-saver -> balanced -> performance -> ultra -> power-saver
#
STATE_FILE="/var/lib/performance-plus/active"
WAYBAR_SIGNAL=13

# Function to apply Ultra settings
apply_ultra_settings() {
    "$HOME/.local/bin/ryzenadj" \
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

CURRENT_PROFILE=$(powerprofilesctl get 2>/dev/null || echo "balanced")
ULTRA_ACTIVE=false
[[ -f "$STATE_FILE" ]] && ULTRA_ACTIVE=true

# Determine next mode
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

# Apply next mode
if [[ "$NEXT" == "ultra" ]]; then
    powerprofilesctl set performance
    sudo mkdir -p /var/lib/performance-plus
    sudo touch "$STATE_FILE"
    # Apply immediately, then re-apply after delays to ensure settings stick
    # (power-profiles-daemon and asusd may reset PPT limits shortly after)
    apply_ultra_settings
    (sleep 3 && apply_ultra_settings) &
    (sleep 9 && apply_ultra_settings) &
else
    if $ULTRA_ACTIVE; then
        sudo rm -f "$STATE_FILE"
    fi
    powerprofilesctl set "$NEXT"
    # Apply undervolt after switching to power-saver (Q)
    if [[ "$NEXT" == "power-saver" ]]; then
        apply_undervolt
        (sleep 3 && apply_undervolt) &
    fi
fi

pkill -RTMIN+$WAYBAR_SIGNAL waybar 2>/dev/null || true
