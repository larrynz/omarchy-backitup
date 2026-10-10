import QtQuick
import qs.Commons

// One point in the snapshot timeline: the day on top, when it ran and how big
// it was underneath.
//
// The date used to live inside a Dropdown, which is the one control that can
// hide every option it has. You could not see how far back your history went,
// or how big each point in it was, without opening the menu and reading it.
// A chip shows both at rest, and the row of them *is* the history.
Rectangle {
  id: root

  property string day: ""
  property string detail: ""
  property bool selected: false
  // The overflow chip ("+12 more") is a chip with a different job, not a
  // different shape: it should read as part of the timeline.
  property bool muted: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal clicked()

  readonly property real _ink: root.selected ? 1.0 : (root.muted ? 0.45 : 1.0)

  implicitWidth: Math.max(Style.space(78), body.implicitWidth + Style.space(18))
  implicitHeight: body.implicitHeight + Style.space(13)

  radius: Style.space(8)
  color: root.selected
         ? StatusPalette.tint(root.accent, 0.13)
         : (mouse.containsMouse ? root._fill(0.07) : root._fill(0.035))
  border.width: Style.space(1)
  border.color: root.selected
                ? StatusPalette.line(root.accent, 0.5)
                : root._fill(0.12)

  function _fill(a) {
    return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, a)
  }

  Column {
    id: body
    anchors.centerIn: parent
    spacing: Style.space(1)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.day
      textFormat: Text.PlainText
      color: root.selected ? root.accent : root.foreground
      opacity: root._ink
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: root.selected
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.detail !== ""
      text: root.detail
      textFormat: Text.PlainText
      color: Qt.darker(root.foreground, 1.55)
      opacity: root._ink
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  Behavior on color { ColorAnimation { duration: 90 } }
}
