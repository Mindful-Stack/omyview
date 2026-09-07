# Omyview — roadmap / next steps

**Status:** v1 shipped and in daily use (2026-09-07). Overlay on SUPER+P; per-monitor
rows; window mini-map with app icons; number/arrow/Enter/click selection; `mode: full`.
Now maintained as a standalone public repo (`Mindful-Stack/omyview`). See `DESIGN.md`
(what/why) and `PLAN.md` (how it was built + the verified gotchas).

## Next steps

### 1. Verify when docked (not yet tested — no external display at build time)
- [ ] Overlay opens on the **focused** monitor, not always the primary
      (`focusedScreen()` matches `Hyprland.focusedMonitor.name` → `Quickshell.screens`).
- [ ] Two-row layout renders: laptop `eDP-1` (1–5) and external `HDMI-A-1` (6–10),
      grouped by each workspace's `.monitor`; collapses to one row when undocked.
- [ ] Window mini-map coordinates are correct on the **external** monitor too (the
      origin/scale conversion was only checked on `eDP-1`, origin `(0,1440)` scale `1.25`).

### 2. v2 — both-screens rendering with dimming (the original idea)
Currently a single overlay on the active monitor shows every monitor's workspaces as
stacked rows. v2: render the overlay on **every** screen at once, each screen showing its
own workspaces prominent and the **other** monitor's section **dimmed**. Likely a
`Variants`/per-screen `PanelWindow` keyed on `Quickshell.screens`.

### 3. v2 — live window thumbnails (screencopy)
Replace/augment the icon mini-map with real scaled window pixels via Quickshell
screencopy. Zero idle cost (captures only while open). Risk: depends on Hyprland's
toplevel-export protocol cooperating with Quickshell — prototype before committing.

### 4. Polish / accuracy
- [ ] Better app-icon resolution: current is `Quickshell.iconPath(class.toLowerCase())`
      with a letter fallback; reverse-DNS or mismatched classes fall back to a letter.
      Improve with `DesktopEntries` heuristic lookup or a class→icon map.
- [ ] Optional: subtract each monitor's reserved bar area (`monitor.reserved`) from the
      mapped mini-map region (v1 maps the full monitor logical area, ignoring the ~26px bar).

### 5. ~~Extract to a standalone repo~~ ✅ done
Extracted from the author's dotfiles into `Mindful-Stack/omyview` (2026-09-07). Installed
per-machine with `omarchy plugin add https://github.com/Mindful-Stack/omyview.git --enable`
and updated with `omarchy plugin update se.mindfulstack.omyview`. See `README.md` for the
consumer-side install + SUPER+P bind.

## Maintenance gotchas (verified in-session)
- **Editing `Overview.qml` requires `omarchy restart shell`** — `omarchy-shell shell
  rescanPlugins` reloads the registry but NOT the live QML component.
- New plugins default **disabled** — `omarchy plugin enable se.mindfulstack.omyview` (stored
  in `~/.config/omarchy/shell.json` `plugins[]`).
- `omarchy plugin add` clones into `~/.config/omarchy/plugins/<manifest id>/`, i.e.
  `se.mindfulstack.omyview/` — the folder is named after the manifest `id`, not the repo.
- SUPER+P toggles open AND close even under the overlay's exclusive keyboard focus
  (Hyprland forwards configured keybinds over the layer); bare keys still reach the overlay.
