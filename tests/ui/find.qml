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
    // Distinguishes: a window on a special workspace leaking into the match list (the spec
    // excludes the scratchpad by excluding special workspaces from the input).
    function test_special_workspace_windows_never_match() {
        view.compositor.workspaces.values.push(wsRow(-99, [client("0xS", "Bitwarden", "secretpad", 100)]))
        view.rebuild()
        type("secretpad")
        compare(view.matches.length, 0)
    }
}
