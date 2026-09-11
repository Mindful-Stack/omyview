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
}
