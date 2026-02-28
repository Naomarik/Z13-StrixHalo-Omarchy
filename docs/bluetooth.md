# Bluetooth — MT7925 on Z13 Flow

## Hardware

| Item | Detail |
|------|--------|
| Chipset | MediaTek MT7925 (combo WiFi+BT) |
| USB device | `13d3:3608` IMC Networks Wireless_Device |
| BT firmware | `/usr/lib/firmware/mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin.zst` |

## Known Issue: hci0 WMT Timeout on Boot

On first boot, `btusb` creates `hci0` from the MT7925 USB BT device. `hci0` hits a WMT init
timeout (~8 seconds) and fails — `bluetoothctl` sees no adapters, BT is completely broken.

**The working adapter is `hci1`**, which only appears after `hci0` has been torn down and `btusb`
reloaded. This is a firmware regression: `linux-firmware-mediatek` 20260221+ changed the MT7925
init behavior so `hci1` no longer auto-appears alongside the failing `hci0`.

### Symptoms

```
# dmesg shows:
Bluetooth: hci0: Execution of wmt command timed out
Bluetooth: hci0: Failed to send wmt func ctrl (-110)

# bluetoothctl shows nothing:
$ bluetoothctl show
(no output)

# btmgmt shows no adapters:
$ sudo btmgmt info
(no output)
```

### Workaround (manual, one-time)

```bash
sudo modprobe -r btusb btmtk && sleep 1 && sudo modprobe btusb
sleep 4
sudo systemctl restart bluetooth
# hci1 should now appear and BT works for the rest of the session
```

### Permanent Fix

A systemd service at `/etc/systemd/system/btusb-reload.service` that runs on every boot:

```ini
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
```

Enable with:
```bash
sudo systemctl daemon-reload
sudo systemctl enable btusb-reload.service
```

Timing: ~17 seconds from boot to working BT. Adjust `sleep 12` and `sleep 4` if needed.

## Root Cause

The `linux-firmware-mediatek` package updated from `20251125-2` to `20260221-1` as part of an
omarchy upgrade. The new MT7925 BT firmware (build `20260106153314`, previously `20251015213201`)
behaves differently on first module load. With the old firmware, both `hci0` (failing WMT) and
`hci1` (working) appeared automatically. With the new firmware, only `hci0` appears, and `hci1`
never initializes unless the module is reloaded.

This is not an omarchy config issue — it's a firmware/kernel interaction specific to this hardware.

## Current State (as of 2026-02-28)

| Item | Value |
|------|-------|
| `linux-firmware-mediatek` | 20260221-1 |
| `bluez` | 5.86-2 |
| `btusb-reload.service` | enabled |
| Working adapter | `hci1` (after service runs) |
| rfkill | `1: asus-bluetooth` and `2: hci0` — both unblocked |
