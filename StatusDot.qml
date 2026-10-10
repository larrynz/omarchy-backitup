import QtQuick

// A colour-coded dot with a soft ring: the destination's state in the one
// form that survives a glance. The ring is a flat halo rather than a glow,
// so it reads the same on every theme -- a blur would wash out on a light
// background and vanish on a dark one.
Item {
  id: root

  property color color: "#888"
  property real dotSize: 8

  implicitWidth: root.dotSize + 6
  implicitHeight: root.dotSize + 6

  Rectangle {
    anchors.centerIn: parent
    width: root.dotSize + 6
    height: root.dotSize + 6
    radius: width / 2
    color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.16)
  }

  Rectangle {
    anchors.centerIn: parent
    width: root.dotSize
    height: root.dotSize
    radius: width / 2
    color: root.color
  }
}
