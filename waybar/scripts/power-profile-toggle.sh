#!/bin/bash
#
# power-profile-toggle.sh
#
# Cycles: power-saver (Q) -> balanced (B) -> performance (P) -> ultra (U) -> power-saver
#
# Q/B/P: stock power-profiles-daemon profiles, then debounced undervolt
# U: full PPT, undervolt
#
STATE_FILE="${POWER_PROFILE_STATE_FILE:-/var/lib/performance-plus/active}"
WAYBAR_SIGNAL=13

RYZENADJ="$HOME/.local/bin/ryzenadj"
POWERPROFILESCTL="${POWERPROFILESCTL:-powerprofilesctl}"
SUDO="${SUDO:-sudo}"
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}/power-profile-toggle"
TUNING_PENDING="$RUNDIR/pending-tuning-profile"
TUNING_DEADLINE="$RUNDIR/tuning-deadline-ms"
TUNING_LOCK="$RUNDIR/tuning.lock"
TUNING_DELAY_MS="${POWER_PROFILE_TUNING_DELAY_MS:-3000}"

mkdir -p "$RUNDIR"

apply_ultra_settings() {
    "$RYZENADJ" \
        --stapm-limit=120000 \
        --fast-limit=120000 \
        --slow-limit=85000 \
        --apu-slow-limit=85000 \
        --set-coall=0x0ffff1
}

apply_ultra_settings_if_active() {
    [[ -f "$STATE_FILE" ]] || exit 0
    apply_ultra_settings
}

clear_pending_tuning() {
    rm -f "$TUNING_PENDING" "$TUNING_DEADLINE"
}

now_ms() {
    date +%s%3N
}

apply_tuning_if_current() {
    local profile=$1

    [[ ! -f "$STATE_FILE" ]] || exit 0
    [[ "$("$POWERPROFILESCTL" get 2>/dev/null)" == "$profile" ]] || exit 0

    case "$profile" in
        # performance boosts clocks/voltage, so it needs a milder undervolt
        performance)             "$RYZENADJ" --set-coall=0x0fffdd ;;  # -35
        power-saver|balanced)    "$RYZENADJ" --set-coall=0x0fffd8 ;;  # -40
        *) exit 0 ;;
    esac
}

schedule_tuning() {
    local profile=$1

    printf '%s\n' "$profile" > "$TUNING_PENDING"
    printf '%s\n' "$(( $(now_ms) + TUNING_DELAY_MS ))" > "$TUNING_DEADLINE"

    (
        local deadline
        local pending_profile
        local remaining

        exec 8>"$TUNING_LOCK"
        flock --nonblock 8 || exit 0

        while true; do
            [[ -s "$TUNING_DEADLINE" ]] || exit 0
            deadline=$(<"$TUNING_DEADLINE")
            remaining=$(( deadline - $(now_ms) ))

            (( remaining <= 0 )) && break
            sleep "$(printf '%d.%03d' "$(( remaining / 1000 ))" "$(( remaining % 1000 ))")"
        done

        [[ -s "$TUNING_PENDING" ]] || exit 0
        pending_profile=$(<"$TUNING_PENDING")
        clear_pending_tuning

        apply_tuning_if_current "$pending_profile"
        flock --unlock 8
    ) &
}

CURRENT_PROFILE=$("$POWERPROFILESCTL" get 2>/dev/null || echo "balanced")
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
    clear_pending_tuning
    "$POWERPROFILESCTL" set performance
    "$SUDO" mkdir -p "$(dirname "$STATE_FILE")"
    "$SUDO" touch "$STATE_FILE"
    apply_ultra_settings
    (sleep 3 && apply_ultra_settings_if_active) &
    (sleep 9 && apply_ultra_settings_if_active) &
else
    if $ULTRA_ACTIVE; then
        "$SUDO" rm -f "$STATE_FILE"
    fi
    "$POWERPROFILESCTL" set "$NEXT"
    schedule_tuning "$NEXT"
fi

pkill -RTMIN+$WAYBAR_SIGNAL waybar 2>/dev/null || true
