import QtQuick
import QtQuick.Layouts
import qs.Commons

// Where you are in the wizard, and how much is left.
//
// Dots instead of a "2 of 5" label: it is the same information, but the shape
// shows the shape of what remains, which is the single biggest fix for a long
// form. Only the current step is named -- naming all five turns the trail into
// a second form to read, and the name is only useful for the one you are on.
RowLayout {
  id: root

  property int count: 5
  property int current: 1        // 1-based
  property var labels: []        // optional; labels[current - 1] is shown
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color doneColor: StatusPalette.ok
  property string fontFamily: Style.font.family

  readonly property string currentLabel:
    (root.labels && root.labels.length >= root.current)
      ? String(root.labels[root.current - 1]) : ""

  function _fill(c, a) {
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  spacing: 0

  Repeater {
    model: root.count

    delegate: RowLayout {
      id: step

      // Every step but the last owns the connector that follows it, and the
      // connectors share the leftover width equally -- so the trail always
      // spans the panel and the dots stay evenly spaced however long the
      // current step's name happens to be.
      Layout.fillWidth: index < root.count - 1
      Layout.alignment: Qt.AlignVCenter
      spacing: 0

      readonly property bool finished: index < root.current - 1
      readonly property bool now: index === root.current - 1

      Rectangle {
        id: dot
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Style.space(20)
        implicitHeight: Style.space(20)
        radius: width / 2
        color: step.now ? root.accent
             : step.finished ? root._fill(root.doneColor, 0.15)
             : "transparent"
        border.width: Style.space(1)
        border.color: step.now ? root.accent
                    : step.finished ? root._fill(root.doneColor, 0.5)
                    : root._fill(root.foreground, 0.18)

        // A finished step shows a tick rather than its number: the number is
        // only worth reading while the step is still ahead of you.
        Text {
          anchors.centerIn: parent
          text: step.finished ? BackItUpStore.iconCheck : String(index + 1)
          textFormat: Text.PlainText
          color: step.now ? Color.background
               : step.finished ? root.doneColor
               : Qt.darker(root.foreground, 1.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: step.now
        }

        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Text {
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Style.space(6)
        visible: step.now && root.currentLabel !== ""
        text: root.currentLabel
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        Layout.fillWidth: visible
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Style.space(6)
        Layout.rightMargin: Style.space(6)
        visible: index < root.count - 1
        implicitHeight: Math.max(1, Style.space(1))
        color: step.finished ? root._fill(root.doneColor, 0.5)
                             : root._fill(root.foreground, 0.14)

        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }
  }
}
