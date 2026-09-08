// THROWAWAY screencopy spike (Task 8). Deleted before v2 lands.
// Run:  qs -p spike/shell.qml
// Renders a live ScreencopyView for every current toplevel so you can judge, per case,
// whether background/inactive/other-monitor windows capture real pixels (not black) and
// whether animating content stays live (not frozen). hasContent only means a buffer
// arrived — judge by eye, not by that flag.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 900
        implicitHeight: 600
        color: "#222"

        Flow {
            anchors.fill: parent
            spacing: 8
            padding: 8

            Repeater {
                model: ToplevelManager.toplevels

                Rectangle {
                    width: 280
                    height: 170
                    color: "#111"
                    border.color: "#555"

                    ScreencopyView {
                        id: cap
                        anchors.fill: parent
                        anchors.margins: 2
                        captureSource: modelData
                        live: true
                    }

                    Text {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.margins: 4
                        color: "#0f0"
                        font.pixelSize: 11
                        text: (modelData.appId || "?") + "  content=" + cap.hasContent
                    }
                }
            }
        }
    }
}
