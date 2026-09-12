import QtQuick

// Find bar — display only. Replaces the key-hint row while a query is active: a magnifier
// glyph at the left, "n of m" pinned at the right, the query filling the space between and
// eliding at its start so the newest characters stay visible. The caller sets the width (the
// card interior); the bar never grows with the query. No key handling and no focus:
// Overview's keyCatcher stays the single focus item (docs/specs/2026-09-11-find-design.md).
Item {
    id: bar
    property string query: ""
    property int count: 0
    property int index: -1            // 0-based rank of the selection, -1 when none
    property color fg: "#ddd"
    property color accent: "#88f"
    property string fontFamily: ""
    property int fontSize: 11
    implicitHeight: Math.max(glyph.implicitHeight, queryText.implicitHeight, countText.implicitHeight) + 4

    Text {   // nf-md-magnify; Omarchy's menu font carries the Nerd glyphs
        id: glyph
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "\u{F0349}"
        color: bar.accent
        font.family: bar.fontFamily; font.pixelSize: bar.fontSize
    }
    Text {
        id: countText
        objectName: "findCount"
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: bar.count > 0 ? (bar.index + 1) + " of " + bar.count : "0 matches"
        color: bar.fg; opacity: 0.55
        font.family: bar.fontFamily; font.pixelSize: bar.fontSize
    }
    Text {
        id: queryText
        objectName: "findQuery"
        anchors { left: glyph.right; right: countText.left; leftMargin: 8; rightMargin: 12
                  verticalCenter: parent.verticalCenter }
        text: bar.query
        textFormat: Text.PlainText        // the query is matched literally, so show it literally
        elide: Text.ElideLeft             // the end of the query is what the user just typed
        color: bar.fg
        opacity: bar.count > 0 ? 1 : 0.5      // muted when nothing matches
        font.family: bar.fontFamily; font.pixelSize: bar.fontSize
        font.weight: Font.DemiBold
    }
}
