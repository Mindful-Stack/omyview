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

    // theme — tone steps, not lines (see docs/specs/2026-09-10-restyle-design.md)
    property color background: Color.menu.background
    property color foreground: Color.menu.text
    property color scrim: Color.menu.scrim
    property color selBackground: Color.menu.selectedBackground
    property color selText: Color.menu.selectedText
    function tone(a) { return Qt.rgba(foreground.r, foreground.g, foreground.b, a) }
    readonly property color wellColor: tone(Style.normalFillAlpha)      // occupied workspace well
    readonly property color emptyWellColor: tone(Style.normalFillAlpha / 2)   // one step lower
    // Typography follows the shell: the menu family and the theme's size tokens, so the picker
    // tracks `omarchy display text size` like every other summoned surface.
    readonly property string fontFamily: Style.font.menuFamily
    readonly property int labelSize: Style.font.bodySmall
    readonly property int captionSize: Style.font.caption
    // Well under a drag: the only workspace-level drop cue (tiled drops also preview the
    // insertion half on the anchor tile), so it must read even on the focused workspace.
    readonly property color dropWellColor: tone(Style.selectedFillAlpha)
    readonly property color hairline: tone(0.12)                          // between previews
    readonly property color accent: selText
    readonly property bool darkTheme:
        (0.299 * background.r + 0.587 * background.g + 0.114 * background.b) < 0.5
    // Badge chip: the card colour, nearly opaque, so the number reads over any preview.
    readonly property color badgeColor: Qt.rgba(background.r, background.g, background.b, 0.88)
    function wsLabel(id) { return id === 10 ? "0" : String(id) }   // matches the 1–0 keys
    // The card owns its radius: Style.cornerRadius mirrors Hyprland rounding, which may be 0.
    readonly property int boxRadius: 8
    readonly property int cardRadius: boxRadius + card.pad

    OmyviewConfig { id: config }

    // headerH is the chip band per monitor group; logic.js lays it out only when more than
    // one monitor has workspaces (see Logic.layout), so a single monitor gets no band.
    readonly property var params: ({
        maxCols: 5, minCellW: 140, maxCellW: 380, cellInset: 3, cellSpacing: 4,
        rowSpacing: 8, headerH: 22, minTileW: 8, minTileH: 6, slotGapTolerance: 24
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
                            workspaceId: ws.id, floating: !!o.floating,
                            fullscreen: Logic.fullscreenMode(o),
                            grouped: !!(o.grouped && o.grouped.length) })
            }
        }
        return { monitors: mons, workspaces: wss, windows: wins,
                 focusedMonitorName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "",
                 availW: root.availCanvasW, params: root.params }
    }

    // Reconcile the tiles ListModel in place (drag-safe: never touch the dragged address).
    property string draggingAddress: ""
    property var pendingMoves: ({})
    // addr -> { mode, deadline }: an un-fullscreen was dispatched; the badge stays hidden until
    // fresh data reports that mode, or the deadline passes (rejected: badge returns).
    property var pendingFullscreen: ({})
    property var dragTile: null
    property int dropTargetWs: -1
    property string dropTargetAddress: ""
    property string dropTargetSide: ""   // "left"|"right"|"top"|"bottom" while a tiled drag hovers a tile
    property real dragViewportX: 0
    property real dragViewportY: 0
    Timer {
        id: reconcileTimer
        interval: 120; repeat: true
        onTriggered: root._reconcileStep()
    }
    function setTileRoles(addr, roles) {
        for (var i = 0; i < tilesModel.count; i++)
            if (tilesModel.get(i).address === addr) { tilesModel.set(i, roles); return }
    }
    // Badge click: turn fullscreen off for `addr` silently (no focus, no workspace switch, the
    // overview stays open). Optimistic: the badge hides now and the tile keeps its recovered
    // slot, which is where the window lands anyway.
    function unfullscreen(addr) {
        var win = _windowByAddress[addr]
        if (!win || !win.fullscreen) return
        pendingFullscreen[addr] = { mode: 0, deadline: Date.now() + 1800 }
        setTileRoles(addr, { fsPending: true })
        Hyprland.dispatch(Logic.unfullscreenLua(addr))
        scheduleRebuild()
        reconcileTimer.restart()
    }
    function reconcileFullscreen(windows) {
        var byAddress = {}
        for (var i = 0; i < windows.length; i++) byAddress[windows[i].address] = windows[i]
        for (var addr in pendingFullscreen) {
            var pending = pendingFullscreen[addr], win = byAddress[addr]
            if (win && win.fullscreen !== pending.mode && Date.now() < pending.deadline) continue
            delete pendingFullscreen[addr]
            setTileRoles(addr, { fsPending: false })
        }
    }
    // Tiles that can anchor a tiled insert inside workspace `workspaceId`: the tiled, settled
    // tiles other than the dragged one, in stacking order.
    function tiledAnchorCandidates(addr, workspaceId) {
        var out = []
        for (var i = 0; i < tilesModel.count; i++) {
            var tile = tilesModel.get(i), win = _windowByAddress[tile.address]
            if (tile.address === addr || tile.wsid !== workspaceId || !win ||
                win.floating || tile.layer === 0 || pendingMoves[tile.address]) continue
            out.push({ x: tile.wx, y: tile.wy, w: tile.ww, h: tile.wh, address: tile.address })
        }
        return out
    }
    // Where a tiled drop of `win` centred at (cx, cy) inside `targetWs` would insert, or null
    // when it should do nothing. One eligibility check shared by the drag preview and the
    // release, so what is highlighted is exactly what a release does (see Logic.tiledDropPlan).
    function tiledDropPlan(addr, win, targetWs, cx, cy) {
        var box = boxForWs(targetWs), mon = box ? _monByName[box.monitorName] : null
        if (!box || !mon) return null
        var same = targetWs === win.workspaceId
        var own = same ? tileRectFor(addr) : null       // the model rect: the recovered slot for a fullscreen window
        return Logic.tiledDropPlan(tiledAnchorCandidates(addr, targetWs), same, own, cx, cy)
    }
    function tileRectFor(addr) {
        for (var i = 0; i < tilesModel.count; i++) {
            var t = tilesModel.get(i)
            if (t.address === addr) return { x: t.wx, y: t.wy, w: t.ww, h: t.wh, wsid: t.wsid }
        }
        return null
    }
    // Tiled drop: re-tile the window at the drop point exactly as a native drag would (one
    // atomic Lua dispatch, see Logic.tiledInsertLua). Two windows end up swapped; more end up
    // re-organised around the hovered window. Returns false when nothing should happen: a
    // drop back onto its own slot, or a lone tiled window dropped inside its own workspace.
    function startTiledInsert(addr, win, targetWs, box, mon, cx, cy, dropX, dropY) {
        var plan = tiledDropPlan(addr, win, targetWs, cx, cy)
        if (!plan) return false
        // Only used when there is no anchor window to measure inside the compositor.
        var fallback = Logic.dropToWindowPos(cx, cy, box, mon, params)
        // Optimistic: the tile stays at the drop point until fresh geometry differs from the
        // pre-drop one (a cross-workspace insert differs by workspace at once). A fullscreen
        // window re-tiled in place reports the same fullscreen rect it started with, so the
        // anchor's geometry is recorded too: any change to it is a sufficient signal that the
        // insert happened (an unrelated anchor change acknowledges early too, but that window is
        // bounded by the deadline and the false-positive is harmless).
        var anchorWin = plan.anchor ? _windowByAddress[plan.anchor] : null
        pendingMoves[addr] = { workspaceId: targetWs, pos: null, deadline: Date.now() + 1800,
                               before: { ws: win.workspaceId, ax: win.ax, ay: win.ay, sw: win.sw, sh: win.sh,
                                         anchor: anchorWin ? { address: plan.anchor, ax: anchorWin.ax, ay: anchorWin.ay,
                                                               sw: anchorWin.sw, sh: anchorWin.sh } : null } }
        for (var i = 0; i < tilesModel.count; i++) {
            if (tilesModel.get(i).address !== addr) continue
            tilesModel.set(i, { wx: dropX, wy: dropY, wsid: targetWs })
            break
        }
        Hyprland.dispatch(Logic.tiledInsertLua(addr, targetWs,
            { anchor: plan.anchor, side: plan.side, x: fallback.x, y: fallback.y }))
        return true
    }
    function submitDrop(addr, targetWs, dropX, dropY, px, py) {
        var box = boxForWs(targetWs), mon = box ? _monByName[box.monitorName] : null
        var win = _windowByAddress[addr]
        if (!box || !mon || !win) return
        var sourceWs = win.workspaceId // model.wsid may still be optimistic
        var tile = tileRectFor(addr)
        if (!win.floating && !win.grouped && tile) {
            var cx = px === undefined ? dropX + tile.w / 2 : px
            var cy = py === undefined ? dropY + tile.h / 2 : py
            if (startTiledInsert(addr, win, targetWs, box, mon, cx, cy, dropX, dropY)) {
                scheduleRebuild()
                reconcileTimer.restart()
            }
            return
        }
        var pos = win.floating ? Logic.dropToWindowPos(dropX, dropY, box, mon, params, win) : null
        if (targetWs === sourceWs && !pos) return // grouped tiled: snap back in place
        var pending = { workspaceId: targetWs, pos: pos, deadline: Date.now() + 1800 }
        pendingMoves[addr] = pending
        // Publish the destination before restoring x/y bindings. Keep it until the
        // compositor acknowledges this move; refreshToplevels is asynchronous.
        for (var i = 0; i < tilesModel.count; i++) {
            if (tilesModel.get(i).address !== addr) continue
            // A floating fullscreen window has no slot: Logic._tileRect would span the whole
            // output and fill the cell until the next rebuild, so keep the tile's current size
            // and only move it to the drop point.
            var rect = (pos && !win.fullscreen) ? Logic._tileRect({ax:pos.x, ay:pos.y, sw:win.sw, sh:win.sh},
                                            mon, box, params) : null
            tilesModel.set(i, { wx: rect ? rect.x : dropX, wy: rect ? rect.y : dropY,
                                ww: rect ? rect.w : tilesModel.get(i).ww,
                                wh: rect ? rect.h : tilesModel.get(i).wh, wsid: targetWs })
            break
        }
        // Floating: transfer + exact position in one compositor-side chunk (nothing here has to
        // outlive the overlay to finish it). Grouped tiled windows only change workspace.
        if (pos) Hyprland.dispatch(Logic.floatingMoveLua(addr, targetWs, pos))
        else Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + targetWs +
                               ', follow = false, window = "address:' + addr + '" })')
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
            if (pending.before) {
                // A re-tile is acknowledged once the dragged window's workspace or geometry
                // differs from the pre-drop record, OR the anchor's geometry does: every insert
                // splits the anchor, and a fullscreen window re-tiled in place ends up
                // reporting the same fullscreen rect it started with.
                var b = pending.before, a = b.anchor, aw = a ? byAddress[a.address] : null
                var ownSame = b.ws === win.workspaceId && b.ax === win.ax && b.ay === win.ay &&
                              b.sw === win.sw && b.sh === win.sh
                var anchorSame = !a || !!(aw && aw.ax === a.ax && aw.ay === a.ay && aw.sw === a.sw && aw.sh === a.sh)
                                  // a vanished anchor acknowledges: the insert is moot
                if (ownSame && anchorSame) continue
                delete pendingMoves[addr]
                continue
            }
            if (!pending.pos || (Math.abs(win.ax - pending.pos.x) <= 1 &&
                                 Math.abs(win.ay - pending.pos.y) <= 1 &&
                                 (!pending.size || (Math.abs(win.sw - pending.size.w) <= 1 &&
                                                    Math.abs(win.sh - pending.size.h) <= 1))))
                delete pendingMoves[addr]
        }
    }
    // Pointer position in canvas coordinates during a drag (viewport point + scroll offset).
    function dragPointer() {
        return { x: dragViewportX + flick.contentX, y: dragViewportY + flick.contentY }
    }
    function updateDropTarget() {
        if (!dragTile) { dropTargetWs = -1; dropTargetAddress = ""; dropTargetSide = ""; return }
        // The pointer decides (as the cursor does in a native drag); the tile is only a ghost.
        var p = dragPointer(), cx = p.x, cy = p.y
        var ws = Logic.hitWorkspace(boxes, cx, cy)
        dropTargetWs = ws === null ? -1 : ws
        var win = _windowByAddress[draggingAddress]
        var tiledDrag = win && !win.floating && !win.grouped && ws !== null
        var plan = tiledDrag ? tiledDropPlan(draggingAddress, win, ws, cx, cy) : null
        dropTargetAddress = plan ? plan.anchor : ""
        dropTargetSide = plan ? plan.side : ""
    }
    function endDrag() {
        var tile = dragTile
        dragTile = null
        draggingAddress = ""
        dropTargetWs = -1
        dropTargetAddress = ""
        dropTargetSide = ""
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
                                wsid: t.workspaceId, floating: floatingFor(t.address),
                                layer: t.layer, fullscreen: t.fullscreen, fsPending: false })
        }
        for (var u = 0; u < d.updates.length; u++) {
            var tu = d.updates[u]
            if (root.draggingAddress === tu.address || pendingMoves[tu.address]) continue   // grab is authoritative
            var iu = indexOf(tu.address)
            if (iu >= 0) tilesModel.set(iu, { wx: tu.x, wy: tu.y, ww: tu.w, wh: tu.h,
                                              title: titleFor(tu.address), cls: clsFor(tu.address), wsid: tu.workspaceId,
                                              floating: floatingFor(tu.address),
                                              layer: tu.layer, fullscreen: tu.fullscreen })
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
        reconcileFullscreen(input.windows)
        if (!Object.keys(pendingMoves).length && !Object.keys(pendingFullscreen).length) reconcileTimer.stop()
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
        // Every dispatched operation is atomic in the compositor; the reconcile timer only
        // clears optimistic state.
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

        Rectangle { anchors.fill: parent; color: root.scrim; visible: config.scrim }
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        // A 28% shadow reads on light themes but vanishes on dark ones (Tokyo Night sweep),
        // so the alpha follows the card's luminance.
        SoftShadow { target: card; color: Qt.rgba(0, 0, 0, root.darkTheme ? 0.55 : 0.28) }
        Rectangle {
            id: card
            anchors.centerIn: parent
            radius: root.cardRadius
            color: root.background
            readonly property int pad: Math.round(Style.space(12))
            // Space the key hints take under the grid, zero when they are switched off.
            readonly property real hintSpace: config.hint ? hint.implicitHeight + 8 : 0
            // Cap the card to the screen so the Flickable viewport can be smaller than the
            // content (`availCanvasW` already keeps canvas width <= this, minus the degenerate
            // narrow-screen case, which is expected to 2-D scroll per the spec).
            readonly property real maxCardW: panel.width > 0 ? panel.width - 16 : 1616
            readonly property real maxCardH: panel.height > 0 ? panel.height - 64 : 900
            implicitWidth: Math.min(canvas.implicitWidth + pad * 2, maxCardW)
            implicitHeight: Math.min(canvas.implicitHeight + pad * 2 + hintSpace, maxCardH)
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
                height: card.height - card.pad * 2 - card.hintSpace
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
                            radius: root.boxRadius
                            // a well sunk into the card; no outline
                            color: isDrop ? root.dropWellColor
                                 : modelData.focused ? root.selBackground
                                 : modelData.occupied ? root.wellColor : root.emptyWellColor

                            // big low-contrast numeral, only where nothing would hide it
                            Text {
                                objectName: "wsNumeral"
                                anchors.centerIn: parent
                                visible: !modelData.occupied
                                text: root.wsLabel(modelData.workspaceId)
                                color: root.foreground
                                opacity: 0.10
                                font.pixelSize: Math.round(modelData.h * 0.45)
                                font.weight: Font.DemiBold
                            }
                            MouseArea {   // click empty area of a workspace => jump
                                anchors.fill: parent
                                onClicked: root.jump(modelData.workspaceId)
                            }
                        }
                    }

                    // monitor chips layer (siblings, above boxes) — plain labels, one per group;
                    // the focused monitor's label is accented. Shown only when the layout has
                    // more than one group (then each group carries a non-zero header band).
                    Repeater {
                        model: root.opened && root.groups.length > 1 ? root.groups : []
                        Text {
                            required property var modelData
                            x: modelData.x + 4; y: modelData.y
                            height: modelData.headerH
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.monitorName
                            color: modelData.focused ? root.accent : root.foreground
                            opacity: modelData.focused ? 1.0 : 0.55
                            font.family: root.fontFamily
                            font.pixelSize: root.labelSize
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1
                        }
                    }

                    // tiles layer (siblings, above boxes)
                    Repeater {
                        model: tilesModel
                        WindowTile {
                            required property var model
                            x: model.wx; y: model.wy; width: model.ww; height: model.wh
                            cls: model.cls
                            tileLayer: model.layer
                            fullscreen: model.fullscreen
                            fullscreenPending: model.fsPending
                            title: model.title
                            dragging: root.draggingAddress === model.address
                            handle: root.handleByAddress[model.address] || null
                            capMode: "live"
                            borderColor: root.dropTargetAddress === model.address ? root.accent : root.hairline
                            dropTarget: root.dropTargetAddress === model.address
                            dropSide: root.dropTargetAddress === model.address ? root.dropTargetSide : ""
                            bg: root.background; fg: root.foreground
                            floating: model.floating
                            fontFamily: root.fontFamily
                            titleSize: root.captionSize
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
                            onUnfullscreenRequested: root.unfullscreen(model.address)
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
                                    delete root.pendingFullscreen[model.address]
                                    root.setTileRoles(model.address, { fsPending: false })
                                    windowTile.beginGrab(m.x, m.y)   // ghost shrinks around the grab point
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
                                    var ptr = root.dragPointer()
                                    if (wasMoved && targetWs >= 0)
                                        root.submitDrop(addr, targetWs, dropX, dropY, ptr.x, ptr.y)
                                    root.endDrag()
                                    if (!wasMoved) {
                                        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
                                        root.close()
                                    }
                                }
                            }
                        }
                    }

                    // badge layer (above tiles): the workspace number stays readable no matter
                    // what the previews contain. One chip per box, top-left corner. Focused
                    // workspace = accent chip. No mouse handling, so clicks fall through.
                    Repeater {
                        model: root.opened ? root.boxes : []
                        Rectangle {
                            required property var modelData
                            objectName: "wsBadge"
                            x: modelData.x + 6; y: modelData.y + 6
                            z: 40   // above resting/hovered tiles, below the selection frame
                            height: badgeText.implicitHeight + 6
                            width: Math.max(height, badgeText.implicitWidth + 10)
                            radius: 5
                            color: modelData.focused ? root.accent : root.badgeColor
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: root.wsLabel(modelData.workspaceId)
                                color: modelData.focused ? root.background : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: root.labelSize
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    // selection frame: the accent outline on the keyboard-selected box. Drags
                    // never move it (keyboard selection and "where I just dropped a window" are
                    // different intents); it only recedes while a drag is in progress.
                    Rectangle {
                        id: selectionFrame
                        readonly property var box:
                            (root.selectedIndex >= 0 && root.selectedIndex < root.boxes.length)
                                ? root.boxes[root.selectedIndex] : null
                        visible: box !== null
                        x: box ? box.x : 0; y: box ? box.y : 0
                        width: box ? box.w : 0; height: box ? box.h : 0
                        z: 50   // above resting/hovered tiles, below the drag ghost
                        radius: root.boxRadius
                        color: "transparent"
                        border.width: 2
                        border.color: root.accent
                        opacity: root.draggingAddress !== "" ? 0.4 : 1
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    // drop wash: the workspace-level drop cue, drawn ABOVE the previews so a
                    // fullscreen or densely tiled workspace cannot hide it. Shown while dragging
                    // over a box whenever no tile-level insertion preview is showing (floating
                    // drags, empty targets, grouped/fullscreen sources); the tinted well
                    // underneath is only a secondary hint.
                    Rectangle {
                        id: dropWash
                        readonly property var box:
                            (root.draggingAddress !== "" && root.dropTargetAddress === "")
                                ? root.boxForWs(root.dropTargetWs) : null
                        visible: box !== null
                        x: box ? box.x : 0; y: box ? box.y : 0
                        width: box ? box.w : 0; height: box ? box.h : 0
                        z: 60   // above resting/hovered tiles and the selection frame, below the ghost
                        radius: root.boxRadius
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                        border.width: 2
                        border.color: root.accent
                    }
                }
            }

            // key hints: each binding as a small key cap plus a label; off via config.hint
            Row {
                id: hint
                visible: config.hint
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                spacing: Math.round(Style.space(12))
                Repeater {
                    model: [ { k: "1–0", l: "jump" }, { k: "↑ ↓ ← →", l: "move" }, { k: "↵", l: "select" },
                             { k: "drag", l: "move window" }, { k: "esc", l: "close" } ]
                    Row {
                        required property var modelData
                        spacing: 5
                        Rectangle {
                            radius: 4
                            color: root.wellColor
                            height: capText.implicitHeight + 4
                            width: capText.implicitWidth + 10
                            Text {
                                id: capText; anchors.centerIn: parent
                                text: modelData.k
                                color: root.foreground; opacity: 0.75
                                font.family: root.fontFamily; font.pixelSize: root.captionSize
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.l
                            color: root.foreground; opacity: 0.45
                            font.family: root.fontFamily; font.pixelSize: root.captionSize
                        }
                    }
                }
            }
        }
    }
}
