import QtQuick
import Quickshell
import Quickshell.Io
import "logic.js" as Logic

// User settings: ~/.config/omarchy/omyview.json (optional, watched). Every key has a default
// (Logic.parseConfig); a missing file, a parse error or an unknown key never changes behaviour.
QtObject {
    id: cfg
    property bool scrim: true        // dim the desktop behind the picker
    property bool hint: true         // key hints under the workspace grid
    property string motion: "auto"   // "auto" follows Hyprland animations:enabled; "full" | "off"

    // Hyprland's own animation switch, probed once per open (async, cheap) and cached. A
    // probe that cannot be read counts as enabled (Logic.hyprAnimationsEnabled).
    property bool hyprAnimations: true
    readonly property string motionEffective: Logic.motionPolicy(motion, hyprAnimations)
    function probeMotion() { hyprProc.running = true }

    readonly property string path: Quickshell.env("HOME") + "/.config/omarchy/omyview.json"

    function apply(raw) {
        var o = Logic.parseConfig(raw)
        cfg.scrim = o.scrim
        cfg.hint = o.hint
        cfg.motion = o.motion
    }

    property FileView file: FileView {
        path: cfg.path
        watchChanges: true
        printErrors: false
        onLoaded: cfg.apply(text())
        onFileChanged: reload()
        onLoadFailed: cfg.apply("")
    }

    property Process hyprProc: Process {
        command: ["hyprctl", "-j", "getoption", "animations:enabled"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: cfg.hyprAnimations = Logic.hyprAnimationsEnabled(text)
        }
    }

    // Warm the cache so the very first open already follows the compositor.
    Component.onCompleted: probeMotion()
}
