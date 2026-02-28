# z13flow

Config, fixes, and tuning for the **ASUS ROG Flow Z13 (2025)** running
[Omarchy](https://github.com/basecamp/omarchy) on Arch Linux.

| | |
|---|---|
| **Machine** | ASUS ROG Flow Z13 (2025) |
| **SoC** | AMD Ryzen AI Max+ 395 (Strix Halo / gfx1151) |
| **CPU** | 16c / 32t |
| **iGPU** | Radeon 8060S — 40 CU |
| **Memory** | 128 GB unified LPDDR5X |
| **OS** | Arch Linux + [Omarchy](https://github.com/basecamp/omarchy) |
| **Kernel** | `linux-g14 6.18.7.arch1-1.2` |
| **Omarchy** | `3.4.0` |
| **WM** | Hyprland |

---

## Contents

**Z13-specific**
- [Kernel & ASUS stack](#kernel--asus-stack)
- [Performance Plus (Ultra mode)](#performance-plus-ultra-mode)
- [Bluetooth workaround](#bluetooth-mt7925-workaround)
- [EasyEffects](#easyeffects)

**General config**
- [Gaming mode](#gaming-mode)
- [Waybar](#waybar)
- [Pacman / makepkg](#pacman--makepkg)

---

- [Repository structure](#repository-structure)

---

## Kernel & ASUS stack

The upstream Arch `linux` kernel does not carry ASUS-specific patches. Without
`linux-g14`, the following either don't work or are severely degraded:

- Fan curve control
- ASUS platform profiles (`Quiet` / `Balanced` / `Performance`)
- PPT / power limit sysfs via `asus-armoury`
- `asusctl` hardware tuning

Add the `[g14]` binary repo to `/etc/pacman.conf`:

```ini
[g14]
Server = https://arch.asus-linux.org
```

Then install:

```bash
sudo pacman -S linux-g14 linux-g14-headers asusctl
sudo systemctl enable --now asusd
```

See [docs/kernel-and-asus-stack.md](docs/kernel-and-asus-stack.md) for full
setup, `asusctl` commands, `asusd` config, fan curves, and rollback procedure.

---

## Performance Plus (Ultra mode)

`power-profiles-daemon` exposes three profiles. Performance Plus adds a fourth
**Ultra** mode that applies `ryzenadj` limits on top of `performance` and
survives suspend/resume.

| Profile | PPT fast | PPT slow | Tctl |
|---|---|---|---|
| Quiet (`Q`) | — | — | — |
| Balanced (`B`) | — | — | — |
| Performance (`P`) | — | — | — |
| **Ultra (`U`)** | **120 W** | **85 W** | **95°C** |

Ultra also applies a `-40` all-core Curve Optimizer (`--set-coall=0x0fffd8`).

The Waybar module cycles `Q → B → P → U → Q` on click and shows live STAPM
watts. A systemd sleep hook re-applies settings after resume.

> **Note:** Calling `ryzenadj` concurrently causes a system hang (SMU mailbox
> deadlock). The `~/.local/bin/ryzenadj` wrapper in this repo enforces an
> exclusive flock + 3-second cooldown across all callers before passing through
> to `/usr/bin/ryzenadj`.

See [docs/performance-plus.md](docs/performance-plus.md) for the full setup:
ryzenadj wrapper, sudoers rules, sleep hook install, and Waybar integration.

---

## EasyEffects

### Speaker output — `IRZ13 Flow` preset

Tuned for the built-in speakers (`Ryzen HD Audio Controller Analog Stereo`).

**Signal chain:** Convolver → Compressor (upward) → Multiband Compressor → EQ → Stereo Tools → Limiter

The EQ boosts 32–256 Hz (+3.5–5.5 dB) to compensate for thin speaker response,
with a gentle high-shelf lift. The multiband compressor glues the low end
without squashing transients.

The convolver stage uses an impulse response (`ir1.irs`) generated with
[hifiscan](https://github.com/levantado/hifiscan) — a frequency sweep
measurement tool that captures the speaker's actual frequency response and
produces a correction IR. To regenerate `ir1.irs` for your own unit (speaker
response varies between devices), run hifiscan with the built-in speakers and
export the result as a WAV.

```bash
cp "easyeffects/output/IRZ13 Flow.json" ~/.local/share/easyeffects/output/
cp easyeffects/irs/ir1.irs ~/.local/share/easyeffects/irs/
```

Then select `IRZ13 Flow` in EasyEffects → Output → Presets.

### Headphone output — `Perfect EQ` preset

Used when listening on headphones instead of the built-in speakers. It applies a
neutral EQ curve suited to headphone output without the heavy bass compensation
the speaker preset needs.

EasyEffects can switch presets automatically based on the output device — go to
**Preferences → Output → Auto-load** and assign `Perfect EQ` to your headphone
device and `IRZ13 Flow` to the built-in speakers. No manual switching needed.

```bash
cp "easyeffects/output/Perfect EQ.json" ~/.local/share/easyeffects/output/
```

### Mic input — `FlowMic` preset

**Signal chain:** RNNoise → Gate → Compressor → Limiter

> **Critical:** set system mic volume to **30%** before enabling this preset.
> The mic clips at hardware level above this before EasyEffects can process it.

```bash
wpctl set-volume @DEFAULT_SOURCE@ 0.30
cp easyeffects/input/FlowMic.json ~/.local/share/easyeffects/input/
```

The compressor's 8 dB makeup gain brings the final output to ~-14 dB RMS —
clean for voice calls without distortion.

See [docs/easyeffects-mic-setup.md](docs/easyeffects-mic-setup.md) for signal
chain details and verification steps.

---

## Bluetooth (MT7925 workaround)

The MediaTek MT7925 BT firmware (since `linux-firmware-mediatek 20260221`)
causes `hci0` to fail on boot with a WMT init timeout. The working adapter is
`hci1`, which only appears after a `btusb` module reload.

**Quick fix (one-time):**

```bash
sudo modprobe -r btusb btmtk && sleep 1 && sudo modprobe btusb
sleep 4
sudo systemctl restart bluetooth
```

**Permanent fix** — a systemd service that runs ~12 seconds after boot:

```bash
sudo cp /dev/stdin /etc/systemd/system/btusb-reload.service << 'EOF'
[Unit]
Description=Reload btusb module to recover MT7925 Bluetooth (hci0 WMT timeout workaround)
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'sleep 12 && modprobe -r btusb btmtk && sleep 1 && modprobe btusb && sleep 4 && systemctl restart bluetooth'
RemainAfterExit=yes

[Install]
WantedBy=bluetooth.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable btusb-reload.service
```

BT is working ~17 seconds after boot. See [docs/bluetooth.md](docs/bluetooth.md).

---

## General config

### Gaming mode

`Super+Shift+F5` switches the entire session from Hyprland to a bare gamescope
session — no nested compositor. Gamescope runs directly on the display, which
avoids the double-composition overhead you get from launching gamescope inside
Hyprland.

The switch is a full session handoff: Hyprland is torn down, suspend is masked
to prevent the display disconnecting mid-switch, and SDDM restarts into the
gamescope session. Steam's "Exit to Desktop" brings you back to Hyprland.

This is set up by `scripts/gaming-mode-install.sh` (sourced from the
[ChimeraOS gamescope-session](https://github.com/ChimeraOS/gamescope-session)
packages). Run it once:

```bash
bash scripts/gaming-mode-install.sh
```

The installer handles: Steam + dependencies, gamescope capabilities
(`cap_sys_nice`), session switching scripts, NetworkManager integration for
gaming mode, and the `Super+Shift+F5` Hyprland keybinding.

The F5 / F6 / F7 keybindings (`Super+F5/F6/F7`) are separate — they launch
gamescope *inside* Hyprland at various resolutions/refresh rates with MangoHud,
for when you want the nested approach.

### Waybar

Custom Waybar config extending Omarchy's defaults.

| Module | Description |
|---|---|
| Power profile | Cycles Q / B / P / Ultra on click, shows current mode |
| Power draw | Live STAPM watts via `ryzenadj -i` |
| Temperature | CPU Tctl + GPU edge with color thresholds |
| Idle lock toggle | Inhibit idle/lock from the bar |
| Notification toggle | Mute mako from the bar |
| Refresh rate toggle | Switch display Hz from the bar |

**Install:**

```bash
cp waybar/config.jsonc waybar/style.css ~/.config/waybar/
cp -r waybar/scripts/ ~/.config/waybar/scripts/
```

For Performance Plus, also install the sleep hook:

```bash
sudo cp waybar/scripts/performance-plus-sleep-hook \
        /lib/systemd/system-sleep/performance-plus
sudo chmod +x /lib/systemd/system-sleep/performance-plus
```

### Pacman / makepkg

`/etc/makepkg.conf` configured for full 32-thread builds:

```bash
MAKEFLAGS="-j$(nproc)"
COMPRESSZST=(zstd -c -T0 -)
```

This matters most for DKMS module rebuilds (`ryzen_smu`) on kernel updates —
without it, builds run effectively single-threaded.

See [docs/pacman-build-config.md](docs/pacman-build-config.md).

---

## Repository structure

```
z13flow/
├── scripts/
│   └── gaming-mode-install.sh     # One-time setup for Super+Shift+F5 gaming mode
├── docs/
│   ├── kernel-and-asus-stack.md   # linux-g14, asusctl, asusd, fan curves
│   ├── performance-plus.md        # Ultra mode — ryzenadj wrapper + sleep hook
│   ├── bluetooth.md               # MT7925 hci0 WMT timeout workaround
│   ├── easyeffects-mic-setup.md   # Mic signal chain and level calibration
│   └── pacman-build-config.md     # makepkg parallel build config
├── easyeffects/
│   ├── output/
│   │   ├── IRZ13 Flow.json        # Speaker preset (EQ + convolver)
│   │   └── Perfect EQ.json        # Headphone preset
│   ├── input/
│   │   └── FlowMic.json           # Mic preset (RNNoise + gate + compress)
│   └── irs/
│       └── ir1.irs                # Impulse response for convolver (generated with hifiscan)
└── waybar/
    ├── config.jsonc               # Module layout
    ├── style.css                  # Styling (imports Omarchy theme)
    └── scripts/
        ├── power-profile-toggle.sh      # Cycles Q/B/P/Ultra on click
        ├── power-profile-status.sh      # JSON status for Waybar module
        ├── power-draw.sh                # Live STAPM watts (ryzenadj -i)
        ├── temperatures.sh              # CPU Tctl + GPU edge temps
        ├── performance-plus-sleep-hook  # Re-applies Ultra on resume
        ├── idle-lock-status.sh          # Idle lock toggle indicator
        ├── notification-status.sh       # Notification mute indicator
        ├── screen-status.sh             # Refresh rate toggle status
        ├── toggle-notifications.sh      # Toggle mako notifications
        └── toggle-refresh-rate.sh       # Toggle display refresh rate
```

---

## Related

- [Omarchy](https://github.com/basecamp/omarchy) — the base Linux desktop setup this builds on
- [asus-linux.org](https://asus-linux.org) — `linux-g14`, `asusctl`, and ASUS Linux community
- [linux-g14 on GitLab](https://gitlab.com/asus-linux/linux-g14) — kernel patch series
