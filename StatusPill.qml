import QtQuick
import qs.Commons

// A state word on a destination card -- Healthy, Running, Failed. Uppercase,
// tiny and pill-shaped so it never competes with the name beside it: the
// name is what the card is, the pill is only how it is doing.
Rectangle {
  id: root

  property string text: ""
  property string state: "idle"
  // An explicit hue, for markers that are not health states -- the "Latest"
  // tag on the newest backup, which is about recency, not about whether the
  // backup worked. StatusPalette stays semantic; this stays a pill.
  // "transparent" reads as unset, since a zero alpha is not a colour anyone
  // would ask a pill to be.
  property color toneOverride: "transparent"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property bool hasToneOverride: root.toneOverride.a > 0
  readonly property color tone: root.hasToneOverride
                                ? root.toneOverride
                                : StatusPalette.color(root.state)
  readonly property bool neutral: !root.hasToneOverride
                                  && root.state !== "ok" && root.state !== "busy"
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
