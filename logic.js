.pragma library

function _index(arr, key) {
    var m = {}
    for (var i = 0; i < arr.length; i++) m[arr[i][key]] = arr[i]
    return m
}

// Monitors that have workspaces, ordered by the lowest workspace id each one holds, so the
// groups read 1..10 top to bottom. Fixed regardless of focus (and of screen position), so a
// group never jumps when the overview is opened from the other screen; the focused group is
// marked, not moved.
function _orderedMonitorNames(monitors, workspaces) {
    var lowest = {}
    for (var i = 0; i < workspaces.length; i++) {
        var ws = workspaces[i]; if (ws.id < 0) continue
        if (!(ws.monitorName in lowest) || ws.id < lowest[ws.monitorName]) lowest[ws.monitorName] = ws.id
    }
    var names = []
    for (var j = 0; j < monitors.length; j++)
        if (monitors[j].name in lowest) names.push(monitors[j].name)
    names.sort(function (a, b) {
        return lowest[a] !== lowest[b] ? lowest[a] - lowest[b] : (a < b ? -1 : a > b ? 1 : 0)
    })
    return names
}

function _monLogical(mon) {
    var s = (mon && mon.scale) ? mon.scale : 1
    return { w: mon.width / s, h: mon.height / s }
}

function _usableRect(mon) {
    var l = _monLogical(mon)
    var r = mon.reserved || [0, 0, 0, 0]
    return { x: r[0], y: r[1], w: l.w - r[0] - r[2], h: l.h - r[1] - r[3] }
}

function _tileRect(win, mon, box, P, slot) {
    var R = _usableRect(mon)
    var mmW = box.w - 2 * P.cellInset, mmH = box.h - 2 * P.cellInset   // was P.cellW/P.cellH
    var k = Math.min(mmW / R.w, mmH / R.h)
    var offX = P.cellInset + (mmW - R.w * k) / 2
    var offY = P.cellInset + (mmH - R.h * k) / 2
    var wx, wy, sw, sh
    if (slot) {                                   // caller-decided rect (recovered slot etc.)
        wx = slot.x; wy = slot.y; sw = slot.w; sh = slot.h
    } else {
        // Callers place flagged fullscreen windows via `slot`; the geometry heuristic remains
        // for unflagged windows that happen to span the output.
        var l = _monLogical(mon)
        var isFull = Math.abs(win.ax - mon.x) <= 1 && Math.abs(win.ay - mon.y) <= 1 &&
             Math.abs(win.sw - l.w) <= 1 && Math.abs(win.sh - l.h) <= 1
        if (isFull)
            return { x: box.x + offX, y: box.y + offY, w: R.w * k, h: R.h * k }
        wx = (win.ax - mon.x) - R.x; wy = (win.ay - mon.y) - R.y; sw = win.sw; sh = win.sh
    }
    var cx = Math.max(0, wx), cy = Math.max(0, wy)
    var cR = Math.min(wx + sw, R.w), cB = Math.min(wy + sh, R.h)
    var cw = cR - cx, ch = cB - cy
    if (cw <= 0 || ch <= 0) return null
    var tx = box.x + offX + cx * k, ty = box.y + offY + cy * k
    var tw = Math.max(P.minTileW, cw * k), th = Math.max(P.minTileH, ch * k)
    tx = Math.max(box.x + P.cellInset, Math.min(tx, box.x + box.w - P.cellInset - tw))
    ty = Math.max(box.y + P.cellInset, Math.min(ty, box.y + box.h - P.cellInset - th))
    return { x: tx, y: ty, w: tw, h: th }
}

// Hyprland's `fullscreen` client field is 0 none / 1 maximized / 2 fullscreen; older callers
// passed a boolean, which means fullscreen.
function fullscreenMode(win) {
    var m = win.fullscreen === true ? 2 : (win.fullscreen | 0)
    return Math.max(0, Math.min(2, m))
}

function _uniqSorted(a) {
    a = a.slice().sort(function (p, q) { return p - q })
    var out = []
    for (var i = 0; i < a.length; i++) if (!out.length || a[i] - out[out.length - 1] > 0.5) out.push(a[i])
    return out
}

// Where a fullscreen window sits in the tiled layout, recovered from what the OTHER tiled
// windows leave uncovered: dwindle slots partition the usable rect, and fullscreen hides the
// others without moving them, so the hole is the slot the window returns to. `R` is the usable
// rect and `others` rects in the same coordinates (floating/fullscreen windows excluded by the
// caller). Grid R on every edge; seed on the uncovered cell with the largest MINIMUM side (a gap
// strip only wins that if a gap is as thick as the slot's thinnest cell, which no sane
// configuration reaches, so no gap configuration is needed); grow while whole neighbouring
// columns/rows are uncovered (absorbs adjacent gap padding, never crosses a neighbour); trim the
// outer band thinner than P.slotGapTolerance on each side (cumulative, so thin projected-edge
// cells just inside the slot are not peeled one after another; at most tol px of a slot edge can
// be lost). Null when nothing usable is uncovered.
function recoverSlot(R, others, P) {
    var tol = P.slotGapTolerance || 24
    var xs = [R.x, R.x + R.w], ys = [R.y, R.y + R.h], rects = []
    for (var i = 0; i < others.length; i++) {
        var o = others[i]
        var x0 = Math.max(R.x, o.x), y0 = Math.max(R.y, o.y)
        var x1 = Math.min(R.x + R.w, o.x + o.w), y1 = Math.min(R.y + R.h, o.y + o.h)
        if (x1 <= x0 || y1 <= y0) continue
        rects.push({ x0: x0, y0: y0, x1: x1, y1: y1 })
        xs.push(x0, x1); ys.push(y0, y1)
    }
    xs = _uniqSorted(xs); ys = _uniqSorted(ys)
    var nx = xs.length - 1, ny = ys.length - 1
    var cov = []                                   // cov[ci][cj]: cell centre inside some rect
    var ci, cj
    for (ci = 0; ci < nx; ci++) {
        cov.push([])
        for (cj = 0; cj < ny; cj++) {
            var cx = (xs[ci] + xs[ci + 1]) / 2, cy = (ys[cj] + ys[cj + 1]) / 2, hit = false
            for (var k = 0; k < rects.length && !hit; k++)
                hit = cx > rects[k].x0 && cx < rects[k].x1 && cy > rects[k].y0 && cy < rects[k].y1
            cov[ci].push(hit)
        }
    }
    var si = -1, sj = -1, best = 0
    for (ci = 0; ci < nx; ci++) for (cj = 0; cj < ny; cj++) {
        if (cov[ci][cj]) continue
        var m = Math.min(xs[ci + 1] - xs[ci], ys[cj + 1] - ys[cj])
        if (m > best) { best = m; si = ci; sj = cj }
    }
    if (si < 0) return null
    function colFree(c, ja, jb) { for (var j = ja; j <= jb; j++) if (cov[c][j]) return false; return true }
    function rowFree(r, ia, ib) { for (var i2 = ia; i2 <= ib; i2++) if (cov[i2][r]) return false; return true }
    var i0 = si, i1 = si, j0 = sj, j1 = sj, grew = true
    while (grew) {
        grew = false
        if (i0 > 0 && colFree(i0 - 1, j0, j1)) { i0--; grew = true }
        if (i1 < nx - 1 && colFree(i1 + 1, j0, j1)) { i1++; grew = true }
        if (j0 > 0 && rowFree(j0 - 1, i0, i1)) { j0--; grew = true }
        if (j1 < ny - 1 && rowFree(j1 + 1, i0, i1)) { j1++; grew = true }
    }
    var tx0 = xs[i0];     while (i0 < i1 && xs[i0 + 1] - tx0 < tol) i0++
    var tx1 = xs[i1 + 1]; while (i1 > i0 && tx1 - xs[i1] < tol) i1--
    var ty0 = ys[j0];     while (j0 < j1 && ys[j0 + 1] - ty0 < tol) j0++
    var ty1 = ys[j1 + 1]; while (j1 > j0 && ty1 - ys[j1] < tol) j1--
    var slot = { x: xs[i0], y: ys[j0], w: xs[i1 + 1] - xs[i0], h: ys[j1 + 1] - ys[j0] }
    return Math.min(slot.w, slot.h) <= tol ? null : slot
}

// Pad `workspaces` so ids 1..count all appear, so the 1–0 keys always have a target even when
// Hyprland has not created a workspace (a persistent rule whose monitor is absent, or no rule
// at all). A synthesized workspace goes on the focused monitor, which is where Hyprland puts
// it when jumped to. `count` <= 0 disables padding. Returns a new array; input untouched.
function padWorkspaces(workspaces, count, focusedMonitorName) {
    var out = workspaces.slice()
    if (!(count > 0) || !focusedMonitorName) return out
    var seen = {}
    for (var i = 0; i < workspaces.length; i++) seen[workspaces[i].id] = true
    for (var id = 1; id <= count; id++)
        if (!seen[id]) out.push({ id: id, monitorName: focusedMonitorName, focused: false, occupied: false })
    return out
}

function layout(input) {
    var P = input.params
    var monByName = _index(input.monitors, "name")
    var order = _orderedMonitorNames(input.monitors, input.workspaces)

    // With more than one monitor group each group gets a chip band (headerH) and an inset
    // (groupInset) so a backdrop can be drawn around it inside the canvas; a single group
    // gets neither, keeping the one-monitor picture flush.
    var multi = order.length > 1
    var headerH = multi ? P.headerH : 0
    var inset = multi ? (P.groupInset || 0) : 0

    // adaptive cell size — maxCols is a CAP, not a floor
    var gap = P.cellSpacing
    // safe default when availW is missing/invalid: maxCols cells at minCellW with the
    // (maxCols-1) gaps between them included, so cols resolves to maxCols and cw clamps
    // to exactly minCellW — finite, valid geometry instead of NaN.
    var availW = (typeof input.availW === "number" && input.availW > 0)
        ? input.availW - 2 * inset : (P.maxCols * P.minCellW + (P.maxCols - 1) * gap)
    var cols = Math.max(1, Math.min(P.maxCols,
        Math.floor((availW + gap) / (P.minCellW + gap))))
    var cw = Math.max(P.minCellW, Math.min(P.maxCellW,
        Math.floor((availW - (cols - 1) * gap) / cols)))
    // Cell height follows each group's own monitor (see the group loop), so the picture is
    // identical whichever screen has focus; `cell.h` reports the focused monitor's for reference.
    function cellHeightFor(mon) {
        var aspect = mon ? _monLogical(mon).w / _monLogical(mon).h : (16 / 10)
        return Math.round(cw / aspect)
    }
    var ch = cellHeightFor(monByName[input.focusedMonitorName])

    var wsByMon = {}
    for (var i = 0; i < input.workspaces.length; i++) {
        var ws = input.workspaces[i]; if (ws.id < 0) continue
        ;(wsByMon[ws.monitorName] = wsByMon[ws.monitorName] || []).push(ws)
    }
    for (var mn in wsByMon) wsByMon[mn].sort(function (a, b) { return a.id - b.id })

    // Groups carry their full bounds (x, y, w, h) — the inset, chip band and rows — so the
    // view can draw a backdrop behind the focused monitor's group.
    var boxes = [], boxByWs = {}, groups = [], y = 0, canvasW = 0
    for (var r = 0; r < order.length; r++) {
        var name = order[r], wss = wsByMon[name] || []
        if (!wss.length) continue
        var focusedGroup = name === input.focusedMonitorName
        var gch = cellHeightFor(monByName[name])
        var group = { monitorName: name, x: 0, y: y, w: 0, h: 0, inset: inset, headerH: headerH,
                      focused: focusedGroup }
        groups.push(group)
        y += inset + headerH
        var groupW = 0
        for (var s = 0; s < wss.length; s += cols) {
            var chunk = wss.slice(s, s + cols)
            for (var c = 0; c < chunk.length; c++) {
                var box = { workspaceId: chunk[c].id, monitorName: name, monFocused: focusedGroup,
                            x: inset + c * (cw + gap), y: y, w: cw, h: gch,
                            focused: !!chunk[c].focused, occupied: !!chunk[c].occupied }
                boxes.push(box); boxByWs[box.workspaceId] = box
            }
            var rowW = chunk.length * cw + (chunk.length - 1) * gap
            if (rowW > groupW) groupW = rowW
            y += gch
            if (s + cols < wss.length) y += P.rowSpacing        // between sub-rows of one group
        }
        y += inset
        group.w = groupW + 2 * inset; group.h = y - group.y
        if (group.w > canvasW) canvasW = group.w
        if (r < order.length - 1) y += P.rowSpacing             // between monitor groups
    }

    // Tiled windows that are not fullscreen or maximized, per workspace, in usable-rect-local
    // coords: what a fullscreen window's slot is recovered from (see recoverSlot).
    var tiledByWs = {}
    for (var pi = 0; pi < input.windows.length; pi++) {
        var pw = input.windows[pi]
        if (pw.floating || fullscreenMode(pw)) continue
        var pbox = boxByWs[pw.workspaceId], pmon = pbox ? monByName[pbox.monitorName] : null
        if (!pmon) continue
        var pR = _usableRect(pmon)
        ;(tiledByWs[pw.workspaceId] = tiledByWs[pw.workspaceId] || []).push(
            { x: (pw.ax - pmon.x) - pR.x, y: (pw.ay - pmon.y) - pR.y, w: pw.sw, h: pw.sh })
    }
    var tiles = []
    for (var wi = 0; wi < input.windows.length; wi++) {
        var win = input.windows[wi], wbox = boxByWs[win.workspaceId]; if (!wbox) continue
        var wmon = monByName[wbox.monitorName]; if (!wmon) continue
        var mode = fullscreenMode(win), layer = win.floating ? 2 : 1, slot = null
        if (mode) {
            var UR = _usableRect(wmon), whole = { x: 0, y: 0, w: UR.w, h: UR.h }
            if (win.floating) {
                slot = { x: UR.w * 0.2, y: UR.h * 0.2, w: UR.w * 0.6, h: UR.h * 0.6 }   // no slot exists
            } else {
                var others = tiledByWs[win.workspaceId] || []
                slot = others.length ? recoverSlot(whole, others, P) : whole
                if (!slot) { slot = whole; layer = 0 }                              // ambiguous → backdrop
            }
        }
        var t = _tileRect(win, wmon, wbox, P, slot)
        if (t) {
            t.address = win.address; t.workspaceId = win.workspaceId
            t.layer = layer; t.fullscreen = mode
            tiles.push(t)
        }
    }
    return { canvasSize: { w: canvasW, h: y }, boxes: boxes, tiles: tiles,
             groups: groups, cell: { w: cw, h: ch, cols: cols } }
}

// Reverse of _tileRect's placement: map a dragged tile's canvas top-left back to the window's
// real global logical top-left, so a floating window can be repositioned to where it was
// dropped inside its own workspace cell. Tiled placement re-tiles at a cursor point instead
// (see tiledInsertLua).
function dropToWindowPos(tileX, tileY, box, mon, P, win) {
    var R = _usableRect(mon)
    var mmW = box.w - 2 * P.cellInset, mmH = box.h - 2 * P.cellInset
    var k = Math.min(mmW / R.w, mmH / R.h)
    var offX = P.cellInset + (mmW - R.w * k) / 2
    var offY = P.cellInset + (mmH - R.h * k) / 2
    var rx = (tileX - box.x - offX) / k
    var ry = (tileY - box.y - offY) / k
    // Include the window's extent so a drop near the edge stays fully visible.
    // Without an extent retain the original point-clamping API for callers.
    var l = _monLogical(mon)
    var minX = mon.x + (win ? R.x : 0), minY = mon.y + (win ? R.y : 0)
    var maxX = win ? Math.max(minX, mon.x + R.x + R.w - win.sw) : mon.x + l.w
    var maxY = win ? Math.max(minY, mon.y + R.y + R.h - win.sh) : mon.y + l.h
    var x = Math.round(Math.max(minX, Math.min(mon.x + R.x + rx, maxX)))
    var y = Math.round(Math.max(minY, Math.min(mon.y + R.y + ry, maxY)))
    // The typed dispatcher reserves -1 for "preserve this axis".
    return { x: x === -1 ? -2 : x, y: y === -1 ? -2 : y }
}

// ---- tiled drop: mirror Hyprland's native drag-and-drop placement ----
//
// A native tiled drop is a re-tile at the cursor: dwindle inserts the window as a new split of
// the node under (or closest to) the cursor, choosing the side by dwindle's smart-split rule —
// the slope of (cursor - node centre) against the node's aspect ratio picks left/right for
// shallow angles and top/bottom for steep ones (DwindleAlgorithm::addTarget, 0.56).

// Side of `rect` a point lands on under that rule: "left" | "right" | "top" | "bottom".
// Division by zero follows IEEE like the C++ (±Infinity → vertical; NaN at the exact centre →
// "top"), so the preview agrees with what the compositor will do.
function dropSide(rect, px, py) {
    var dx = px - (rect.x + rect.w / 2), dy = py - (rect.y + rect.h / 2)
    if (Math.abs(dy / dx) < rect.h / rect.w) return dx > 0 ? "right" : "left"
    return dy > 0 ? "bottom" : "top"
}

// Squared distance from a point to a rect (0 inside) — used to pick the closest tiled tile
// when a drop lands in a gap, matching dwindle's getClosestNode fallback.
function rectDistanceSq(rect, px, py) {
    var dx = Math.max(rect.x - px, 0, px - (rect.x + rect.w))
    var dy = Math.max(rect.y - py, 0, py - (rect.y + rect.h))
    return dx * dx + dy * dy
}

// Where a tiled drop centred at (cx, cy) inside a workspace box would insert, shared by the
// drag preview and the release so they can never disagree. `candidates` are the canvas rects
// ({x, y, w, h, address}) of the tiled windows that can anchor the insert, in stacking order
// (later wins a tie); `own` is the dragged tile's own rect when the drop is inside its own
// workspace (`sameWorkspace`), or null. Returns { anchor, side } — anchor "" when the target
// workspace has nothing tiled and the window simply fills it — or null when nothing should
// happen: a drop back onto the window's own slot, or a lone tiled window dropped inside its
// own workspace.
function tiledDropPlan(candidates, sameWorkspace, own, cx, cy) {
    if (own && cx >= own.x && cx <= own.x + own.w && cy >= own.y && cy <= own.y + own.h) return null
    var best = null, bestD = Infinity
    for (var i = candidates.length - 1; i >= 0; i--) {
        var d = rectDistanceSq(candidates[i], cx, cy)
        if (d < bestD) { bestD = d; best = candidates[i] }
    }
    if (!best) return sameWorkspace ? null : { anchor: "", side: "" }
    return { anchor: best.address, side: dropSide(best, cx, cy) }
}

// Lua statement defining `run(d)`: dispatch `d` and raise when the compositor reports failure.
// hl.dispatch never raises (Hyprland 0.56.2, LuaBindingsToplevel.cpp hlDispatch): a failed
// dispatcher — even one that hit a Lua error internally — comes back as { ok = false,
// error = "..." }. Raising inside our pcall turns that into the failure path: the sequence
// stops, the guarded cleanup runs, and reportLua names the failed step.
function dispatchGuardLua() {
    return 'local function run(d) local r = hl.dispatch(d) if r and r.ok == false then error(tostring(r.error), 0) end return r end'
}

// Lua statements that report a failure captured as `ok, err` (from pcall) for the operation
// `what`: to the compositor log (Hyprland rebinds `print` to its log with a [Lua] prefix) and
// as an on-screen notification (guarded: hl.notification is missing on older Hyprland). Errors
// inside our own pcall are otherwise invisible — the compositor only logs uncaught ones.
// Returns newline-separated statements; the outermost chunk builder must flatten to one line.
function reportLua(what) {
    return (
        'if not ok then\n' +
        '  local msg = "omyview: ' + what + ' failed: " .. tostring(err)\n' +
        '  print(msg)\n' +
        '  pcall(function() hl.notification.create({ text = msg, duration = 4000, icon = "error" }) end)\n' +
        'end'
    )
}

// One atomic Lua chunk (Hyprland Lua-config mode evaluates `dispatch` payloads as
// `hl.dispatch(<payload>)`, and accepts a function) that replays a native tiled drop:
//   strip the target workspace's fullscreen window (and the dragged window's own fullscreen,
//   if any) so every window is measured in its tiled slot → float the window (detaches it from
//   the tree) → move it silently to the target workspace if needed → warp the cursor onto the
//   anchor's `side` edge → un-float (re-tiles at the cursor) → re-apply the fullscreen modes
//   stripped above → restore focus (only if the dispatcher moved it) and the cursor.
// Detaching the window re-lays out the target workspace, so the cursor point is computed from
// the anchor's geometry AFTER the float, not from the overview's pre-drop layout: the edge
// midpoint of the requested side (inset so the hit test resolves to the anchor), which under
// dwindle's smart-split slope rule always picks that side. `placement` is { anchor, side, x, y }:
// anchor is the window address to split (or "" when the workspace has nothing tiled) and x/y
// the global fallback point used when there is no anchor to measure.
// While it runs, smart_split is forced on so the side follows the cursor regardless of the
// user's force_split, and use_active_for_splits is turned off on the focused monitor's active
// workspace so the anchor is the window under the cursor rather than the focused window.
// Hidden workspaces keep use_active on: there dwindle already falls back to the closest node
// by geometry. Everything runs inside the compositor before the next frame, so nothing flashes.
// The risky steps run in a pcall; the un-float, both fullscreen re-applies and the config
// restore are separate guarded steps that re-read state, so a throw never leaves the window
// floating, and the error is reported (log + notification). Layouts other than dwindle get a
// plain silent move: the cursor-based insert is dwindle behaviour.
function tiledInsertLua(addr, targetWs, placement) {
    var ws = String(parseInt(targetWs, 10))
    var gx = Math.round(placement.x), gy = Math.round(placement.y)
    var side = { left: 1, right: 1, top: 1, bottom: 1 }[placement.side] ? placement.side : ""
    var anchorSel = placement.anchor ? '"address:' + placement.anchor + '"' : 'nil'
    // Built readable, then flattened to one line: the IPC request is a single line.
    return (
        'function()\n' +
        '  local sel = "address:' + addr + '"\n' +
        '  local w = hl.get_window(sel)\n' +
        '  if not w or w.floating then return end\n' +
        '  local anchorSel = ' + anchorSel + '\n' +
        '  local prevW = hl.get_active_window()\n' +
        '  local cur = hl.get_cursor_pos()\n' +
        '  ' + dispatchGuardLua() + '\n' +
        '  local same = w.workspace ~= nil and w.workspace.id == ' + ws + '\n' +
        '  local layout = hl.get_config("general.layout")\n' +
        '  if layout ~= nil and layout ~= "dwindle" then\n' +
        '    local ok, err = pcall(function()\n' +
        '      if not same then run(hl.dsp.window.move({ workspace = "' + ws + '", follow = false, window = sel })) end\n' +
        '    end)\n' +
        '    ' + reportLua('tiled insert') + '\n' +
        '    ' + restoreFocusLua('prevW', 'cur') + '\n' +
        '    return\n' +
        '  end\n' +
        '  local smart = hl.get_config("dwindle.smart_split")\n' +
        '  local useActive = hl.get_config("dwindle.use_active_for_splits")\n' +
        '  local aws = hl.get_active_workspace()\n' +
        '  local onActive = aws ~= nil and aws.id == ' + ws + '\n' +
        // Fullscreen bookkeeping. The target workspace's fullscreen window is stripped so every
        // window there (the anchor included) is measured in its tiled slot, and re-applied
        // afterwards; the dragged window's own mode is kept only for a same-workspace re-tile.
        '  local tws = hl.get_workspace("' + ws + '")\n' +
        '  local fsWin = tws and tws.fullscreen_window or nil\n' +
        '  local fa = fsWin and tostring(fsWin.address or "") or ""\n' +
        '  if fa ~= "" and fa:sub(1, 2) ~= "0x" then fa = "0x" .. fa end\n' +
        '  local fsSel = fa ~= "" and ("address:" .. fa) or nil\n' +
        '  local fsMode = fsWin and tws.fullscreen_mode or 0\n' +
        '  local ownMode = same and w.fullscreen or 0\n' +
        '  hl.config({ dwindle = { smart_split = true, use_active_for_splits = not onActive } })\n' +
        '  local ok, err = pcall(function()\n' +
        '    if fsSel then ' + fullscreenBodyLua('fsSel', '0') + ' end\n' +
        '    ' + fullscreenBodyLua('sel', '0') + '\n' +
        '    run(hl.dsp.window.float({ window = sel, action = "toggle" }))\n' +
        '    if not same then\n' +
        '      run(hl.dsp.window.move({ workspace = "' + ws + '", follow = false, window = sel }))\n' +
        '    end\n' +
        '    local x, y = ' + gx + ', ' + gy + '\n' +
        '    local a = anchorSel and hl.get_window(anchorSel) or nil\n' +
        '    if a and a.at and a.size then\n' +
        '      local inset = 2\n' +
        '      x, y = a.at.x + a.size.x / 2, a.at.y + a.size.y / 2\n' +
        '      if "' + side + '" == "left" then x = a.at.x + inset\n' +
        '      elseif "' + side + '" == "right" then x = a.at.x + a.size.x - 1 - inset\n' +
        '      elseif "' + side + '" == "top" then y = a.at.y + inset\n' +
        '      elseif "' + side + '" == "bottom" then y = a.at.y + a.size.y - 1 - inset end\n' +
        '    end\n' +
        '    run(hl.dsp.cursor.move({ x = math.floor(x + 0.5), y = math.floor(y + 0.5) }))\n' +
        '  end)\n' +
        // Cleanup. On success the un-float IS the re-tile (at the cursor). Each step re-reads
        // state and is guarded on its own, so a failure above — or in an earlier cleanup step —
        // never leaves the window floating, the workspace un-fullscreened, or the config changed.
        // The window was tiled on entry, so any floating state here is ours to undo. A failing
        // cleanup step folds into ok/err so it is reported too (the first error wins).
        '  local function step(f) local g, e = pcall(f) if not g then ok, err = false, err or e end end\n' +
        '  step(function() local fw = hl.get_window(sel); if fw and fw.floating then run(hl.dsp.window.float({ window = sel, action = "toggle" })) end end)\n' +
        '  step(function() if fsSel and fsSel ~= sel then ' + fullscreenBodyLua('fsSel', 'fsMode') + ' end end)\n' +
        '  step(function() if ownMode ~= 0 then ' + fullscreenBodyLua('sel', 'ownMode') + ' end end)\n' +
        '  hl.config({ dwindle = { smart_split = smart, use_active_for_splits = useActive } })\n' +
        '  ' + reportLua('tiled insert') + '\n' +
        '  ' + restoreFocusLua('prevW', 'cur') + '\n' +
        'end'
    ).replace(/\n\s*/g, ' ')
}

// ---- fullscreen ----
//
// Lua statements that leave the window selected by the Lua expression `sel` (e.g. '"address:0x1"'
// or a local name) in fullscreen mode `modeExpr` (a Lua expression: 0 off, 1 maximized,
// 2 fullscreen). Re-reads the window and toggles only when its mode differs, so the statements
// are idempotent and a stale request is harmless. Hyprland's toggle turns fullscreen OFF when
// asked for the mode the window already has and SWITCHES modes otherwise, so when turning off the
// name is taken from the window's current mode.
// Returns newline-separated statements; the outermost chunk builder must flatten to one line.
function fullscreenBodyLua(sel, modeExpr) {
    return (
        'do local fw, fm = hl.get_window(' + sel + '), ' + modeExpr + '\n' +
        '  if fw and fm and fw.fullscreen ~= fm then\n' +
        '    local name = (fm == 1 or (fm == 0 and fw.fullscreen == 1)) and "maximized" or "fullscreen"\n' +
        '    run(hl.dsp.window.fullscreen({ window = ' + sel + ', mode = name, action = "toggle" }))\n' +
        '  end\n' +
        'end'
    )
}

// Lua statements that re-focus the window `prevExpr` (an HL.Window or nil, read before the
// change) when the active window is no longer it, then move the cursor back to `curExpr`
// (an HL.Vec2 or nil). The probe (tests/integration/probe-fullscreen.sh) showed the fullscreen
// dispatcher can drop focus to nil, and focusing warps the cursor, so every chunk that touches
// fullscreen ends with this. Addresses from Lua may lack the 0x prefix hyprctl uses.
// Returns newline-separated statements; the outermost chunk builder must flatten to one line.
function restoreFocusLua(prevExpr, curExpr) {
    return (
        'do local nowW = hl.get_active_window()\n' +
        '  if ' + prevExpr + ' and (not nowW or nowW.address ~= ' + prevExpr + '.address) then\n' +
        '    local a = tostring(' + prevExpr + '.address)\n' +
        '    if a:sub(1, 2) ~= "0x" then a = "0x" .. a end\n' +
        '    hl.dispatch(hl.dsp.focus({ window = "address:" .. a }))\n' +
        '  end\n' +
        '  if ' + curExpr + ' then hl.dispatch(hl.dsp.cursor.move({ x = ' + curExpr + '.x, y = ' + curExpr + '.y })) end\n' +
        'end'
    )
}

// One atomic chunk that turns fullscreen off for `addr`. Focus is left unchanged (re-focused
// only if the dispatcher moved it) and the cursor is restored. Used by the tile badge. The
// toggle runs inside pcall so restoreFocusLua still runs (and
// focus/cursor still land back where they were) even if the dispatcher throws — parity with
// tiledInsertLua's pcall-wrapped re-tile step.
function unfullscreenLua(addr) {
    return (
        'function()\n' +
        '  local prevW, cur = hl.get_active_window(), hl.get_cursor_pos()\n' +
        '  ' + dispatchGuardLua() + '\n' +
        '  local ok, err = pcall(function()\n' +
        fullscreenBodyLua('"address:' + addr + '"', '0') + '\n' +
        '  end)\n' +
        reportLua('un-fullscreen') + '\n' +
        restoreFocusLua('prevW', 'cur') + '\n' +
        'end'
    ).replace(/\n\s*/g, ' ')
}

// One atomic chunk that moves the floating window `addr` to workspace `targetWs` (skipped when
// it is already there) and then to the exact global position `pos` — in that order, because a
// workspace transfer relocates a floating window (especially across monitors), so positioning
// must come after it. Both happen inside the compositor before the next frame, so nothing in
// the overlay has to survive to finish the move: an unloaded overlay loses only its optimistic
// tile, never the operation. Tiled windows return early (they take the tiled-insert chunk).
// The position payload keeps the exact-coordinate string form the old two-phase move used.
function floatingMoveLua(addr, targetWs, pos) {
    var ws = String(parseInt(targetWs, 10))
    var x = Math.round(pos.x), y = Math.round(pos.y)
    return (
        'function()\n' +
        '  local sel = "address:' + addr + '"\n' +
        '  local w = hl.get_window(sel)\n' +
        '  if not w or not w.floating then return end\n' +
        '  local prevW, cur = hl.get_active_window(), hl.get_cursor_pos()\n' +
        '  ' + dispatchGuardLua() + '\n' +
        '  local same = w.workspace ~= nil and w.workspace.id == ' + ws + '\n' +
        '  local ok, err = pcall(function()\n' +
        '    if not same then run(hl.dsp.window.move({ workspace = "' + ws + '", follow = false, window = sel })) end\n' +
        '    run(hl.dsp.window.move({ x = "' + x + '", y = "' + y + '", window = sel }))\n' +
        '  end)\n' +
        '  ' + reportLua('floating move') + '\n' +
        '  ' + restoreFocusLua('prevW', 'cur') + '\n' +
        'end'
    ).replace(/\n\s*/g, ' ')
}

function _center(b) { return { x: b.x + b.w / 2, y: b.y + b.h / 2 } }

// Spatial arrow-key navigation over the wrapped grid. dir: "left"|"right"|"up"|"down".
// Left/right move within the same row (vertical overlap required); up/down pick the nearest
// box above/below, weighting vertical distance and preferring the closest column. Returns the
// new index, or the current index when there is no box in that direction.
function navigate(boxes, currentIndex, dir) {
    if (currentIndex < 0 || currentIndex >= boxes.length) return currentIndex
    var c = _center(boxes[currentIndex]), rowH = boxes[currentIndex].h
    var best = -1, bestCost = Infinity
    for (var i = 0; i < boxes.length; i++) {
        if (i === currentIndex) continue
        var p = _center(boxes[i]), dx = p.x - c.x, dy = p.y - c.y, cost
        if (dir === "right") { if (dx <= 0 || Math.abs(dy) > rowH / 2) continue; cost = dx + Math.abs(dy) * 4 }
        else if (dir === "left") { if (dx >= 0 || Math.abs(dy) > rowH / 2) continue; cost = -dx + Math.abs(dy) * 4 }
        else if (dir === "down") { if (dy <= 0) continue; cost = dy + Math.abs(dx) * 0.5 }
        else if (dir === "up") { if (dy >= 0) continue; cost = -dy + Math.abs(dx) * 0.5 }
        else continue
        if (cost < bestCost) { bestCost = cost; best = i }
    }
    return best >= 0 ? best : currentIndex
}

function hitWorkspace(boxes, px, py) {
    for (var i = 0; i < boxes.length; i++) {
        var b = boxes[i]
        if (px >= b.x && px <= b.x + b.w && py >= b.y && py <= b.y + b.h)
            return b.workspaceId
    }
    return null
}

// Index of the box showing workspace `id`, or -1.
function indexOfWorkspace(boxes, id) {
    for (var i = 0; i < boxes.length; i++) if (boxes[i].workspaceId === id) return i
    return -1
}

function diffByAddress(prevAddresses, nextTiles) {
    var prev = {}
    for (var i = 0; i < prevAddresses.length; i++) prev[prevAddresses[i]] = true
    var next = {}, adds = [], updates = []
    for (var j = 0; j < nextTiles.length; j++) {
        var t = nextTiles[j]
        next[t.address] = true
        if (prev[t.address]) updates.push(t); else adds.push(t)
    }
    var removes = []
    for (var a in prev) if (!next[a]) removes.push(a)
    return { adds: adds, updates: updates, removes: removes }
}

// Pixels per tick, ramping smoothly up to 900 px/s within a 48px edge band.
function edgeScrollDelta(pointer, viewport, offset, content, elapsedMs) {
    var limit = Math.max(0, content - viewport)
    if (limit === 0 || viewport <= 0) return 0
    var band = Math.min(48, viewport / 2), velocity = 0
    if (pointer < band) velocity = -Math.min(1, (band - pointer) / band)
    else if (pointer > viewport - band) velocity = Math.min(1, (pointer - viewport + band) / band)
    return Math.max(0, Math.min(limit, offset + velocity * 900 * elapsedMs / 1000)) - offset
}

// ---- motion policy and user config ----

// "auto" follows Hyprland's animations:enabled; "full" / "off" override it. Unknown values
// are "auto", so a typo in omyview.json never freezes the picker.
function motionPolicy(configured, hyprAnimations) {
    if (configured === "full" || configured === "off") return configured
    return hyprAnimations ? "full" : "off"
}

// Parse `hyprctl -j getoption animations:enabled`. Hyprland 0.56 reports {"bool": true};
// older builds reported {"int": 1}. Anything unreadable counts as enabled: a failed probe
// must not lose motion.
function hyprAnimationsEnabled(json) {
    var o = null
    try { o = JSON.parse(String(json || "")) } catch (e) { return true }
    if (!o || typeof o !== "object") return true
    if (typeof o["bool"] === "boolean") return o["bool"]
    if (typeof o["int"] === "number") return o["int"] !== 0
    return true
}

// ~/.config/omarchy/omyview.json → a fully-defaulted settings object. Every key has a default;
// a missing file, a parse error, a wrong type or an unknown key never changes behaviour.
function parseConfig(raw) {
    var o = {}
    try { o = JSON.parse(String(raw || "")) || {} } catch (e) { o = {} }
    if (typeof o !== "object") o = {}
    return {
        scrim: (typeof o.scrim === "boolean") ? o.scrim : true,
        hint: (typeof o.hint === "boolean") ? o.hint : true,
        workspaces: (typeof o.workspaces === "number" && isFinite(o.workspaces))
            ? Math.max(0, Math.floor(o.workspaces)) : 10,
        motion: (o.motion === "full" || o.motion === "off") ? o.motion : "auto"
    }
}
