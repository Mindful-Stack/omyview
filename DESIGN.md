# Omyview — design (v1)

Date: 2026-09-06 · Omarchy 4.0.2 (Quattro) · Hyprland 0.56.2 · Quickshell shell

A Quickshell workspace overview for Omarchy, triggered by SUPER+P. Replaces the
dead v3 `workspace-picker.sh` (which relied on `walker`, removed in Quattro).

## Goal

Press SUPER+P to get a visual overview of all workspaces (grouped by monitor) and
jump to one — keyboard or mouse.

## Scope

**v1 (this design):**
- One overlay, on the **active monitor only**.
- Shows **every connected monitor's workspaces**, grouped into one boxed **row per
  monitor** (dynamic via Hyprland's workspace→monitor mapping). Docked → two rows
  (laptop eDP-1, external HDMI-A-1); undocked → collapses to just the laptop's row.
- **No dimming** (everything is on one screen).

**Deferred (v2, not now):**
- Rendering the overlay on *both* physical screens simultaneously, with the
  non-active monitor's section dimmed.
- Live pixel thumbnails per window (via Quickshell screencopy). Drops in per-window
  without changing the architecture. Zero idle cost (only captures while open), so
  safe to add later; kept out of v1 only to avoid the Hyprland toplevel-export
  dependency risk on the first build.

## Behavior

- **Trigger:** SUPER+P **toggles** the overlay (open *and* close), via `omarchy-shell
  shell toggle`. Esc, a scrim click (outside the rows), and selecting a workspace also
  close it. Verified 2026-09-06: the overlay uses *exclusive* keyboard focus so bare keys
  (numbers/arrows/Esc) reach it, **and** Hyprland still processes the SUPER+P keybind over
  that exclusive focus — so both coexist. (An earlier assumption that exclusive focus
  would swallow SUPER+P was disproved by testing; no on-demand-focus change needed.)
- **Cells:** one per workspace. Windows drawn as a **spatial mini-map** — each window a
  rounded box at its real relative position/size with the app icon (title if it fits).
  Focused workspace = accent border; empty = dimmed. Excludes `special:scratchpad`.
- **`mode` setting** (one property, default `full`):
  - `full` — all pinned workspaces for each monitor, empties dimmed (stable positions).
  - `occupied` — only workspaces with windows.
- **Select:** number keys jump (1-9, `0`=10) · arrow keys move highlight + Enter ·
  mouse click · Esc cancels. Jump via Hyprland dispatch `workspace <id>`.
- **Styling:** pulls the active Omarchy theme (colors/fonts) so it matches the bar and
  re-themes automatically.

## Layout

```
              ACTIVE MONITOR (overlay, centered)
┌─ Laptop · eDP-1 ─────────────────────────────────┐
│  [1★]   [2]    [3]    [4]    [5]                  │
└──────────────────────────────────────────────────┘
┌─ External · HDMI-A-1 ────────────────────────────┐
│  [6]    [7]    [8]    [9]    [10]                 │
└──────────────────────────────────────────────────┘
              1-0 jump · click · Esc close
```

## Architecture / integration

- Omarchy-shell **user plugin**: `~/.config/omarchy/plugins/se.mindfulstack.omyview/`
  (`manifest.json` + `Overview.qml` + any JS helpers). Lives in the user config dir →
  survives `omarchy update`; hot-reloads on save (`omarchy-shell shell rescanPlugins`
  to force).
- Toggled via `omarchy-shell shell toggle se.mindfulstack.omyview`, bound to **SUPER+P** in
  `~/.config/hypr/bindings.lua` (replacing the walker picker line).
- Built on the shell's shared overlay (`Ui/Panel.qml`) + Hyprland service. Data:
  `Hyprland.workspaces` (each with `.toplevels` = its windows incl. geometry + app id,
  `.monitor`), `Hyprland.focusedWorkspace`, `Hyprland.focusedMonitor`.

## Resolved architecture facts (from shell sources)

- Surface = a `PanelWindow` (Quickshell.Wayland), **not** `Ui/Panel.qml` (that is only
  the IPC open/close lifecycle base). Mirror Clipboard's `PanelWindow`: fullscreen
  anchors, `color:"transparent"`, `WlrLayershell.layer: WlrLayer.Overlay`,
  `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive`, `exclusionMode: Ignore`,
  a scrim `Rectangle` (`Color.menu.scrim`) + a scrim `MouseArea{onClicked: close()}`,
  and a focusable `keyCatcher` `Item{ focus:true; Keys.priority: BeforeItem }`.
- Clipboard sets no `screen:`, so we must: set the `PanelWindow.screen` to the
  Quickshell screen whose `.name` matches `Hyprland.focusedMonitor.name`, resolved when
  opening.
- Window geometry (`toplevel.lastIpcObject.at/size/class`) can be **stale** — call
  `Hyprland.refreshToplevels()` on open and bind to the resulting updates.
- Coordinates: window `at`/`size` are global **logical** px; monitor origin is
  `Hyprland monitor .x/.y` (logical), monitor logical size = physical/scale. Convert to
  monitor-local logical (subtract origin) before scaling into a cell. Real numbers:
  eDP-1 origin (0,1440), 2560×1600 @ scale 1.25 → 2048×1280 logical.

## Open implementation questions (resolve in the build plan)

- App-icon resolution from app id / class (find the shell's icon-lookup helper).
- Which dispatch form actually switches workspace from an overlay (`Hyprland.dispatch`
  vs shelling `hyprctl dispatch` with the lua `hl.dsp.focus` form the bar widget uses).

---

## v2 — live previews + drag-and-drop (2026-09-09)

v2 replaces the icon mini-map with live window thumbnails and adds drag-and-drop of windows
between workspaces. See `docs/specs/2026-09-08-omyview-previews-drag-drop-design.md` (design)
and `docs/plans/2026-09-08-v2-previews-drag-drop.md` (task-by-task build).

- **Shared canvas, per-monitor rows kept.** The card holds one non-clipped canvas with two
  sibling layers: workspace **boxes** (drop targets) and absolutely-positioned window **tiles**.
  Tiles are canvas-level siblings so one can be dragged across the whole surface onto any box.
- **Pure logic seam (`logic.js`).** All coordinate math, monitor-row ordering, the usable-rect
  window→tile mapping (one reference rect per monitor: `size − reserved`, letterboxed +
  centered; fullscreen fills it, others clip to it), `hitWorkspace`, and the address-keyed
  reconcile diff live in a dependency-free `.pragma library` module — unit-tested offscreen via
  `qmltestrunner` (Tier 1 CI). `Overview.qml` only wires Quickshell singletons to it.
- **Live previews (`WindowTile.qml`).** A `ScreencopyView` fed the wl `Toplevel` handle,
  resolved by joining `ToplevelManager.toplevels[].HyprlandToplevel.address` to the window's
  Hyprland address. `capMode` (`live`/`snapshot`/`icon`) with an icon fallback; captures run
  only while open. Cross-output live capture verified on Hyprland 0.56.2.
- **Drag-safe reconcile.** The tiles model is an address-keyed `ListModel` reconciled in place
  (never wholesale-reassigned), and the dragged address is never removed/replaced mid-drag —
  so the pointer grab and its `ScreencopyView` survive refreshes.
- **Silent move + reconcile.** On drop, `hl.dsp.window.move({ workspace, follow = false, … })`
  (typed dispatch in Hyprland Lua configuration mode; works via Quickshell and `hyprctl`),
  then `refreshToplevels()` and a bounded reconcile so the tile settles on real geometry.
- **Testing.** Tier 1 numeric unit tests (`logic.js`) in CI; Tier 2 nested-Hyprland integration
  (`tests/integration/move.sh`) asserts the silent-move semantics on a real, isolated Hyprland.

## Drag repair and polish (2026-09-09)

- Refresh each existing tile's floating role; changing a window from tiled to floating must
  immediately enable floating placement.
- Hold optimistic drop geometry per address until fresh client workspace/coordinates match.
  After 1.8 seconds, rejected moves return to compositor geometry. Separate grabs can have
  independent pending moves. A new grab supersedes its address's old pending destination.
- For floating workspace transfers, send position only after the target workspace appears
  in fresh client data. Coordinates are quoted global logical pixels, bounded by the full
  window's extent and the target monitor's usable area.
- Centralize release/cancellation/close cleanup. Tile stacking stays a declarative binding
  to dragging/hover state. A missing dragged client cancels the gesture on refresh.
- Edge scrolling ramps within 48 logical pixels of the viewport boundary. Content changes
  offset the held tile equally, keeping it under the pointer and updating the target highlight.
  Background refreshes no longer scroll back to the keyboard-selected workspace.
- Offscreen Qt tests cover real mouse events and binding restoration. The integration test
  exercises production Overview methods through real Quickshell in a disposable Lua session.

## Addressed tiled drops (2026-09-10)

The earlier same-workspace tiled snap-back limitation is superseded. Hyprland 0.56.2 accepts
`hl.dsp.window.swap({window="address:SOURCE", target="address:TARGET"})`. No focus step is
needed. A Lua function saves `hl.get_cursor_pos()`, dispatches the swap and restores the cursor,
because the native swap warps it even for hidden workspaces.

Drop hit-testing uses the dragged tile's center and excludes the source, floating/fullscreen
windows and pending targets. Same-workspace drops swap both tiles optimistically; acknowledgement
checks both positions and sizes. Cross-workspace drops transfer first, then swap with the chosen
target using its fresh geometry. The target remains on its workspace. If it disappears or
becomes ineligible, the completed transfer retains normal tiling. Empty workspace drops also
use normal tiling. The target tile is highlighted before release.

Verified with real Quickshell and three tiled windows: exchanging positions/sizes without
changing active workspace or cursor; transferring to a selected slot on a hidden workspace.
