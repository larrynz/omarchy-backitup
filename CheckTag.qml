import QtQuick
import qs.Commons

// A glyph and a word: the promises a destination made, and whether it kept
// them. In the health strip of a card, where a sentence would be too much.
Row {
  id: root

  property string text: ""
  property string state: "idle"   // ok / bad / idle
  property string glyph: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color tone:
    root.state === "ok" ? StatusPalette.ok
    : root.state === "bad" ? StatusPalette.bad
    : Qt.darker(root.foreground, 1.55)

  spacing: Style.space(5)

  Text {
    anchors.verticalCenter: parent.verticalCenter
    visible: root.glyph !== ""
    text: root.glyph
    textFormat: Text.PlainText
    color: root.tone
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: root.text
    textFormat: Text.PlainText
    color: root.tone
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
