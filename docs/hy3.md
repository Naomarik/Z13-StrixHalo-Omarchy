# hy3 — Manual Tiling Layout Plugin

[hy3](https://github.com/outfoxxed/hy3) is a Hyprland plugin that adds
i3/sway-style manual tiling. It replaces Hyprland's built-in dwindle/master
layouts with explicit split-direction control.

---

## Install

```bash
hyprpm update
hyprpm add https://github.com/outfoxxed/hy3
hyprpm enable hy3
hyprpm reload
```

`hyprpm` compiles the plugin against the running Hyprland version — make sure
`linux-g14-headers` matches the running kernel before running this.

After any Hyprland or kernel update:

```bash
hyprpm update && hyprpm reload
```

---

## Plugin config

```ini
plugin {
    hy3 {
        no_gaps_when_only = 1

        tabs {
            padding = 0
            radius = 0
            border_width = 1
        }

        autotile {
            enable = true
            trigger_width = 300
            trigger_height = 500
        }
    }
}
```

- **`no_gaps_when_only = 1`** — removes gaps when only one window is on the workspace
- **`autotile`** — automatically splits windows when the container exceeds 300×500px, so new windows tile without needing an explicit split key

---

## Keybindings

### Focus

| Key | Action |
|---|---|
| `Super + J/K/L/;` | Move focus left / up / down / right |
| `Super + ←/↑/↓/→` | Move focus (arrow keys) |
| `Super + A` | Raise focus to parent group |
| `Super + Escape` | Lower focus into child group |

### Move windows

| Key | Action |
|---|---|
| `Super + Shift + J/K/L/;` | Move window left / up / down / right |
| `Super + Shift + ←/↑/↓/→` | Move window (arrow keys) |

### Groups / splits

| Key | Action |
|---|---|
| `Super + H` | Make horizontal split group |
| `Super + T` | Make tab group |
| `Super + TAB` | Toggle tab mode on current group |
| `Super + E` | Toggle split direction (h ↔ v) on current group |
