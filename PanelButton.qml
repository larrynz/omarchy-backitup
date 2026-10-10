import QtQuick
import qs.Commons

// A labelled action. Four weights, and the weight is the whole point: a
// filled primary that is the one thing to do, a plain secondary beside it,
// a danger that means "stop", and a ghost for the sideways errands at the
// bottom that should not look like a decision.
Rectangle {
  id: root

  property string label: ""
  property string glyph: ""
  property string variant: "default"   // default / primary / danger / ghost
  property bool block: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal clicked()

  readonly property bool primary: root.variant === "primary"
  readonly property bool danger: root.variant === "danger"
  readonly property bool ghost: root.variant === "ghost"
  readonly property bool hot: area.containsMouse && root.enabled
  readonly property color tone: root.primary ? root.accent
                               : root.danger ? StatusPalette.bad
                               : root.foreground

  readonly property color labelColor:
    !root.enabled ? Qt.darker(root.foreground, 2.2)
    : root.primary ? Color.background
    : root.ghost ? Qt.darker(root.foreground, 1.55)
    : root.tone

  width: root.block && parent ? parent.width : implicitWidth
  implicitWidth: content.implicitWidth + Style.space(14) * 2
  implicitHeight: Style.space(root.ghost ? 28 : 36)
  radius: Style.space(8)
  opacity: root.enabled ? 1.0 : 0.6

  color: !root.enabled ? "transparent"
       : root.primary ? (root.hot ? Qt.lighter(root.accent, 1.08) : root.accent)
       : root.ghost ? (root.hot ? root._fill(0.075) : "transparent")
       : root.danger ? StatusPalette.tint(StatusPalette.bad, root.hot ? 0.14 : 0.07)
       : root._fill(root.hot ? 0.075 : 0.045)

  border.width: root.primary || root.danger ? Style.space(1)
              : root.ghost ? 0
              : Style.space(1)
  border.color: root.primary ? root.accent
              : root.danger ? StatusPalette.line(StatusPalette.bad, 0.4)
              : root._fill(root.hot ? 0.28 : 0.14)

  function _fill(a) {
    return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, a)
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.glyph !== ""
      text: root.glyph
      textFormat: Text.PlainText
      color: root.labelColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      textFormat: Text.PlainText
      color: root.labelColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: root.primary
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  Behavior on color { ColorAnimation { duration: 90 } }
}
