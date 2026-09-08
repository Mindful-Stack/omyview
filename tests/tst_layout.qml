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
}
