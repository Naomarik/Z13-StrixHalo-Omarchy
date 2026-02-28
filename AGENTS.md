# AGENTS.md — z13flow

## Project Overview

Linux desktop configuration repository for an ASUS ROG Flow Z13 (2025) running
Arch Linux + Omarchy (Hyprland/Wayland). Contains Hyprland configs, Waybar
modules with custom scripts, EasyEffects audio presets, and a gaming-mode
installer. **No build system, package manager, or test framework** — this is a
dotfiles/config repo composed of Bash scripts, Hyprland `.conf` files, JSONC,
CSS, and JSON presets.

## Repository Layout

```
z13flow/
├── hypr/               # Hyprland config: bindings, monitors, input, visuals
│   ├── *.conf          # Sourced by hyprland.conf in order
│   └── scripts/        # Keybind-triggered scripts (window mgmt, dictation, etc.)
├── waybar/
│   ├── config.jsonc    # Waybar panel module definitions
│   ├── style.css       # Waybar stylesheet
│   └── scripts/        # Polling/signal scripts for Waybar custom modules
├── easyeffects/        # EasyEffects audio presets (input/output JSON + IRS)
├── scripts/            # Standalone installers (gaming-mode-install.sh)
├── docs/               # Supplementary documentation (markdown)
└── README.md           # Hardware baseline, quick-start, feature docs
```

## Build / Lint / Test Commands

There is no build step, linter, or test suite. Validation is manual:

```bash
# Syntax-check a script without executing it
bash -n waybar/scripts/temperatures.sh

# Lint with shellcheck (if installed)
shellcheck waybar/scripts/*.sh hypr/scripts/*.sh scripts/*.sh

# Validate Waybar JSONC (strip comments, pipe to jq)
sed 's|//.*||' waybar/config.jsonc | jq . > /dev/null

# Reload Hyprland config after changes
hyprctl reload

# Restart Waybar to pick up script or config changes
pkill waybar && hyprctl dispatch exec waybar
```

There are no single-test or test-runner commands. To verify a script works,
run it directly (most scripts are safe to invoke standalone).

## Shell Script Style Guide

### Shebang and Error Handling

- Use `#!/bin/bash` for scripts that rely on Bash features (arrays, `[[`, `${VAR#pattern}`).
- Use `#!/usr/bin/env bash` only when portability across PATH differences matters.
- Small utility scripts (< 50 lines) omit `set -e`; they rely on explicit
  conditionals and `exit` codes instead.
- Large installer scripts use strict mode: `set -Euo pipefail`.
- Suppress expected failures inline with `2>/dev/null` or `|| true`.

### Naming Conventions

- **Script filenames**: lowercase, hyphen-separated — `toggle-window-mode.sh`,
  `power-profile-toggle.sh`.
- **Variables**: `UPPER_SNAKE_CASE` for constants, config values, and exported
  vars. `lower_snake_case` for locals.
- **Functions** (rare, only in large scripts): `lower_snake_case` — e.g.,
  `validate_environment()`, `check_package()`.
- **Logging helpers** (installer only): `info()`, `warn()`, `err()`, `die()`.

### Formatting

- **Indentation**: 2 or 4 spaces (not tabs). Most scripts use 4-space indent;
  some smaller ones use 2-space. Be consistent within a file.
- **Line length**: no hard limit, but keep under ~120 characters where practical.
- **Quoting**: always double-quote variable expansions (`"$VAR"`, `"$(...)"`)
  unless word splitting is intentionally desired.
- **Braces**: use `${VAR}` when adjacent to other text; plain `$VAR` is fine
  when unambiguous.
- **Conditionals**: prefer `[[ ]]` over `[ ]` for string/regex tests. Use
  `[ ]` (POSIX) only in trivially simple guards.

### Patterns and Idioms

- **Waybar JSON output**: scripts that feed Waybar custom modules must print
  a single JSON line: `{"text":"...", "tooltip":"...", "class":"..."}`.
  Use Pango markup in `text` for color: `<span color='#ff4444'>icon</span>`.
- **Waybar signal refresh**: after changing state, signal Waybar with
  `pkill -RTMIN+N waybar` (N is the module's `signal` value in config.jsonc).
- **State files**: toggle state tracked via flag files in `/tmp/`, `/run/`,
  or `/var/lib/` — existence of the file = feature is active.
- **Hyprland IPC**: use `hyprctl <subcommand> -j` for JSON output, parse with
  `jq`. Common: `hyprctl activewindow -j`, `hyprctl workspaces -j`,
  `hyprctl monitors -j`, `hyprctl clients -j`.
- **Notifications**: use `notify-send "Title" "Body"` with `-u critical` for
  errors and `-t <ms>` for auto-dismiss.
- **Background work**: long-running post-processing (transcription, encoding)
  goes into a subshell `( ... ) &` to keep the triggering keybind responsive.
- **Cleanup on exit**: use `trap cleanup EXIT` when the script creates temp
  files or spawns background processes that must be reaped.

### Error Handling

- Small scripts: guard with `[[ -z "$var" ]] && exit 0` for early exits.
  Non-critical failures: `command 2>/dev/null || true`.
- Large scripts (`gaming-mode-install.sh`): use `die "message"` for fatal
  errors (prints to stderr, logs via `logger`, exits non-zero). Validate
  prerequisites at the top with `command -v ... || die "..."`.

## Hyprland Config Style

- Files in `hypr/` are **Hyprlang** format (not INI, not TOML).
- `hyprland.conf` sources Omarchy defaults first, then per-file overrides.
- One concern per file: `bindings.conf`, `monitors.conf`, `input.conf`,
  `looknfeel.conf`, etc.
- Comments with `#`. Keep inline comments short.
- Bind format: `bind = MODS, KEY, dispatcher, args` — group related binds
  under `# Section` comment headers.

## Waybar Config Style

- `config.jsonc` uses JSONC (JSON with `//` comments).
- Each custom module references a script via `"exec"` and optionally listens
  for clicks via `"on-click"` / `"on-click-right"`.
- Signal-based modules use `"exec-on-event": false` with `"signal": N`.
- Interval-based modules use `"interval": <seconds>`.

## CSS (Waybar)

- `waybar/style.css` follows standard CSS targeting Waybar widget selectors
  (`#custom-<name>`, `.modules-left`, `#battery`, etc.).
- Colors are hex (`#rrggbb`). Font: system default set by Omarchy theme.

## Dependencies to Be Aware Of

Scripts assume these tools are installed and in PATH:
`hyprctl`, `jq`, `notify-send`, `sensors`, `pkill`, `wl-copy`, `wtype`,
`slurp`, `gpu-screen-recorder`, `ffmpeg`, `ffplay`, `v4l2-ctl`,
`powerprofilesctl`, `ryzenadj` (at `~/.local/bin/ryzenadj`),
`omarchy-launch-walker`.

## Git Practices

- `.gitignore` excludes `opencode/`, `.env*`, private keys, and certificates.
- No CI/CD pipelines — changes are applied locally after `git pull`.
- Commit messages should be concise and describe what config changed and why.

## Important Caveats

- `ryzenadj` calls require `sudo` or appropriate polkit rules for hardware
  tuning (STAPM limits, undervolt). Scripts assume this is pre-configured.
- The `gaming-mode-install.sh` script (2595 lines) creates systemd services,
  polkit rules, sudoers entries, and udev rules. It should only be run
  intentionally — never as part of routine testing.
- Monitor configs in `monitors.conf` are hardware-specific (eDP-1 internal
  panel + DP-1 external). Editing these without matching hardware will break
  display output.
