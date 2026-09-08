# Omyview v2 — live previews + drag-and-drop (design)

Date: 2026-09-08 · Target: Omarchy Quattro (4.x), Hyprland 0.56.2, Quickshell 0.3.1
Status: **approved design, pre-implementation**

## Goal

Bring Omyview's overview closer to [end-4's dots-hyprland overview](https://github.com/end-4/dots-hyprland):

1. **Live window previews** — each window drawn as a real, live thumbnail of its
   contents instead of an icon box.
2. **Drag-and-drop between workspaces** — grab a window tile and drop it on another
   workspace to move it there (silently, without switching to that workspace).

While keeping Omyview's identity: workspaces stay grouped into **one row per monitor**
(not end-4's flat rows×columns grid), and the overlay stays a single on-demand
`PanelWindow` on the focused monitor.

## Feasibility (confirmed, not assumed)

- **Screencopy works on Hyprland natively.** end-4 runs live thumbnails on Hyprland via
  Quickshell's `ScreencopyView` — no `hyprpm` / toplevel-export plugin. Our Quickshell
  0.3.1 ships `Quickshell.Wayland._Screencopy` (`ScreencopyView` with `captureSource`,
  `live`, `hasContent`) and `_ToplevelManagement` (`ToplevelManager`, `Toplevel`).
- **The capture handle ↔ Hyprland join:** iterate `ToplevelManager.toplevels`, read
  `toplevel.HyprlandToplevel.address`, and match to the window's Hyprland address. We
  already read geometry from `Hyprland.toplevels[].lastIpcObject` in v1, so we do **not**
  adopt end-4's `hyprctl clients -j` polling.
- **Silent move dispatch:** `hl.dsp.window.move({ workspace = N, follow = false, window =
  "address:0x…" })`. v1 already uses `hl.dsp.*` (`hl.dsp.focus`), so the typed dispatcher
  is known-good on our Hyprland.

The **one residual risk** — whether a *background / occluded* window captures real pixels
(vs. black) on our exact Quickshell/Hyprland versions — is settled by a step-0 spike below,
not by this design.

## Scope

**In:**
- Live-thumbnail window tiles with icon fallback.
- Drag a tile onto another workspace → silent move.
- Refactor: a dependency-free logic module (for testability, see Testing).
- Reserved-bar-area subtraction so tiles don't sit under the bar.
- Tier 1 unit tests (CI) + Tier 2 integration test (local).

**Out (deferred, explicitly YAGNI for v2):**
- Both-screens simultaneous render + non-active dimming (still a future item).
- Workspace **paging** (all workspaces shown in rows, as v1).
- Dragging to **reposition a floating window within** its own workspace (end-4 does this).
- **Rotated-monitor** (`transform`) handling.
- Full pointer-drag pixel e2e (Tier 3).

## Architecture

The overlay is unchanged at the shell level: a `PanelWindow` on the focused monitor with a
scrim, exclusive keyboard focus, and a centered card (v1's structure). What changes is the
**inside of the card**: v1's clipped per-cell mini-maps become a single **non-clipped
canvas** carrying two sibling layers.

```
card
└── canvas  (Item, non-clipped, size = logic.canvasSize)
    ├── boxes layer     Repeater over logic.boxes    → workspace Rectangle + number + DropArea
    └── tiles layer     Repeater over logic.tiles     → WindowTile (ScreencopyView + icon + drag MouseArea)
```

Tiles are **canvas-level siblings** drawn above the boxes, not children of a cell — that is
what lets a tile be dragged across the whole surface and dropped on any box. Box positions
still describe per-monitor rows, so visually it reads like v1; the windows just float on a
layer above and can cross boundaries.

### Components

**1. `logic.mjs` — a pure JS module, no Quickshell imports.**
The testable seam, imported by both `Overview.qml` (`import "logic.mjs" as Logic`) and the
test QML. Given plain data, computes the layout. No side effects, no singletons.

```
layout(input) -> {
  canvasSize: { w, h },
  boxes:  [{ workspaceId, monitorName, x, y, w, h, focused, occupied }],
  tiles:  [{ address, workspaceId, x, y, w, h }],   // canvas-absolute
}

hitWorkspace(boxes, px, py) -> workspaceId | null    // point → drop target

input = {
  monitors:   [{ name, x, y, width, height, scale, reserved:[l,t,r,b], transform }],
  workspaces: [{ id, monitorName, focused, occupied }],
  windows:    [{ address, cls, ax, ay, sw, sh, workspaceId, floating }],
  focusedMonitorName: "eDP-1",
  params:     { cellW, cellH, cellInset, cellSpacing, rowSpacing, rowLabelH }
}
```

Responsibilities: row grouping by monitor, box placement, per-monitor letterbox scale
`k = min((cellW−2·inset)/monLogicalW, (cellH−2·inset)/monLogicalH)`, window→canvas mapping
`tileX = box.x + inset + (win.ax − mon.x − reserved.l)·k` (same for Y with `reserved.t`),
monitor logical size `width/scale × height/scale`, ordering rows with `focusedMonitorName`
first then by monitor `x`, and skipping `id < 0` / special workspaces. This is the whole
coordinate-math surface — and the whole Tier 1 test surface.

`hitWorkspace` is the pure point→box test used by Tier 1; the live view can rely on each
box's `DropArea` for hover feedback and use `hitWorkspace` as the authoritative drop
resolver so gesture and tests agree.

**2. `Overview.qml` — the view.** Wires Quickshell singletons to the logic and renders.
- Builds `input` from `Hyprland.workspaces`, `.monitor`, `lastIpcObject`, `monitor.reserved`.
- Builds `address → wl Toplevel` map from `ToplevelManager.toplevels`.
- Calls `logic.layout(input)` on open and on refresh; renders boxes + tiles.
- Owns interaction (keyboard, click, drag) and dispatch. Keeps v1's open/close/refresh,
  focused-screen targeting, number/arrow/Enter selection, Esc/scrim close.

**3. `WindowTile` (inline component or `WindowTile.qml`).** One window.
- `ScreencopyView { captureSource: (root.opened && handle) ? handle : null; live: true }`.
- App-icon overlay (`Quickshell.iconPath(cls.toLowerCase(), true)`), small in a corner;
  centered/enlarged when the tile is very small (end-4's `compactMode`).
- Rounded corners via `layer.effect: OpacityMask` over a rounded mask (end-4's approach).
- Fallback: when `!handle || !hasContent`, render v1's icon box (icon or first-letter).
- `MouseArea` with `drag.target: tile`, `z` raised while dragging; click / middle-click.

## Data flow

```
open()
  → Hyprland.refreshMonitors() / refreshToplevels()
  → build input {monitors, workspaces, windows}  (from Hyprland singletons + lastIpcObject)
  → build handleByAddress  (from ToplevelManager.toplevels[].HyprlandToplevel.address)
  → logic.layout(input) → {boxes, tiles, canvasSize}
  → render; each tile looks up handleByAddress[tile.address] for its ScreencopyView
refresh (Timer, while open)
  → rebuild input + layout (geometry can be stale right after events)
```

## Interaction model

| Action | Effect |
| --- | --- |
| **Drag tile → drop on another workspace box** | `hl.dsp.window.move({ workspace = N, follow = false, window = "address:ADDR" })` (silent). **Overview stays open.** Tile snaps to recomputed spot after a staleness timer; drop on same/none → snap back. |
| **Left-click tile** | `hl.dsp.focus({ window = "address:ADDR" })` + close overview. |
| **Middle-click tile** | `hl.dsp.window.close({ window = "address:ADDR" })`. |
| **Click empty workspace box** | `hl.dsp.focus({ workspace = N })` + close (v1). |
| **Number / arrows / Enter** | Jump / move highlight / select (v1, unchanged). |
| **Esc / scrim click** | Close (v1, unchanged). |

Drag detail: on press set `Drag.active`, hotspot to cursor, record source workspace; on
release read the drop target (via each box's `DropArea` `onEntered`/`onExited`, or
`logic.hitWorkspace`), dispatch if the target differs from the source, else snap back.

## Step 0 — screencopy spike (gates the build)

A throwaway `qs -p spike/shell.qml` (kept out of the plugin) that renders a `ScreencopyView`
of **one background, unfocused, occluded** window and confirms live pixels update on our
Quickshell 0.3.1 / Hyprland 0.56.2.

- **Green** (real pixels) → build live tiles as designed.
- **Black / no content for background windows** → fall back to **capture-on-open snapshot**
  (`live:false` + `captureFrame()`), or, if that also fails, **icon+title tiles**. Either way
  **drag-and-drop still ships** — it does not depend on capture.

The spike is deleted before v2 lands; its result is recorded in the implementation plan.

## Testing

**Tier 1 — pure-logic unit tests (CI, offscreen, no compositor).** Confirmed available:
`qmltestrunner`, the `QtTest` QML module, and the `offscreen` QPA plugin are all installed.
Tests load `logic.mjs` (no Quickshell imports) and assert on `layout()` / `hitWorkspace()`:
- Single monitor: N workspaces → N boxes in one row; a window at monitor origin maps to the
  box's top-left inset; a full-screen window fills the letterboxed area.
- Two monitors: two rows, focused monitor first; a window on monitor 2 maps into row 2.
- Reserved-bar subtraction shifts/scales tiles off the bar region.
- `hitWorkspace` returns the right workspace for points inside each box and `null` in gaps.
- Edge cases: empty workspace, `id < 0` skipped, window partly off-monitor clamped sanely.

Runs via `QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/` in GitHub Actions on push.

**Tier 2 — headless-Hyprland integration (local target, e.g. `just test-integration`).**
Hyprland ships the headless backend; `foot` (test client) and `wtype` are installed. The
test: start Hyprland headless in a nested session, spawn two `foot` clients on different
workspaces, dispatch the **drop's effect** — `hl.dsp.window.move({ workspace = N, follow =
false, window = "address:ADDR" })` — then assert `hyprctl clients -j` shows the window on
workspace N and that the **active** workspace did **not** change (proves `follow = false`).
This validates the exact dispatch syntax + address targeting on real Hyprland. It does not
drive the mouse gesture; it covers everything downstream of "released over workspace N."

**Not covered by tests (honest boundary):** whether a live preview shows real pixels of a
background window is GPU/screencopy-dependent and not reliably assertable in headless CI —
that stays the step-0 spike plus the runtime `hasContent` fallback. Full pointer-drag pixel
e2e (Tier 3) is out of scope (needs `ydotool`, flaky, low marginal value).

## Risks & gotchas (from end-4 + v1)

- **Occluded-window capture** — the step-0 spike gates this; fallbacks defined.
- **Capture perf** — `captureSource: null` when closed so screencopy never runs idle.
- **Scale / reserved** — multiply by `monitor.scale`, subtract `reserved[]`; get it wrong and
  tiles land off-box. Rotated monitors (`transform`) explicitly deferred.
- **Post-move staleness** — `lastIpcObject` lags a move; a short timer repositions the tile
  after dispatch (end-4's `arbitraryRaceConditionDelay` pattern).
- **QML reload** — editing `Overview.qml` needs `omarchy restart shell`, not just rescan.
- **Special/lock workspaces** — skip `id < 0` (v1 already does).

## File / repo changes

```
Overview.qml            (rewritten: canvas + boxes + tiles + DnD)
logic.mjs               (new: pure layout/join/hit-testing)     ← Tier 1 target
WindowTile.qml          (new, optional: per-window preview tile)
tests/tst_layout.qml    (new: QtTest cases over logic.mjs)
justfile                (new: `test`, `test-integration` targets)
.github/workflows/ci.yml(new: Tier 1 on push)
manifest.json           (version → 0.2.0)
DESIGN.md / ROADMAP.md  (updated to reflect v2)
```

`manifest.json` gains no new entry points (still `overlay: Overview.qml`); the logic module
and tile are plain imports, not manifest-declared.

## Sequencing (for the implementation plan)

1. Step-0 screencopy spike → record result, pick capture strategy.
2. Extract `logic.mjs` from v1's `monitorRows()`; add canvas-absolute tiles + `hitWorkspace`.
3. Tier 1 tests + CI green.
4. Rewrite `Overview.qml` to the canvas/boxes/tiles structure (still icon tiles).
5. Add `WindowTile` live previews (per spike outcome) + reserved-bar subtraction.
6. Add drag-and-drop + dispatch + staleness timer.
7. Tier 2 integration target.
8. Update `DESIGN.md` / `ROADMAP.md`, bump version, manual multi-monitor pass.
