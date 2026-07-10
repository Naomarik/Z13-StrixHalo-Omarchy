#!/bin/bash
#
# ============================================================================
# WARNING: Repeatedly calling ryzenadj causes SYSTEM CRASHES.
# ryzenadj must be called at MOST 1 time per second — never more.
# All ryzenadj invocations must go through the debounce/rate-limit logic
# in this script. Do not add direct or rapid ryzenadj calls.
#
# Constraints (from the owner — keep these when revising this script):
# - Crashes have happened two ways: severe undervolts, and ryzenadj being
#   called too rapidly. Both must be guarded against.
# - Clicks must NEVER be ignored: the UI stays responsive to every click,
#   and the script internally debounces/rate-limits so it "settles" on the
#   LAST profile the user clicked. No hard cooldown that swallows clicks.
# ============================================================================
#
# power-profile-toggle.sh
#
# Cycles: power-saver (Q) -> balanced (B) -> performance (P) -> ultra (U) -> power-saver
#
# Q/B/P: stock power-profiles-daemon profiles, then debounced undervolt
# U: full PPT, undervolt
#
# Every click advances the DESIRED profile immediately (waybar shows it via the
# pending file). A single background worker applies the profile switch once
# clicks settle (SETTLE_MS), then applies ryzenadj tuning TUNING_DELAY_MS after
# the last click. Last click wins; ryzenadj is never called rapidly.
#
STATE_FILE="${POWER_PROFILE_STATE_FILE:-/var/lib/performance-plus/active}"
WAYBAR_SIGNAL=13

RYZENADJ="$HOME/.local/bin/ryzenadj"
SUDO="${SUDO:-sudo}"
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}/power-profile-toggle"
PENDING="$RUNDIR/pending-profile"          # desired profile awaiting apply
SETTLE_DEADLINE="$RUNDIR/settle-deadline-ms"
TUNING_DEADLINE="$RUNDIR/tuning-deadline-ms"
WORKER_LOCK="$RUNDIR/worker.lock"
SETTLE_MS="${POWER_PROFILE_SETTLE_MS:-400}"
TUNING_DELAY_MS="${POWER_PROFILE_TUNING_DELAY_MS:-5000}"

mkdir -p "$RUNDIR"

now_ms() {
    date +%s%3N
}

power_profile_get() {
    python3.14 /usr/bin/powerprofilesctl get 2>/dev/null || powerprofilesctl get 2>/dev/null
}

power_profile_set() {
    python3.14 /usr/bin/powerprofilesctl set "$1" 2>/dev/null || powerprofilesctl set "$1"
}

signal_waybar() {
    pkill -RTMIN+$WAYBAR_SIGNAL waybar 2>/dev/null || true
}

next_profile() {
    case "$1" in
        power-saver) echo "balanced" ;;
        balanced)    echo "performance" ;;
        performance) echo "ultra" ;;
        ultra)       echo "power-saver" ;;
        *)           echo "balanced" ;;
    esac
}

apply_profile() {
    local profile=$1

    if [[ "$profile" == "ultra" ]]; then
        power_profile_set performance
        "$SUDO" mkdir -p "$(dirname "$STATE_FILE")"
        "$SUDO" touch "$STATE_FILE"
    else
        [[ -f "$STATE_FILE" ]] && "$SUDO" rm -f "$STATE_FILE"
        power_profile_set "$profile"
    fi
}

# Hard rate limit: ryzenadj at most once per second (crashes otherwise)
RYZENADJ_LAST_TS="$RUNDIR/ryzenadj-last-ts"
ryzenadj_rate_limited() {
    local now last wait_ms
    now=$(now_ms)
    if [[ -s "$RYZENADJ_LAST_TS" ]]; then
        last=$(<"$RYZENADJ_LAST_TS")
        if [[ "$last" =~ ^[0-9]+$ ]]; then
            wait_ms=$(( 1000 - (now - last) ))
            if (( wait_ms > 0 )); then
                sleep "$(printf '%d.%03d' "$(( wait_ms / 1000 ))" "$(( wait_ms % 1000 ))")"
            fi
        fi
    fi
    printf '%s\n' "$(now_ms)" > "$RYZENADJ_LAST_TS"
    "$RYZENADJ" "$@"
}

apply_tuning_if_current() {
    local profile=$1

    if [[ "$profile" == "ultra" ]]; then
        [[ -f "$STATE_FILE" ]] || return 0
        [[ "$(power_profile_get)" == "performance" ]] || return 0
        ryzenadj_rate_limited \
            --stapm-limit=120000 \
            --fast-limit=120000 \
            --slow-limit=85000 \
            --apu-slow-limit=85000 \
            --set-coall=0x0ffff1
        return 0
    fi

    [[ ! -f "$STATE_FILE" ]] || return 0
    [[ "$(power_profile_get)" == "$profile" ]] || return 0

    case "$profile" in
        power-saver)
            ryzenadj_rate_limited \
                --stapm-limit=28000 \
                --fast-limit=35000 \
                --slow-limit=28000 \
                --apu-slow-limit=28000 \
                --set-coall=0x0fffec \
                --power-saving
            ;;
        balanced)
            ryzenadj_rate_limited \
                --stapm-limit=45000 \
                --fast-limit=55000 \
                --slow-limit=45000 \
                --apu-slow-limit=45000 \
                --set-coall=0x0fffec
            ;;
        performance)
            ryzenadj_rate_limited \
                --stapm-limit=65000 \
                --fast-limit=85000 \
                --slow-limit=65000 \
                --apu-slow-limit=65000 \
                --set-coall=0x0fffec \
                --max-performance
            ;;
    esac
}

wait_for_deadline() {
    local deadline_file=$1 deadline remaining
    while true; do
        [[ -s "$deadline_file" ]] || return 0
        deadline=$(<"$deadline_file")
        remaining=$(( deadline - $(now_ms) ))
        (( remaining <= 0 )) && return 0
        sleep "$(printf '%d.%03d' "$(( remaining / 1000 ))" "$(( remaining % 1000 ))")"
    done
}

run_worker() {
    exec 8>"$WORKER_LOCK"
    flock --nonblock 8 || exit 0

    local desired

    while true; do
        # Wait until clicks stop (deadline keeps moving on each click)
        wait_for_deadline "$SETTLE_DEADLINE"
        [[ -s "$PENDING" ]] || break
        desired=$(<"$PENDING")

        apply_profile "$desired"
        signal_waybar

        # Wait out the tuning delay; more clicks extend it and change PENDING
        wait_for_deadline "$TUNING_DEADLINE"

        if [[ -s "$PENDING" && "$(<"$PENDING")" != "$desired" ]]; then
            continue  # user clicked again — re-settle on the new profile
        fi

        rm -f "$PENDING" "$SETTLE_DEADLINE" "$TUNING_DEADLINE"
        apply_tuning_if_current "$desired"
        break
    done

    flock --unlock 8
}

# --- Click path ---------------------------------------------------------

# Base the next step on the pending (desired) profile if one exists,
# so rapid clicks keep cycling instead of being ignored.
if [[ -s "$PENDING" ]]; then
    CURRENT=$(<"$PENDING")
elif [[ -f "$STATE_FILE" ]]; then
    CURRENT="ultra"
else
    CURRENT=$(power_profile_get || echo "balanced")
fi

NEXT=$(next_profile "$CURRENT")
NOW=$(now_ms)
printf '%s\n' "$NEXT" > "$PENDING"
printf '%s\n' "$(( NOW + SETTLE_MS ))" > "$SETTLE_DEADLINE"
printf '%s\n' "$(( NOW + TUNING_DELAY_MS ))" > "$TUNING_DEADLINE"

run_worker &

signal_waybar
