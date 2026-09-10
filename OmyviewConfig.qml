import QtQuick
import Quickshell
import Quickshell.Io

// User settings: ~/.config/omarchy/omyview.json (optional, watched). Every key has a default
// here; a missing file, a parse error or an unknown key never changes behaviour.
QtObject {
    id: cfg
    property bool scrim: true

    readonly property string path: Quickshell.env("HOME") + "/.config/omarchy/omyview.json"

    function apply(raw) {
        var o = {}
        try { o = JSON.parse(String(raw || "")) || {} } catch (e) { o = {} }
        cfg.scrim = (typeof o.scrim === "boolean") ? o.scrim : true
    }

    property FileView file: FileView {
        path: cfg.path
        watchChanges: true
        printErrors: false
        onLoaded: cfg.apply(text())
        onFileChanged: reload()
        onLoadFailed: cfg.apply("")
    }
}
