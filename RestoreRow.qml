import QtQuick
import qs.Commons

// One entry in a snapshot listing: a file or folder you can choose, or the
// ".." row that walks back up.
//
// Selection is standard: a plain click chooses the row, file or folder, so the
// highlight always means "this will be restored". Opening is separate -- a
// folder's chevron, or a double-click -- so choosing a folder no longer means
// reaching for a tiny button somewhere else.
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
  // In the restore selection or not. Files and folders both take part; ".." is
  // navigation and never does.
  property bool queued: false
  // Keyboard cursor, distinct from mouse hover and from the queue.
  property bool hasCursor: false

  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal activated(int modifiers)
  signal opened(bool viaDoubleClick)

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
    onClicked: root.activated(mouse.modifiers)
    onDoubleClicked: root.opened(true)
  }

  // The disclosure. A folder's chevron opens it without choosing it, so the
  // whole row can be a plain click-to-select target like a file manager's.
  // Declared after the row MouseArea so it wins the click on its own square.
  MouseArea {
    anchors.verticalCenter: indicator.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: Style.space(7)
    width: Style.space(20)
    height: Style.space(20)
    visible: root.isDirectory
    enabled: visible
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened(false)
  }
}
