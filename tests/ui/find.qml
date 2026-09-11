import QtQuick
import QtTest

TestCase {
    id: tc
    name: "Find"
    when: windowShown
    width: 1200; height: 800; visible: true
    property var view
    property var mon
    Component { id: overview; Overview {} }

    // One monitor at origin (0,1440) like drag.qml; workspaces 1..3 with named windows:
    //   ws1: 0xA class "chromium" title "Slack alternatives - Chromium"
    //   ws2: 0xB class "Slack"    title "Slack"
    //   ws3: 0xC class "foot"     title "daniel@host: ~"
    function client(addr, cls, title, x) {
        return { address: addr, at: [x, 1500], size: [500, 400], floating: false,
                 title: title, "class": cls, fullscreen: 0 }
    }
    function wsRow(id, clients) {
        return { id: id, monitor: mon,
                 toplevels: { values: clients.map(function (c) { return { lastIpcObject: c } }) } }
    }
    function seed(v) {
        mon = { name: "TEST", x: 0, y: 1440, width: 1920, height: 1080,
                scale: 1, lastIpcObject: { reserved: [0, 26, 0, 0], transform: 0 } }
        v.compositor.monitors = { values: [mon] }
        v.compositor.focusedMonitor = mon
        v.compositor.focusedWorkspace = { id: 1 }
        v.compositor.workspaces = { values: [
            wsRow(1, [client("0xA", "chromium", "Slack alternatives - Chromium", 100)]),
            wsRow(2, [client("0xB", "Slack", "Slack", 100)]),
            wsRow(3, [client("0xC", "foot", "daniel@host: ~", 100)])
        ] }
    }
    function init() {
        view = createTemporaryObject(overview, tc)
        verify(view !== null)
        view.motion.scale = 0
        seed(view)
        view.open()
        wait(400)
    }
    function cleanup() { view.close() }
    function row(addr) {
        for (var i = 0; i < view.testModel.count; i++)
            if (view.testModel.get(i).address === addr) return view.testModel.get(i)
        fail("no tile row for " + addr)
    }
    function type(s) { for (var i = 0; i < s.length; i++) keyClick(s.charAt(i)) }

    // Distinguishes: a fixture where keyClick never reaches keyCatcher (focus lost to the
    // TestCase or a child). Escape on an empty query closes — an effect only Keys.onPressed
    // can produce, so a pass proves dispatch, not a property the test set itself.
    function test_keys_reach_the_catcher() {
        verify(view.testKeys.activeFocus, "keyCatcher must hold active focus after open()")
        compare(view.opened, true)
        keyClick(Qt.Key_Escape)
        compare(view.opened, false, "Escape must close via the key handler")
    }

    // Distinguishes: a fixture where keyClick("3") (the string path QTest::asciiToKey takes,
    // which every type() call uses) does not reach Keys.onPressed. A digit with an empty query
    // jumps and closes — an effect only the handler produces.
    function test_character_keys_reach_the_catcher() {
        type("3")
        compare(view.opened, false, "a digit typed as a string must reach Keys.onPressed")
        compare(view.compositor.commands.length, 1)
        verify(view.compositor.commands[0].indexOf('workspace = "3"') >= 0)
    }

    // Distinguishes: a handler that leaves letters unhandled, or one that appends control
    // text (Backspace would then grow the query instead of shrinking it).
    function test_typing_builds_and_backspace_edits_the_query() {
        type("sla")
        compare(view.query, "sla")
        keyClick(Qt.Key_Backspace)
        compare(view.query, "sl")
        keyClick(Qt.Key_Backspace, Qt.ControlModifier)
        compare(view.query, "", "Ctrl+Backspace clears")
        compare(view.opened, true, "editing never closes")
    }
    // Distinguishes: roles computed from something other than findMatches (all true / all
    // false), and a selectedMatch that is not rank 1. For "slack": class Slack (0xB) beats the
    // title-only chromium tab (0xA); foot (0xC) does not match.
    function test_query_sets_tile_roles() {
        type("slack")
        compare(row("0xB").matched, true);  compare(row("0xB").selectedMatch, true)
        compare(row("0xA").matched, true);  compare(row("0xA").selectedMatch, false)
        compare(row("0xC").matched, false); compare(row("0xC").selectedMatch, false)
        compare(view.matches.length, 2)
    }
    // Distinguishes: Escape closing while a query is active (no "unwind"), and roles left
    // stale after the query clears.
    function test_escape_unwinds_then_closes() {
        type("foot")
        compare(row("0xC").matched, true)
        keyClick(Qt.Key_Escape)
        compare(view.query, "")
        compare(view.opened, true, "first Escape only clears the query")
        compare(row("0xC").matched, false)
        compare(row("0xC").selectedMatch, false)
        keyClick(Qt.Key_Escape)
        compare(view.opened, false, "second Escape closes")
    }
    // Distinguishes: digits always jumping (query would stay "s") or never jumping.
    function test_digit_jumps_only_while_query_is_empty() {
        type("s")
        keyClick("2")
        compare(view.query, "s2")
        compare(view.compositor.commands.length, 0, "a digit inside a query must not dispatch")
        keyClick(Qt.Key_Backspace); keyClick(Qt.Key_Backspace)
        compare(view.query, "")
        keyClick("2")
        verify(view.compositor.commands.some(function (c) { return c.indexOf('workspace = "2"') >= 0 }),
               "a digit with an empty query jumps")
        compare(view.opened, false)
    }
    // Distinguishes: Enter jumping to the workspace (spec: it must focus the *window*), and
    // Enter with a query but no match doing something.
    function test_enter_focuses_the_selected_window() {
        type("foot")
        keyClick(Qt.Key_Return)
        compare(view.compositor.commands.length, 1)
        verify(view.compositor.commands[0].indexOf('window = "address:0xC"') >= 0,
               "Enter must dispatch a window focus, got: " + view.compositor.commands[0])
        compare(view.opened, false)
    }
    function test_enter_with_no_match_does_nothing() {
        type("zzz")
        compare(view.matches.length, 0)
        keyClick(Qt.Key_Return)
        compare(view.compositor.commands.length, 0)
        compare(view.opened, true)
    }
    // Distinguishes: a space starting a query (would set query " " and dim everything).
    function test_space_does_not_start_a_query() {
        keyClick(Qt.Key_Space)
        compare(view.query, "")
        type("sl"); keyClick(Qt.Key_Space)
        compare(view.query, "sl ")
    }
    // Distinguishes: bare-letter handling swallowing chords. Ctrl+S is reserved: it must
    // neither type nor act.
    function test_ctrl_chords_are_ignored() {
        keyClick("s", Qt.ControlModifier)
        compare(view.query, "")
        compare(view.compositor.commands.length, 0)
        compare(view.opened, true)
    }
    // Distinguishes: a chord guard placed after the action branches (Ctrl+2 would jump and
    // close, Alt+Enter would accept, Ctrl+Tab would cycle). Only Ctrl+Backspace is a chord
    // with a meaning.
    function test_modified_action_keys_are_ignored() {
        keyClick("2", Qt.ControlModifier)
        compare(view.compositor.commands.length, 0, "Ctrl+2 must not jump")
        compare(view.opened, true)
        type("slack")                                   // ranked: 0xB, 0xA
        keyClick(Qt.Key_Tab, Qt.ControlModifier)
        compare(view.selectedMatchAddress, "0xB", "Ctrl+Tab must not cycle")
        keyClick(Qt.Key_Return, Qt.AltModifier)
        compare(view.compositor.commands.length, 0, "Alt+Enter must not accept")
        compare(view.opened, true)
        keyClick(Qt.Key_Escape, Qt.MetaModifier)
        compare(view.query, "slack", "Meta+Esc must not clear")
        keyClick(Qt.Key_Backspace, Qt.ControlModifier)
        compare(view.query, "", "Ctrl+Backspace is the one chord that acts")
    }
    // Distinguishes: a kept-loaded overlay reopening with the previous query.
    function test_reopen_starts_with_an_empty_query() {
        type("foot")
        view.close(); wait(50)
        view.open(); wait(400)
        compare(view.query, "")
        compare(view.matches.length, 0)
        compare(row("0xC").matched, false)
    }
    // Distinguishes: a background rebuild scrolling the viewport when the selected match did not
    // change (any compositor event would yank the view back onto the match every settle tick).
    function test_background_rebuild_keeps_the_scroll_position() {
        type("slack")
        view.testFlick.contentY = 40
        view.rebuild()
        compare(view.selectedMatchAddress, "0xB")
        compare(view.testFlick.contentY, 40, "same match, no scroll")
    }
    // Distinguishes: a window on a special workspace leaking into the match list (the spec
    // excludes the scratchpad by excluding special workspaces from the input). Positive control
    // first: the same window matches when it is on a normal workspace, so a broken matcher
    // cannot pass this test by matching nothing at all.
    function test_special_workspace_windows_never_match() {
        var special = wsRow(4, [client("0xS", "Bitwarden", "secretpad", 100)])
        view.compositor.workspaces.values.push(special)
        view.rebuild()
        type("secretpad")
        compare(view.matches.length, 1, "positive control: on a normal workspace it matches")
        keyClick(Qt.Key_Escape)
        special.id = -99
        view.rebuild()
        type("secretpad")
        compare(view.matches.length, 0, "on a special workspace it is not in the input at all")
    }

    function boxOf(wsId) {
        for (var i = 0; i < view.boxes.length; i++) if (view.boxes[i].workspaceId === wsId) return view.boxes[i]
        fail("no box for workspace " + wsId)
    }
    // Distinguishes: Tab not cycling, cycling not wrapping, Shift+Tab going forward, and the
    // frame not following the match's workspace.
    function test_cycle_wraps_and_moves_the_frame() {
        type("slack")                                  // ranked: 0xB (ws2), 0xA (ws1)
        compare(view.selectedId, 2)
        keyClick(Qt.Key_Tab)
        compare(view.selectedMatchAddress, "0xA"); compare(view.selectedId, 1)
        keyClick(Qt.Key_Tab)
        compare(view.selectedMatchAddress, "0xB", "wraps to the first")
        keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
        compare(view.selectedMatchAddress, "0xA", "Shift+Tab goes back")
        keyClick(Qt.Key_Down)
        compare(view.selectedMatchAddress, "0xB", "arrows cycle too while a query is active")
        compare(row("0xB").selectedMatch, true); compare(row("0xA").selectedMatch, false)
    }
    // Distinguishes: the pre-fix rule "keep the selected address if it still matches" on a
    // query EDIT. Seed: "sa" (0xP) and "xsa" (0xQ). For "s" 0xP ranks first (word start);
    // Tab selects 0xQ; typing "a" keeps 0xQ matching but 0xP is rank 1 again and must win.
    function test_query_edit_always_selects_rank_one() {
        view.compositor.workspaces.values = [
            wsRow(1, [client("0xP", "sa", "", 100)]),
            wsRow(2, [client("0xQ", "xsa", "", 100)])
        ]
        view.rebuild()
        type("s")
        compare(view.selectedMatchAddress, "0xP")
        keyClick(Qt.Key_Tab)
        compare(view.selectedMatchAddress, "0xQ")
        type("a")
        compare(view.matches.length, 2, "both still match 'sa'")
        compare(view.selectedMatchAddress, "0xP", "an edit re-selects rank 1")
    }
    // Distinguishes: a rebuild applying the edit rule (would snap back to rank 1).
    function test_rebuild_keeps_the_selected_address() {
        type("slack")
        keyClick(Qt.Key_Tab)
        compare(view.selectedMatchAddress, "0xA")
        view.rebuild()
        compare(view.selectedMatchAddress, "0xA")
        compare(row("0xA").selectedMatch, true)
    }
    // Successor rule. Seed three matches w1, w2, w3 (classes "w1".."w3", ranked in order:
    // equal scores keep input order). Remove the selected one at middle / last / sole.
    function seedThree() {
        view.compositor.workspaces.values = [
            wsRow(1, [client("0x1", "w1", "", 100)]),
            wsRow(2, [client("0x2", "w2", "", 100)]),
            wsRow(3, [client("0x3", "w3", "", 100)])
        ]
        view.rebuild()
    }
    function removeWorkspace(id) {
        view.compositor.workspaces.values = view.compositor.workspaces.values.filter(
            function (w) { return w.id !== id })
        view.rebuild()
    }
    // Distinguishes: "else 0" (would select 0x1) from the clamped old index (new 2nd = 0x3).
    function test_removed_middle_match_selects_its_successor() {
        seedThree(); type("w")
        keyClick(Qt.Key_Tab); compare(view.selectedMatchAddress, "0x2")
        removeWorkspace(2)
        compare(view.matches.length, 2)
        compare(view.selectedMatchAddress, "0x3")
        compare(view.selectedId, 3)
    }
    // Distinguishes: an unclamped index (out of range → no selection) from the new last.
    function test_removed_last_match_selects_new_last() {
        seedThree(); type("w")
        keyClick(Qt.Key_Tab); keyClick(Qt.Key_Tab); compare(view.selectedMatchAddress, "0x3")
        removeWorkspace(3)
        compare(view.matches.length, 2)
        compare(view.selectedMatchAddress, "0x2")
    }
    // Distinguishes: a stale selectedMatchAddress or a query that gets cleared by the rebuild.
    function test_removed_sole_match_leaves_no_selection_but_keeps_the_query() {
        seedThree(); type("w3")
        compare(view.matches.length, 1); compare(view.selectedMatchAddress, "0x3")
        removeWorkspace(3)
        compare(view.matches.length, 0)
        compare(view.matchIndex, -1)
        compare(view.selectedMatchAddress, "")
        compare(view.query, "w3")
    }
    // Distinguishes: restoring via rebuild()'s nearest-position rule (would land on ws 3,
    // the box that took ws 2's position) instead of the focused workspace (ws 1).
    function test_clear_restores_focused_workspace_when_original_is_gone() {
        keyClick(Qt.Key_Right)                          // box selection: ws 2
        compare(view.selectedId, 2)
        type("foot")                                    // match on ws 3
        compare(view.selectedId, 3)
        removeWorkspace(2)
        keyClick(Qt.Key_Escape)
        compare(view.query, "")
        compare(view.selectedId, 1, "focused workspace, not the nearest surviving position")
    }
    function test_clear_restores_the_pre_query_workspace() {
        keyClick(Qt.Key_Right)
        compare(view.selectedId, 2)
        type("foot")
        compare(view.selectedId, 3)
        keyClick(Qt.Key_Escape)
        compare(view.selectedId, 2)
    }
    // Visibility on an overflowing layout: 40 workspaces on one monitor (8 rows of 5) exceed
    // the 736 px card. The test asserts the overflow as a precondition so a layout change
    // that stops overflowing fails loudly instead of passing vacuously.
    function seedOverflow() {
        var rows = []
        for (var i = 1; i <= 40; i++)
            rows.push(wsRow(i, i === 40 ? [client("0xN", "needle", "needle", 100)]
                              : i === 1 ? [client("0xH", "hay", "hay", 100)] : []))
        view.compositor.workspaces.values = rows
        view.rebuild()
        verify(view.testFlick.contentHeight > view.testFlick.height + 100, "fixture must overflow")
    }
    function boxVisible(wsId) {
        var b = boxOf(wsId), f = view.testFlick
        return b.y >= f.contentY - 0.5 && b.y + b.h <= f.contentY + f.height + 0.5
    }
    // Distinguishes: moving selectedIndex without ensureSelectedVisible() (frame offscreen).
    function test_typing_scrolls_the_match_into_view() {
        seedOverflow()
        verify(!boxVisible(40), "ws 40 starts out of view")
        type("needle")
        compare(view.selectedId, 40)
        verify(boxVisible(40), "typing must scroll the match into view")
    }
    // "e" matches "edge" (ws 1, rank 1: word-start 'e' and class bonus, shorter) and "needle"
    // (ws 40). Tab moves from the visible top row to the last row; it must scroll.
    function test_cycling_scrolls_into_view() {
        seedOverflow()
        view.compositor.workspaces.values[0].toplevels.values.push({ lastIpcObject: client("0xE", "edge", "edge", 700) })
        view.rebuild()
        type("e")
        compare(view.matches.length, 2)
        compare(view.selectedId, 1); verify(boxVisible(1)); verify(!boxVisible(40))
        keyClick(Qt.Key_Tab)
        compare(view.selectedId, 40)
        verify(boxVisible(40), "cycling must scroll the new selection into view")
        keyClick(Qt.Key_Tab)
        compare(view.selectedId, 1)
        verify(boxVisible(1), "and back")
    }
    function test_restore_scrolls_the_pre_query_box_into_view() {
        seedOverflow()
        for (var i = 0; i < 7; i++) keyClick(Qt.Key_Down)   // walk the selection to the last row
        compare(view.selectedId, 36)
        verify(boxVisible(36))
        type("hay")                                     // match on ws 1: scrolls to the top
        compare(view.selectedId, 1); verify(boxVisible(1)); verify(!boxVisible(36))
        keyClick(Qt.Key_Escape)
        compare(view.selectedId, 36)
        verify(boxVisible(36), "restoring must scroll the pre-query box into view")
    }
    // Task 4 review carry-forward: rematchAfterRebuild() must scroll when the rebuild changes
    // the selected match (only a kept match suppresses the scroll). Seed the overflow layout
    // with a second matching window "edge" in the top row so "e" matches both edge (rank 1,
    // ws 1) and needle (ws 40); remove edge so the successor (needle) is the new match, which
    // sits in the last row and must be scrolled into view. Fails if followMatch is ever called
    // with `false` unconditionally.
    function test_rebuild_that_changes_the_match_scrolls_to_it() {
        seedOverflow()
        view.compositor.workspaces.values[0].toplevels.values.push({ lastIpcObject: client("0xE", "edge", "edge", 700) })
        view.rebuild()
        type("e")
        compare(view.matches.length, 2)
        compare(view.selectedMatchAddress, "0xE"); compare(view.selectedId, 1)
        verify(boxVisible(1)); verify(!boxVisible(40))
        view.compositor.workspaces.values[0].toplevels.values =
            view.compositor.workspaces.values[0].toplevels.values.filter(
                function (t) { return t.lastIpcObject.address !== "0xE" })
        view.rebuild()
        compare(view.matches.length, 1)
        compare(view.selectedMatchAddress, "0xN")
        compare(view.selectedId, 40)
        verify(boxVisible(40), "a rebuild that changes the match must scroll to it")
    }
}
