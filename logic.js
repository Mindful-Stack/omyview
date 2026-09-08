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
    var mmW = P.cellW - 2 * P.cellInset, mmH = P.cellH - 2 * P.cellInset
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
    // keep the (possibly min-clamped) tile inside the cell's mini-map inset
    tx = Math.max(box.x + P.cellInset, Math.min(tx, box.x + P.cellW - P.cellInset - tw))
    ty = Math.max(box.y + P.cellInset, Math.min(ty, box.y + P.cellH - P.cellInset - th))
    return { x: tx, y: ty, w: tw, h: th }
}

function layout(input) {
    var P = input.params
    var monByName = _index(input.monitors, "name")
    var order = _orderedMonitorNames(input.monitors, input.workspaces, input.focusedMonitorName)

    var wsByMon = {}
    for (var i = 0; i < input.workspaces.length; i++) {
        var ws = input.workspaces[i]
        if (ws.id < 0) continue
        ;(wsByMon[ws.monitorName] = wsByMon[ws.monitorName] || []).push(ws)
    }
    for (var mn in wsByMon)
        wsByMon[mn].sort(function (a, b) { return a.id - b.id })

    var boxes = [], boxByWs = {}, rowTop = 0, canvasW = 0
    for (var r = 0; r < order.length; r++) {
        var wss = wsByMon[order[r]] || []
        if (!wss.length) continue
        var cellsY = rowTop + P.rowLabelH
        for (var c = 0; c < wss.length; c++) {
            var box = {
                workspaceId: wss[c].id, monitorName: order[r],
                x: c * (P.cellW + P.cellSpacing), y: cellsY, w: P.cellW, h: P.cellH,
                focused: !!wss[c].focused, occupied: !!wss[c].occupied
            }
            boxes.push(box); boxByWs[box.workspaceId] = box
        }
        var rowW = wss.length * P.cellW + (wss.length - 1) * P.cellSpacing
        if (rowW > canvasW) canvasW = rowW
        rowTop = cellsY + P.cellH + P.rowSpacing
    }
    var canvasH = rowTop > 0 ? rowTop - P.rowSpacing : 0

    var tiles = []
    for (var wi = 0; wi < input.windows.length; wi++) {
        var win = input.windows[wi]
        var wbox = boxByWs[win.workspaceId]
        if (!wbox) continue
        var wmon = monByName[wbox.monitorName]
        if (!wmon) continue
        var t = _tileRect(win, wmon, wbox, P)
        if (t) { t.address = win.address; t.workspaceId = win.workspaceId; tiles.push(t) }
    }
    return { canvasSize: { w: canvasW, h: canvasH }, boxes: boxes, tiles: tiles }
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
