import QtQuick
import qs.Commons

// One "what you are about to set up" line: a fixed-width key, then the value.
//
// The key column is a fixed width so five rows of different names line up into
// a table without a header -- the alignment is the header. The value wraps
// anywhere, because the values here are paths and repository URLs, which have
// no spaces to break at.
Item {
  id: root

  property string key: ""
  property string value: ""
  property bool separator: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property real pad: Style.space(8)
  readonly property real gap: Style.space(10)
  readonly property real keyWidth: Style.space(84)
  readonly property color hair:
    Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.09)

  implicitHeight: Math.max(keyText.implicitHeight, valueText.implicitHeight)
                  + root.pad * 2
  width: parent ? parent.width : implicitWidth

  // The lip between rows, skipped on the first so the list does not look
  // like it starts one pixel late.
  Rectangle {
    visible: root.separator
    anchors.top: parent.top
    width: parent.width
    height: Math.max(1, Style.space(1))
    color: root.hair
  }

  Text {
    id: keyText
    anchors.left: parent.left
    anchors.leftMargin: Style.space(11)
    anchors.top: parent.top
    anchors.topMargin: root.pad
    width: root.keyWidth
    text: root.key
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: Qt.darker(root.foreground, 1.55)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    id: valueText
    anchors.left: keyText.right
    anchors.leftMargin: root.gap
    anchors.right: parent.right
    anchors.rightMargin: Style.space(11)
    anchors.top: parent.top
    anchors.topMargin: root.pad
    text: root.value
    textFormat: Text.PlainText
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
