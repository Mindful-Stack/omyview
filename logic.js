.pragma library

function _index(arr, key) {
    var m = {}
    for (var i = 0; i < arr.length; i++) m[arr[i][key]] = arr[i]
    return m
}

function _orderedMonitorNames(monitors, workspaces, focusedName) {
    var present = {}
    for (var i = 0; i < workspaces.length; i++)
        if (workspaces[i].id >= 0) present[workspaces[i].monitorName] = true
    var byName = _index(monitors, "name")
    var names = []
    for (var j = 0; j < monitors.length; j++)
        if (present[monitors[j].name]) names.push(monitors[j].name)
    names.sort(function (a, b) {
        if (a === focusedName && b !== focusedName) return -1
        if (b === focusedName && a !== focusedName) return 1
        return byName[a].x - byName[b].x
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

function _tileRect(win, mon, box, P) {
    var l = _monLogical(mon), R = _usableRect(mon)
    var mmW = box.w - 2 * P.cellInset, mmH = box.h - 2 * P.cellInset   // was P.cellW/P.cellH
    var k = Math.min(mmW / R.w, mmH / R.h)
    var offX = P.cellInset + (mmW - R.w * k) / 2
    var offY = P.cellInset + (mmH - R.h * k) / 2
    var isFull = !!win.fullscreen ||
        (Math.abs(win.ax - mon.x) <= 1 && Math.abs(win.ay - mon.y) <= 1 &&
         Math.abs(win.sw - l.w) <= 1 && Math.abs(win.sh - l.h) <= 1)
    if (isFull)
        return { x: box.x + offX, y: box.y + offY, w: R.w * k, h: R.h * k }
    var wx = (win.ax - mon.x) - R.x, wy = (win.ay - mon.y) - R.y
    var cx = Math.max(0, wx), cy = Math.max(0, wy)
    var cR = Math.min(wx + win.sw, R.w), cB = Math.min(wy + win.sh, R.h)
    var cw = cR - cx, ch = cB - cy
    if (cw <= 0 || ch <= 0) return null
    var tx = box.x + offX + cx * k, ty = box.y + offY + cy * k
    var tw = Math.max(P.minTileW, cw * k), th = Math.max(P.minTileH, ch * k)
    tx = Math.max(box.x + P.cellInset, Math.min(tx, box.x + box.w - P.cellInset - tw))
    ty = Math.max(box.y + P.cellInset, Math.min(ty, box.y + box.h - P.cellInset - th))
    return { x: tx, y: ty, w: tw, h: th }
}

function layout(input) {
    var P = input.params
    var monByName = _index(input.monitors, "name")
    var order = _orderedMonitorNames(input.monitors, input.workspaces, input.focusedMonitorName)

    // adaptive cell size — maxCols is a CAP, not a floor
    var gap = P.cellSpacing
    // safe default when availW is missing/invalid: maxCols cells at minCellW with the
    // (maxCols-1) gaps between them included, so cols resolves to maxCols and cw clamps
    // to exactly minCellW — finite, valid geometry instead of NaN.
    var availW = (typeof input.availW === "number" && input.availW > 0)
        ? input.availW : (P.maxCols * P.minCellW + (P.maxCols - 1) * gap)
    var cols = Math.max(1, Math.min(P.maxCols,
        Math.floor((availW + gap) / (P.minCellW + gap))))
    var cw = Math.max(P.minCellW, Math.min(P.maxCellW,
        Math.floor((availW - (cols - 1) * gap) / cols)))
    var fmon = monByName[input.focusedMonitorName]
    var aspect = fmon ? _monLogical(fmon).w / _monLogical(fmon).h : (16 / 10)
    var ch = Math.round(cw / aspect)

    var wsByMon = {}
    for (var i = 0; i < input.workspaces.length; i++) {
        var ws = input.workspaces[i]; if (ws.id < 0) continue
        ;(wsByMon[ws.monitorName] = wsByMon[ws.monitorName] || []).push(ws)
    }
    for (var mn in wsByMon) wsByMon[mn].sort(function (a, b) { return a.id - b.id })

    var boxes = [], boxByWs = {}, groups = [], y = 0, canvasW = 0
    for (var r = 0; r < order.length; r++) {
        var name = order[r], wss = wsByMon[name] || []
        if (!wss.length) continue
        var focusedGroup = name === input.focusedMonitorName
        groups.push({ monitorName: name, x: 0, y: y, headerH: P.headerH, focused: focusedGroup })
        y += P.headerH
        for (var s = 0; s < wss.length; s += cols) {
            var chunk = wss.slice(s, s + cols)
            for (var c = 0; c < chunk.length; c++) {
                var box = { workspaceId: chunk[c].id, monitorName: name, monFocused: focusedGroup,
                            x: c * (cw + gap), y: y, w: cw, h: ch,
                            focused: !!chunk[c].focused, occupied: !!chunk[c].occupied }
                boxes.push(box); boxByWs[box.workspaceId] = box
            }
            var rowW = chunk.length * cw + (chunk.length - 1) * gap
            if (rowW > canvasW) canvasW = rowW
            y += ch
            if (s + cols < wss.length) y += P.rowSpacing        // between sub-rows of one group
        }
        if (r < order.length - 1) y += P.rowSpacing             // between monitor groups
    }

    var tiles = []
    for (var wi = 0; wi < input.windows.length; wi++) {
        var win = input.windows[wi], wbox = boxByWs[win.workspaceId]; if (!wbox) continue
        var wmon = monByName[wbox.monitorName]; if (!wmon) continue
        var t = _tileRect(win, wmon, wbox, P)
        if (t) { t.address = win.address; t.workspaceId = win.workspaceId; tiles.push(t) }
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

// Real global point for a canvas point inside a workspace cell, pulled strictly inside the
// anchor window's rect (when given) so the compositor's hit test resolves to that window even
// after rounding, gaps, or borders. `anchor` is a buildInput window ({ax, ay, sw, sh}).
function dropAnchorPoint(px, py, box, mon, P, anchor) {
    var p = dropToWindowPos(px, py, box, mon, P)
    if (!anchor) return p
    var inset = 2
    return { x: Math.round(Math.max(anchor.ax + inset, Math.min(p.x, anchor.ax + anchor.sw - 1 - inset))),
             y: Math.round(Math.max(anchor.ay + inset, Math.min(p.y, anchor.ay + anchor.sh - 1 - inset))) }
}

// One atomic Lua chunk (Hyprland Lua-config mode evaluates `dispatch` payloads as
// `hl.dispatch(<payload>)`, and accepts a function) that replays a native tiled drop:
//   float the window (detaches it from the tree) → move it silently to the target workspace if
//   needed → warp the cursor to the drop point → un-float (re-tiles at the cursor) → restore.
// While it runs, smart_split is forced on so the side follows the cursor regardless of the
// user's force_split, and use_active_for_splits is turned off on the focused monitor's active
// workspace so the anchor is the window under the cursor rather than the focused window.
// Hidden workspaces keep use_active on: there dwindle already falls back to the closest node
// by geometry. Everything runs inside the compositor before the next frame, so nothing flashes,
// and config, cursor and focus are restored even if a step throws.
function tiledInsertLua(addr, targetWs, x, y) {
    var ws = String(parseInt(targetWs, 10)), gx = Math.round(x), gy = Math.round(y)
    // Built readable, then flattened to one line: the IPC request is a single line.
    return (
        'function()\n' +
        '  local sel = "address:' + addr + '"\n' +
        '  local w = hl.get_window(sel)\n' +
        '  if not w or w.floating then return end\n' +
        '  local cur = hl.get_cursor_pos()\n' +
        '  local smart = hl.get_config("dwindle.smart_split")\n' +
        '  local useActive = hl.get_config("dwindle.use_active_for_splits")\n' +
        '  local aws = hl.get_active_workspace()\n' +
        '  local onActive = aws ~= nil and aws.id == ' + ws + '\n' +
        '  hl.config({ dwindle = { smart_split = true, use_active_for_splits = not onActive } })\n' +
        '  pcall(function()\n' +
        '    hl.dispatch(hl.dsp.window.float({ window = sel, action = "toggle" }))\n' +
        '    if w.workspace == nil or w.workspace.id ~= ' + ws + ' then\n' +
        '      hl.dispatch(hl.dsp.window.move({ workspace = "' + ws + '", follow = false, window = sel }))\n' +
        '    end\n' +
        '    hl.dispatch(hl.dsp.cursor.move({ x = ' + gx + ', y = ' + gy + ' }))\n' +
        '    hl.dispatch(hl.dsp.window.float({ window = sel, action = "toggle" }))\n' +
        '  end)\n' +
        '  hl.config({ dwindle = { smart_split = smart, use_active_for_splits = useActive } })\n' +
        '  if cur then hl.dispatch(hl.dsp.cursor.move({ x = cur.x, y = cur.y })) end\n' +
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
