# ASUS ROG Flow Z13 (2025) - Omarchy Config & Tuning

![Arch Linux](https://img.shields.io/badge/Arch-Linux-1793D1?logo=arch-linux&logoColor=white)
![Omarchy](https://img.shields.io/badge/Omarchy-3.4.0-111111)
![Hyprland](https://img.shields.io/badge/WM-Hyprland-4B8BBE)
![Hardware](https://img.shields.io/badge/Target-ROG%20Flow%20Z13%20(2025)-CC0000)

Config, fixes, and performance tuning for the **ASUS ROG Flow Z13 (2025)** running
[Omarchy](https://github.com/basecamp/omarchy) on Arch Linux.

> This repo is intentionally hardware-specific and opinionated. If you apply it
> on other machines, treat power, thermal, fan, and EQ settings as starting
> points, not universal defaults.

## Tested baseline

| Component | Value |
|---|---|
| Machine | ASUS ROG Flow Z13 (2025) |
| SoC | AMD Ryzen AI Max+ 395 (Strix Halo / gfx1151) |
| CPU | 16c / 32t |
| iGPU | Radeon 8060S (40 CU) |
| Memory | 128 GB unified LPDDR5X |
| OS | Arch Linux + [Omarchy](https://github.com/basecamp/omarchy) |
| Kernel | `linux-g14 6.18.7.arch1-1.2` |
| Omarchy | `3.4.0` |
| Window manager | Hyprland |

## Contents

- [What this repo includes](#what-this-repo-includes)
- [Quick start](#quick-start)
- [Platform setup](#platform-setup)
- [Desktop configuration](#desktop-configuration)
- [Audio presets (EasyEffects)](#audio-presets-easyeffects)
- [Build performance (pacman/makepkg)](#build-performance-pacmanmakepkg)
- [Repository layout](#repository-layout)
- [Related projects](#related-projects)

## What this repo includes

- **Kernel and ASUS stack** (`linux-g14`, `asusctl`, `asusd`) for proper fan and platform profile control
- **Performance Plus**: adds an `Ultra` mode (`Q -> B -> P -> U`) on top of `power-profiles-daemon`
- **Waybar modules** for profile switching, live STAPM watts, thermals, idle lock, notifications, and refresh-rate toggles
- **EasyEffects presets** for speakers, headphones, and microphone processing
- **Bluetooth workaround** for MT7925 (`hci0` WMT timeout on boot)
- **hy3 tiling + gaming mode session handoff** for workflow and performance

## Quick start

1) Copy desktop/audio configs:

```bash
mkdir -p ~/.config/hypr ~/.config/waybar
mkdir -p ~/.local/share/easyeffects/{input,output,irs}

cp -r hypr/* ~/.config/hypr/
cp waybar/config.jsonc waybar/style.css ~/.config/waybar/
cp -r waybar/scripts ~/.config/waybar/

cp easyeffects/output/*.json ~/.local/share/easyeffects/output/
cp easyeffects/input/*.json ~/.local/share/easyeffects/input/
cp easyeffects/irs/*.irs ~/.local/share/easyeffects/irs/
```

2) Install platform stack and services (kernel, ASUS daemon, optional modules) using the sections below.

3) Restart your session (`Hyprland`, `Waybar`, EasyEffects) after copying files.

## Platform setup

### Kernel and ASUS stack

The upstream Arch `linux` kernel misses ASUS-specific patches needed for full
control on this device. `linux-g14` restores fan curves, profile integration,
and userspace tuning support.

Add the `[g14]` repository to `/etc/pacman.conf`:

```ini
[g14]
Server = https://arch.asus-linux.org
```

Install and enable the daemon:

```bash
sudo pacman -S linux-g14 linux-g14-headers asusctl
sudo systemctl enable --now asusd
```

Full setup and rollback guide: [docs/kernel-and-asus-stack.md](docs/kernel-and-asus-stack.md)

### Performance Plus (Ultra mode)

`power-profiles-daemon` exposes three stock profiles. This repo layers an
additional `Ultra` mode on top of `performance` using `ryzenadj`, and re-applies
it automatically after suspend/resume.

Profile limits reported by `ryzenadj -i` on this machine (plugged in):

| Profile | PPT fast | PPT slow | Tctl |
|---|---|---|---|
| Quiet (`Q`) | 55 W | 40 W | default |
| Balanced (`B`) | 71 W | 52 W | default |
| Performance (`P`) | 86 W | 70 W | default |
| Ultra (`U`) | 120 W | 85 W | 95 C |

> Values are lower on battery — these are AC/plugged-in readings.

Ultra also applies a `-40` all-core Curve Optimizer (`--set-coall=0x0fffd8`).
Quiet also applies the same Curve Optimizer 2 seconds after switching.

The Waybar module cycles `Q -> B -> P -> U -> Q` on click and reports live
STAPM watts.

Important stability note: concurrent `ryzenadj` writes can hang the system on
this platform, so the setup uses a wrapper with an exclusive lock and cooldown.

Full setup: [docs/performance-plus.md](docs/performance-plus.md)

### Bluetooth workaround (MT7925)

With `linux-firmware-mediatek 20260221+`, the MT7925 adapter may fail at boot
(`hci0` WMT timeout). Reloading `btusb` brings up a working adapter (`hci1`).

One-time recovery:

```bash
sudo modprobe -r btusb btmtk && sleep 1 && sudo modprobe btusb
sleep 4
sudo systemctl restart bluetooth
```

Permanent systemd workaround and diagnostics:
[docs/bluetooth.md](docs/bluetooth.md)

## Desktop configuration

### hy3 tiling

[hy3](https://github.com/outfoxxed/hy3) replaces default Hyprland layouts with
i3/sway-style explicit tiling. Autotile is enabled (trigger: 300x500).

Common bindings:

| Key | Action |
|---|---|
| `Super + H` | Horizontal split |
| `Super + T` | Tab group |
| `Super + TAB` | Toggle tab mode |
| `Super + E` | Flip split direction |
| `Super + J/K/L/;` | Move focus |
| `Super + Shift + J/K/L/;` | Move window |

Install/update details: [docs/hy3.md](docs/hy3.md)

### SwayOSD

`swayosd-server` 0.3.0 has a recurring `SIGSEGV` crash (GTK4/libwayland race). It also
silently loses D-Bus registration if it starts before the session bus is ready. Both leave the
OSD dead mid-session with no indication.

Fix: managed as a user systemd service with `Restart=always` and `After=dbus.socket` instead
of relying on Hyprland's `exec-once`. See [docs/swayosd.md](docs/swayosd.md).

### Gaming mode

`Super+Shift+F5` performs a full session handoff from Hyprland to a bare
gamescope session (not nested), then returns via Steam "Exit to Desktop".

Install once:

```bash
bash scripts/gaming-mode-install.sh
```

### Waybar modules

| Module | Behavior |
|---|---|
| Power profile | Cycles `Q / B / P / U` |
| Power draw | Live STAPM watts (`ryzenadj -i`) |
| Temperature | CPU Tctl + GPU edge with thresholds |
| Idle lock toggle | Enables/disables idle lock |
| Notification toggle | Mutes/unmutes mako notifications |
| Refresh-rate toggle | Switches panel refresh rate |

Install:

```bash
cp waybar/config.jsonc waybar/style.css ~/.config/waybar/
cp -r waybar/scripts ~/.config/waybar/scripts/
```

If you use Performance Plus, also install the resume hook and boot service:

```bash
# Resume hook (re-applies on wake from suspend)
sudo cp waybar/scripts/performance-plus-sleep-hook /lib/systemd/system-sleep/performance-plus
sudo chmod +x /lib/systemd/system-sleep/performance-plus

# Boot service (re-applies on boot if Ultra was active)
sudo cp waybar/scripts/performance-plus-boot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable performance-plus-boot.service
```

## Audio presets (EasyEffects)

### Speakers - `IRZ13 Flow`

- Signal chain: `Convolver -> Compressor (upward) -> Multiband Compressor -> EQ -> Stereo Tools -> Limiter`
- Tuned for built-in speakers (`Ryzen HD Audio Controller Analog Stereo`)
- Uses `easyeffects/irs/ir1.irs` generated with [hifiscan](https://github.com/levantado/hifiscan)

Install:

```bash
cp "easyeffects/output/IRZ13 Flow.json" ~/.local/share/easyeffects/output/
cp easyeffects/irs/ir1.irs ~/.local/share/easyeffects/irs/
```

### Headphones - `Perfect EQ`

- Neutral headphone curve without heavy speaker bass compensation
- Can be auto-loaded per device in EasyEffects preferences

Install:

```bash
cp "easyeffects/output/Perfect EQ.json" ~/.local/share/easyeffects/output/
```

### Microphone - `FlowMic`

- Signal chain: `RNNoise -> Gate -> Compressor -> Limiter`
- Set mic input volume to `30%` before enabling this preset to avoid hardware clipping

Install:

```bash
wpctl set-volume @DEFAULT_SOURCE@ 0.30
cp easyeffects/input/FlowMic.json ~/.local/share/easyeffects/input/
```

Detailed mic setup and validation:
[docs/easyeffects-mic-setup.md](docs/easyeffects-mic-setup.md)

## Build performance (pacman/makepkg)

For faster package builds (especially DKMS rebuilds), set:

```bash
MAKEFLAGS="-j$(nproc)"
COMPRESSZST=(zstd -c -T0 -)
```

Guide: [docs/pacman-build-config.md](docs/pacman-build-config.md)

## Repository layout

```text
z13flow/
├── docs/
│   ├── bluetooth.md
│   ├── easyeffects-mic-setup.md
│   ├── hy3.md
│   ├── kernel-and-asus-stack.md
│   ├── pacman-build-config.md
│   ├── performance-plus.md
│   └── swayosd.md
├── easyeffects/
│   ├── input/
│   │   └── FlowMic.json
│   ├── irs/
│   │   └── ir1.irs
│   └── output/
│       ├── IRZ13 Flow.json
│       └── Perfect EQ.json
├── hypr/
│   ├── hyprland.conf
│   ├── bindings.conf
│   └── scripts/
├── scripts/
│   └── gaming-mode-install.sh
└── waybar/
    ├── config.jsonc
    ├── style.css
    └── scripts/
```

## Related projects

- [Omarchy](https://github.com/basecamp/omarchy) - base desktop environment this repo builds on
- [asus-linux.org](https://asus-linux.org) - ASUS Linux packages and tooling (`linux-g14`, `asusctl`)
- [linux-g14 (GitLab)](https://gitlab.com/asus-linux/linux-g14) - kernel patch source
