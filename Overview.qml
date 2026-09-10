// Omyview — v2. Canvas + boxes + live tiles. See DESIGN.md / docs/specs, docs/plans.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "logic.js" as Logic

Item {
    id: root
    property bool opened: false
    property var targetScreen: null

    property var boxes: []
    property var handleByAddress: ({})
    property int selectedIndex: -1
    readonly property int selectedId:
        (selectedIndex >= 0 && selectedIndex < boxes.length) ? boxes[selectedIndex].workspaceId : -1

    // theme
    property color background: Color.menu.background
    property color foreground: Color.menu.text
    property color borderColor: Color.menu.border
    property color scrim: Color.menu.scrim
    property color selBackground: Color.menu.selectedBackground
    property color selText: Color.menu.selectedText
    readonly property int cornerRadius: Style.cornerRadius

    readonly property var params: ({
        maxCols: 5, minCellW: 140, maxCellW: 380, cellInset: 6, cellSpacing: 8,
        rowSpacing: 12, headerH: 22, minTileW: 8, minTileH: 6
    })

    property var groups: []
    // Card interior logical width available to the canvas: panel.width (logical, not
    // screen.width*dpr) minus the card's own padding and a little breathing room.
    readonly property real availCanvasW: panel.width > 0 ? panel.width - 2 * card.pad - 16 : 1600
    onAvailCanvasWChanged: if (opened) rebuild()

    function focusedScreen() {
        var mon = Hyprland.focusedMonitor, screens = Quickshell.screens || []
        for (var i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name) return screens[i]
        return screens.length ? screens[0] : null
    }

    // Build handleByAddress from the wl toplevels (address <- HyprlandToplevel.address).
    function buildHandles() {
        var map = {}, tls = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
        for (var i = 0; i < tls.length; i++) {
            var t = tls[i], h = t.HyprlandToplevel
            if (h && h.address) map["0x" + h.address] = t
        }
        root.handleByAddress = map
    }

    function buildInput() {
        var mons = [], hmons = Hyprland.monitors ? Hyprland.monitors.values : []
        for (var i = 0; i < hmons.length; i++) {
            var m = hmons[i]
            mons.push({ name: m.name, x: m.x, y: m.y, width: m.width, height: m.height,
                        scale: m.scale, reserved: m.lastIpcObject ? m.lastIpcObject.reserved : [0,0,0,0],
                        transform: m.lastIpcObject ? m.lastIpcObject.transform : 0 })
        }
        var wss = [], hws = Hyprland.workspaces ? Hyprland.workspaces.values : []
        var focusedWsId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
        var wins = []
        for (var j = 0; j < hws.length; j++) {
            var ws = hws[j]; if (!ws || ws.id < 0) continue
            var mon = ws.monitor
            wss.push({ id: ws.id, monitorName: mon ? mon.name : "?",
                       focused: ws.id === focusedWsId,
                       occupied: ws.toplevels && ws.toplevels.values.length > 0 })
            var tls = ws.toplevels ? ws.toplevels.values : []
            for (var t = 0; t < tls.length; t++) {
                var o = tls[t] ? tls[t].lastIpcObject : null
                if (!o || !o.at || !o.size || !o.address) continue
                wins.push({ address: o.address, cls: o["class"] || "", title: o.title || "",
                            ax: o.at[0], ay: o.at[1], sw: o.size[0], sh: o.size[1],
                            workspaceId: ws.id, floating: !!o.floating, fullscreen: !!o.fullscreen })
            }
        }
        return { monitors: mons, workspaces: wss, windows: wins,
                 focusedMonitorName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "",
                 availW: root.availCanvasW, params: root.params }
    }

    // Reconcile the tiles ListModel in place (drag-safe: never touch the dragged address).
    property string draggingAddress: ""
    property var pendingMoves: ({})
    property var dragTile: null
    property int dropTargetWs: -1
    property string dropTargetAddress: ""
    property real dragViewportX: 0
    property real dragViewportY: 0
    Timer {
        id: reconcileTimer
        interval: 120; repeat: true
        onTriggered: root._reconcileStep()
    }
    function _movePosition(addr, pos) {
        Hyprland.dispatch('hl.dsp.window.move({ x = "' + pos.x + '", y = "' + pos.y +
                          '", window = "address:' + addr + '" })')
    }
    function tiledTargetAt(addr, workspaceId, x, y) {
        for (var i = tilesModel.count - 1; i >= 0; i--) {
            var tile = tilesModel.get(i), win = _windowByAddress[tile.address]
            if (tile.address === addr || tile.wsid !== workspaceId || !win ||
                win.floating || win.fullscreen || pendingMoves[tile.address]) continue
            if (x >= tile.wx && x <= tile.wx + tile.ww &&
                y >= tile.wy && y <= tile.wy + tile.wh) return tile.address
        }
        return ""
    }
    function previewWindow(addr, win) {
        var box = boxForWs(win.workspaceId), mon = box ? _monByName[box.monitorName] : null
        if (!box || !mon) return
        var rect = Logic._tileRect(win, mon, box, params)
        if (!rect) return
        for (var i = 0; i < tilesModel.count; i++) {
            if (tilesModel.get(i).address === addr) {
                tilesModel.set(i, {wx:rect.x, wy:rect.y, ww:rect.w, wh:rect.h, wsid:win.workspaceId})
                return
            }
        }
    }
    function startTiledSwap(addr, targetAddr, win, target) {
        if (!win || !target || win.floating || target.floating || win.fullscreen ||
            target.fullscreen || win.workspaceId !== target.workspaceId || addr === targetAddr)
            return false
        var deadline = Date.now() + 1800
        pendingMoves[addr] = {workspaceId:win.workspaceId, pos:{x:target.ax,y:target.ay},
                              size:{w:target.sw,h:target.sh}, positioning:true, deadline:deadline}
        pendingMoves[targetAddr] = {workspaceId:win.workspaceId, pos:{x:win.ax,y:win.ay},
                                    size:{w:win.sw,h:win.sh}, positioning:true, deadline:deadline}
        previewWindow(addr, target)
        previewWindow(targetAddr, win)
        // An addressed swap works without focusing either window, even on hidden
        // workspaces. Hyprland warps to the source; restore the pointer in the same call.
        Hyprland.dispatch('function() local p = hl.get_cursor_pos(); ' +
                          'hl.dispatch(hl.dsp.window.swap({ window = "address:' + addr +
                          '", target = "address:' + targetAddr + '" })); ' +
                          'if p then hl.dispatch(hl.dsp.cursor.move({ x = p.x, y = p.y })) end end')
        return true
    }
    function submitDrop(addr, targetWs, dropX, dropY) {
        var box = boxForWs(targetWs), mon = box ? _monByName[box.monitorName] : null
        var win = _windowByAddress[addr]
        if (!box || !mon || !win) return
        var sourceWs = win.workspaceId // model.wsid may still be optimistic
        var pos = win.floating ? Logic.dropToWindowPos(dropX, dropY, box, mon, params, win) : null
        var targetAddr = ""
        if (!win.floating && !win.fullscreen) {
            for (var ti = 0; ti < tilesModel.count; ti++) {
                var tile = tilesModel.get(ti)
                if (tile.address !== addr) continue
                targetAddr = tiledTargetAt(addr, targetWs, dropX + tile.ww / 2, dropY + tile.wh / 2)
                break
            }
        }
        if (targetWs === sourceWs && !pos) {
            if (targetAddr && startTiledSwap(addr, targetAddr, win, _windowByAddress[targetAddr])) {
                scheduleRebuild()
                reconcileTimer.restart()
            }
            return
        }
        var pending = { workspaceId: targetWs, pos: pos, swapTarget: targetAddr,
                        positioning: targetWs === sourceWs,
                        deadline: Date.now() + 1800 }
        pendingMoves[addr] = pending
        // Publish the destination before restoring x/y bindings. Keep it until the
        // compositor acknowledges this move; refreshToplevels is asynchronous.
        for (var i = 0; i < tilesModel.count; i++) {
            if (tilesModel.get(i).address !== addr) continue
            var rect = pos ? Logic._tileRect({ax:pos.x, ay:pos.y, sw:win.sw, sh:win.sh},
                                            mon, box, params) : null
            tilesModel.set(i, { wx: rect ? rect.x : dropX, wy: rect ? rect.y : dropY,
                                ww: rect ? rect.w : tilesModel.get(i).ww,
                                wh: rect ? rect.h : tilesModel.get(i).wh, wsid: targetWs })
            break
        }
        if (targetWs !== sourceWs) {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + targetWs +
                              ', follow = false, window = "address:' + addr + '" })')
        } else _movePosition(addr, pos)
        scheduleRebuild()
        reconcileTimer.restart()
    }
    function _reconcileStep() {
        if (typeof Hyprland.refreshToplevels === "function") Hyprland.refreshToplevels()
        if (typeof Hyprland.refreshWorkspaces === "function") Hyprland.refreshWorkspaces()
        root.rebuild()
    }
    function reconcileMoves(windows) {
        var byAddress = {}
        for (var i = 0; i < windows.length; i++) byAddress[windows[i].address] = windows[i]
        for (var addr in pendingMoves) {
            var pending = pendingMoves[addr], win = byAddress[addr]
            if (Date.now() >= pending.deadline) {
                delete pendingMoves[addr] // rejected move: return to authoritative geometry
                continue
            }
            if (!win || win.workspaceId !== pending.workspaceId) continue
            if (pending.swapTarget) {
                var target = byAddress[pending.swapTarget]
                if (target && target.workspaceId === pending.workspaceId &&
                    startTiledSwap(addr, pending.swapTarget, win, target)) continue
                // The destination closed or ceased to be tiled: keep the completed transfer.
                delete pendingMoves[addr]
                continue
            }
            if (pending.pos && !pending.positioning) {
                // Wait for workspace transfer before positioning: transfer itself can
                // relocate a floating window, especially across different monitors.
                pending.positioning = true
                _movePosition(addr, pending.pos)
                continue
            }
            if (!pending.pos || (Math.abs(win.ax - pending.pos.x) <= 1 &&
                                 Math.abs(win.ay - pending.pos.y) <= 1 &&
                                 (!pending.size || (Math.abs(win.sw - pending.size.w) <= 1 &&
                                                    Math.abs(win.sh - pending.size.h) <= 1))))
                delete pendingMoves[addr]
        }
        if (!Object.keys(pendingMoves).length) reconcileTimer.stop()
    }
    function updateDropTarget() {
        if (!dragTile) { dropTargetWs = -1; dropTargetAddress = ""; return }
        var ws = Logic.hitWorkspace(boxes, dragTile.x + dragTile.width / 2,
                                   dragTile.y + dragTile.height / 2)
        dropTargetWs = ws === null ? -1 : ws
        var win = _windowByAddress[draggingAddress]
        dropTargetAddress = win && !win.floating && !win.fullscreen && ws !== null
            ? tiledTargetAt(draggingAddress, ws, dragTile.x + dragTile.width / 2,
                            dragTile.y + dragTile.height / 2) : ""
    }
    function endDrag() {
        var tile = dragTile
        dragTile = null
        draggingAddress = ""
        dropTargetWs = -1
        dropTargetAddress = ""
        if (tile) tile.restoreDrag()
    }
    Timer {
        id: edgeScroll
        interval: 16; repeat: true
        running: root.dragTile !== null && root.dragTile.dragMoved
        onTriggered: {
            var dx = Logic.edgeScrollDelta(root.dragViewportX, flick.width, flick.contentX,
                                           flick.contentWidth, interval)
            var dy = Logic.edgeScrollDelta(root.dragViewportY, flick.height, flick.contentY,
                                           flick.contentHeight, interval)
            flick.contentX += dx
            flick.contentY += dy
        }
    }
    function applyTiles(tiles) {
        var prev = []
        for (var i = 0; i < tilesModel.count; i++) prev.push(tilesModel.get(i).address)
        var d = Logic.diffByAddress(prev, tiles)
        function indexOf(addr) {
            for (var i = 0; i < tilesModel.count; i++)
                if (tilesModel.get(i).address === addr) return i
            return -1
        }
        for (var a = 0; a < d.adds.length; a++) {
            var t = d.adds[a]
            tilesModel.append({ address: t.address, wx: t.x, wy: t.y, ww: t.w, wh: t.h,
                                cls: clsFor(t.address), title: titleFor(t.address),
                                wsid: t.workspaceId, floating: floatingFor(t.address) })
        }
        for (var u = 0; u < d.updates.length; u++) {
            var tu = d.updates[u]
            if (root.draggingAddress === tu.address || pendingMoves[tu.address]) continue   // grab is authoritative
            var iu = indexOf(tu.address)
            if (iu >= 0) tilesModel.set(iu, { wx: tu.x, wy: tu.y, ww: tu.w, wh: tu.h,
                                              title: titleFor(tu.address), cls: clsFor(tu.address), wsid: tu.workspaceId,
                                              floating: floatingFor(tu.address) })
        }
        for (var rmi = 0; rmi < d.removes.length; rmi++) {
            if (root.draggingAddress === d.removes[rmi] || pendingMoves[d.removes[rmi]]) continue // cancel handled elsewhere
            var ir = indexOf(d.removes[rmi]); if (ir >= 0) tilesModel.remove(ir)
        }
    }

    property var _clsByAddress: ({})
    property var _titleByAddress: ({})
    property var _floatingByAddress: ({})
    property var _monByName: ({})
    property var _windowByAddress: ({})
    function clsFor(addr) { return root._clsByAddress[addr] || "" }
    function titleFor(addr) { return root._titleByAddress[addr] || "" }
    function floatingFor(addr) { return !!root._floatingByAddress[addr] }
    function boxForWs(id) {
        for (var i = 0; i < boxes.length; i++) if (boxes[i].workspaceId === id) return boxes[i]
        return null
    }

    function rebuild() {
        buildHandles()
        var input = buildInput()
        var cmap = {}, tmap = {}, fmap = {}, wmap = {}
        for (var i = 0; i < input.windows.length; i++) {
            wmap[input.windows[i].address] = input.windows[i]
            cmap[input.windows[i].address] = input.windows[i].cls
            tmap[input.windows[i].address] = input.windows[i].title
            fmap[input.windows[i].address] = input.windows[i].floating
        }
        root._windowByAddress = wmap
        if (draggingAddress && !wmap[draggingAddress]) endDrag()
        reconcileMoves(input.windows)
        root._clsByAddress = cmap
        root._titleByAddress = tmap
        root._floatingByAddress = fmap
        var monmap = {}
        for (var mi = 0; mi < input.monitors.length; mi++) monmap[input.monitors[mi].name] = input.monitors[mi]
        root._monByName = monmap
        var res = Logic.layout(input)
        root.boxes = res.boxes
        root.groups = res.groups
        canvas.implicitWidth = res.canvasSize.w
        canvas.implicitHeight = res.canvasSize.h
        applyTiles(res.tiles)
        if (root.selectedIndex < 0) {
            var fi = -1
            for (var b = 0; b < res.boxes.length; b++) if (res.boxes[b].focused) { fi = b; break }
            root.selectedIndex = fi >= 0 ? fi : (res.boxes.length ? 0 : -1)
        } else {
            root.selectedIndex = res.boxes.length
                ? Math.min(Math.max(root.selectedIndex, 0), res.boxes.length - 1) : -1
        }
    }

    function selectByNav(dir) {
        if (!boxes.length) return
        var i = selectedIndex < 0 ? 0 : selectedIndex
        selectedIndex = Logic.navigate(boxes, i, dir)
        ensureSelectedVisible()
    }

    // Nudge the Flickable minimally so the selected box is fully inside the viewport.
    function ensureSelectedVisible() {
        if (selectedIndex < 0 || selectedIndex >= boxes.length) return
        var b = boxes[selectedIndex]
        if (b.y < flick.contentY) flick.contentY = b.y
        else if (b.y + b.h > flick.contentY + flick.height) flick.contentY = b.y + b.h - flick.height
        if (b.x < flick.contentX) flick.contentX = b.x
        else if (b.x + b.w > flick.contentX + flick.width) flick.contentX = b.x + b.w - flick.width
    }
    function jump(id) {
        if (id === undefined || id === null) return
        Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })'); root.close()
    }
    function open() {
        if (typeof Hyprland.refreshMonitors === "function") Hyprland.refreshMonitors()
        targetScreen = focusedScreen(); selectedIndex = -1; opened = true
        rebuild()          // instant paint from current data
        ensureSelectedVisible()
        scheduleRebuild()  // then settle as fresh toplevel geometry lands
        Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    }
    function close() {
        endDrag()
        // A dispatched workspace move still needs its positioning/ack phase when closed.
        settleTimer.stop()
        opened = false
    }
    function toggle() { if (opened) close(); else open() }

    // Ask Hyprland for fresh client data, then rebuild a few times over ~300ms so a window
    // opened while the overview is visible appears once its async geometry arrives — a single
    // rebuild here would read stale/empty `lastIpcObject` geometry. Bursts of events coalesce
    // into one settle window (the tick counter resets on each schedule).
    function scheduleRebuild() {
        if (typeof Hyprland.refreshToplevels === "function") Hyprland.refreshToplevels()
        if (typeof Hyprland.refreshWorkspaces === "function") Hyprland.refreshWorkspaces()
        settleTimer.ticks = 0
        settleTimer.restart()
    }
    Timer {
        id: settleTimer
        interval: 60; repeat: true
        property int ticks: 0
        onTriggered: {
            if (root.opened) root.rebuild()
            if (++ticks >= 5) stop()
        }
    }
    ListModel { id: tilesModel }

    // Window/workspace changes while open: refresh + settle (never an immediate stale rebuild).
    Connections {
        target: Hyprland
        function onRawEvent() { if (root.opened) root.scheduleRebuild() }
    }

    PanelWindow {
        id: panel
        visible: root.opened
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "omyview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        Rectangle { anchors.fill: parent; color: root.scrim }
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Rectangle {
            id: card
            anchors.centerIn: parent
            radius: root.cornerRadius
            color: root.background
            border.width: 1
            border.color: root.borderColor
            readonly property int pad: 16
            // Cap the card to the screen so the Flickable viewport can be smaller than the
            // content (`availCanvasW` already keeps canvas width <= this, minus the degenerate
            // narrow-screen case, which is expected to 2-D scroll per the spec).
            readonly property real maxCardW: panel.width > 0 ? panel.width - 16 : 1616
            readonly property real maxCardH: panel.height > 0 ? panel.height - 64 : 900
            implicitWidth: Math.min(canvas.implicitWidth + pad * 2, maxCardW)
            implicitHeight: Math.min(canvas.implicitHeight + pad * 2 + hint.height + 8, maxCardH)
            MouseArea { anchors.fill: parent; onClicked: {} }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true }
                    else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) { root.jump(e.key - Qt.Key_0); e.accepted = true }
                    else if (e.key === Qt.Key_0) { root.jump(10); e.accepted = true }
                    else if (e.key === Qt.Key_Left) { root.selectByNav("left"); e.accepted = true }
                    else if (e.key === Qt.Key_Right) { root.selectByNav("right"); e.accepted = true }
                    else if (e.key === Qt.Key_Up) { root.selectByNav("up"); e.accepted = true }
                    else if (e.key === Qt.Key_Down) { root.selectByNav("down"); e.accepted = true }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (root.selectedId >= 0) root.jump(root.selectedId); e.accepted = true
                    }
                }
            }

            Flickable {
                id: flick
                x: card.pad; y: card.pad
                width: card.width - card.pad * 2
                height: card.height - card.pad * 2 - hint.height - 8
                contentWidth: canvas.implicitWidth
                contentHeight: canvas.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                // Edge scrolling drives the viewport while a tile owns the pointer grab.
                interactive: !root.draggingAddress
                property real previousX: 0
                property real previousY: 0
                onContentXChanged: {
                    if (root.dragTile) root.dragTile.x += contentX - previousX
                    previousX = contentX
                    root.updateDropTarget()
                }
                onContentYChanged: {
                    if (root.dragTile) root.dragTile.y += contentY - previousY
                    previousY = contentY
                    root.updateDropTarget()
                }

                // Content shrinking (windows/workspaces closing) must never leave the viewport
                // scrolled past the new end.
                onContentWidthChanged: flick.contentX = Math.max(0, Math.min(flick.contentX, flick.contentWidth - flick.width))
                onContentHeightChanged: flick.contentY = Math.max(0, Math.min(flick.contentY, flick.contentHeight - flick.height))

                Item {
                    id: canvas
                    x: 0; y: 0
                    width: implicitWidth; height: implicitHeight
                    implicitWidth: 100; implicitHeight: 100

                    // boxes layer
                    Repeater {
                        model: root.opened ? root.boxes : []
                        Rectangle {
                            required property var modelData
                            readonly property bool isSel: modelData.workspaceId === root.selectedId
                            readonly property bool isDrop: root.draggingAddress !== "" &&
                                                           modelData.workspaceId === root.dropTargetWs
                            x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                            radius: 6
                            color: modelData.focused ? root.selBackground : "transparent"
                            border.width: (isDrop || isSel) ? 3 : (modelData.focused ? 2 : 1)
                            border.color: isDrop ? root.selText : isSel ? root.foreground
                                                : (modelData.focused ? root.selBackground : root.borderColor)
                            opacity: (isDrop || modelData.occupied || modelData.focused) ? 1.0 : 0.5

                            Text {
                                anchors.centerIn: parent
                                text: modelData.workspaceId === 10 ? "0" : String(modelData.workspaceId)
                                color: modelData.focused ? root.selText : root.foreground
                                opacity: 0.25; font.pixelSize: 22
                            }
                            MouseArea {   // click empty area of a workspace => jump
                                anchors.fill: parent
                                onClicked: root.jump(modelData.workspaceId)
                            }
                        }
                    }

                    // monitor chips layer (siblings, above boxes) — one per group, focused
                    // monitor's chip accented so multiple monitors are always distinguishable.
                    Repeater {
                        model: root.opened ? root.groups : []
                        Rectangle {
                            required property var modelData
                            x: modelData.x; y: modelData.y
                            height: modelData.headerH - 4
                            radius: 4
                            readonly property color accent: root.selBackground
                            color: modelData.focused ? accent : "transparent"
                            border.width: 1
                            border.color: modelData.focused ? accent : root.borderColor
                            implicitWidth: chipText.implicitWidth + 12
                            Text {
                                id: chipText; anchors.centerIn: parent
                                text: modelData.monitorName
                                color: modelData.focused ? root.selText : root.foreground
                                opacity: modelData.focused ? 1.0 : 0.6
                                font.pixelSize: 11
                            }
                        }
                    }

                    // tiles layer (siblings, above boxes)
                    Repeater {
                        model: tilesModel
                        WindowTile {
                            required property var model
                            x: model.wx; y: model.wy; width: model.ww; height: model.wh
                            cls: model.cls
                            title: model.title
                            dragging: root.draggingAddress === model.address
                            handle: root.handleByAddress[model.address] || null
                            capMode: "live"
                            borderColor: root.dropTargetAddress === model.address ? root.selText : root.borderColor
                            dropTarget: root.dropTargetAddress === model.address
                            bg: root.background; fg: root.foreground
                            id: windowTile
                            readonly property bool dragMoved: dragArea.moved
                            function restoreDrag() {
                                dragArea.drag.target = undefined
                                dragArea.moved = false
                                x = Qt.binding(function () { return model.wx })
                                y = Qt.binding(function () { return model.wy })
                            }
                            Component.onDestruction: {
                                if (root.dragTile === windowTile) root.endDrag()
                            }
                            MouseArea {
                                id: dragArea
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                preventStealing: true
                                drag.target: undefined
                                property bool moved: false
                                onPressed: function (m) {
                                    if (m.button !== Qt.LeftButton) return
                                    // A second grab supersedes that address's pending visual state.
                                    delete root.pendingMoves[model.address]
                                    root.draggingAddress = model.address
                                    root.dragTile = windowTile
                                    moved = false
                                    drag.target = windowTile
                                    var p = mapToItem(flick, m.x, m.y)
                                    root.dragViewportX = p.x; root.dragViewportY = p.y
                                    root.updateDropTarget()
                                }
                                onPositionChanged: function (m) {
                                    if (!pressed || root.dragTile !== windowTile) return
                                    if (drag.active) moved = true
                                    var p = mapToItem(flick, m.x, m.y)
                                    root.dragViewportX = p.x; root.dragViewportY = p.y
                                    root.updateDropTarget()
                                }
                                onCanceled: if (root.dragTile === windowTile) root.endDrag()
                                onReleased: function (m) {
                                    if (m.button === Qt.MiddleButton) {
                                        Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + model.address + '" })')
                                        return
                                    }
                                    if (root.dragTile !== windowTile) return
                                    var addr = model.address, wasMoved = moved
                                    // Capture before rebinding. Never dispatch for a drop outside a box.
                                    root.updateDropTarget()
                                    var targetWs = root.dropTargetWs
                                    var dropX = windowTile.x, dropY = windowTile.y
                                    if (wasMoved && targetWs >= 0)
                                        root.submitDrop(addr, targetWs, dropX, dropY)
                                    root.endDrag()
                                    if (!wasMoved) {
                                        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
                                        root.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                id: hint
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                text: "1–0 jump · arrows move · Enter select · drag a window · Esc close"
                color: root.foreground; opacity: 0.5; font.pixelSize: 11
            }
        }
    }
}
