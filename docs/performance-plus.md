# Performance Plus (Ultra) — Power Management System

Custom power management layer for the ASUS Zenbook Z13 (Strix Halo / gfx1151).
Adds an **Ultra** mode on top of `power-profiles-daemon` that applies ryzenadj
overclocking settings and survives suspend/resume cycles.

---

## Overview

`power-profiles-daemon` only supports three profiles: `power-saver`, `balanced`,
`performance`. It has no plugin API for custom profiles. Ultra mode lives
alongside it as a separate state tracked by a flag file, with
`power-profiles-daemon` locked to `performance` underneath it.

### Cycle order (clicking the Waybar module)

```
Q (power-saver) → B (balanced) → P (performance) → ⚡ U (ultra) → Q
```

### What Ultra does

Sets the following via `ryzenadj` on top of the `performance` base profile:

```
--fast-limit=120000      # PPT fast limit: 120W  (plugged in)
--slow-limit=85000       # PPT slow limit: 85W   (plugged in)
--apu-slow-limit=85000   # APU slow limit: 85W   (plugged in)
--tctl-temp=95           # Thermal limit: 95°C
--set-coall=0x0fffd8     # Curve Optimizer: -40 all-core
```

> All PPT values are measured/applied while plugged in (AC). On battery the
> firmware enforces lower limits regardless of what ryzenadj sets.

These settings are re-applied automatically after suspend/resume when Ultra
is active.

### What Quiet (Q) does

Quiet uses the stock `power-saver` profile limits (55 W fast / 40 W slow,
plugged in). In addition, the `-40` all-core Curve Optimizer is applied
2 seconds after switching to Q, and re-applied after suspend/resume.

---

## Files

| Path | Purpose |
|------|---------|
| `~/.local/bin/ryzenadj` | Global throttling wrapper — shadows `/usr/bin/ryzenadj` |
| `~/.config/waybar/scripts/power-profile-toggle.sh` | Cycles profiles on click, enables/disables Ultra |
| `~/.config/waybar/scripts/power-profile-status.sh` | Returns JSON for Waybar module |
| `~/.config/waybar/scripts/power-draw.sh` | Shows live `STAPM value/limit W` in Waybar |
| `~/.config/waybar/scripts/performance-plus-sleep-hook` | Source copy of the sleep hook |
| `~/.config/waybar/scripts/performance-plus-ac-hook` | Source copy of the AC power hook |
| `/lib/systemd/system-sleep/performance-plus` | Installed sleep hook (re-applies on resume) |
| `/usr/lib/performance-plus/ac-hook` | Installed AC hook (re-applies on AC plug-in) |
| `/etc/udev/rules.d/99-performance-plus-ac.rules` | Udev rule triggering AC hook on power change |
| `/etc/systemd/system/performance-plus-boot.service` | Boot service (re-applies on boot if Ultra active) |
| `/etc/tmpfiles.d/ryzenadj.conf` | Provisions `/run/ryzenadj/` (0777) at boot for shared lock files |
| `/var/lib/performance-plus/active` | Flag file — exists = Ultra is active |
| `/etc/sudoers.d/performance-plus` | Passwordless sudo rules for the above |

---

## ryzenadj wrapper — `~/.local/bin/ryzenadj`

Sits earlier in `PATH` than `/usr/bin/ryzenadj` so it intercepts all calls
transparently. Enforces a single global lock shared across every caller
(waybar, sleep hook, toggle script).

### Why this is needed

Calling `ryzenadj` multiple times in rapid succession causes a **system hang**.
The root cause is the `ryzen_smu` kernel module — it uses `mutex_lock()` on the
SMU mailbox. If a second userspace call hits the mailbox before the firmware
finishes processing the first, the system locks up.

### Two safety mechanisms

1. **Exclusive write lock** (`/run/ryzenadj/lock` via `flock`) — only one write
   can execute at a time.
2. **3-second cooldown** (`/run/ryzenadj/last` timestamp) — enforced between
   any two write calls.

### Queuing (not skipping)

If a write call arrives during the cooldown or while locked, it is **not
dropped**. Instead:
- Its args are written to `/run/ryzenadj/pending` (overwriting any prior queued
  call — last write wins)
- A background waiter is spawned (guarded by `/run/ryzenadj/retry` so only one
  waiter exists at a time)
- The waiter sleeps for the remaining cooldown, then re-invokes the wrapper

Result: no matter how many rapid calls arrive, exactly two executions happen —
the first immediately, then one more ~3s later with the final args.

### Read path (`-i`)

Info reads are treated differently — they must never block or queue:
- If the lock is free: run live, update `/run/ryzenadj/cache`, return output
- If the lock is held (write in progress): return `/run/ryzenadj/cache`
  immediately

This means Waybar's 10-second status poll never contends with a profile switch.

### State files

State files live in `/run/ryzenadj/` (mode 0777, tmpfs) so both user and root
processes share them without permission errors. The directory is provisioned at
boot by `/etc/tmpfiles.d/ryzenadj.conf`.

| File | Purpose |
|------|---------|
| `/run/ryzenadj/lock` | Exclusive write lock |
| `/run/ryzenadj/last` | Epoch timestamp of last write |
| `/run/ryzenadj/cache` | Cached output of last `-i` call |
| `/run/ryzenadj/pending` | Null-delimited args of queued write |
| `/run/ryzenadj/retry` | Lock ensuring only one retry waiter exists |

### Performance impact

Measured on Strix Halo:

| Call | Avg time (5 runs) |
|------|-------------------|
| `sudo /usr/bin/ryzenadj -i` (real binary) | ~12ms |
| `~/.local/bin/ryzenadj -i` (wrapper) | ~14ms |

**Wrapper overhead: ~2ms** (~17%). The hardware SMU query dominates at ~10ms.
At a 10-second Waybar interval, this is 0.14% of one 180Hz frame budget spread
across 10 seconds — unmeasurable in practice.

### Does it affect gaming?

No. Three reasons:

1. The `ryzen_smu.ko` mutex is **not shared** with the game, GPU driver, or
   `amd_pstate`. It is only contended between `ryzenadj` callers. Our wrapper
   ensures there is never more than one concurrent caller.
2. During a `-i` read the SMU co-processor refreshes the PM table into DRAM;
   the CPU cores are not involved.
3. Write calls (setting limits) are processed by the **SMU co-processor** — a
   separate microcontroller on the die — asynchronously from CPU execution.

---

## Source code

### `~/.local/bin/ryzenadj`

```bash
#!/bin/bash
#
# ~/.local/bin/ryzenadj — global throttling wrapper
#
# Sits in front of /usr/bin/ryzenadj and enforces a single shared lock
# across ALL callers (waybar status, sleep hook, profile toggle, etc.)
#
# Behaviour:
#   -i (read/info)  → return cached output immediately if locked; never queue
#   everything else → queue: wait for lock, then run (last queued args win)
#
# State files live in /run/ryzenadj so both user and root can share them.
# The directory is provisioned by /etc/tmpfiles.d/ryzenadj.conf at boot.
#   /run/ryzenadj/lock    — flock lockfile (exclusive for writes)
#   /run/ryzenadj/last    — epoch timestamp of last write
#   /run/ryzenadj/cache   — last stdout of ryzenadj -i
#   /run/ryzenadj/pending — null-delimited args for the queued write
#   /run/ryzenadj/retry   — flock lockfile: ensures only one retry waiter
#

REAL=/usr/bin/ryzenadj
RUNDIR=/run/ryzenadj
LOCKFILE=$RUNDIR/lock
TIMESTAMP=$RUNDIR/last
CACHE=$RUNDIR/cache
PENDING=$RUNDIR/pending
RETRY_LOCK=$RUNDIR/retry

# Guard: ensure runtime dir exists (tmpfiles.d creates it on boot, but be safe)
mkdir -p "$RUNDIR" && chmod 0777 "$RUNDIR" 2>/dev/null || true
COOLDOWN=3  # seconds between write calls

# ── Info / read path ─────────────────────────────────────────────────────────
if [[ $# -eq 1 && "$1" == "-i" ]]; then
    exec 9>"$LOCKFILE"
    if flock --nonblock 9; then
        # Lock acquired — run live and update cache
        OUTPUT=$(sudo "$REAL" -i 2>&1)
        STATUS=$?
        echo "$OUTPUT" > "$CACHE"
        flock --unlock 9
        echo "$OUTPUT"
        exit $STATUS
    else
        # Locked by a write — return cached value immediately
        if [[ -f "$CACHE" ]]; then
            cat "$CACHE"
            exit 0
        else
            echo "ryzenadj: locked, no cache yet" >&2
            exit 1
        fi
    fi
fi

# ── Write path ───────────────────────────────────────────────────────────────
# Cooldown check first
if [[ -f "$TIMESTAMP" ]]; then
    LAST=$(cat "$TIMESTAMP" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    ELAPSED=$(( NOW - LAST ))
    if (( ELAPSED < COOLDOWN )); then
        REMAINING=$(( COOLDOWN - ELAPSED ))
        echo "ryzenadj: cooldown active, queuing for retry in ${REMAINING}s" >&2
        printf '%s\0' "$@" > "$PENDING"
        exec 8>"$RETRY_LOCK"
        if flock --nonblock 8; then
            (
                sleep "$REMAINING"
                if [[ -f "$PENDING" ]]; then
                    mapfile -d '' ARGS < "$PENDING"
                    rm -f "$PENDING"
                    "$0" "${ARGS[@]}"
                fi
                flock --unlock 8
            ) &
        fi
        exit 0
    fi
fi

# Acquire write lock
exec 9>"$LOCKFILE"
if ! flock --nonblock 9; then
    echo "ryzenadj: locked, queuing" >&2
    printf '%s\0' "$@" > "$PENDING"
    exec 8>"$RETRY_LOCK"
    if flock --nonblock 8; then
        (
            sleep "$COOLDOWN"
            if [[ -f "$PENDING" ]]; then
                mapfile -d '' ARGS < "$PENDING"
                rm -f "$PENDING"
                "$0" "${ARGS[@]}"
            fi
            flock --unlock 8
        ) &
    fi
    exit 0
fi

# Lock acquired — run
rm -f "$PENDING"
date +%s > "$TIMESTAMP"
sudo "$REAL" "$@"
STATUS=$?
flock --unlock 9
exit $STATUS
```

---

### `~/.config/waybar/scripts/power-profile-toggle.sh`

```bash
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
```

---

### `~/.config/waybar/scripts/power-profile-status.sh`

```bash
#!/bin/bash
#
# Power Profile Status Script for Waybar
# Returns JSON with current power profile icon and tooltip
#

STATE_FILE="/var/lib/performance-plus/active"
PROFILE=$(powerprofilesctl get 2>/dev/null || echo "balanced")

# Ultra overrides everything
if [[ -f "$STATE_FILE" ]]; then
    ICON="<span color='#ffaa00'>⚡</span> (U)"
    TOOLTIP="Power profile: Ultra (Performance Plus)\nRyzenAdj OC active — survives suspend"
else
    case "$PROFILE" in
        performance)
            ICON="<span color='#ff6666'>󰓅</span> (P)"
            TOOLTIP="Power profile: performance"
            ;;
        balanced)
            ICON="󰾅 (B)"
            TOOLTIP="Power profile: balanced"
            ;;
        power-saver)
            ICON="<span color='#6699ff'>󰾆</span> (Q)"
            TOOLTIP="Power profile: power-saver"
            ;;
        *)
            ICON=""
            TOOLTIP="Power profile: unknown"
            ;;
    esac
fi

# Return JSON for Waybar
echo "{\"text\":\"$ICON\",\"tooltip\":\"$TOOLTIP\"}"
```

---

### `~/.config/waybar/scripts/power-draw.sh`

```bash
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
```

---

### `/lib/systemd/system-sleep/performance-plus`

Installed via:
```bash
sudo cp ~/.config/waybar/scripts/performance-plus-sleep-hook \
    /lib/systemd/system-sleep/performance-plus
sudo chmod 755 /lib/systemd/system-sleep/performance-plus
```

### Boot service — `/etc/systemd/system/performance-plus-boot.service`

Re-applies Ultra ryzenadj settings on boot if the state file exists (survives reboots).

Installed via:
```bash
sudo cp ~/.config/waybar/scripts/performance-plus-boot.service \
    /etc/systemd/system/performance-plus-boot.service
sudo systemctl daemon-reload
sudo systemctl enable performance-plus-boot.service
```

```ini
[Unit]
Description=Performance Plus (Ultra) - Re-apply ryzenadj on boot
After=multi-user.target
ConditionPathExists=/var/lib/performance-plus/active

[Service]
Type=oneshot
RemainAfterExit=yes
Environment="RYZENADJ=/home/naomarik/.local/bin/ryzenadj"
Environment="STATE_FILE=/var/lib/performance-plus/active"
ExecStart=/bin/bash -c '\
    apply_ultra() { \
        "$RYZENADJ" --fast-limit=120000 --slow-limit=85000 --apu-slow-limit=85000 --tctl-temp=95 --set-coall=0x0fffd8; \
    }; \
    apply_ultra; \
    (sleep 3 && apply_ultra) & \
    (sleep 9 && apply_ultra) & \
    wait'

[Install]
WantedBy=multi-user.target
```

---

```bash
#!/bin/bash
#
# /lib/systemd/system-sleep/performance-plus
#
# Systemd sleep hook that re-applies Performance Plus (Ultra) ryzenadj
# settings after resume from suspend/hibernate.
#
# Called by systemd with: $1 = pre|post, $2 = suspend|hibernate|hybrid-sleep|suspend-then-hibernate
#
# Only runs ryzenadj on POST (resume), never on pre-suspend.
# The throttle in the ryzenadj wrapper prevents rapid re-application.
#
# Why apply multiple times? asusd runs on_prepare_for_sleep(false) at the same
# time as this hook and may reset platform PPT limits shortly after resume.
# We apply immediately, then re-apply at 3s and 9s to ensure our 120W limits stick.
#

RYZENADJ="${RYZENADJ:-/home/naomarik/.local/bin/ryzenadj}"
STATE_FILE="/var/lib/performance-plus/active"

# Function to apply Ultra settings
apply_ultra_settings() {
    "$RYZENADJ" \
        --fast-limit=120000 \
        --slow-limit=85000 \
        --apu-slow-limit=85000 \
        --tctl-temp=95 \
        --set-coall=0x0fffd8
}

# Function to apply undervolt for power-saver mode
apply_undervolt() {
    "$RYZENADJ" --set-coall=0x0fffd8
}

case "$1" in
    post)
        # Re-apply Ultra ryzenadj settings if Ultra mode is active
        if [[ -f "$STATE_FILE" ]]; then
            # Apply immediately after resume (asusd may reset shortly after)
            apply_ultra_settings
            # Wait 3s and re-apply to override asusd's platform profile reset
            (sleep 3 && apply_ultra_settings) &
            # Wait 6s more and verify/re-apply one more time to ensure it sticks
            (sleep 9 && apply_ultra_settings) &
        # Re-apply undervolt if power-saver (Q) is active
        elif [[ "$(powerprofilesctl get 2>/dev/null)" == "power-saver" ]]; then
            apply_undervolt
            (sleep 3 && apply_undervolt) &
            (sleep 9 && apply_undervolt) &
        fi
        ;;
    pre)
        # Nothing to do before suspend
        ;;
esac
```

---

### AC power hook — `/usr/lib/performance-plus/ac-hook`

When AC power is unplugged and replugged, `power-profiles-daemon` re-applies
its stock PPT limits for the active profile, overwriting Ultra's ryzenadj
overrides. This udev-triggered hook re-applies them after a 5-second delay
(ppd takes longer to settle on power source changes than on profile switches).

Installed via:
```bash
sudo mkdir -p /usr/lib/performance-plus
sudo cp ~/.config/waybar/scripts/performance-plus-ac-hook \
    /usr/lib/performance-plus/ac-hook
sudo chmod 755 /usr/lib/performance-plus/ac-hook

sudo tee /etc/udev/rules.d/99-performance-plus-ac.rules > /dev/null <<'EOF'
SUBSYSTEM=="power_supply", KERNEL=="AC0", ATTR{online}=="1", RUN+="/usr/lib/performance-plus/ac-hook"
EOF

sudo udevadm control --reload-rules
```

```bash
#!/bin/bash
#
# /usr/lib/performance-plus/ac-hook
#
# Udev helper: re-applies Performance Plus (Ultra) ryzenadj settings when
# AC power is plugged in.
#
# Called by udev rule 99-performance-plus-ac.rules.  Udev handlers must
# return quickly.  Udev kills all children in its cgroup when RUN+= exits,
# so we use systemd-run to spawn the delayed re-apply in its own transient
# scope, outside udev's process lifetime.
#

RYZENADJ="/home/naomarik/.local/bin/ryzenadj"
STATE_FILE="/var/lib/performance-plus/active"

# Only act when Ultra is active and AC is online
[[ -f "$STATE_FILE" ]] || exit 0
[[ "$(cat /sys/class/power_supply/AC0/online 2>/dev/null)" == "1" ]] || exit 0

# Delay 5s to let power-profiles-daemon finish re-applying its own PPT limits,
# then override with Ultra values.
systemd-run --no-block bash -c "
    sleep 5
    $RYZENADJ \
        --fast-limit=120000 \
        --slow-limit=85000 \
        --apu-slow-limit=85000 \
        --tctl-temp=95 \
        --set-coall=0x0fffd8
"
```

---

## Waybar config

The built-in `power-profiles-daemon` module was replaced with a custom module
that can display the Ultra state. In `~/.config/waybar/config.jsonc`:

```jsonc
"custom/power-profile": {
  "exec": "~/.config/waybar/scripts/power-profile-status.sh",
  "return-type": "json",
  "interval": 10,
  "signal": 13,
  "on-click": "~/.config/waybar/scripts/power-profile-toggle.sh",
  "tooltip": true
},

"custom/power-draw": {
  "exec": "~/.config/waybar/scripts/power-draw.sh",
  "return-type": "json",
  "interval": 10,
  "on-click": "xdg-terminal-exec btop"
},
```

Signal 13 (`RTMIN+13`) is sent by the toggle script after every profile change
to force an immediate Waybar refresh without waiting for the 10s interval.

---

## Sudoers — `/etc/sudoers.d/performance-plus`

```
# Performance Plus — allow <your-username> to call the ryzenadj wrapper and manage state
<your-username> ALL=(root) NOPASSWD: /home/<your-username>/.local/bin/ryzenadj
<your-username> ALL=(root) NOPASSWD: /bin/mkdir -p /var/lib/performance-plus
<your-username> ALL=(root) NOPASSWD: /bin/touch /var/lib/performance-plus/active
<your-username> ALL=(root) NOPASSWD: /bin/rm -f /var/lib/performance-plus/active
```

Note: `/usr/bin/ryzenadj` is also covered by the pre-existing
`/etc/sudoers.d/ryzenadj` rule. Adjust the above if your user already has
broad sudo access.

---

## ryzen_smu kernel module notes

The `ryzen_smu` DKMS module (`/lib/modules/.../updates/dkms/ryzen_smu.ko.zst`)
is a third-party driver by Leonardo Gates, not part of upstream Linux.

It uses two kernel mutexes:

```c
static DEFINE_MUTEX(amd_pci_mutex);  // guards PCI config space access
static DEFINE_MUTEX(amd_smu_mutex);  // guards SMU mailbox command sequences
```

`smu_send_command()` holds `amd_smu_mutex` for the full duration of a mailbox
round-trip (write args → write command → poll response). This is a **sleeping
mutex** — any other kernel thread calling into the same module blocks until it
is released.

**These mutexes are not shared with:**
- `amd_pstate` (CPU frequency scaling driver)
- AMDGPU driver
- Game processes
- Any other kernel subsystem

They are only contended between concurrent `ryzenadj` userspace processes. The
wrapper ensures this never happens.

The PM table read path (`ryzenadj -i`) works differently: the SMU co-processor
writes telemetry into a DRAM region mapped with `ioremap_cache()`. Reading it
is a `memcpy_fromio()` — the CPU cores are not stalled. One SMU command is sent
first to trigger a refresh (`smu_transfer_table_to_dram`), but this completes
in ~10ms on Strix Halo.
