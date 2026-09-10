import QtQuick
import QtQuick.Effects

// Soft elevation shadow (end-4 style) for the card and for floating window tiles.
// RectangularShadow is a standalone shader item, so it costs no offscreen layer over the live
// previews. Declare it as a sibling *before* the item it belongs to so it paints underneath.
// `radius` defaults to the target's own radius; override it for targets without one.
RectangularShadow {
    property Item target: parent
    anchors.fill: target
    radius: (target && target.radius !== undefined) ? target.radius : 0
    blur: 28
    spread: 0
    offset: Qt.vector2d(0, 6)
    color: Qt.rgba(0, 0, 0, 0.28)
    cached: true
}
