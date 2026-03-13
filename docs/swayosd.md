# SwayOSD — OSD Overlay for Volume / Brightness

## Problem: Two Failure Modes, Same Root Cause

`swayosd-server` 0.3.0 has a GTK4/libwayland race condition that manifests two ways:

**1. SIGSEGV crash mid-session** — the OSD stops appearing with no warning:

```
# coredumpctl list swayosd-server:
Sat 2026-02-07  SIGSEGV  /usr/bin/swayosd-server
Tue 2026-02-10  SIGSEGV  /usr/bin/swayosd-server
Thu 2026-03-12  SIGSEGV  /usr/bin/swayosd-server
```

Stack: `libgtk-4.so.1` → `libwayland-client.so.0` → `wl_display_dispatch_queue_pending`.

**2. Silent broken start on login** — process is alive but client can't connect:

```
$ swayosd-client --output-volume raise
Could not connect to SwayOSD Server with error:
org.freedesktop.DBus.Error.ServiceUnknown: The name is not activatable
```

The server needs to register two D-Bus names (`org.erikreider.swayosd` and
`org.erikreider.swayosd-server`). When it races with Wayland compositor init, GTK4
partially fails and only one name gets registered — the process stays up but broken.

No upstream fix in 0.3.0.

## Fix: systemd User Service with D-Bus Health Check

Replace the Hyprland `exec-once` launch with a user systemd service. Omarchy's default
`autostart.conf` still runs `uwsm-app -- swayosd-server` on session start, but swayosd
self-detects a running instance and exits cleanly — the systemd service remains
the authoritative instance.

`ExecStartPost` verifies both D-Bus names registered within 3 seconds. If the check fails
(broken start), it kills the server so `Restart=always` triggers a clean retry.
`After=wayland-session@hyprland.desktop.target` delays start until Hyprland is ready,
reducing the frequency of broken starts.

**`~/.config/systemd/user/swayosd-server.service`:**

```ini
[Unit]
Description=SwayOSD Server
PartOf=graphical-session.target
After=graphical-session.target
After=dbus.socket
After=wayland-session@hyprland.desktop.target

[Service]
ExecStart=/usr/bin/swayosd-server
# Verify both D-Bus names registered; kill to force a restart if not
ExecStartPost=/bin/bash -c 'sleep 3 && busctl --user list | grep -q org.erikreider.swayosd-server || systemctl --user kill swayosd-server'
Restart=always
RestartSec=2

[Install]
WantedBy=graphical-session.target
```

Enable once:

```bash
systemctl --user daemon-reload
systemctl --user enable --now swayosd-server.service
```

## Current State (as of 2026-03-13)

| Item | Value |
|------|-------|
| `swayosd` | 0.3.0-1 |
| Service file | `~/.config/systemd/user/swayosd-server.service` |
| Service state | enabled, `Restart=always`, D-Bus health check on start |
| Root cause | GTK4/libwayland race in 0.3.0, no upstream fix |
