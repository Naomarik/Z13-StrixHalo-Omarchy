# hy3 — Manual Tiling Layout Plugin

[hy3](https://github.com/outfoxxed/hy3) is a Hyprland plugin that adds
i3/sway-style manual tiling. It replaces Hyprland's built-in dwindle/master
layouts with explicit split-direction control.

## Install

```bash
hyprpm update
hyprpm add https://github.com/outfoxxed/hy3
hyprpm enable hy3
hyprpm reload
```

`hyprpm` compiles the plugin against the running kernel headers — make sure
`linux-g14-headers` is installed and matches the running kernel before running
this.

## After a kernel/Hyprland update

Re-run `hyprpm update && hyprpm reload` to recompile the plugin against the
new version.

## Config

`bindings.conf` sets `general { layout = hy3 }` and all the `hy3:*` dispatch
bindings (movefocus, movewindow, makegroup, changegroup, etc.).
