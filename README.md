# Omyview

A workspace overview overlay for [Omarchy](https://omarchy.org)'s Quickshell shell.
Press **SUPER+P** to get a visual, spatial overview of every workspace — grouped by
monitor, with a mini-map of each window in its real position — and jump to any workspace
by keyboard or mouse.

Built to replace the dead `walker`-based `workspace-picker.sh` after Omarchy Quattro
removed `walker`.

## Features

- **Per-monitor rows.** Workspaces are grouped into one boxed row per monitor, derived
  live from Hyprland's workspace→monitor mapping. Docked shows two rows; undocked collapses
  to one.
- **Window mini-map.** Each workspace cell draws its windows as rounded boxes at their real
  relative position and size, with the app icon (falls back to the first letter of the
  window class).
- **Fast selection.** Number keys jump (`1`–`9`, `0` = 10), arrow keys move the highlight +
  `Enter`, mouse click, and hover-to-highlight. `Esc` or a click outside closes.
- **Theme-aware.** Pulls the active Omarchy theme's colors and fonts, so it matches the bar
  and re-themes automatically.
- **Zero idle cost.** It's an on-demand overlay — nothing runs until you summon it.

## Requirements

- Omarchy **Quattro (4.x)** or newer, with the Quickshell shell (`omarchy-shell`).
- Hyprland (tested on 0.56.2).

## Install

```bash
omarchy plugin add https://github.com/Mindful-Stack/omyview.git --enable
```

This clones the plugin into `~/.config/omarchy/plugins/se.mindfulstack.omyview/` and enables
it. (New plugins default to disabled; `--enable` turns it on.)

Then bind **SUPER+P** to toggle it. In `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + P", "Workspace overview", "omarchy-shell shell toggle se.mindfulstack.omyview")
```

(Or in `bindings.conf`: `bind = SUPER, P, exec, omarchy-shell shell toggle se.mindfulstack.omyview`.)

Reload Hyprland's config, and press **SUPER+P**.

## Usage

| Key / action        | Effect                                    |
| ------------------- | ----------------------------------------- |
| **SUPER+P**         | Toggle the overlay (open and close)       |
| **1–9, 0**          | Jump to that workspace (`0` = 10)         |
| **← → ↑ ↓**         | Move the highlight                        |
| **Enter**           | Jump to the highlighted workspace         |
| **Click / hover**   | Jump to / highlight a cell                |
| **Esc / click-out** | Close                                     |

## Configuration

`Overview.qml` exposes a `mode` property (default `"full"`):

- `"full"` — every persistent workspace per monitor, empties dimmed (stable positions).
- `"occupied"` — only workspaces that have windows (plus the focused one).

After editing `Overview.qml`, run `omarchy restart shell` — `omarchy-shell shell
rescanPlugins` reloads the manifest but **not** the live QML component.

## Updating

```bash
omarchy plugin update se.mindfulstack.omyview
```

## Development

- `DESIGN.md` — what it does and why (the v1 design).
- `PLAN.md` — how it was built, task by task, with the Hyprland/Quickshell gotchas verified
  along the way.
- `ROADMAP.md` — what's next (docked verification, both-screens dimming, live thumbnails).

## License

MIT — see [LICENSE](LICENSE).
