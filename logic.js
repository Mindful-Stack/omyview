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
    var cols = Math.max(1, Math.min(P.maxCols,
        Math.floor((input.availW + gap) / (P.minCellW + gap))))
    var cw = Math.max(P.minCellW, Math.min(P.maxCellW,
        Math.floor((input.availW - (cols - 1) * gap) / cols)))
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
