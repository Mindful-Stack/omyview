import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "logic.js" as Logic

ShellRoot {
    Overview { id: overview }
    IpcHandler {
        target: "dragtest"
        function drop(address: string, workspace: int, x: int, y: int): void {
            overview.rebuild()
            var win = overview._windowByAddress[address]
            var box = overview.boxForWs(workspace)
            var mon = overview._monByName[box.monitorName]
            var rect = Logic._tileRect({ax:x,ay:y,sw:win.sw,sh:win.sh},mon,box,overview.params)
            overview.submitDrop(address,workspace,rect.x,rect.y)
        }
        // Drop so that the dragged tile's CENTRE maps to real global point (gx, gy) in `workspace`.
        function dropPoint(address: string, workspace: int, gx: int, gy: int): void {
            overview.rebuild()
            var box = overview.boxForWs(workspace), mon = overview._monByName[box.monitorName]
            var t = overview.tileRectFor(address)
            var r = Logic._tileRect({ax:gx, ay:gy, sw:1, sh:1}, mon, box, overview.params)
            overview.submitDrop(address, workspace, r.x - t.w / 2, r.y - t.h / 2, r.x, r.y)
        }
        function openOverview(): void { overview.open() }
        function pending(): string { return JSON.stringify(overview.pendingMoves) }
        function unfullscreen(address: string): void { overview.rebuild(); overview.unfullscreen(address) }
        function pendingFullscreen(): string { return JSON.stringify(overview.pendingFullscreen) }
    }
}
