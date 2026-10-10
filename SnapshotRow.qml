import QtQuick
import qs.Commons

// One backup in the manage list: the date it was taken, what it holds, and a
// delete that stays quiet until you reach for it.
//
// The row itself does nothing. In the restore listing a row is a choice, so
// the whole row is the target; here the only thing worth clicking is the
// delete, and it is the one irreversible action in the plugin. So the delete
// arms on approach -- dim at rest, red under the cursor -- and everything
// else about the row is inert. A misplaced click in this list lands on
// nothing rather than on a delete.
//
// Every Text is pinned to PlainText, for the same reason as RestoreRow: the
// detail line carries a count and a size out of restic, and on the default
// AutoText Qt would decide for itself whether a string is markup.
Item {
  id: root

  property string name: ""
  property string detail: ""
  // The newest backup. Worth marking, because it is the one a restore is
  // usually after and the one retention will keep longest.
  property bool latest: false
  // Rows are separated by a hairline inside one bordered box, so every row
  // but the first draws one.
  property bool showHairline: false
  // False while a delete is pruning: the list stays on screen, but reaching
  // for a second delete mid-prune would queue work against a repository that
  // is being rewritten.
  property bool deleteEnabled: true

  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal deleteRequested()

  readonly property bool hot: mouse.containsMouse
  readonly property bool deleteHot: deleteArea.containsMouse && root.deleteEnabled

  implicitHeight: Style.space(34)
  height: implicitHeight

  function _fill(a) {
    return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, a)
  }

  Rectangle {
    anchors.fill: parent
    color: root.hot
           ? root._fill(0.05)
           : (root.deleteHot ? StatusPalette.tint(StatusPalette.bad, 0.04) : "transparent")
  }

  Rectangle {
    visible: root.showHairline
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Style.space(1)
    color: root._fill(0.08)
  }

  // Hover for the row wash only; it takes no clicks, so the row stays inert
  // and the delete stays the only target. Declared before the Row so the
  // delete button stacks above it and keeps its own hover.
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }

  Row {
    id: line
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(9)
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Text {
      id: glyph
      width: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      text: BackItUpStore.iconBox
      textFormat: Text.PlainText
      color: root.latest ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Text {
      id: name
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(Style.space(24),
                      line.width - glyph.width - latestTag.width - detail.width
                      - deleteButton.width - line.spacing * (root.latest ? 4 : 3))
      text: root.name
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    StatusPill {
      id: latestTag
      anchors.verticalCenter: parent.verticalCenter
      visible: root.latest
      width: visible ? implicitWidth : 0
      text: "Latest"
      toneOverride: root.accent
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      id: detail
      anchors.verticalCenter: parent.verticalCenter
      width: implicitWidth
      text: root.detail
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item {
      id: deleteButton
      width: Style.space(26)
      height: width
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: root.deleteHot ? StatusPalette.tint(StatusPalette.bad, 0.12) : "transparent"
      }

      Text {
        anchors.centerIn: parent
        text: BackItUpStore.iconTrash
        textFormat: Text.PlainText
        color: root.deleteHot ? StatusPalette.bad : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      MouseArea {
        id: deleteArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.deleteEnabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.deleteRequested()
      }
    }
  }
}
