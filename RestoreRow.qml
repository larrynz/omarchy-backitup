import QtQuick
import qs.Commons

// One entry in a snapshot listing: a folder to descend into, a file to queue
// or drop, or the ".." row that walks back up.
//
// Two shapes for two jobs, which is the whole redesign of this row. A chevron
// means "this opens" and belongs to folders; a tick or a plus means "this is
// chosen" and belongs to files. The old row used the same highlight for both,
// so the only way to learn which a row would do was to click it.
//
// Every Text here is pinned to PlainText, and that is not boilerplate: these
// are file names out of somebody's backup. On the default AutoText, Qt decides
// for itself whether a string is markup, and a name containing an <img> tag
// would be rendered as rich text -- which really does fetch the URL, from the
// shell process, to a host the file name chose.
Item {
  id: root

  property string entryName: ""
  property string entryType: "file"
  property var entrySize: null
  property var entryTime: null
  // A file can be in the restore queue or not. Folders and ".." never are:
  // clicking a folder walks into it, and the folder you are standing in is
  // restorable from the footer.
  property bool queued: false
  // Keyboard cursor, distinct from mouse hover and from the queue.
  property bool hasCursor: false

  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal activated()

  readonly property bool isDirectory: root.entryType === "dir"
  readonly property bool isUp: root.entryType === "up"
  readonly property bool isFile: !root.isDirectory && !root.isUp
  readonly property bool hot: mouse.containsMouse || root.hasCursor

  implicitHeight: Style.space(26)
  height: implicitHeight

  function _fill(a) {
    return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, a)
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.queued
           ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.13)
           : ((mouse.containsMouse || root.hasCursor) ? root._fill(0.08) : "transparent")
  }

  Row {
    id: line
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(7)
    anchors.rightMargin: Style.space(7)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Text {
      id: glyph
      width: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      text: root.isUp ? BackItUpStore.iconUp
                      : (root.isDirectory ? BackItUpStore.iconFolder : BackItUpStore.iconFile)
      textFormat: Text.PlainText
      color: root.isDirectory || root.isUp ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Text {
      id: name
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(Style.space(24),
                      line.width - glyph.width - meta.width - indicator.width - line.spacing * 3)
      text: root.entryName + (root.isDirectory ? "/" : "")
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      color: root.queued ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: meta
      anchors.verticalCenter: parent.verticalCenter
      width: implicitWidth
      text: root.isFile && root.entrySize !== null && root.entrySize !== undefined
            ? BackItUpStore.humanBytes(root.entrySize) : ""
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item {
      id: indicator
      width: Style.space(20)
      height: width
      anchors.verticalCenter: parent.verticalCenter

      // A folder is a door.
      Text {
        anchors.centerIn: parent
        visible: root.isDirectory
        text: BackItUpStore.iconChevronRight
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      // A file is a choice: plus means not queued, tick means queued.
      Rectangle {
        anchors.centerIn: parent
        visible: root.isFile
        width: Style.space(16)
        height: width
        radius: width / 2
        color: root.queued ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                           : "transparent"
        border.width: Style.space(1)
        border.color: root.queued ? StatusPalette.line(root.accent, 0.5)
                                  : root._fill(0.18)

        Text {
          anchors.centerIn: parent
          text: root.queued ? BackItUpStore.iconCheck : BackItUpStore.iconPlus
          textFormat: Text.PlainText
          color: root.queued ? root.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
