# SwayOSD — OSD Overlay for Volume / Brightness

## Problem: Recurring SIGSEGV Crashes

`swayosd-server` 0.3.0 crashes with `SIGSEGV` (signal 11) inside `libgtk-4.so.1`
during Wayland dispatch. The crash happens mid-session with no user-visible warning —
the OSD simply stops appearing. Nothing restarts it automatically.

```
# coredumpctl list swayosd-server shows recurring crashes:
Sat 2026-02-07  SIGSEGV  /usr/bin/swayosd-server
Tue 2026-02-10  SIGSEGV  /usr/bin/swayosd-server
Thu 2026-03-12  SIGSEGV  /usr/bin/swayosd-server
```

Stack top: `libgtk-4.so.1` → `libwayland-client.so.0` → `wl_display_dispatch_queue_pending`.
Upstream GTK4/libwayland race condition in swayosd 0.3.0. No fix available yet.

## Problem: D-Bus Timing on Session Start

Even without a crash, the OSD can silently stop working after login:

```
$ swayosd-client --output-volume raise
Could not connect to SwayOSD Server with error:
org.freedesktop.DBus.Error.ServiceUnknown: The name is not activatable
```

The process is alive (`pgrep swayosd` returns a PID) but lost its D-Bus registration
because it started before the session bus was fully ready.

## Fix: systemd User Service with Auto-Restart

Replace the Hyprland `exec-once` launch with a user systemd service. Omarchy's default
`autostart.conf` still runs `uwsm-app -- swayosd-server` on session start, but swayosd
self-detects a running instance and exits cleanly — the systemd service remains
the authoritative instance.

**`~/.config/systemd/user/swayosd-server.service`:**

```ini
[Unit]
Description=SwayOSD Server
PartOf=graphical-session.target
After=graphical-session.target
After=dbus.socket

[Service]
ExecStart=/usr/bin/swayosd-server
Restart=always
RestartSec=2

[Install]
WantedBy=graphical-session.target
```

`After=dbus.socket` ensures it never starts before the session bus is ready,
fixing the silent D-Bus failure. `Restart=always` with a 2-second delay covers
the crash case.

Enable once:

```bash
systemctl --user daemon-reload
systemctl --user enable --now swayosd-server.service
```

## Current State (as of 2026-03-12)

| Item | Value |
|------|-------|
| `swayosd` | 0.3.0-1 |
| Service file | `~/.config/systemd/user/swayosd-server.service` |
| Service state | enabled, `Restart=always`, `After=dbus.socket` |
| Crash root cause | GTK4/libwayland race in 0.3.0, no upstream fix |
