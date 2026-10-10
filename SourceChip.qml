import QtQuick
import qs.Commons

// One folder in the "what gets backed up" list.
//
// A chip rather than a row with a bare ×: each source is an object you can
// point at and remove, and the folder glyph plus the trailing × say which is
// which without a legend. The path is the content, so it takes the width and
// the remove affordance stays a fixed target at the end -- an × that slides
// around with the filename is how you delete the wrong folder.
Rectangle {
  id: root

  property string path: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal removeRequested()

  readonly property bool hot: removeArea.containsMouse
  readonly property color dim: Qt.darker(root.foreground, 1.55)

  implicitHeight: Style.space(32)
  height: implicitHeight
  radius: Style.space(7)
  color: "transparent"
  border.width: Style.space(1)
  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

  Row {
    id: line
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(9)

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      text: BackItUpStore.iconFolder
      textFormat: Text.PlainText
      // Yellow, the same as a folder in the restore listing: one folder looks
      // like a folder wherever it appears.
      color: StatusPalette.warn
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Text {
      id: pathText
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(Style.space(24),
                      line.width - glyph.width - remove.width - line.spacing * 2)
      text: root.path
      textFormat: Text.PlainText
      // Middle, not right: the tail of a path is the folder that matters and
      // the head says where it lives, so either end is worth more than the
      // middle.
      elide: Text.ElideMiddle
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      id: remove
      width: Style.space(24)
      height: width
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.fill: parent
        radius: Style.space(5)
        color: root.hot ? StatusPalette.tint(StatusPalette.bad, 0.12) : "transparent"
      }

      Text {
        anchors.centerIn: parent
        text: "\u00d7"
        textFormat: Text.PlainText
        color: root.hot ? StatusPalette.bad : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        id: removeArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.removeRequested()
      }
    }
  }
}
