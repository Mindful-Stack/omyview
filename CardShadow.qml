import QtQuick
import QtQuick.Effects

// Soft elevation under the card (end-4 style). RectangularShadow is a standalone shader item,
// so it costs no offscreen layer over the live previews. Place it as a sibling *before* the
// card so it paints underneath.
RectangularShadow {
    required property Item target
    anchors.fill: target
    radius: target.radius
    blur: 28
    spread: 0
    offset: Qt.vector2d(0, 6)
    color: Qt.rgba(0, 0, 0, 0.28)
    cached: true
}
