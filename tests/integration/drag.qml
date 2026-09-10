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
        function dropOn(address: string, targetAddress: string): void {
            overview.rebuild()
            var win = overview._windowByAddress[address], target = overview._windowByAddress[targetAddress]
            var box = overview.boxForWs(target.workspaceId), mon = overview._monByName[box.monitorName]
            var targetRect = Logic._tileRect(target,mon,box,overview.params)
            var sourceBox = overview.boxForWs(win.workspaceId)
            var sourceRect = Logic._tileRect(win,overview._monByName[sourceBox.monitorName],sourceBox,overview.params)
            overview.submitDrop(address,target.workspaceId,
                targetRect.x+(targetRect.w-sourceRect.w)/2,targetRect.y+(targetRect.h-sourceRect.h)/2)
        }
        function openOverview(): void { overview.open() }
        function pending(): string { return JSON.stringify(overview.pendingMoves) }
    }
}
