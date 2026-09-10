# Omyview — visual restyle (2026-09-10)

Branch `restyle` (worktree), based on `drag-ghost`. Motion/animation work is deferred to a
follow-up spec; this one only changes surfaces, radii, and what marks selection.

## Why

Compared with end-4's overview the picker reads as "boxes in boxes": card border, workspace
border and tile border are three nested 1px lines on one flat tone. end-4 uses tone steps
instead of lines, concentric corner radii, a soft shadow for elevation, and a single accent
frame for selection. The card here was square because it bound to `Style.cornerRadius`, which
mirrors Hyprland `decoration:rounding` (0 on the author's machine).

## Design

- **Card.** Own radius (`boxRadius + pad` = 20), padding 12, no border, soft
  `RectangularShadow` (QtQuick.Effects, Qt ≥ 6.9; no offscreen layer). Colour stays
  `Color.menu.background`.
- **Scrim.** Kept, `Color.menu.scrim`, now switchable via config (see below). Scrim-click
  dismissal works regardless.
- **Workspace wells.** No border. Fill = menu text colour at `Style.normalFillAlpha` (0.04
  default). Focused workspace = `Color.menu.selectedBackground`. Drop target while dragging =
  text colour at `Style.selectedFillAlpha`. Radius 8. Cell gap 6, inset 3, row gap 10.
- **Numeral.** Large DemiBold workspace number behind the windows, ~45 % of cell height,
  10 % opacity.
- **Selection frame.** One 2px `Color.menu.selectedText` (accent) rounded frame drawn above
  the tiles on the keyboard-selected box. Drags never move it (it recedes to 40 % while a
  drag is in progress). Replaces the 1/2/3px border ladder.
- **Drop cue.** No frame. The well under the pointer fills at `Style.selectedFillAlpha`
  (0.18) so it reads even on the focused workspace, and tiled drops additionally preview the
  insertion half on the anchor tile. Keeping selection and drop apart means the selection
  never "flies" to the drop target and back.
- **Window tiles.** Rest at scale 1 (was 0.95, so previews never filled their rect), hover
  1.03. No border except a 12 % hairline so adjacent previews with zero Hyprland gaps do not
  merge, and a 2px accent border when the tile is the tiled-insert anchor. Radius 5
  (box radius minus inset).
- **Monitor chip.** Plain text, no border; accent for the focused monitor. The header row is
  only laid out when more than one monitor has workspaces (`logic.js` decides).
- **Hint.** Unchanged text, 40 % opacity.

## Config

`~/.config/omarchy/omyview.json` (watched, optional):

```json
{ "scrim": true }
```

Missing file or key = default. Loaded by `OmyviewConfig.qml`; the offscreen test fixture stubs
it and `CardShadow.qml` with plain items.

## Out of scope

Easing/animation block, hover tint, glide timing tuning — next spec.
