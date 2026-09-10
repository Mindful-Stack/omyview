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

    property bool dropTarget: false
    // "left"|"right"|"top"|"bottom": which half a dragged tiled window would take here
    property string dropSide: ""

    readonly property bool wantCapture: handle !== null && capMode !== "icon"
    readonly property string iconUrl: Quickshell.iconPath(String(cls).toLowerCase(), true)

    // Drag ghost: while in transit the tile shrinks around the grabbed point (so that point stays
    // under the pointer and the ghost never hides the drop highlight) and turns translucent.
    // The pointer, not the ghost, decides where a tiled window lands.
    property real grabX: width / 2         // grab point in tile coords, set by Overview at press
    property real grabY: height / 2
    readonly property real dragScale: 0.6
    readonly property real dragOpacity: 0.6
    readonly property alias ghostScale: ghost.xScale

    HoverHandler { id: hh; enabled: !tile.dragging }
    scale: dragging ? 1 : (hh.hovered ? 1.05 : 0.95)
    transformOrigin: Item.Center
    z: dragging ? 99999 : (hh.hovered ? 10 : 0)
    opacity: dragging ? dragOpacity : 1
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }
    Behavior on opacity { NumberAnimation { duration: 100 } }
    transform: Scale {
        id: ghost
        origin.x: tile.grabX; origin.y: tile.grabY
        xScale: tile.dragging ? tile.dragScale : 1
        yScale: xScale
        Behavior on xScale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }
    }

    ClippingRectangle {
        anchors.fill: parent
        color: tile.bg
        radius: 6
        border.width: tile.dropTarget ? 3 : 1
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

    // insertion preview: the half of this tile the dragged tiled window will be split into
    Rectangle {
        visible: tile.dropSide.length > 0
        color: tile.borderColor
        opacity: 0.45
        radius: 4
        x: tile.dropSide === "right" ? parent.width / 2 : 0
        y: tile.dropSide === "bottom" ? parent.height / 2 : 0
        width: (tile.dropSide === "left" || tile.dropSide === "right") ? parent.width / 2 : parent.width
        height: (tile.dropSide === "top" || tile.dropSide === "bottom") ? parent.height / 2 : parent.height
    }
}
