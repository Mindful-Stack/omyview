import QtQuick
import QtTest

TestCase {
    id: tc
    name: "Scratchpad"
    when: windowShown
    width: 1200; height: 800; visible: true
    property var view
    property var mon
    // Hyprland allocates special ids dynamically; the fixture deliberately uses one that is NOT
    // -98 (the id on the dev machine) so every assertion on -2 proves the remap, not a coincidence.
    readonly property int scratchHyprId: -73   // lowercase: QML property names cannot start with a capital
    Component { id: overview; Overview {} }

    function client(addr, cls, title, x, floating) {
        return { address: addr, at: [x, 1500], size: [500, 400], floating: !!floating,
                 title: title, "class": cls, fullscreen: 0 }
    }
    function wsRow(id, clients, name) {
        return { id: id, name: name === undefined ? String(id) : name, monitor: mon,
                 toplevels: { values: clients.map(function (c) { return { lastIpcObject: c } }) } }
    }
    // ws1: 0xA chromium (tiled) · ws2: 0xB Slack (floating) · scratchpad: 0xS Bitwarden (floating)
    function seed(v, withScratch) {
        mon = { name: "TEST", x: 0, y: 1440, width: 1920, height: 1080,
                scale: 1, lastIpcObject: { reserved: [0, 26, 0, 0], transform: 0 } }
        v.compositor.monitors = { values: [mon] }
        v.compositor.focusedMonitor = mon
        v.compositor.focusedWorkspace = { id: 1 }
        var rows = [ wsRow(1, [client("0xA", "chromium", "Chromium", 100, false)]),
                     wsRow(2, [client("0xB", "Slack", "Slack", 100, true)]) ]
        if (withScratch !== false)
            rows.push(wsRow(scratchHyprId, [client("0xS", "Bitwarden", "Bitwarden", 900, true)], "special:scratchpad"))
        v.compositor.workspaces = { values: rows }
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
    function boxOf(wsId) {
        for (var i = 0; i < view.boxes.length; i++) if (view.boxes[i].workspaceId === wsId) return view.boxes[i]
        return null
    }
    function row(addr) {
        for (var i = 0; i < view.testModel.count; i++)
            if (view.testModel.get(i).address === addr) return view.testModel.get(i)
        return null
    }
    function type(s) { for (var i = 0; i < s.length; i++) keyClick(s.charAt(i)) }
    function ctrlS() { keyClick("s", Qt.ControlModifier) }
    function canvasItems(name) {
        var out = [], ch = view.testCanvas.children
        for (var i = 0; i < ch.length; i++) if (ch[i].objectName === name) out.push(ch[i])
        return out
    }

    // Distinguishes: the special workspace leaking into the layout by default (the pre-feature
    // exclusion broken), and a row keyed on Hyprland's id instead of the constant.
    function test_hidden_by_default_and_shown_by_ctrl_s_with_the_constant_id() {
        compare(boxOf(-2), null); compare(boxOf(scratchHyprId), null); compare(row("0xS"), null)
        ctrlS()
        verify(boxOf(-2) !== null, "the scratchpad box uses the constant id")
        compare(boxOf(scratchHyprId), null, "Hyprland's id never reaches the layout")
        compare(boxOf(-2).special, "scratchpad")
        compare(boxOf(-2).monitorName, "TEST")
        verify(row("0xS") !== null); compare(row("0xS").wsid, -2)
        ctrlS()
        compare(boxOf(-2), null); compare(row("0xS"), null)
    }
    // Distinguishes: the shown state surviving a close/open (spec: hidden on every open).
    function test_reopen_starts_hidden() {
        ctrlS(); verify(boxOf(-2) !== null)
        view.close(); wait(50); view.open(); wait(400)
        compare(view.scratchpadShown, false); compare(boxOf(-2), null)
    }
    // Distinguishes: Enter on the scratchpad dispatching a workspace focus by id (Hyprland has no
    // workspace -2) instead of the guarded show chunk, and the overlay staying open.
    function test_enter_on_the_scratchpad_box_shows_it_and_closes() {
        ctrlS()
        keyClick(Qt.Key_Down)                      // ws 1 → the row below: the scratchpad
        compare(view.selectedId, -2)
        keyClick(Qt.Key_Return)
        compare(view.compositor.commands.length, 1)
        var cmd = view.compositor.commands[0]
        verify(cmd.indexOf('workspace.toggle_special("scratchpad")') >= 0, "show chunk, got: " + cmd)
        verify(cmd.indexOf('get_active_special_workspace') >= 0, "guarded against hiding")
        verify(cmd.indexOf('workspace = "-2"') < 0)
        compare(view.opened, false)
    }
    // Distinguishes: a box click on the scratchpad going through the numeric jump.
    function test_click_on_the_empty_scratchpad_box_shows_it() {
        seed(view, false); ctrlS()                 // empty scratchpad: nothing but the box
        var b = boxOf(-2); verify(b !== null)
        var p = view.testCanvas.mapToItem(tc, b.x + b.w / 2, b.y + b.h / 2)
        mouseClick(tc, p.x, p.y, Qt.LeftButton)
        verify(view.compositor.commands[0].indexOf('toggle_special') >= 0)
        compare(view.opened, false)
    }
    // Distinguishes: the synthetic empty row missing when Hyprland reports no scratchpad.
    function test_empty_scratchpad_still_gets_a_row() {
        seed(view, false); view.rebuild()
        ctrlS()
        var b = boxOf(-2); verify(b !== null, "synthetic row")
        compare(b.occupied, false)
        compare(view.testModel.count, 2, "no tiles in it")
    }
    // Distinguishes: find matching scratchpad windows while hidden, or not matching them when shown.
    function test_find_matches_scratchpad_windows_only_while_shown() {
        type("bitwarden")
        compare(view.matches.length, 0)
        ctrlS()
        compare(view.matches.length, 1); compare(view.selectedMatchAddress, "0xS")
        compare(row("0xS").selectedMatch, true)
        ctrlS()
        compare(view.matches.length, 0)
        compare(view.query, "bitwarden", "toggling the row never touches the query")
    }
    // Distinguishes: a digit reaching the scratchpad (there is no digit for it) — "2" must jump
    // to workspace 2 with the row shown, exactly as without it.
    function test_digits_never_target_the_scratchpad() {
        ctrlS()
        keyClick("2")
        verify(view.compositor.commands[0].indexOf('workspace = "2"') >= 0)
        compare(view.opened, false)
    }
    // Distinguishes: labels for the scratchpad rendering "-2".
    function test_labels_and_hint() {
        compare(view.wsLabel(-2), "S"); compare(view.wsLabel(10), "0"); compare(view.wsLabel(3), "3")
        var hints = view.testHintModel, found = false
        for (var i = 0; i < hints.length; i++) if (hints[i].k === "ctrl+s") found = true
        verify(found, "hint row advertises ctrl+s")
    }
    // Distinguishes: the box selection lost when the row it sits on is hidden.
    function test_hiding_the_selected_row_moves_the_selection_to_a_real_box() {
        ctrlS(); keyClick(Qt.Key_Down); compare(view.selectedId, -2)
        ctrlS()
        verify(view.selectedId !== -2 && view.selectedId !== -1, "selection lands on a workspace")
    }
    // Carry-forward (Task 1 review): a scratchpad workspace whose ws.monitor is null (Hyprland
    // reports one on a monitor that no longer exists, or none at all) must not be silently
    // dropped from the tile layout — buildInput() falls back to the focused monitor's name for
    // the scratchpad record specifically, instead of the normal "?" fallback that layout()
    // treats as unknown and skips.
    function test_scratchpad_with_null_monitor_still_gets_its_tile() {
        var rows = [ wsRow(1, [client("0xA", "chromium", "Chromium", 100, false)]) ]
        var scratch = wsRow(scratchHyprId, [client("0xS", "Bitwarden", "Bitwarden", 900, true)], "special:scratchpad")
        scratch.monitor = null
        rows.push(scratch)
        view.compositor.workspaces = { values: rows }
        ctrlS()
        verify(row("0xS") !== null, "the scratchpad tile survives a null ws.monitor")
    }
    // Distinguishes: buildInput admitting ANY negative-id workspace while shown (the unnamed
    // `special`, which holds share-picker popups, would join the row and steal the synthetic
    // scratchpad's place). Only the workspace NAMED special:scratchpad may enter.
    function test_only_the_named_special_enters_the_layout() {
        var rows = [ wsRow(1, [client("0xA", "chromium", "Chromium", 100, false)]),
                     wsRow(-99, [client("0xP", "Popup", "Share popup", 300, true)], "special"),
                     wsRow(scratchHyprId, [client("0xS", "Bitwarden", "Bitwarden", 900, true)], "special:scratchpad") ]
        view.compositor.workspaces = { values: rows }
        ctrlS()
        compare(row("0xP"), null, "the unnamed special must not enter the layout")
        verify(row("0xS") !== null)
        compare(boxOf(-2).occupied, true, "the real scratchpad, not a synthetic row")
    }
    // Distinguishes: the chip visibility ignoring `special` (single-monitor mode would show no
    // label on the row) and the chip text falling through to the monitor branch.
    function test_scratchpad_row_carries_its_chip_in_single_monitor_mode() {
        ctrlS()
        var chips = canvasItems("monitorChip"), shown = chips.filter(function (c) { return c.visible })
        compare(shown.length, 1, "only the scratchpad chip is visible with one monitor")
        compare(shown[0].text, "SCRATCHPAD")
    }
    // Distinguishes: a card narrower than its hint row (six entries spill onto the scrim).
    function test_card_is_at_least_as_wide_as_the_hint_row() {
        verify(view.testCard.width + 0.5 >= view.testHintRow.implicitWidth + 2 * view.testCard.pad)
    }
}
