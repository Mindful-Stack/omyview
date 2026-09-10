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
        // The grab point is the ghost's scale origin, so it is invariant under the in-transit
        // shrink animation and is exactly the point that must stay under the pointer.
        var visual=t.mapToItem(tc,t.grabX,t.grabY)
        wait(100)
        verify(view.testFlick.contentY > before, "Holding near the edge must scroll")
        var after=t.mapToItem(tc,t.grabX,t.grabY)
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
    // A tiled drop replays a native drag-and-drop as ONE atomic Lua dispatch (float → cursor →
    // un-float); nothing else is sent, and the tile holds the drop point until the compositor's
    // fresh geometry differs from the pre-drop one.
    function test_tiled_drop_replays_native_insert_in_one_dispatch() {
        addTarget(1)
        dragOntoTarget(1)
        compare(view.compositor.commands.length,1)
        var cmd=view.compositor.commands[0]
        verify(cmd.indexOf('hl.dsp.window.float(')>=0)
        verify(cmd.indexOf('hl.dsp.cursor.move(')>=0)
        verify(cmd.indexOf('"address:0x123"')>=0)
        verify(cmd.indexOf('smart_split = true')>=0)
        verify(cmd.indexOf('window.swap')<0)
        var pending=view.pendingMoves[client.address]
        verify(pending !== undefined && pending.pos === null)
        var shown=tile().x
        view.rebuild()
        compare(tile().x,shown,"Stale geometry must not undo the optimistic drop")
        client.at=[1000,1540]; view.rebuild()   // the compositor re-tiled it
        verify(view.pendingMoves[client.address] === undefined)
        compare(view.compositor.commands.length,1,"No follow-up dispatch after the atomic insert")
    }
    function test_tiled_drag_previews_insertion_side() {
        addTarget(1)
        var source=view.testModel.get(0), target=view.testModel.get(1)
        var t=tile(), p=t.mapToItem(tc,t.width/2,t.height/2)
        mousePress(tc,p.x,p.y,Qt.LeftButton)
        mouseMove(tc,p.x+12,p.y+2,20)
        // hover the right quarter of the target tile, vertically centred → "right"
        var dx=(target.wx+target.ww*0.9)-(source.wx+source.ww/2)
        var dy=(target.wy+target.wh/2)-(source.wy+source.wh/2)
        mouseMove(tc,p.x+dx,p.y+dy,20)
        compare(view.dropTargetAddress,"0x456")
        compare(view.dropTargetSide,"right")
        // and the top edge → "top"
        mouseMove(tc,p.x+(target.wx+target.ww/2)-(source.wx+source.ww/2),p.y+(target.wy+2)-(source.wy+source.wh/2),20)
        compare(view.dropTargetSide,"top")
        view.close()
        mouseRelease(tc,p.x+dx,p.y+dy,Qt.LeftButton)
        compare(view.dropTargetSide,"")
    }
    function test_tiled_cross_workspace_inserts_in_one_dispatch() {
        addTarget(2)
        dragOntoTarget(2)
        compare(view.compositor.commands.length,1)
        var cmd=view.compositor.commands[0]
        verify(cmd.indexOf('workspace = "2"')>=0)
        verify(cmd.indexOf('hl.dsp.window.float(')>=0)
        compare(view.testModel.get(0).wsid,2,"tile shows the target workspace at once")
        var ws=view.compositor.workspaces.values
        ws[0].toplevels.values=[]
        client.at=[400,1540]
        ws[1].toplevels.values.push({lastIpcObject:client})
        view.rebuild()
        compare(Object.keys(view.pendingMoves).length,0)
        compare(view.compositor.commands.length,1,"No follow-up dispatch after the atomic insert")
        compare(view.testModel.get(0).wsid,2)
    }
    function test_lone_tiled_window_dropped_in_own_workspace_snaps_back() {
        var other=addTarget(1);other.floating=true;view.rebuild()
        var before=tile().x
        dragOntoTarget(1)
        compare(view.compositor.commands.length,0)
        compare(tile().x,before)
    }
    function test_ghost_shrinks_and_fades_while_dragging_and_restores() {
        var t=tile(), p=t.mapToItem(tc,t.width/2,t.height/2)
        mousePress(tc,p.x,p.y,Qt.LeftButton)
        mouseMove(tc,p.x+12,p.y+2,20)
        mouseMove(tc,p.x+40,p.y+20,20)
        wait(200)
        fuzzyCompare(t.opacity,0.6,0.02,"translucent in transit")
        fuzzyCompare(t.ghostScale,0.6,0.02,"shrunk in transit")
        mouseRelease(tc,p.x+40,p.y+20,Qt.LeftButton)
        wait(200)
        fuzzyCompare(t.opacity,1,0.02,"opaque after release")
        fuzzyCompare(t.ghostScale,1,0.02,"full size after release")
    }
    // The pointer picks the target and side, not the ghost's centre: grab the tile at its
    // right edge (so the ghost's centre trails well left of the pointer, further still by the
    // drag threshold) and point at the target's RIGHT quarter — centre-based targeting would
    // say "left".
    function test_pointer_not_ghost_centre_picks_target_and_side() {
        addTarget(1)
        var target=view.testModel.get(1), t=tile()
        var g=t.mapToItem(tc,t.width-4,4)
        mousePress(tc,g.x,g.y,Qt.LeftButton)
        mouseMove(tc,g.x+12,g.y+2,20)
        var goal=view.testCanvas.mapToItem(tc,target.wx+target.ww*0.9,target.wy+target.wh/2)
        mouseMove(tc,goal.x,goal.y,20)
        compare(view.dropTargetAddress,"0x456")
        compare(view.dropTargetSide,"right")
        verify(t.x+t.width/2 < target.wx+target.ww/2, "ghost centre is on the target's left half")
        view.close()
        mouseRelease(tc,goal.x,goal.y,Qt.LeftButton)
    }
    // Re-grabbing while the 100ms release animation is still running must not shift the tile:
    // the Scale origin moves to the new grab point while the scale is still on its way back
    // to 1, which would displace the rendered tile by (grab − oldOrigin)·(1 − scale).
    function test_regrab_during_release_animation_keeps_grab_point_under_pointer() {
        var t=tile(), g=t.mapToItem(tc,t.width-4,4)   // first grab: right edge
        mousePress(tc,g.x,g.y,Qt.LeftButton)
        mouseMove(tc,g.x+12,g.y+2,20)
        mouseMove(tc,g.x+30,g.y+10,20)
        mouseRelease(tc,g.x+30,g.y+10,Qt.LeftButton)
        wait(30)                                        // release animation in flight
        verify(t.ghostScale < 0.98, "precondition: still animating back to full size")
        var g2=t.mapToItem(tc,4,4)                      // second grab: left edge, as rendered now
        mousePress(tc,g2.x,g2.y,Qt.LeftButton)
        var p=t.mapToItem(tc,t.grabX,t.grabY)
        fuzzyCompare(p.x,g2.x,1,"grab point under the pointer right after the press")
        fuzzyCompare(p.y,g2.y,1)
        mouseMove(tc,g2.x+12,g2.y+2,20)                 // activates the drag
        var off=t.mapToItem(tc,t.grabX,t.grabY)
        var offX=off.x-(g2.x+12), offY=off.y-(g2.y+2)
        mouseMove(tc,g2.x+40,g2.y+16,20)
        wait(120)                                       // let the shrink animation finish
        var after=t.mapToItem(tc,t.grabX,t.grabY)
        fuzzyCompare(after.x-(g2.x+40),offX,1,"no jump-back when the drag activates or animates")
        fuzzyCompare(after.y-(g2.y+16),offY,1)
        view.close()
        mouseRelease(tc,g2.x+40,g2.y+16,Qt.LeftButton)
    }
    // A drag that never leaves the window's own slot is a no-op on release, so it must not
    // preview an insertion into another tile either: preview and release share one check.
    function test_short_drag_inside_own_slot_previews_nothing_and_dispatches_nothing() {
        addTarget(1)
        var t=tile(), p=t.mapToItem(tc,t.width/2,t.height/2)
        mousePress(tc,p.x,p.y,Qt.LeftButton)
        mouseMove(tc,p.x+12,p.y+2,20)
        mouseMove(tc,p.x+20,p.y+6,20)
        compare(view.dropTargetWs,1,"still over its own workspace")
        compare(view.dropTargetAddress,"","no anchor while inside the own slot")
        compare(view.dropTargetSide,"")
        mouseRelease(tc,p.x+20,p.y+6,Qt.LeftButton)
        compare(view.compositor.commands.length,0,"release must not dispatch")
        verify(view.pendingMoves[client.address] === undefined)
    }
    // The dispatched Lua names the anchor and the side the preview showed; the point is
    // measured inside the compositor after detaching, not taken from the overview's layout.
    function test_tiled_drop_dispatches_previewed_anchor_and_side() {
        addTarget(1)
        var target=view.testModel.get(1), t=tile(), p=t.mapToItem(tc,t.width/2,t.height/2)
        mousePress(tc,p.x,p.y,Qt.LeftButton)
        mouseMove(tc,p.x+12,p.y+2,20)
        var goal=view.testCanvas.mapToItem(tc,target.wx+target.ww/2,target.wy+target.wh-2)
        mouseMove(tc,goal.x,goal.y,20)
        compare(view.dropTargetAddress,"0x456")
        compare(view.dropTargetSide,"bottom")
        mouseRelease(tc,goal.x,goal.y,Qt.LeftButton)
        compare(view.compositor.commands.length,1)
        var cmd=view.compositor.commands[0]
        verify(cmd.indexOf('"address:0x456"')>=0,"anchor identity is passed to Lua")
        verify(cmd.indexOf('== "bottom" then')>=0,"side is passed to Lua")
        verify(cmd.indexOf('hl.get_window(anchorSel)')>=0,"anchor geometry is measured in Lua")
    }
    function test_grouped_tiled_window_is_not_retiled() {
        addTarget(1); client.grouped=["0x123"]; view.rebuild()
        dragOntoTarget(1)
        compare(view.compositor.commands.length,0)
    }
    // Hover a floating drag over a workspace whose only window is fullscreen (its preview fills
    // the well, hiding the well tint): the drop wash must show on that box, above the preview.
    function test_floating_drag_over_fullscreen_workspace_shows_wash_above_preview() {
        client.floating=true
        var full={address:"0x456",at:[0,1440],size:[1920,1080],floating:false,
                  title:"Full","class":"test",fullscreen:1}
        view.compositor.workspaces.values[1].toplevels.values.push({lastIpcObject:full})
        view.rebuild()
        var wash=view.testDropWash, b=view.boxes[1]
        verify(!wash.visible,"no wash before a drag")
        var t=tile(), p=t.mapToItem(tc,t.width/2,t.height/2)
        mousePress(tc,p.x,p.y,Qt.LeftButton)
        mouseMove(tc,p.x+12,p.y+2,20)
        var goal=view.testCanvas.mapToItem(tc,b.x+b.w/2,b.y+b.h/2)
        mouseMove(tc,goal.x,goal.y,20)
        compare(view.dropTargetWs,2)
        verify(wash.visible,"wash shows over the target box")
        compare(wash.x,b.x); compare(wash.y,b.y); compare(wash.width,b.w)
        var children=view.testCanvas.children, fullTile=null
        for (var i=0;i<children.length;i++)
            if (children[i].model && children[i].model.address==="0x456") fullTile=children[i]
        verify(fullTile!==null && wash.z > fullTile.z,"wash stacks above the fullscreen preview")
        view.close()
        mouseRelease(tc,goal.x,goal.y,Qt.LeftButton)
        verify(!wash.visible,"wash gone after release")
    }
    // A tiled drag with an insertion preview keeps the cue on the anchor tile: no wash.
    function test_tiled_drag_with_insertion_preview_shows_no_wash() {
        addTarget(1)
        var target=view.testModel.get(1), t=tile(), p=t.mapToItem(tc,t.width/2,t.height/2)
        mousePress(tc,p.x,p.y,Qt.LeftButton)
        mouseMove(tc,p.x+12,p.y+2,20)
        var goal=view.testCanvas.mapToItem(tc,target.wx+target.ww*0.9,target.wy+target.wh/2)
        mouseMove(tc,goal.x,goal.y,20)
        compare(view.dropTargetAddress,"0x456")
        verify(!view.testDropWash.visible,"insertion preview replaces the wash")
        view.close()
        mouseRelease(tc,goal.x,goal.y,Qt.LeftButton)
    }
    function canvasItems(name) {
        var out=[], children=view.testCanvas.children
        for (var i=0;i<children.length;i++) if (children[i].objectName===name) out.push(children[i])
        return out
    }
    // Every workspace carries a number badge stacked above its previews; the big numeral
    // shows only on empty workspaces, where nothing can hide it.
    function test_badge_on_every_box_above_tiles_numeral_only_when_empty() {
        var badges=canvasItems("wsBadge")
        compare(badges.length, view.boxes.length, "one badge per workspace box")
        var t=tile()
        for (var i=0;i<badges.length;i++) {
            var b=view.boxes[i]
            verify(badges[i].visible)
            verify(badges[i].x >= b.x && badges[i].y >= b.y, "badge sits inside its box")
            verify(badges[i].z > t.z, "badge stacks above a resting tile")
        }
        var numerals=[], boxes=view.testCanvas.children
        for (var j=0;j<boxes.length;j++) {
            var kids=boxes[j].children||[]
            for (var k=0;k<kids.length;k++) if (kids[k].objectName==="wsNumeral") numerals.push(kids[k])
        }
        compare(numerals.length, 2)
        verify(!numerals[0].visible, "occupied workspace 1 hides the big numeral")
        verify(numerals[1].visible, "empty workspace 2 shows the big numeral")
    }

}
