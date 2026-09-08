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

---

## Install

### Requirements

- Omarchy **Quattro (4.x)** or newer, with the Quickshell shell (`omarchy-shell` on your
  `PATH` — it ships with Omarchy).
- Hyprland (developed against 0.56.2).

### 1. Add the plugin

```bash
omarchy plugin add https://github.com/Mindful-Stack/omyview.git --enable
```

This clones the plugin into `~/.config/omarchy/plugins/se.mindfulstack.omyview/` (the folder
is named after the manifest `id`, not the repo) and enables it. New plugins default to
disabled, so the `--enable` flag matters — without it, run `omarchy plugin enable
se.mindfulstack.omyview` afterwards.

Verify it's installed and enabled:

```bash
omarchy plugin list | grep omyview
# se.mindfulstack.omyview   enabled   third-party   overlay   Omyview
```

### 2. Bind a key to toggle it

Omyview only appears when you toggle it, so bind a key. **SUPER+P** is the intended bind.

If your Omarchy uses the Lua binding config (`~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + P", "Workspace overview", "omarchy-shell shell toggle se.mindfulstack.omyview")
```

If you use plain Hyprland config (`~/.config/hypr/bindings.conf` or `hyprland.conf`):

```ini
bind = SUPER, P, exec, omarchy-shell shell toggle se.mindfulstack.omyview
```

Then reload Hyprland so the bind takes effect:

```bash
hyprctl reload
```

### 3. Use it

Press **SUPER+P**. The overlay opens on your focused monitor.

| Key / action        | Effect                                    |
| ------------------- | ----------------------------------------- |
| **SUPER+P**         | Toggle the overlay (open and close)       |
| **1–9, 0**          | Jump to that workspace (`0` = 10)         |
| **← → ↑ ↓**         | Move the highlight                        |
| **Enter**           | Jump to the highlighted workspace         |
| **Click / hover**   | Jump to / highlight a cell                |
| **Esc / click-out** | Close                                     |

### Updating

```bash
omarchy plugin update se.mindfulstack.omyview
```

### Uninstalling

```bash
omarchy plugin remove se.mindfulstack.omyview
```

…then delete the SUPER+P bind you added and `hyprctl reload`.

### Troubleshooting

- **Nothing happens on SUPER+P.** Check the plugin is `enabled` (`omarchy plugin list |
  grep omyview`) and that your bind targets the exact id `se.mindfulstack.omyview`. Re-run
  `hyprctl reload` after editing the bind.
- **`summon: plugin not enabled` in the shell log.** Run `omarchy plugin enable
  se.mindfulstack.omyview`.
- **It opens on the wrong monitor.** Focused-monitor targeting is verified on a single
  display; multi-monitor is still being validated — see `ROADMAP.md`.

---

## Configuration

`Overview.qml` exposes a `mode` property near the top (default `"full"`):

- `"full"` — every persistent workspace per monitor, empties dimmed (stable positions).
- `"occupied"` — only workspaces that have windows (plus the focused one).

Edit the value, then run `omarchy restart shell` (see the note in Contributing about why a
plain rescan isn't enough).

---

## Contributing

Contributions are welcome — bug reports, fixes, and the roadmap items in `ROADMAP.md`.

### Project layout

| File          | What it is                                                        |
| ------------- | ----------------------------------------------------------------- |
| `manifest.json` | Omarchy plugin manifest (id, kind, entry point). Schema v1.     |
| `Overview.qml`  | The whole plugin — a single QML component (the overlay).        |
| `DESIGN.md`     | What it does and why (the v1 design).                           |
| `PLAN.md`       | How it was built, task by task, with the verified gotchas.      |
| `ROADMAP.md`    | What's next (docked verification, both-screens dimming, thumbs).|

If you're new to Quickshell/QML: it's Qt Quick (declarative UI, JavaScript for logic). You
don't need to know it deeply — `Overview.qml` is self-contained and commented, and the shell
APIs it uses (`Hyprland.*`, `Quickshell.*`, `Color.menu.*`) are documented inline in
`DESIGN.md`.

### Local development loop

1. **Work against a live checkout.** The version Omarchy runs lives at
   `~/.config/omarchy/plugins/se.mindfulstack.omyview/` (a clone of this repo). Either edit
   there directly, or clone this repo elsewhere for development:

   ```bash
   git clone git@github.com:Mindful-Stack/omyview.git
   cd omyview
   ```

2. **Edit `Overview.qml`.**

3. **Reload the shell to see the change:**

   ```bash
   omarchy restart shell
   ```

   > ⚠️ **Editing QML requires `omarchy restart shell`, not just a rescan.**
   > `omarchy-shell shell rescanPlugins` reloads the manifest/registry but **not** the live
   > QML component, so your code change won't show until a full shell restart.

4. **Validate the manifest** before you commit (the shell enforces the same checks and will
   silently refuse a bad manifest):

   ```bash
   omarchy plugin validate .
   ```

### Testing

There's no unit-test harness — this is a visual overlay, so "testing" means reloading the
shell and checking behavior. Before opening a PR, confirm:

- [ ] `omarchy plugin validate .` passes.
- [ ] SUPER+P opens and closes the overlay; `Esc` and click-outside close it.
- [ ] Number keys `1`–`0` jump to the right workspace; arrows + `Enter` work; click works.
- [ ] The window mini-map roughly matches your real window layout.
- [ ] It re-themes correctly after `omarchy theme next` (or any theme switch).
- [ ] If you have a second monitor: the two-row layout and per-monitor mini-map coordinates
      are correct (this path is still being validated — call it out in the PR).

### Submitting changes

1. Branch off `main`: `git checkout -b your-change`.
2. Keep commits focused; write a clear message explaining the *why*.
3. If you change behavior, update `DESIGN.md`/`ROADMAP.md` to match.
4. Open a PR against `Mindful-Stack/omyview`. Describe what you tested from the checklist
   above (a screenshot or short screen recording helps a lot for UI changes).

Maintainers: **@DanielThyselius**, **@dotnetemmanuel**.

---

## License

MIT — see [LICENSE](LICENSE).
