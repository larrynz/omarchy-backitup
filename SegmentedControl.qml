import QtQuick
import qs.Commons

// A small set of mutually exclusive choices, all visible at once.
//
// A segmented control rather than the click-to-cycle row it replaces: cycling
// hides every option but the current one, so you cannot see what the choices
// are without clicking through them, and you cannot get back to the one you
// had without going all the way round. Four or five options fit across a
// panel; anything longer wants a list, not a segment.
Rectangle {
  id: root

  property var options: []       // [{ value: "daily", label: "daily" }]
  property string value: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal selected(string value)

  readonly property real seam: Math.max(1, Style.space(1))
  readonly property color stroke:
    Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

  implicitHeight: Style.space(32)
  height: implicitHeight
  radius: Style.space(8)
  // The container itself is the seam colour: the gaps between the segments
  // are just the background showing through, which is how the mockup draws
  // it, and it means no borders to keep in sync with the fill.
  color: root.stroke
  border.width: Style.space(1)
  border.color: root.stroke
  clip: true

  Row {
    id: line
    anchors.fill: parent
    anchors.margins: root.seam
    spacing: root.seam

    Repeater {
      model: root.options

      delegate: Rectangle {
        id: opt

        readonly property bool on: String(modelData.value) === root.value
        readonly property bool hot: area.containsMouse

        width: Math.max(Style.space(20),
                        (line.width - line.spacing * Math.max(0, root.options.length - 1))
                        / Math.max(1, root.options.length))
        height: line.height
        color: opt.on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
             : opt.hot ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
             : Color.background

        Text {
          anchors.centerIn: parent
          text: modelData.label !== undefined ? String(modelData.label)
                                              : String(modelData.value)
          textFormat: Text.PlainText
          elide: Text.ElideRight
          width: parent.width - Style.space(6)
          horizontalAlignment: Text.AlignHCenter
          color: opt.on ? root.accent : Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: opt.on
        }

        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.selected(String(modelData.value))
        }

        Behavior on color { ColorAnimation { duration: 90 } }
      }
    }
  }
}
