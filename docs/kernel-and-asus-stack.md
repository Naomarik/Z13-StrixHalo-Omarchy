# Kernel & ASUS Hardware Stack

Everything needed to get fan control, platform profiles, and hardware tuning
working on the ASUS Zenbook Z13 (Strix Halo) under Arch Linux.

---

## Why a custom kernel?

The upstream Arch `linux` kernel does not carry ASUS-specific patches. Without
`linux-g14`, the following either don't work or are severely degraded:

- Fan curve control (fans run at BIOS defaults, no software control)
- ASUS platform profile integration (`Quiet` / `Balanced` / `Performance` via
  ACPI)
- `asusctl` hardware tuning knobs (keyboard backlight, charge thresholds, etc.)
- PPT/power limit exposure via `asus-armoury` sysfs interface
- Various device-specific WMI methods (panel overdrive, mini-LED, etc.)

The patches live at `gitlab.com/asus-linux/linux-g14` and are applied on top
of the standard Arch kernel.

---

## The `[g14]` binary repository

The asus-linux project maintains a pre-built binary pacman repository so you
don't have to compile the kernel yourself.

Add to `/etc/pacman.conf`:

```ini
[g14]
Server = https://arch.asus-linux.org
```

This repo provides `linux-g14`, `linux-g14-headers`, `asusctl`,
`rog-control-center`, and other ASUS-specific packages as pre-built binaries.

### Installing the kernel

```bash
paru -S linux-g14 linux-g14-headers
# or directly:
sudo pacman -S linux-g14 linux-g14-headers
```

After install, update the bootloader so the new kernel is selectable.

---

## paru vs AUR for linux-g14

`paru -S linux-g14` will prefer the `[g14]` binary repo over AUR because
named repos take priority. You get a pre-built binary — fast, no compilation.

To force the AUR (source build) path explicitly:
```bash
paru -S aur/linux-g14 aur/linux-g14-headers
```

The AUR PKGBUILD pulls:
- Vanilla kernel tarball from `kernel.org`
- Arch Linux kernel patches from `github.com/archlinux/linux`
- ASUS patch series from `gitlab.com/asus-linux/linux-g14`

Then compiles locally. This gives you options like `march=native` in the kernel
config but takes much longer. **Use the binary repo unless you have a specific
reason to build from source.**

History shows several attempts at forcing AUR builds and then falling back to
manually installing cached `.pkg.tar.zst` files — the binary repo is the
reliable path.

---

## Currently installed (as of Feb 2026)

```
linux-g14          6.18.7.arch1-1.2
linux-g14-headers  6.18.7.arch1-1.2
asusctl            6.3.2-0.1
rog-control-center 6.3.2-0.1
```

Running kernel: `6.18.7-arch1-1.2-g14`

---

## asusctl + asusd

`asusctl` is the userspace CLI. `asusd` is the daemon that owns the hardware.
`asusd` must be running for any of this to work.

```bash
systemctl status asusd      # check it's running
systemctl enable asusd      # enable on boot (should already be)
```

`asusd` is marked `static` — it doesn't need explicit enabling, it's pulled in
by other units.

### Key asusctl commands

```bash
asusctl profile --list          # list platform profiles
asusctl profile -p Performance  # set profile
asusctl -k low                  # keyboard backlight: off/low/med/high
asusctl -k med
asusctl -k high
asusctl fan-curve --list        # list fan curve profiles
asusctl fan-curve -m            # show current mode
```

### Monitoring sensors while tuning

```bash
watch -n 0.5 'sensors | grep -E "(PPT|Tctl|edge|W|fan|RPM)"'
```

This was the primary command used during initial tuning — shows PPT draw,
CPU temp (Tctl), and fan RPM all at once at 500ms refresh.

---

## asusd configuration

Config lives in `/etc/asusd/`. Edited by `asusd` itself on change, or manually.

### `/etc/asusd/asusd.ron`

Current config:

```ron
(
    charge_control_end_threshold: 80,
    base_charge_control_end_threshold: 0,
    disable_nvidia_powerd_on_battery: true,
    ac_command: "",
    bat_command: "",
    platform_profile_linked_epp: true,
    platform_profile_on_battery: Quiet,
    change_platform_profile_on_battery: true,
    platform_profile_on_ac: Performance,
    change_platform_profile_on_ac: true,
    profile_quiet_epp: Power,
    profile_balanced_epp: BalancePower,
    profile_custom_epp: Performance,
    profile_performance_epp: Performance,
    ac_profile_tunings: { ... },   // all disabled
    dc_profile_tunings: { ... },   // all disabled
    armoury_settings: {
        PanelOverdrive: 1,
    },
)
```

Key decisions:
- **Charge limit: 80%** — protects battery longevity
- **On battery → Quiet profile** — automatic on unplug
- **On AC → Performance profile** — automatic on plug-in
- **EPP linked to platform profile** — `amd_pstate` Energy Performance
  Preference follows the profile automatically
- **Panel overdrive: enabled** — reduces display ghosting

### `/etc/asusd/fan_curves.ron`

Fan curves per platform profile. PWM values are 0–255. Currently all
`enabled: false` — meaning the BIOS/firmware default curves are used.
To activate custom curves, set `enabled: true` per entry.

```ron
(
    profiles: (
        quiet: [
            (fan: CPU, pwm: (2, 2, 22, 30, 43, 56, 68, 68),
                        temp: (50, 54, 58, 62, 64, 67, 71, 71), enabled: false),
            (fan: GPU, pwm: (2, 2, 22, 33, 45, 58, 71, 71),
                        temp: (50, 54, 58, 62, 64, 67, 71, 71), enabled: false),
        ],
        balanced: [
            (fan: CPU, pwm: (2, 22, 30, 43, 56, 68, 89, 102),
                        temp: (48, 53, 57, 60, 63, 65, 70, 76), enabled: false),
            (fan: GPU, pwm: (2, 22, 33, 45, 58, 71, 94, 107),
                        temp: (48, 53, 57, 60, 63, 65, 70, 76), enabled: false),
        ],
        performance: [
            (fan: CPU, pwm: (30, 56, 68, 86, 94, 114, 132, 147),
                        temp: (42, 50, 55, 60, 65, 70, 75, 80), enabled: false),
            (fan: GPU, pwm: (33, 58, 71, 89, 99, 119, 137, 155),
                        temp: (42, 50, 55, 60, 65, 70, 75, 80), enabled: false),
        ],
        custom: [],
    ),
)
```

PWM scale: `0` = off, `255` = 100%. So `147` ≈ 58% max fan speed in
performance profile. The 8 entries are (temp, pwm) curve points.

To enable custom fan curves:
```bash
asusctl fan-curve -e true   # enable for current profile
# then edit /etc/asusd/fan_curves.ron and restart asusd
sudo systemctl restart asusd
```

---

## Relationship between asusd profiles and power-profiles-daemon

`asusd` and `power-profiles-daemon` both write to the same ACPI
`platform_profile` sysfs interface (`/sys/firmware/acpi/platform_profile`).
They co-exist because `asusd.ron` has `platform_profile_linked_epp: true` —
`asusd` defers EPP control to `power-profiles-daemon` while still owning fan
curves and hardware-specific tunings.

The profile names map as:

| asusd | power-profiles-daemon | ACPI platform_profile |
|-------|-----------------------|-----------------------|
| Quiet | power-saver | quiet |
| Balanced | balanced | balanced |
| Performance | performance | performance |

**Ultra mode** (from `performance-plus.md`) sits on top of `performance` /
`Performance` and applies additional ryzenadj limits that neither `asusd` nor
`power-profiles-daemon` can express natively.

---

## Kernel update procedure

When a new `linux-g14` is available:

```bash
sudo pacman -Syu          # updates everything including linux-g14
# reboot into new kernel
# DKMS modules (ryzen_smu etc.) rebuild automatically via pacman hooks
```

If a kernel update breaks something, the old package is cached at
`/var/cache/pacman/pkg/` and can be rolled back:

```bash
sudo pacman -U /var/cache/pacman/pkg/linux-g14-<version>-x86_64.pkg.tar.zst \
               /var/cache/pacman/pkg/linux-g14-headers-<version>-x86_64.pkg.tar.zst
```

This exact pattern appears multiple times in shell history and is the reliable
rollback path.
