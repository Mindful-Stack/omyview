# Omyview v3 Milestone A — design

Date: 2026-09-09 · Target: Omarchy Quattro, Hyprland 0.56.2, Quickshell 0.3.1 · builds on v2.
Status: **approved design, pre-implementation.** Ideas/priority: `docs/roadmap-v3-ideas.md`.

## Goal

Four improvements to the shipped v2 overview, keeping the shared-canvas / per-monitor-rows
identity and the pure-`logic.js` seam:

1. **Bigger tiles** via consistent-size cells that fit 5 across the screen and **wrap** beyond.
2. **Monitor distinction** — a name chip per monitor group + a theme accent on the focused one.
3. **Hover/select zoom** on window tiles (mouse hover only).
4. **Drag polish + style** — drop-target highlight during drag, rounded thumbnails, soft
   selection glow, centralized easing.

## Scope

**In:** the four features above.
**Out (Milestone B):** semantic "animate from real position" motion, spring settle,
in-workspace rearrange, per-monitor-aspect cells, empty-workspace wallpaper crops, tile-level
keyboard navigation.

## Feature 1 — bigger tiles: fit-5-across + wrap (`logic.js`)

Cells are a **consistent size** sized so 5 fit across the focused screen; a monitor with more
than 5 workspaces wraps into additional **sub-rows of ≤5** — cells never shrink to cram more in.

### Sizing (computed in `layout()`, was fixed `params.cellW/cellH`)
- `maxCols = params.maxCols` (5).
- `cw = clamp((availW − (maxCols−1)·cellSpacing) / maxCols, params.minCellW, params.maxCellW)`
  where `availW` is a new input = the canvas's available logical width (Overview passes
  `panel width − 2·cardPad − safety`).
- `aspect = focusedMonitorLogicalW / focusedMonitorLogicalH` (from the focused monitor;
  fallback 16/10). `ch = round(cw / aspect)` — cells look like little screens; the focused
  monitor's cells have no letterbox, others letterbox their usable rect into the cell as today.
- Clamp values: `minCellW = 140`, `maxCellW = 380` (avoid microscopic cells on a narrow screen,
  or absurd cells on an ultrawide).

### Wrap + placement
- Monitor groups keep focused-first-then-by-x order (v2).
- Within a group, sort workspaces by id and **chunk into sub-rows of `maxCols`** (8 workspaces →
  a sub-row of 5 then a sub-row of 3).
- Each **monitor group** has one header row (its chip, Feature 2) above its first sub-row; its
  sub-rows stack directly under it. Box `x = col·(cw+cellSpacing)`; `y` accumulates down through
  headers, sub-rows (`ch`), and spacings.
- `canvasSize.w` = widest actual sub-row; `canvasSize.h` = total stacked height. Cells carry
  `w:cw, h:ch`.

### `_tileRect` refactor
`_tileRect` currently reads `P.cellW/P.cellH` for the mini-map size. Change it to read
**`box.w`/`box.h`** instead, so tile mapping follows each box's actual (now computed) size. No
other tile math changes — bigger cells give bigger tiles for free. `hitWorkspace` is unchanged
(point-in-box over all boxes still resolves wrapped layouts).

### Overflow
Overview compares `canvasSize.h` to the available height; if it exceeds, the canvas lives in a
**`Flickable`** (vertical scroll) inside the card. Cells never shrink below `minCellW`.

### `logic.js` input/param changes
- `input` gains `availW` (number, logical px).
- `params` gains `maxCols`, `minCellW`, `maxCellW`; drops the fixed `cellW`/`cellH` (now derived);
  keeps `cellInset, cellSpacing, rowSpacing, headerH (was rowLabelH), minTileW, minTileH`.
- **Tier 1 tests** updated: existing box/tile cases re-expressed against computed `cw/ch`; new
  cases for (a) 5-across sizing from `availW` with the clamps, (b) wrap at >5 into sub-rows,
  (c) `canvasSize` with wrapping, (d) `_tileRect` using `box.w/h`.

## Feature 2 — monitor distinction (`Overview.qml`)

- The header row (`headerH`, raised from 16 to ~22) renders a **monitor name chip** per group —
  a small rounded `Rectangle` with the monitor name (e.g. `eDP-1`), anchored at the group's
  top-left.
- **Accent:** the **focused monitor's** group gets the theme accent — the chip filled with the
  accent, plus a thin accent strip along the header. Non-focused groups get a neutral/muted chip
  (border color) and no strip. The chip name disambiguates multiple non-focused monitors.
- Accent token: the active Omarchy theme's accent (reuse `Color.menu.selectedBackground` or the
  nearest accent token; confirm the exact token during implementation). Neutral = `Color.menu.border`.

## Feature 3 — hover/select zoom (`WindowTile.qml`), QML only

- Tiles rest at `scale 0.95`; on **mouse hover** they animate to `1.05` and raise `z` above
  siblings (draws over neighbors, **no reflow** — position/size unchanged), via one
  `Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }`,
  `transformOrigin: Item.Center`.
- On hover, a small **label** fades in at the bottom of the tile showing the **window title**
  (fallback: the app class). Title is view-only data — plumbed `buildInput` (`o.title`) → the
  tiles `ListModel` → a new `WindowTile.title` property. It does **not** go through `logic.js`
  (not layout-relevant), keeping the pure module unchanged for this. (Confirm `lastIpcObject`
  exposes `.title` during implementation.)
- Hover is a separate `HoverHandler` (or `hoverEnabled` flag) that must **not** interfere with
  the existing drag `MouseArea`; the drag's `z=99999` still wins over the hover z-raise.
- Keyboard navigation is unchanged (still workspace boxes). No `logic.js` change → visual test only.

## Feature 4 — drag polish + style

- **Drop-target highlight during drag:** the tile's drag `MouseArea.onPositionChanged` computes
  `Logic.hitWorkspace(boxes, cx, cy)` and sets a `root.dropTargetWs`; the matching workspace box
  renders an accent border/glow while `root.draggingAddress` is set. Cleared on release.
- **Rounded thumbnails:** wrap the `ScreencopyView` in `Quickshell.Widgets.ClippingRectangle`
  (radius + GPU clip, confirmed available in 0.3.1) — replaces the current square `clip: true`.
  Icon fallback stays layered as today.
- **Soft selection glow:** the selected/focused box gets a soft glow/shadow (`QtQuick.Effects`
  `MultiEffect` shadow, or a blurred offset duplicate) + an **animated** border, instead of the
  hard 3px outline. Glow on boxes only (few), not on every tile.
- **Centralized easing:** a small `readonly property var anim` (durations + easing) block in
  `Overview.qml`, applied uniformly to hover, selection, and the drop-highlight `Behavior`s.

## Architecture / components

- **`logic.js`** (pure) — sizing + wrap + placement; the only Tier-1-tested change.
- **`Overview.qml`** — passes `availW`; renders monitor headers/chips/accent; Flickable canvas;
  drop-target highlight; soft selection; easing constants.
- **`WindowTile.qml`** — hover zoom + label; `ClippingRectangle` rounding.
- No new files required. A tiny constants block (accents + easing) lives in `Overview.qml`.

## Testing

- **Tier 1 (CI):** the sizing/wrap/placement logic in `logic.js`, numeric — the only unit-tested
  part (see Feature 1 test list). Existing Tier 1 cases adjusted to computed cell sizes.
- **Visual (live, by the user):** bigger tiles + wrap render correctly; monitor chips + focused
  accent; hover zoom feels right and doesn't reflow; rounded thumbnails; drop-target highlight
  during drag; soft selection; scroll when a monitor has many workspaces.
- **Tier 2:** unaffected.

## Risks / gotchas

- **Flickable vs drag:** dragging a tile inside a scrolling canvas — ensure the drag gesture
  isn't stolen by the Flickable (set `Flickable.interactive` off during a tile drag, or use
  press-delay). Watch-item for implementation.
- **Hover vs drag on the same tile:** keep hover-scale (HoverHandler) and drag (MouseArea)
  independent so hover doesn't fight `drag.target`; verify hover-zoom is suppressed mid-drag.
- **`availW` units:** must be **logical** px (the card's coordinate space), not physical — derive
  from the panel/card width, not raw `screen.width·devicePixelRatio`.
- **ClippingRectangle composition:** confirm the icon-fallback layer and border still compose
  correctly inside the clip.
- **Accent token:** confirm the theme exposes a usable accent distinct from background/border.
- **`headerH` height bump** must be reflected in `canvasSize.h` and box `y` math (it's in logic).

## Sequencing (for the plan)

1. `logic.js` — computed sizing + wrap + `_tileRect` box.w/h + Tier 1 tests (green in CI).
2. `Overview.qml` — pass `availW`; Flickable canvas; render bigger wrapped boxes (verify live).
3. Monitor chips + focused-accent header.
4. `WindowTile` — `ClippingRectangle` rounding; hover zoom + label.
5. Drop-target highlight during drag + soft selection glow + centralized easing.
6. Docs + version bump (0.3.0) + live pass; Tier 2 re-run.
