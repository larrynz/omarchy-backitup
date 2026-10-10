import QtQuick
import qs.Commons

// The verdict at the top of the panel: one sentence that answers "am I safe?"
// before any number appears. Built around a status stripe and a tinted badge,
// so the answer is legible from the corner of the eye -- the colour says it
// first, the words confirm it.
Rectangle {
  id: root

  property string state: "idle"   // ok / busy / warn / bad / idle
  property string verdict: ""
  property string sub: ""
  property string subStrong: ""
  property string meta: ""
  property string glyph: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color tone: StatusPalette.color(root.state)
  readonly property real pad: Style.space(14)

  width: parent ? parent.width : implicitWidth
  implicitHeight: inner.implicitHeight + root.pad * 2
  radius: Style.space(7)
  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.045)
  border.width: Style.space(1)
  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
  clip: true

  // Three pixels of state colour down the leading edge. The badge carries the
  // state too, but the stripe is what survives when the hero is half-scrolled
  // off the top of the panel.
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(3)
    color: root.tone
  }

  Row {
    id: inner
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: root.pad
    spacing: Style.space(13)

    Rectangle {
      width: Style.space(40)
      height: Style.space(40)
      radius: width / 2
      color: StatusPalette.tint(root.tone, 0.13)
      border.width: Style.space(1)
      border.color: StatusPalette.line(root.tone, 0.4)

      Text {
        anchors.centerIn: parent
        text: root.glyph
        textFormat: Text.PlainText
        color: root.tone
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconLarge
      }
    }

    Column {
      width: parent.width - Style.space(40) - parent.spacing
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: root.verdict
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.state === "idle" ? root.foreground : root.tone
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Row {
        width: parent.width
        spacing: Style.space(4)

        Text {
          text: root.sub
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        Text {
          text: root.subStrong
          textFormat: Text.PlainText
          visible: text !== ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: root.meta
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Qt.darker(root.foreground, 1.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
