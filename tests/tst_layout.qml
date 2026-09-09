import QtQuick
import QtTest
import "../logic.js" as Logic

TestCase {
    name: "Layout"

    readonly property var params: ({
        cellW: 160, cellH: 100, cellInset: 6, cellSpacing: 8,
        rowSpacing: 12, rowLabelH: 16, minTileW: 8, minTileH: 6
    })

    // eDP-1: 2560x1600 @1.25 => 2048x1280 logical; 26px top bar reserved.
    function edp() {
        return { name: "eDP-1", x: 0, y: 0, width: 2560, height: 1600,
                 scale: 1.25, reserved: [0, 26, 0, 0], transform: 0 }
    }

    function boxById(res, id) {
        for (var i = 0; i < res.boxes.length; i++)
            if (res.boxes[i].workspaceId === id) return res.boxes[i]
        return null
    }

    function test_single_monitor_boxes_and_canvas() {
        var input = {
            monitors: [edp()],
            workspaces: [
                { id: 1, monitorName: "eDP-1", focused: true,  occupied: true },
                { id: 2, monitorName: "eDP-1", focused: false, occupied: false },
                { id: 3, monitorName: "eDP-1", focused: false, occupied: true }
            ],
            windows: [],
            focusedMonitorName: "eDP-1",
            params: params
        }
        var r = Logic.layout(input)
        compare(r.boxes.length, 3, "three boxes")
        var b1 = boxById(r, 1), b2 = boxById(r, 2), b3 = boxById(r, 3)
        // cells start below the row label: y = rowLabelH
        compare(b1.x, 0);   compare(b1.y, 16)
        compare(b2.x, 168); compare(b2.y, 16)   // 160 + 8 spacing
        compare(b3.x, 336)
        verify(b1.focused); verify(!b2.focused)
        // canvas: widest row = 3*160 + 2*8 = 496 ; height = label+cell = 116
        compare(r.canvasSize.w, 496)
        compare(r.canvasSize.h, 116)
    }

    function test_two_monitors_focused_row_first() {
        var hdmi = { name: "HDMI-A-1", x: 2560, y: 0, width: 1920, height: 1080,
                     scale: 1, reserved: [0, 26, 0, 0], transform: 0 }
        var input = {
            monitors: [edp(), hdmi],
            workspaces: [
                { id: 6, monitorName: "HDMI-A-1", focused: false, occupied: true },
                { id: 1, monitorName: "eDP-1",    focused: true,  occupied: true }
            ],
            windows: [],
            focusedMonitorName: "eDP-1",
            params: params
        }
        var r = Logic.layout(input)
        // focused monitor's workspace sits in the top row (smaller y) despite input order
        verify(boxById(r, 1).y < boxById(r, 6).y)
    }

    function test_skips_negative_workspace_ids() {
        var input = {
            monitors: [edp()],
            workspaces: [
                { id: 1,  monitorName: "eDP-1", focused: true,  occupied: true },
                { id: -99, monitorName: "eDP-1", focused: false, occupied: false }
            ],
            windows: [], focusedMonitorName: "eDP-1", params: params
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
            focusedMonitorName: "eDP-1", params: params
        }
        var r = Logic.layout(input)
        var b = boxById(r, 1), t = tilesByAddr(r, "0xA")
        verify(t !== null)
        var lo = 0.5
        verify(t.x >= b.x + params.cellInset - lo)
        verify(t.y >= b.y + params.cellInset - lo)
        verify(t.x + t.w <= b.x + params.cellW - params.cellInset + lo)
        verify(t.y + t.h <= b.y + params.cellH - params.cellInset + lo)
    }

    // Unequal aspect: an ultrawide usable area is wider than the cell's mini-map aspect,
    // so it is width-limited => letterboxed vertically (offY > inset), horizontally flush.
    function test_unequal_aspect_letterboxes_on_short_axis() {
        var uw = { name: "DP-1", x: 0, y: 0, width: 5120, height: 1440,
                   scale: 1, reserved: [0, 0, 0, 0], transform: 0 }
        var input = {
            monitors: [uw],
            workspaces: [{ id: 1, monitorName: "DP-1", focused: true, occupied: true }],
            // fullscreen window fills the usable rect exactly, so its tile == the fitted R
            windows: [{ address: "0xF", cls: "x", ax: 0, ay: 0, sw: 5120, sh: 1440,
                        workspaceId: 1, floating: false, fullscreen: true }],
            focusedMonitorName: "DP-1", params: params
        }
        var r = Logic.layout(input)
        var b = boxById(r, 1), t = tilesByAddr(r, "0xF")
        // width-limited: fills mini-map width (148), centered vertically inside mmH (88)
        fuzzyCompare(t.w, 148, 0.5, "fills mini-map width")
        verify(t.h < 88 - 1)                       // letterboxed on height
        verify(t.y > b.y + params.cellInset + 0.5) // vertically centered, not flush to inset
    }

    // Fullscreen fills R; a non-fullscreen window that pokes above the usable top is clipped
    // to R (shorter, but starting at the same usable-top line). The clip window is NOT the
    // full output (sw 1000, sh 1200), so the 1px fullscreen auto-detect must not claim it.
    function test_fullscreen_fills_but_nonfullscreen_clips() {
        function run(w) {
            return Logic.layout({ monitors: [edp()],
                workspaces: [{ id: 1, monitorName: "eDP-1", focused: true, occupied: true }],
                windows: [w], focusedMonitorName: "eDP-1", params: params })
        }
        var full = tilesByAddr(run({ address: "0xF", cls: "x", ax: 0, ay: 0,
            sw: 2048, sh: 1280, workspaceId: 1, floating: false, fullscreen: true }), "0xF")
        // ay:0 is above the usable top (R.y=26) => clipped; not full output => not auto-full
        var norm = tilesByAddr(run({ address: "0xN", cls: "x", ax: 0, ay: 0,
            sw: 1000, sh: 1200, workspaceId: 1, floating: false, fullscreen: false }), "0xN")
        // fullscreen fills the height-limited mini-map exactly (mmH = 88)
        fuzzyCompare(full.h, 88, 0.5, "fullscreen fills limiting axis")
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
            focusedMonitorName: "eDP-1", params: params })
        compare(tilesByAddr(r, "0xOff"), null, "off-usable window is skipped")
    }

    // A hairline window is clamped to the minimum visible size.
    function test_min_size_clamp() {
        var r = Logic.layout({ monitors: [edp()],
            workspaces: [{ id: 1, monitorName: "eDP-1", focused: true, occupied: true }],
            windows: [{ address: "0xTiny", cls: "x", ax: 100, ay: 100, sw: 2, sh: 2,
                        workspaceId: 1, floating: true, fullscreen: false }],
            focusedMonitorName: "eDP-1", params: params })
        var t = tilesByAddr(r, "0xTiny")
        compare(t.w, params.minTileW); compare(t.h, params.minTileH)
    }

    function test_hit_workspace() {
        var r = Logic.layout({ monitors: [edp()],
            workspaces: [
                { id: 1, monitorName: "eDP-1", focused: true,  occupied: true },
                { id: 2, monitorName: "eDP-1", focused: false, occupied: false }
            ], windows: [], focusedMonitorName: "eDP-1", params: params })
        var b2 = boxById(r, 2)
        // centre of box 2 => ws 2
        compare(Logic.hitWorkspace(r.boxes, b2.x + 80, b2.y + 50), 2)
        // the gap between box 1 and box 2 (x in 160..168) => null
        compare(Logic.hitWorkspace(r.boxes, 164, b2.y + 50), null)
        // above the cells, in the row-label band (y < 16) => null
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
        var r = Logic.layout({ monitors: [edp()],
            workspaces: [{ id: 1, monitorName: "eDP-1", focused: true, occupied: true }],
            windows: [{ address: "0xFS", cls: "x", ax: 500, ay: 400, sw: 300, sh: 200,
                        workspaceId: 1, floating: false, fullscreen: true }],
            focusedMonitorName: "eDP-1", params: params })
        var b = boxById(r, 1), t = tilesByAddr(r, "0xFS")
        verify(t !== null)
        fuzzyCompare(t.h, 88, 0.5, "fullscreen fills R height (mmH)")
        verify(t.w > 100)                        // fill: R.w*k ~143.7; a clipped 300px would be ~21
        fuzzyCompare(t.y, b.y + 6, 0.5)          // offY
    }

    // Pins the min-size clamp's position clamp: a hairline window near the far edge of the
    // usable area, once widened to minTileW, must not spill past the cell's mini-map inset.
    function test_min_clamp_stays_within_minimap_at_edge() {
        var r = Logic.layout({ monitors: [edp()],
            workspaces: [{ id: 1, monitorName: "eDP-1", focused: true, occupied: true }],
            windows: [{ address: "0xEdge", cls: "x", ax: 2046, ay: 100, sw: 2, sh: 2,
                        workspaceId: 1, floating: true, fullscreen: false }],
            focusedMonitorName: "eDP-1", params: params })
        var b = boxById(r, 1), t = tilesByAddr(r, "0xEdge")
        verify(t !== null)
        compare(t.w, params.minTileW)                                   // min-clamped
        verify(t.x + t.w <= b.x + params.cellW - params.cellInset + 0.01) // stays in the inset
    }
}
