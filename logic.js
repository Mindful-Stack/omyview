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

    var tiles = []   // filled in Task 3/4
    return { canvasSize: { w: canvasW, h: canvasH }, boxes: boxes, tiles: tiles,
             _boxByWs: boxByWs, _monByName: monByName }
}
