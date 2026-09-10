# Omyview — roadmap / next steps

**Status:** **v2 shipped (2026-09-09).** Overlay on SUPER+P; per-monitor rows; **live window
thumbnails** (Quickshell `ScreencopyView`); **drag-and-drop of windows between workspaces**
(silent move); number/arrow/Enter selection; click-to-focus / middle-click-close. Coordinate
math + reconcile in a unit-tested `logic.js` (Tier 1 CI); Tier 2 nested-Hyprland integration.
Maintained as a standalone public repo (`Mindful-Stack/omyview`). See `DESIGN.md` (what/why),
`docs/specs/` + `docs/plans/` (the v2 design + build), and `PLAN.md` (v1 build log). Window
states (2026-09-10): fullscreen windows drawn in their recovered slot with an un-fullscreen
badge; floating tiles stack above tiled.

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

### 3. ~~v2 — live window thumbnails (screencopy)~~ ✅ done (2026-09-09)
Real scaled window pixels via Quickshell `ScreencopyView`, captures only while open. The
toplevel-export path cooperates with Quickshell on Hyprland 0.56.2 — verified live across all
cases: occluded, **cross-output** (a window on another monitor renders live), and **hidden
workspaces** (a workspace not shown on any monitor still captures — case B confirmed). So
`capMode` stays `live` everywhere; the icon fallback remains for windows without a handle.

### 4. ~~v2 — drag-and-drop between workspaces~~ ✅ done (2026-09-09)
Drag a window tile onto another workspace box → `hl.dsp.window.move(follow=false)` (silent).
Overview stays open; post-move `refreshToplevels()` reconcile with bounded recovery.

### 5. Polish / accuracy
- [ ] Better app-icon resolution: current is `Quickshell.iconPath(class.toLowerCase())`
      with a letter fallback; reverse-DNS or mismatched classes fall back to a letter.
      Improve with `DesktopEntries` heuristic lookup or a class→icon map.
- [x] Subtract each monitor's reserved bar area (`monitor.reserved`) — done: the v2 usable-rect
      model maps against `monitor size − reserved`.

### 6. ~~Extract to a standalone repo~~ ✅ done
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
