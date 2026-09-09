import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

Item {
    id: tile
    // set by the caller:
    property var handle: null            // wl Toplevel, or null
    property string cls: ""
    property string capMode: "live"      // "live" | "snapshot" | "icon"
    property color borderColor: "#888"
    property color bg: "#1a1a1a"
    property color fg: "#ddd"
    property string title: ""
    property bool dragging: false        // set by Overview during a drag to suppress hover-zoom

    readonly property bool wantCapture: handle !== null && capMode !== "icon"
    readonly property string iconUrl: Quickshell.iconPath(String(cls).toLowerCase(), true)

    HoverHandler { id: hh; enabled: !tile.dragging }
    scale: hh.hovered ? 1.05 : 0.95
    transformOrigin: Item.Center
    z: hh.hovered ? 10 : 0
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }

    ClippingRectangle {
        anchors.fill: parent
        color: tile.bg
        radius: 6
        border.width: 1
        border.color: tile.borderColor

        ScreencopyView {
            id: cap
            anchors.fill: parent
            visible: tile.wantCapture && cap.hasContent
            captureSource: tile.wantCapture ? tile.handle : null
            live: tile.capMode === "live"
        }

        // icon fallback: shown when not capturing, or until the first frame arrives
        Image {
            anchors.centerIn: parent
            visible: !cap.visible && tile.iconUrl.length > 0
            source: tile.iconUrl
            width: Math.min(40, parent.width * 0.5)
            height: width
            fillMode: Image.PreserveAspectFit
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
        }
        Text {
            anchors.centerIn: parent
            visible: !cap.visible && tile.iconUrl.length === 0
            text: String(tile.cls).substring(0, 1).toUpperCase()
            color: tile.fg
            font.pixelSize: Math.min(20, parent.height * 0.5)
        }
    }

    // title label (bottom), fades in on hover
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: lbl.implicitHeight + 4
        color: Qt.rgba(0, 0, 0, 0.55)
        visible: hh.hovered && lbl.text.length > 0
        opacity: hh.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
        Text {
            id: lbl; anchors.centerIn: parent; color: "#fff"; font.pixelSize: 10
            elide: Text.ElideRight; width: parent.width - 8
            text: tile.title.length ? tile.title : tile.cls
        }
    }
}
