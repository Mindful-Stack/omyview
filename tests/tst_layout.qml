import QtQuick
import QtTest
import "../logic.js" as Logic

TestCase {
    name: "Layout"

    readonly property var params: ({
        maxCols: 5, minCellW: 140, maxCellW: 380, cellInset: 6, cellSpacing: 8,
        rowSpacing: 12, headerH: 22, minTileW: 8, minTileH: 6
    })

    // eDP-1: 2560x1600 @1.25 => 2048x1280 logical; 26px top bar reserved.
    function edp() {
        return { name: "eDP-1", x: 0, y: 0, width: 2560, height: 1600,
                 scale: 1.25, reserved: [0, 26, 0, 0], transform: 0 }
    }

    function hdmi() {
        return { name: "HDMI-A-1", x: 2560, y: 0, width: 1920, height: 1080,
                 scale: 1, reserved: [0, 26, 0, 0], transform: 0 }
    }

    function boxById(res, id) {
        for (var i = 0; i < res.boxes.length; i++)
            if (res.boxes[i].workspaceId === id) return res.boxes[i]
        return null
    }

    // wide anchor: availW 1632 => cols 5, cw 320, ch 200 (eDP aspect 1.6)
    function test_cell_size_and_boxes_wide() {
        var r = Logic.layout({ monitors:[edp()],
            workspaces:[{id:1,monitorName:"eDP-1",focused:true,occupied:true},
                        {id:2,monitorName:"eDP-1",focused:false,occupied:false},
                        {id:3,monitorName:"eDP-1",focused:false,occupied:true}],
            windows:[], focusedMonitorName:"eDP-1", availW:1632, params:params })
        compare(r.cell.cols, 5); compare(r.cell.w, 320); compare(r.cell.h, 200)
        var b1=boxById(r,1), b2=boxById(r,2)
        compare(b1.x,0);   compare(b1.y,22)            // below the headerH header
        compare(b2.x,328)                              // 320 + 8 gap
        compare(r.canvasSize.w, 976)                   // 3*320 + 2*8
        compare(r.canvasSize.h, 222)                   // headerH 22 + ch 200
    }
    // narrow screen: fewer columns, never wider than availW
    function test_narrow_adaptive_cols_no_overflow() {
        var r = Logic.layout({ monitors:[edp()],
            workspaces:[{id:1,monitorName:"eDP-1",focused:true,occupied:true},
                        {id:2,monitorName:"eDP-1",focused:false,occupied:false},
                        {id:3,monitorName:"eDP-1",focused:false,occupied:false},
                        {id:4,monitorName:"eDP-1",focused:false,occupied:false}],
            windows:[], focusedMonitorName:"eDP-1", availW:600, params:params })
        compare(r.cell.cols, 4)                        // floor((600+8)/148)=4, capped at 5 (n/a)
        compare(r.canvasSize.w, 600)                    // full row: 4*144 + 3*8 = 600 = availW
    }
    // missing/invalid availW must not corrupt geometry into NaN — degraded but usable
    function test_missing_availw_yields_safe_default() {
        var r = Logic.layout({ monitors:[edp()],
            workspaces:[{id:1,monitorName:"eDP-1",focused:true,occupied:true}],
            windows:[], focusedMonitorName:"eDP-1", params:params })
        compare(r.cell.w, 140); compare(r.cell.cols, 5)
        verify(isFinite(r.canvasSize.w)); verify(isFinite(r.canvasSize.h))
    }
    // degenerate: below minCellW => 1 column, cell clamped up to minCellW
    function test_degenerate_narrow_clamps_to_min() {
        var r = Logic.layout({ monitors:[edp()],
            workspaces:[{id:1,monitorName:"eDP-1",focused:true,occupied:true}],
            windows:[], focusedMonitorName:"eDP-1", availW:100, params:params })
        compare(r.cell.cols, 1); compare(r.cell.w, 140)   // clamped up; may exceed availW (2-D scroll)
    }
    // >cols workspaces wrap into sub-rows
    function test_wrap_into_subrows() {
        var wss=[]; for (var i=1;i<=7;i++) wss.push({id:i,monitorName:"eDP-1",focused:i===1,occupied:true})
        var r = Logic.layout({ monitors:[edp()], workspaces:wss, windows:[],
            focusedMonitorName:"eDP-1", availW:1632, params:params })
        compare(boxById(r,5).y, 22)                    // first sub-row
        compare(boxById(r,6).x, 0)                     // second sub-row, first column
        compare(boxById(r,6).y, 234)                   // 22 + ch200 + rowSpacing12
        compare(r.canvasSize.h, 434)                   // 22 + 200 + 12 + 200
    }
    // two monitors stack, focused group first, groups metadata present
    function test_two_monitor_groups() {
        var r = Logic.layout({ monitors:[edp(),hdmi()],
            workspaces:[{id:1,monitorName:"eDP-1",focused:true,occupied:true},
                        {id:6,monitorName:"HDMI-A-1",focused:false,occupied:true}],
            windows:[], focusedMonitorName:"eDP-1", availW:1632, params:params })
        compare(r.groups.length, 2)
        compare(r.groups[0].monitorName, "eDP-1"); verify(r.groups[0].focused)
        compare(r.groups[0].y, 0); compare(r.groups[1].y, 234)   // eDP header0+row → 222, +rowSpacing12
        verify(boxById(r,1).y < boxById(r,6).y)
    }

    function test_skips_negative_workspace_ids() {
        var input = {
            monitors: [edp()],
            workspaces: [
                { id: 1,  monitorName: "eDP-1", focused: true,  occupied: true },
                { id: -99, monitorName: "eDP-1", focused: false, occupied: false }
            ],
            windows: [], focusedMonitorName: "eDP-1", availW: 1632, params: params
        }
        var r = Logic.layout(input)
        compare(r.boxes.length, 1, "special/lock workspace id<0 excluded")
    }

    function tilesByAddr(res, addr) {
        for (var i = 0; i < res.tiles.length; i++)
            if (res.tiles[i].address === addr) return res.tiles[i]
        return null
    }

    // A normal window fully inside the usable area must land entirely within its box's
    // mini-map inset — never bleeding outside (the exact failure of the old formula that
    // subtracted the reserved origin but scaled against the whole monitor).
    function test_tile_stays_within_minimap_fractional_scale() {
        var input = {
            monitors: [edp()],   // scale 1.25, reserved top 26
            workspaces: [{ id: 1, monitorName: "eDP-1", focused: true, occupied: true }],
            windows: [{ address: "0xA", cls: "foot", ax: 100, ay: 200,
                        sw: 800, sh: 600, workspaceId: 1, floating: false, fullscreen: false }],
            focusedMonitorName: "eDP-1", availW: 1632, params: params
        }
        var r = Logic.layout(input)
        var b = boxById(r, 1), t = tilesByAddr(r, "0xA")
        verify(t !== null)
        var lo = 0.5
        verify(t.x >= b.x + params.cellInset - lo)
        verify(t.y >= b.y + params.cellInset - lo)
        verify(t.x + t.w <= b.x + b.w - params.cellInset + lo)
        verify(t.y + t.h <= b.y + b.h - params.cellInset + lo)
    }

    // Unequal aspect: an ultrawide usable area is wider than the cell's mini-map aspect,
    // so it is width-limited => letterboxed vertically (offY > inset), horizontally flush.
    // NOTE: the ultrawide monitor must NOT be the focused monitor here — cw/ch are now
    // derived from the *focused* monitor's aspect and reused for every box (Task 1), so a
    // sole+focused ultrawide monitor would size its own box to match its own aspect and the
    // letterbox axis this test pins would flip. Keeping eDP-1 focused (cell 320x200) and
    // putting the ultrawide workspace on an unfocused DP-1 reproduces genuine aspect
    // mismatch between the shared 320x200 cell's mini-map and DP-1's usable rect.
    function test_unequal_aspect_letterboxes_on_short_axis() {
        var uw = { name: "DP-1", x: 2560, y: 0, width: 5120, height: 1440,
                   scale: 1, reserved: [0, 0, 0, 0], transform: 0 }
        var input = {
            monitors: [edp(), uw],
            workspaces: [{ id: 1, monitorName: "DP-1", focused: false, occupied: true }],
            // fullscreen window fills the usable rect exactly, so its tile == the fitted R
            windows: [{ address: "0xF", cls: "x", ax: 2560, ay: 0, sw: 5120, sh: 1440,
                        workspaceId: 1, floating: false, fullscreen: true }],
            focusedMonitorName: "eDP-1", availW: 1632, params: params
        }
        var r = Logic.layout(input)
        var b = boxById(r, 1), t = tilesByAddr(r, "0xF")
        // width-limited: fills mini-map width (box.w-2*inset = 308), centered vertically
        // inside mmH (box.h-2*inset = 188)
        fuzzyCompare(t.w, 308, 0.5, "fills mini-map width")
        verify(t.h < 188 - 1)                       // letterboxed on height
        verify(t.y > b.y + params.cellInset + 0.5)  // vertically centered, not flush to inset
    }

    // Fullscreen fills R; a non-fullscreen window that pokes above the usable top is clipped
    // to R (shorter, but starting at the same usable-top line). The clip window is NOT the
    // full output (sw 1000, sh 1200), so the 1px fullscreen auto-detect must not claim it.
    function test_fullscreen_fills_but_nonfullscreen_clips() {
        function run(w) {
            return Logic.layout({ monitors: [edp()],
                workspaces: [{ id: 1, monitorName: "eDP-1", focused: true, occupied: true }],
                windows: [w], focusedMonitorName: "eDP-1", availW: 1632, params: params })
        }
        var full = tilesByAddr(run({ address: "0xF", cls: "x", ax: 0, ay: 0,
            sw: 2048, sh: 1280, workspaceId: 1, floating: false, fullscreen: true }), "0xF")
        // ay:0 is above the usable top (R.y=26) => clipped; not full output => not auto-full
        var norm = tilesByAddr(run({ address: "0xN", cls: "x", ax: 0, ay: 0,
            sw: 1000, sh: 1200, workspaceId: 1, floating: false, fullscreen: false }), "0xN")
        // fullscreen fills the height-limited mini-map exactly (mmH = 188)
        fuzzyCompare(full.h, 188, 0.5, "fullscreen fills limiting axis")
        // clipped window is shorter than the full fill, but shares the usable-top line
        verify(norm.h < full.h - 1)
        fuzzyCompare(norm.y, full.y, 0.5, "clip starts at usable top, not in the bar band")
    }

    // A window entirely left of the monitor has no intersection with R => no tile.
    function test_offscreen_window_yields_no_tile() {
        var r = Logic.layout({ monitors: [edp()],
            workspaces: [{ id: 1, monitorName: "eDP-1", focused: true, occupied: true }],
            windows: [{ address: "0xOff", cls: "x", ax: -500, ay: 100, sw: 200, sh: 200,
                        workspaceId: 1, floating: false, fullscreen: false }],
            focusedMonitorName: "eDP-1", availW: 1632, params: params })
        compare(tilesByAddr(r, "0xOff"), null, "off-usable window is skipped")
    }

    // A hairline window is clamped to the minimum visible size.
    function test_min_size_clamp() {
        var r = Logic.layout({ monitors: [edp()],
            workspaces: [{ id: 1, monitorName: "eDP-1", focused: true, occupied: true }],
            windows: [{ address: "0xTiny", cls: "x", ax: 100, ay: 100, sw: 2, sh: 2,
                        workspaceId: 1, floating: true, fullscreen: false }],
            focusedMonitorName: "eDP-1", availW: 1632, params: params })
        var t = tilesByAddr(r, "0xTiny")
        compare(t.w, params.minTileW); compare(t.h, params.minTileH)
    }

    function test_hit_workspace() {
        var r = Logic.layout({ monitors: [edp()],
            workspaces: [
                { id: 1, monitorName: "eDP-1", focused: true,  occupied: true },
                { id: 2, monitorName: "eDP-1", focused: false, occupied: false }
            ], windows: [], focusedMonitorName: "eDP-1", availW: 1632, params: params })
        var b2 = boxById(r, 2)
        // centre of box 2 => ws 2 (cell is 320x200)
        compare(Logic.hitWorkspace(r.boxes, b2.x + 160, b2.y + 100), 2)
        // the gap between box 1 and box 2 (x in 320..328) => null
        compare(Logic.hitWorkspace(r.boxes, 324, b2.y + 100), null)
        // above the cells, in the header band (y < headerH 22) => null
        compare(Logic.hitWorkspace(r.boxes, 10, 4), null)
    }

    function test_diff_by_address() {
        var prev = ["0xA", "0xB"]
        var next = [{ address: "0xB", x: 1, y: 1, w: 1, h: 1 },
                    { address: "0xC", x: 2, y: 2, w: 2, h: 2 }]
        var d = Logic.diffByAddress(prev, next)
        compare(d.adds.length, 1);    compare(d.adds[0].address, "0xC")
        compare(d.updates.length, 1); compare(d.updates[0].address, "0xB")
        compare(d.removes.length, 1); compare(d.removes[0], "0xA")
    }

    // The earlier fullscreen fixtures used geometry equal to the output, so the clip path
    // happens to equal the fill path there and the `if (isFull)` branch is never pinned. Here
    // the window is fullscreen-FLAGGED but reports small/offset geometry: fill must still fill
    // R (the flag wins), whereas clipping that geometry would give a tiny ~21px-wide tile.
    function test_fullscreen_flag_fills_R_even_when_geometry_small() {
        var r = Logic.layout({ monitors:[edp()],
            workspaces:[{id:1,monitorName:"eDP-1",focused:true,occupied:true}],
            windows:[{address:"0xFS",cls:"x",ax:500,ay:400,sw:300,sh:200,
                      workspaceId:1,floating:false,fullscreen:true}],
            focusedMonitorName:"eDP-1", availW:1632, params:params })
        var t = tilesByAddr(r,"0xFS")
        verify(t !== null)
        fuzzyCompare(t.h, 188, 0.5, "fullscreen fills R height = box.h-2*inset")
        verify(t.w > 100)
    }

    // Pins the min-size clamp's position clamp: a hairline window near the far edge of the
    // usable area, once widened to minTileW, must not spill past the cell's mini-map inset.
    function test_min_clamp_stays_within_minimap_at_edge() {
        var r = Logic.layout({ monitors: [edp()],
            workspaces: [{ id: 1, monitorName: "eDP-1", focused: true, occupied: true }],
            windows: [{ address: "0xEdge", cls: "x", ax: 2046, ay: 100, sw: 2, sh: 2,
                        workspaceId: 1, floating: true, fullscreen: false }],
            focusedMonitorName: "eDP-1", availW: 1632, params: params })
        var b = boxById(r, 1), t = tilesByAddr(r, "0xEdge")
        verify(t !== null)
        compare(t.w, params.minTileW)                                // min-clamped
        verify(t.x + t.w <= b.x + b.w - params.cellInset + 0.01)      // stays in the inset
    }

    // dropToWindowPos is the inverse of tile placement: a floating window at real (ax,ay),
    // once mapped to its tile and then mapped back from that tile's top-left, must land at
    // (ax,ay) again (within rounding). Fails if the reverse math drifts from _tileRect.
    function test_drop_to_window_pos_roundtrip() {
        var win = { address:"0xF", cls:"x", ax:600, ay:500, sw:400, sh:300,
                    workspaceId:1, floating:true, fullscreen:false }
        var r = Logic.layout({ monitors:[edp()],
            workspaces:[{id:1,monitorName:"eDP-1",focused:true,occupied:true}],
            windows:[win], focusedMonitorName:"eDP-1", availW:1632, params:params })
        var b = boxById(r,1), t = tilesByAddr(r,"0xF")
        var back = Logic.dropToWindowPos(t.x, t.y, b, edp(), params)
        fuzzyCompare(back.x, 600, 1.5, "recovers real x")
        fuzzyCompare(back.y, 500, 1.5, "recovers real y")
    }
    // Never emit a negative coord (Hyprland reads -1 as "preserve axis"; negatives fling
    // the window off-screen). A drop above/left of the mini-map content clamps to >= 0.
    function test_drop_to_window_pos_clamps_nonnegative() {
        var r = Logic.layout({ monitors:[edp()],
            workspaces:[{id:1,monitorName:"eDP-1",focused:true,occupied:true}],
            windows:[], focusedMonitorName:"eDP-1", availW:1632, params:params })
        var b = boxById(r,1)
        var back = Logic.dropToWindowPos(b.x - 50, b.y - 50, b, edp(), params) // above-left of cell
        verify(back.x >= 0); verify(back.y >= 0)
    }

    function indexOfWs(r, id) {
        for (var i = 0; i < r.boxes.length; i++) if (r.boxes[i].workspaceId === id) return i
        return -1
    }
    // 10 workspaces => two rows of 5. Arrow nav must move by ROW vertically and by column
    // horizontally — Down on ws3 lands on ws8 (the cell directly below), not ws4.
    function test_arrow_nav_2d_grid() {
        var wss = []; for (var i = 1; i <= 10; i++) wss.push({ id:i, monitorName:"eDP-1", focused:i===1, occupied:true })
        var r = Logic.layout({ monitors:[edp()], workspaces:wss, windows:[],
                               focusedMonitorName:"eDP-1", availW:1632, params:params })
        var i3 = indexOfWs(r, 3)
        // Down from 3 -> 8 (directly below); Up from there -> back to 3
        var down = Logic.navigate(r.boxes, i3, "down")
        compare(r.boxes[down].workspaceId, 8)
        compare(r.boxes[Logic.navigate(r.boxes, down, "up")].workspaceId, 3)
        // Right/Left stay in the row
        compare(r.boxes[Logic.navigate(r.boxes, i3, "right")].workspaceId, 4)
        compare(r.boxes[Logic.navigate(r.boxes, i3, "left")].workspaceId, 2)
        // End of row: Right from ws5 has no box to its right -> unchanged
        var i5 = indexOfWs(r, 5)
        compare(Logic.navigate(r.boxes, i5, "right"), i5)
        // Down from ws10 (bottom row) -> no box below -> unchanged
        var i10 = indexOfWs(r, 10)
        compare(Logic.navigate(r.boxes, i10, "down"), i10)
    }
    function test_drop_keeps_entire_window_in_usable_bounds() {
        var mon=edp(); mon.y=1440
        var box={x:0,y:22,w:320,h:200}
        var p=Logic.dropToWindowPos(319,221,box,mon,params,{sw:600,sh:400})
        compare(p.x,1448)
        compare(p.y,2320)
        p=Logic.dropToWindowPos(-100,-100,box,mon,params,{sw:600,sh:400})
        compare(p.x,0); compare(p.y,1466)
    }
    function test_edge_scroll_is_bounded_and_proportional() {
        compare(Logic.edgeScrollDelta(200,400,100,1000,16),0)
        verify(Logic.edgeScrollDelta(399,400,100,1000,16)>0)
        verify(Logic.edgeScrollDelta(1,400,100,1000,16)<0)
        compare(Logic.edgeScrollDelta(0,400,0,1000,16),0)
        compare(Logic.edgeScrollDelta(400,400,599,1000,16),1)
        compare(Logic.edgeScrollDelta(400,400,0,300,16),0)
    }

    // dropSide mirrors dwindle's smart-split rule (slope of point-from-centre vs aspect), so
    // the drag preview shows the half the compositor will actually split into.
    function test_drop_side_follows_smart_split_rule() {
        var wide = { x: 0, y: 0, w: 400, h: 200 }
        compare(Logic.dropSide(wide, 20, 100), "left")
        compare(Logic.dropSide(wide, 380, 100), "right")
        compare(Logic.dropSide(wide, 200, 10), "top")
        compare(Logic.dropSide(wide, 200, 190), "bottom")
        compare(Logic.dropSide(wide, 380, 150), "right")    // shallow angle wins near a corner
        compare(Logic.dropSide(wide, 250, 190), "bottom")   // steep angle wins near a corner
        var tall = { x: 0, y: 0, w: 200, h: 400 }
        compare(Logic.dropSide(tall, 100, 380), "bottom")
        compare(Logic.dropSide(tall, 190, 220), "right")
        compare(Logic.dropSide(tall, 100, 200), "top")      // exact centre: NaN slope → top, like the C++
    }
    function test_rect_distance_is_zero_inside_and_grows_outside() {
        var r = { x: 10, y: 10, w: 100, h: 50 }
        compare(Logic.rectDistanceSq(r, 50, 30), 0)
        compare(Logic.rectDistanceSq(r, 0, 30), 100)
        compare(Logic.rectDistanceSq(r, 120, 70), 200)
    }
    // The drop plan is what the preview highlights and what a release does. A drop back onto
    // the window's own slot, or a lone tiled window dropped inside its own workspace, plans
    // nothing; otherwise the nearest candidate anchors and the side follows the smart-split rule.
    function test_tiled_drop_plan_shares_eligibility_between_preview_and_release() {
        var own = { x: 0, y: 0, w: 100, h: 100 }
        var other = { x: 200, y: 0, w: 100, h: 100, address: "0xb" }
        compare(Logic.tiledDropPlan([other], true, own, 50, 50), null, "own slot: nothing")
        compare(Logic.tiledDropPlan([other], true, own, 100, 100), null, "own slot edge: nothing")
        compare(Logic.tiledDropPlan([], true, own, 150, 50), null, "lone window in own workspace: nothing")
        var plan = Logic.tiledDropPlan([other], true, own, 150, 50)
        compare(plan.anchor, "0xb", "nearest tiled tile anchors even from the gap")
        compare(plan.side, "left")
        compare(Logic.tiledDropPlan([other], false, null, 290, 50).side, "right")
        var empty = Logic.tiledDropPlan([], false, null, 150, 50)
        compare(empty.anchor, "", "empty destination: insert without an anchor")
        compare(empty.side, "")
        // Ties go to the later (top-most) candidate.
        var twin = { x: 200, y: 0, w: 100, h: 100, address: "0xc" }
        compare(Logic.tiledDropPlan([other, twin], false, null, 250, 50).anchor, "0xc")
    }
    // The atomic Lua chunk must replay a native drop in order: float → (move) → measure the
    // anchor → cursor → un-float, with smart_split forced on and the cursor restored, and never
    // embed NaN/undefined. The cursor point is derived from the anchor's geometry read AFTER the
    // float (detaching the window re-lays out the workspace), on the requested side.
    function test_tiled_insert_lua_replays_native_drop() {
        var lua = Logic.tiledInsertLua("0xabc", 3, { anchor: "0xdef", side: "bottom", x: 512.6, y: 1800.2 })
        verify(lua.indexOf('address:0xabc') >= 0)
        verify(lua.indexOf('"address:0xdef"') >= 0)
        verify(lua.indexOf('smart_split = true') >= 0)
        verify(lua.indexOf('workspace = "3"') >= 0)
        verify(lua.indexOf('local x, y = 513, 1800') >= 0, "fallback point when there is no anchor")
        verify(lua.indexOf('== "bottom" then y = a.at.y + a.size.y') >= 0, "bottom edge of the anchor")
        verify(lua.indexOf('hl.get_cursor_pos()') >= 0)
        verify(lua.indexOf('NaN') < 0 && lua.indexOf('undefined') < 0)
        var order = [lua.indexOf('window.float('), lua.indexOf('window.move('),
                     lua.indexOf('hl.get_window(anchorSel)'), lua.indexOf('cursor.move('),
                     lua.lastIndexOf('window.float(')]
        for (var i = 1; i < order.length; i++) verify(order[i] > order[i - 1], "step order " + i)
        verify(lua.lastIndexOf('smart_split = smart') > lua.lastIndexOf('window.float('), "config restored after re-tile")
        var none = Logic.tiledInsertLua("0xabc", 2, { anchor: "", side: "", x: 10, y: 20 })
        verify(none.indexOf('local anchorSel = nil') >= 0, "no anchor: plain fallback point")
        verify(none.indexOf('local x, y = 10, 20') >= 0)
        var bad = Logic.tiledInsertLua("0xabc", 2, { anchor: "0xdef", side: "sideways", x: 1, y: 2 })
        verify(bad.indexOf('sideways') < 0, "unknown side falls back to the anchor centre")
    }

}
