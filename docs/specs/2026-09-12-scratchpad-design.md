# Omyview — scratchpad row (design)

Date: 2026-09-12 · Target: Omarchy Quattro, Hyprland 0.56.2 (Lua config mode), Quickshell 0.3.1 ·
builds on find (`main` at `4382847`).
Status: **approved design, pre-implementation.** Branch `scratchpad`.

## Goal

Show Omarchy's scratchpad (`special:scratchpad`, which holds e.g. Bitwarden and Spotify) in the
overview on demand, as its own row below the workspaces, hidden by default. It is a real box:
selectable, a drag target, searchable while shown, and later lockable.

## Scope

**In:** a per-summon toggle (Ctrl+S), a trailing layout group for the scratchpad, Enter/click
that brings the scratchpad up, drops onto it, find over its windows while shown, the sentinel
audit that makes a negative workspace id legal, tests.

**Out:** other special workspaces (the unnamed `special` only ever holds transient share
popups), persisting the shown state across summons, a config key for the default, a number
key for the scratchpad, tiled insertion into the scratchpad.

## Decisions (brainstorm 2026-09-12)

- **Hidden on every open.** Ctrl+S shows the row for this summon only. Bare letters type into
  find, so the toggle is a chord; it works with or without a query.
- **Enter / box click = bring the scratchpad up and close.** Same effect as SUPER+S when the
  scratchpad is hidden; guarded so it never *hides* an already-visible scratchpad.
- **Drops land as a plain silent move.** Scratchpad windows are floating; there is no tiled
  anchor to split, so the tiled-insert plan is never used for this target.
- **Find matches scratchpad windows only while the row is shown.** Shown windows are in the
  layout input like any other; hidden ones are not.
- **Only `special:scratchpad`.** One row, one workspace.
- **An empty scratchpad still shows its row** when toggled: it is still a place to drop
  windows.
- **First-class box (approach A).** The scratchpad flows through the existing box/tile pipeline
  so thumbnails, drag, find, the selection frame and the future lock treat it uniformly. The
  cost is an audit of the "negative id means none" checks.

## Behaviour

| Key / action                    | effect                                                                 |
|---------------------------------|------------------------------------------------------------------------|
| Ctrl+S                          | toggle `scratchpadShown` (any query state); rebuild                    |
| digits                          | never target the scratchpad                                            |
| arrows                          | reach it spatially (it is the bottom row); with a query, only if a window in it matches |
| Enter on the scratchpad box     | dispatch the guarded show chunk (below), close                         |
| click on the empty box          | same as Enter                                                          |
| click on a tile in the row      | focus that window (existing path; Hyprland raises the scratchpad)      |
| drop a window on the box        | `hl.dsp.window.move({ workspace = "special:scratchpad", follow = false })`, plus the floating position chunk for floating windows |
| drag a tile out of the row      | existing paths (floating move / tiled insert) to the numeric target    |
| Esc / SUPER+P                   | unchanged                                                              |

`scratchpadShown` is reset to false in `open()`. A rebuild while shown keeps the row; the row
never appears on its own after a compositor event.

**The show chunk** (`Logic.scratchpadShowLua()`), a single guarded line like every other chunk:
```lua
local ws = hl.get_active_special_workspace()
if not (ws and ws.name == "special:scratchpad") then run(hl.dsp.workspace.toggle_special("scratchpad")) end
```
wrapped in the standard `dispatchGuardLua` / `reportLua` frame. The lua-check mock gains
`get_active_special_workspace` and `workspace.toggle_special`; the behaviour suite covers both
branches (hidden → toggles; already active → no dispatch).

## Layout and data

- `buildInput()` includes a special workspace only when `scratchpadShown` and its name is
  `special:scratchpad`; the workspace record gains `special: "scratchpad"` (normal workspaces:
  `""`). If Hyprland reports no such workspace, a synthetic one is added on the focused monitor
  with no windows (the empty row).
- `Logic.layout` appends **one trailing group** after the monitor groups, separated by
  `rowSpacing`: a header band (`headerH`, always, even in single-monitor mode) whose chip reads
  `SCRATCHPAD`, and one box of the normal cell width whose height follows the scratchpad's own
  monitor. The group is never `focused` (no backdrop). Boxes carry `special` so the view can
  label them; the group carries `special` so the chip repeater can render it whether or not
  there is more than one monitor group.
- Labels: the badge and the empty-well numeral show `S` for the scratchpad (`wsLabel`).
- Tiles: unchanged — scratchpad windows are floating with real geometry relative to their
  monitor, so `_tileRect` places them like any floating window.

## Sentinel audit

The scratchpad id is -98. Today several places use `id >= 0` / `id < 0` to mean "has a
workspace". After this change:

- `-1` stays the one "none" sentinel (`selectedIndex`, `dropTargetWs`, `preQuerySelectedId`).
- `Logic.hasWs(id)` (`typeof id === "number" && isFinite(id) && id !== -1`) replaces every
  `>= 0` test on a workspace id: rebuild's `keepId`, `restorePreQuerySelection`, the drop
  release (`targetWs`), and Enter's `selectedId` check.
- Places that must **exclude specials** keep an explicit `ws.special` / `id < 0` test:
  `padWorkspaces`, `_orderedMonitorNames`, the monitor-group loop in `layout`, the digit keys.
- Dispatch targets: `Logic.wsSelector(box)` returns `"special:scratchpad"` for the scratchpad
  box and the numeric id otherwise; `floatingMoveLua` and the plain move use it. `jump()` is
  never called with the scratchpad id (Enter on it goes to the show chunk).

## Visuals

- Row placement: below the last monitor group, `rowSpacing` above it, the box left-aligned.
- Chip: same style as the monitor chips, text `SCRATCHPAD`, never accented.
- Badge / numeral: `S`.
- Drop cues, selection frame, find ring and dim: unchanged, they key on the box.
- Hint row: `ctrl+s · scratchpad` before `esc · close`.

## Edge cases

- Ctrl+S with the overlay showing a query: the row appears, its windows join the match list on
  the same rebuild; hiding it drops them and the successor rule picks the next match.
- A drag in flight when Ctrl+S is pressed: the row toggles; the drag continues; if the dragged
  window's own row disappears (dragging a scratchpad tile, then hiding the row) the drag is
  cancelled via the existing `Component.onDestruction` → `endDrag()` path.
- The scratchpad on another monitor (docked): the row height follows that monitor; the show
  chunk toggles on the focused monitor, which is how SUPER+S behaves too.
- Nested/CI fixture: the compositor stub seeds a `-98` workspace with `name:
  "special:scratchpad"` and floating clients; `buildInput()` reads `ws.name`.

## Tests

- **Tier 1, `tests/tst_layout.qml`**: trailing group appended below the groups with a header
  band in single-monitor mode; box height from the scratchpad's monitor; no group when the input
  has no special; `hasWs` accepts -98 and rejects -1/undefined; `wsSelector` returns the name for
  the scratchpad box.
- **Tier 1, Lua behaviour suite**: `scratchpadShowLua` toggles when no special is active or a
  different one is; does nothing when `special:scratchpad` is active; dispatch failure reported.
- **Tier 1, offscreen UI (`tests/ui/scratchpad.qml`)**: Ctrl+S shows a box with id -98 and a
  tile for each seeded scratchpad window, Ctrl+S again hides both; reopen starts hidden; Enter on
  the box dispatches the show chunk and closes; a digit never selects it; Down from the last
  workspace row lands on it; with a query, its windows match only while shown; a drop on it
  dispatches a move naming `special:scratchpad`; an empty scratchpad still yields a box; the
  hint row carries `ctrl+s`.
- **Tier 2**: nothing new (the show chunk is exercised by the Lua mock; a live check confirms
  the scratchpad rises on Enter).
