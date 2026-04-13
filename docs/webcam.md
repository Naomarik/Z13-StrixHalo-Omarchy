# Webcam Fix After Suspend (ASUS 5M Webcam)

The ASUS 5M webcam on the ROG Flow Z13 (2025) can stop working after suspend/resume
and doesn't automatically recover on wake.

## Problem

- After suspend, the USB controller (PCI c4:00.4) powering the webcam fails to
  properly resume
- dmesg shows error: `usb usb1: can't set config #1, error -19`
- The webcam device disappears from `/dev/video*` and `lsusb`
- `v4l2-ctl --list-devices` shows no camera

## Immediate Fix

Run the fix script to reset the USB controller and restore the camera:

```bash
~/fix-webcam.sh
```

Or manually:

```bash
sudo bash -c 'echo 1 > /sys/bus/pci/devices/0000:c4:00.4/remove && sleep 2 && echo 1 > /sys/bus/pci/rescan'
```

This resets the AMD Strix Halo USB 3.1 controller (PCI device c4:00.4) that the
camera is attached to, forcing re-enumeration of all USB devices on that bus.

## Automatic Fix on Resume

A systemd service has been installed to automatically fix this after every
suspend/resume cycle:

```bash
sudo systemctl enable fix-webcam-suspend.service
```

The service runs after the system wakes from:
- suspend-to-RAM
- hibernate  
- hybrid-sleep

## Device Details

| Attribute | Value |
|-----------|-------|
| Device | ASUS 5M webcam |
| USB ID | 636e:0bda |
| Bus | USB 1-1 |
| Controller | AMD Strix Halo USB 3.1 xHCI (PCI c4:00.4) |
| Driver | uvcvideo |

## Verification

Check if the webcam is detected:

```bash
v4l2-ctl --list-devices
```

Should show:
```
ASUS 5M webcam: ASUS 5M webcam (usb-0000:c4:00.4-1):
	/dev/video0
	/dev/video1
	/dev/video2
	/dev/video3
	/dev/media0
	/dev/media1
```

## Files Created

- `~/fix-webcam.sh` - Manual fix script
- `/etc/systemd/system/fix-webcam-suspend.service` - Automatic resume fix
- `/etc/udev/rules.d/99-webcam.rules` - Prevents USB autosuspend for the camera

## Related

- [Bluetooth workaround](bluetooth.md) - Similar USB controller issues with MT7925
- Kernel: `linux-g14 6.18.7.arch1-1.2` or later includes the xhci fixes
