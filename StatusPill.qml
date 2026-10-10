import QtQuick
import qs.Commons

// A state word on a destination card -- Healthy, Running, Failed. Uppercase,
// tiny and pill-shaped so it never competes with the name beside it: the
// name is what the card is, the pill is only how it is doing.
Rectangle {
  id: root

  property string text: ""
  property string state: "idle"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color tone: StatusPalette.color(root.state)
  readonly property bool neutral: root.state !== "ok" && root.state !== "busy"
                                  && root.state !== "warn" && root.state !== "bad"

  implicitWidth: label.implicitWidth + Style.space(7) * 2
  implicitHeight: label.implicitHeight + Style.space(2) * 2
  radius: height / 2
  color: root.neutral ? "transparent" : StatusPalette.tint(root.tone, 0.08)
  border.width: Style.space(1)
  border.color: root.neutral
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                : StatusPalette.line(root.tone, 0.4)

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text.toUpperCase()
    textFormat: Text.PlainText
    color: root.neutral ? Qt.darker(root.foreground, 1.55) : root.tone
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 0.6
  }
}
