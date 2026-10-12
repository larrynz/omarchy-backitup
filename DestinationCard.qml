import QtQuick
import qs.Commons

// One destination: the dot and name say which, the pill says how it is doing,
// the metrics say how much and how old, and the health strip says whether the
// promises were kept. Everything the old panel spread over five paragraphs,
// in the shape the eye reads top to bottom.
Rectangle {
  id: root

  property var destination: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var d: root.destination
  readonly property string state: root.d ? BackItUpStore.destinationStatus(root.d) : "idle"
  // A run in flight has no verdict of its own yet, so the previous run's
  // problems must not sit under it wearing the same red: the card reports the
  // live run and nothing else until a result exists.
  readonly property bool busy: root.state === "busy"
  readonly property color tone: StatusPalette.color(root.state)
  readonly property color dim: Qt.darker(root.foreground, 1.55)

  readonly property string stateLabel: {
    if (root.state === "ok") return "Healthy"
    if (root.state === "busy") return "Running"
    if (root.state === "warn") return "Check"
    if (root.state === "bad") return "Failed"
    return "Never"
  }

  readonly property var metricList: root.d ? BackItUpStore.destinationMetrics(root.d) : []
  readonly property string fallbackDetail: root.d ? BackItUpStore.destinationDetail(root.d) : ""
  readonly property string snapshotProblemText:
    (root.d && !root.busy && BackItUpStore.destinationSnapshotProblem(root.d))
      ? BackItUpStore.destinationSnapshot(root.d) : ""

  // The metrics as one wrapping line, the numbers in the foreground colour and
  // the words dimmer. Markup rather than a row of Texts, so the line wraps
  // between whole quantities instead of stranding a separator at the start of
  // the second line. The angle brackets are built from character codes: a
  // literal one does not always survive every edit path to disk, and the
  // failure is a silently unstyled line.
  readonly property string metricsMarkup: {
    var lt = String.fromCharCode(60)
    var gt = String.fromCharCode(62)
    var fg = root.foreground.toString()
    var dm = root.dim.toString()
    var parts = []
    var list = root.metricList
    for (var i = 0; i < list.length; i++) {
      parts.push(lt + "font color=\"" + fg + "\"" + gt
                 + lt + "b" + gt + list[i].value + lt + "/b" + gt
                 + lt + "/font" + gt
                 + " "
                 + lt + "font color=\"" + dm + "\"" + gt
                 + list[i].label + lt + "/font" + gt)
    }
    return parts.join("  \u00b7  ")
  }

  // The promises a destination made, and whether it kept them. An audit that
  // went clean and a system snapshot that was taken are both settled facts,
  // so they read as quiet green tags rather than as sentences.
  readonly property var tagList: {
    var out = []
    if (!root.d || root.busy) return out
    var audit = root.d.last_audit
    if (audit && audit.unreadable !== undefined && audit.unreadable !== null) {
      var n = Number(audit.unreadable)
      if (n === 0)
        out.push({ state: "ok", glyph: BackItUpStore.iconCheck, label: "Audit clean" })
      else
        out.push({ state: "bad", glyph: BackItUpStore.iconAlert,
                   label: n + (n === 1 ? " file unreadable" : " files unreadable") })
    }
    if (root.d.last_run && root.d.last_run.system_snapshot) {
      if (BackItUpStore.destinationSnapshotProblem(root.d))
        out.push({ state: "bad", glyph: BackItUpStore.iconAlert, label: "System snapshot failed" })
      else
        out.push({ state: "ok", glyph: BackItUpStore.iconCheck, label: "System snapshot taken" })
    }
    return out
  }

  width: parent ? parent.width : implicitWidth
  implicitHeight: body.implicitHeight
  radius: Style.space(7)
  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.045)
  border.width: Style.space(1)
  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
  clip: true

  Column {
    id: body
    width: parent.width

    // --- name, dot, pill ------------------------------------------------

    Item {
      width: parent.width
      implicitHeight: Style.space(10) * 2
                      + Math.max(dot.implicitHeight, nameText.implicitHeight, pill.implicitHeight)

      StatusDot {
        id: dot
        anchors.left: parent.left
        anchors.leftMargin: Style.space(11)
        anchors.verticalCenter: parent.verticalCenter
        color: root.tone
      }

      Text {
        id: nameText
        anchors.left: dot.right
        anchors.leftMargin: Style.space(10)
        anchors.right: pill.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: root.d ? BackItUpStore.destinationLabel(root.d) : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      StatusPill {
        id: pill
        anchors.right: parent.right
        anchors.rightMargin: Style.space(11)
        anchors.verticalCenter: parent.verticalCenter
        state: root.state
        text: root.stateLabel
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }

    // --- metrics (indented under the name) ------------------------------

    // The quantities under the name: how much is stored, how many snapshots,
    // what last night added.
    Text {
      id: metricsText
      width: parent.width
      leftPadding: Style.space(29)
      rightPadding: Style.space(11)
      bottomPadding: Style.space(10)
      visible: !metricDetailFallback.visible
      text: root.metricsMarkup
      textFormat: Text.StyledText
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // After a failure, or when a run is in flight, the useful line is how old
    // the newest good copy is -- not the repository size, which does not
    // answer the question anyone is asking.
    Text {
      id: metricDetailFallback
      width: parent.width
      leftPadding: Style.space(29)
      rightPadding: Style.space(11)
      bottomPadding: Style.space(10)
      visible: root.metricList.length === 0 && text !== ""
      text: root.fallbackDetail
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // A system snapshot that was asked for and not taken needs its reason
    // kept -- the tag says it broke, this says why, and the fix is usually
    // named in the reason. So this paragraph is never elided: a truncated
    // "add the snapper group ACL in /etc/snapper/configs/root" is exactly the
    // half that would have fixed it.
    Text {
      width: parent.width
      leftPadding: Style.space(29)
      rightPadding: Style.space(11)
      bottomPadding: visible ? Style.space(10) : 0
      visible: root.snapshotProblemText !== ""
      text: root.snapshotProblemText
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: StatusPalette.bad
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // --- health strip ---------------------------------------------------

    Rectangle {
      width: parent.width
      implicitHeight: healthRow.implicitHeight + Style.space(8) * 2
      visible: root.tagList.length > 0
      color: Qt.rgba(0, 0, 0, 0.14)

      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(1)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
      }

      Row {
        id: healthRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(11)
        anchors.rightMargin: Style.space(11)
        spacing: Style.space(12)

        Repeater {
          model: root.tagList

          CheckTag {
            anchors.verticalCenter: parent.verticalCenter
            state: modelData.state
            glyph: modelData.glyph
            text: modelData.label
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
        }
      }
    }
  }
}
