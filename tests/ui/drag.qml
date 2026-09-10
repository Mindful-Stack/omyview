import QtQuick
import QtTest

TestCase {
    id: tc
    name: "Drag"
    when: windowShown
    width: 1200; height: 800; visible: true
    property var view
    property var client
    Component { id: overview; Overview {} }
    function init() {
        view = createTemporaryObject(overview, tc)
        verify(view !== null)
        var mon = {name:"TEST", x:0, y:1440, width:1920, height:1080,
                   scale:1, lastIpcObject:{reserved:[0,26,0,0],transform:0}}
        client = {address:"0x123", at:[100,1540], size:[600,400], floating:false,
                  title:"Test", "class":"test", fullscreen:0}
        view.compositor.monitors = {values:[mon]}
        view.compositor.focusedMonitor = mon
        view.compositor.focusedWorkspace = {id:1}
        view.compositor.workspaces = {values:[
            {id:1,monitor:mon,toplevels:{values:[{lastIpcObject:client}]}},
            {id:2,monitor:mon,toplevels:{values:[]}}
        ]}
        view.open()
        wait(350)
    }
    function cleanup() { view.close() }
    function tile() {
        var children = view.testCanvas.children
        for (var i=0;i<children.length;i++)
            if (children[i].model && children[i].model.address === "0x123") return children[i]
        fail("Tile not found")
    }
    function dragBy(dx, dy) {
        var t = tile(), p = t.mapToItem(tc, t.width/2, t.height/2)
        mousePress(tc, p.x, p.y, Qt.LeftButton)
        mouseMove(tc, p.x + 12, p.y + 2, 20)
        mouseMove(tc, p.x + dx, p.y + dy, 20)
        mouseRelease(tc, p.x + dx, p.y + dy, Qt.LeftButton)
    }
    function test_float_toggle_updates_existing_tile() {
        client.floating = true
        view.rebuild()
        compare(view.testModel.get(0).floating, true)
        dragBy(35, 20)
        verify(view.compositor.commands.some(function(c) {return c.indexOf('x = "') >= 0}),
               "Floating drag must dispatch a coordinate move after toggling")
    }
    function test_drop_survives_stale_refresh() {
        client.floating = true
        // Recreate the row so this test isolates pending geometry from floating-role refresh.
        view.testModel.clear(); view.rebuild()
        var before = tile().x
        dragBy(35, 20)
        var dropped = tile().x
        verify(dropped > before + 10, "Tile must move with the pointer")
        view.rebuild()
        compare(tile().x, dropped, "Stale geometry must not undo a pending drop")
    }
    function test_cancel_restores_drag_state() {
        var t=tile(), p=t.mapToItem(tc,t.width/2,t.height/2)
        mousePress(tc,p.x,p.y,Qt.LeftButton)
        mouseMove(tc,p.x+12,p.y+2,20)
        mouseMove(tc,p.x+35,p.y+20,20)
        view.close()
        mouseRelease(tc,p.x+35,p.y+20,Qt.LeftButton)
        compare(t.x,view.testModel.get(0).wx)
        verify(t.z < 100, "Cancel must restore tile stacking")
        compare(view.compositor.commands.length,0,"Closing mid-drag must not dispatch a drop")
    }
    function test_acknowledgement_releases_pending_geometry() {
        client.floating = true; view.rebuild()
        dragBy(35,20)
        var pending = view.pendingMoves[client.address]
        verify(pending !== undefined)
        client.at = [pending.pos.x,pending.pos.y]
        view.rebuild()
        verify(view.pendingMoves[client.address] === undefined)
        client.at = [200,1600]; view.rebuild()
        verify(Math.abs(tile().x - view.testModel.get(0).wx) < 0.01)
    }
    function test_rejected_move_times_out() {
        client.floating = true; view.rebuild()
        var before = tile().x
        dragBy(35,20)
        view.pendingMoves[client.address].deadline = Date.now()-1
        view.rebuild()
        compare(tile().x,before)
        verify(view.pendingMoves[client.address] === undefined)
    }
    function test_cross_workspace_waits_before_positioning() {
        client.floating = true; view.rebuild()
        dragBy(view.boxes[1].x-view.boxes[0].x,20)
        compare(view.compositor.commands.length,1)
        verify(view.compositor.commands[0].indexOf('workspace = 2') >= 0)
        var dropped = tile().x
        view.rebuild(); compare(tile().x,dropped)
        var ws = view.compositor.workspaces.values
        ws[0].toplevels.values=[]
        ws[1].toplevels.values=[{lastIpcObject:client}]
        view.rebuild()
        compare(view.compositor.commands.length,2)
        verify(view.compositor.commands[1].indexOf('x = "') >= 0)
        compare(tile().x,dropped)
        var p=view.pendingMoves[client.address].pos
        client.at=[p.x,p.y]; view.rebuild()
        verify(view.pendingMoves[client.address] === undefined)
        compare(view.testModel.get(0).wsid,2)
    }
    function test_outside_drop_does_not_move_floating_window() {
        client.floating=true; view.rebuild()
        var before=tile().x
        dragBy(-160,0)
        compare(view.compositor.commands.length,0)
        compare(tile().x,before)
    }
    function test_window_closing_mid_drag_cancels() {
        var t=tile(), p=t.mapToItem(tc,t.width/2,t.height/2)
        mousePress(tc,p.x,p.y,Qt.LeftButton)
        mouseMove(tc,p.x+12,p.y+2,20)
        mouseMove(tc,p.x+35,p.y+20,20)
        verify(view.draggingAddress !== "")
        view.compositor.workspaces.values[0].toplevels.values=[]
        view.rebuild()
        compare(view.draggingAddress,"")
        compare(view.dropTargetWs,-1)
        compare(view.testModel.count,0)
        mouseRelease(tc,p.x+35,p.y+20,Qt.LeftButton)
        compare(view.compositor.commands.length,0)
    }
    function test_edge_scroll_keeps_tile_under_pointer() {
        var ws=view.compositor.workspaces.values
        for (var i=3;i<=45;i++) ws.push({id:i,monitor:ws[0].monitor,toplevels:{values:[]}})
        view.rebuild()
        var t=tile(), p=t.mapToItem(tc,t.width/2,t.height/2)
        var edge=view.testFlick.mapToItem(tc,100,view.testFlick.height-4)
        mousePress(tc,p.x,p.y,Qt.LeftButton)
        mouseMove(tc,p.x+12,p.y+2,20)
        mouseMove(tc,edge.x,edge.y,20)
        var before=view.testFlick.contentY
        var visual=t.mapToItem(tc,0,0)
        wait(100)
        verify(view.testFlick.contentY > before, "Holding near the edge must scroll")
        var after=t.mapToItem(tc,0,0)
        verify(Math.abs(visual.y-after.y)<1, "Scrolling must keep the tile under the pointer")
        view.close()
        mouseRelease(tc,edge.x,edge.y,Qt.LeftButton)
        var stopped=view.testFlick.contentY
        wait(50); compare(view.testFlick.contentY,stopped)
    }

    function test_second_drop_uses_actual_source_workspace() {
        client.floating=true; view.rebuild()
        var b=view.boxes[1]
        // The tile may already show workspace 2 while the real transfer is pending.
        view.testModel.setProperty(0,"wsid",2)
        view.submitDrop(client.address,2,b.x+30,b.y+30)
        verify(view.compositor.commands[0].indexOf('workspace = 2') >= 0)
    }

    function test_app_class_refreshes_existing_tile() {
        var original = tile()
        compare(original.cls, "test")
        client["class"] = "updated-app"
        client.title = "Updated title"
        view.rebuild()
        compare(view.testModel.count, 1)
        compare(tile(), original, "Metadata refresh must preserve the tile instance")
        compare(original.cls, "updated-app", "Fallback icon must follow updated app identity")
        compare(original.title, "Updated title")
    }

    function addTarget(ws) {
        var other={address:"0x456",at:[1000,1540],size:[600,400],floating:false,
                   title:"Other", "class":"test",fullscreen:0}
        view.compositor.workspaces.values[ws-1].toplevels.values.push({lastIpcObject:other})
        view.rebuild()
        return other
    }
    function dragOntoTarget(ws) {
        var source=view.testModel.get(0), target=view.testModel.get(1)
        dragBy(target.wx-source.wx+12,target.wy-source.wy+2)
    }
    function test_tiled_swap_uses_explicit_addresses() {
        addTarget(1)
        dragOntoTarget(1)
        compare(view.compositor.commands.length,1)
        var cmd=view.compositor.commands[0]
        verify(cmd.indexOf('hl.dsp.window.swap(')>=0)
        verify(cmd.indexOf('window = "address:0x123"')>=0)
        verify(cmd.indexOf('target = "address:0x456"')>=0)
        verify(cmd.indexOf('hl.get_cursor_pos()')>=0,"Swap must restore cursor")
    }
    function test_tiled_cross_workspace_places_at_target() {
        var other=addTarget(2)
        dragOntoTarget(2)
        compare(view.compositor.commands.length,1)
        verify(view.compositor.commands[0].indexOf('workspace = 2')>=0)
        var ws=view.compositor.workspaces.values
        ws[0].toplevels.values=[]
        // Model Hyprland's default insertion before targeted rearrangement.
        client.at=[1000,2000];client.size=[600,300]
        ws[1].toplevels.values.push({lastIpcObject:client})
        view.rebuild()
        compare(view.compositor.commands.length,2)
        verify(view.compositor.commands[1].indexOf('hl.dsp.window.swap(')>=0)
        // Both tiles stay optimistic until swapped geometry arrives.
        var a=view.testModel.get(0).wx,b=view.testModel.get(1).wx
        view.rebuild()
        compare(view.testModel.get(0).wx,a);compare(view.testModel.get(1).wx,b)
        var oldAt=client.at,oldSize=client.size
        client.at=other.at;client.size=other.size
        other.at=oldAt;other.size=oldSize
        view.rebuild()
        compare(Object.keys(view.pendingMoves).length,0)
        compare(view.testModel.get(0).wsid,2)
        compare(view.testModel.get(1).wsid,2)
    }
    function test_tiled_drop_ignores_floating_target() {
        var other=addTarget(1);other.floating=true;view.rebuild()
        dragOntoTarget(1)
        compare(view.compositor.commands.length,0)
    }

}
