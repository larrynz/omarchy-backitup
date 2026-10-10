import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Deleting a backup, one date at a time.
//
// The restore picker walks into a snapshot's files; this one stays one level
// up, because the thing being managed is the snapshot itself. The old shape
// here hid the whole history inside a dropdown and put one red row under it:
// you could not see what you had without picking through it, and the only
// thing on screen that did anything was the destructive one.
//
// So the history is the view now. Every backup is a row with its date and what
// it holds, the newest is marked, and the delete lives on each row where it
// stays quiet until you reach for it. The confirm still spells out the date and
// the file count: two deliberate interactions from an irreversible operation.
FocusScope {
  id: root

  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  // Same confirm routing as the restore browser: ConfirmDialog brings its own
  // mouse handling but no keyboard, so Escape and Enter have to be routed in
  // from outside.
  readonly property bool confirmOpen: deleteConfirm.opened
  function confirmCancel() { deleteConfirm.opened = false }
  function confirmAccept() {
    if (root.snapshotId !== "")
      BackItUpStore.startDelete(BackItUpStore.browseDest, root.snapshotId)
    // Cleared before the outcome is known: on success the reload lands on the
    // newest remaining backup, and on failure the error line says why while
    // the list waits for a fresh pick.
    root.snapshotId = ""
    deleteConfirm.opened = false
  }

  signal back()

  // A dedicated focus sink, and this is not ceremony. forceActiveFocus() on a
  // FocusScope hands focus to whichever child held it last, so after you touch
  // the destination picker once, "give the keyboard back" would keep handing it
  // straight back to the picker. Focus goes to this item explicitly. Escape and
  // Enter are the two keys that matter here.
  Item {
    id: keySink
    focus: true

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        if (deleteConfirm.opened) root.confirmCancel()
        else root.back()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (deleteConfirm.opened) root.confirmAccept()
        event.accepted = true
      }
    }
  }

  function takeFocus() { keySink.forceActiveFocus() }

  // Loads its own contents when it comes on screen, rather than trusting
  // whoever opened it to have done so. The click that opens this was once the
  // only thing calling loadSnapshots, which meant any other route in showed an
  // empty list and nothing else.
  function ensureLoaded() {
    if (!visible) return
    if (BackItUpStore.destinations.length === 0) return
    takeFocus()
    if (!BackItUpStore.snapshotsLoaded && !BackItUpStore.snapshotsBusy)
      BackItUpStore.loadSnapshots()
  }

  onVisibleChanged: ensureLoaded()
  Component.onCompleted: ensureLoaded()

  Connections {
    target: BackItUpStore
    function onDestinationsChanged() { root.ensureLoaded() }
  }

  // The snapshot a delete is armed against, set when a row's delete is
  // clicked and cleared when the confirm resolves either way.
  property string snapshotId: ""

  function currentSnapshot() {
    for (var i = 0; i < BackItUpStore.snapshots.length; i++)
      if (String(BackItUpStore.snapshots[i].id) === root.snapshotId)
        return BackItUpStore.snapshots[i]
    return null
  }

  function formatCount(value) {
    var n = Number(value)
    if (!isFinite(n)) return ""
    return n.toLocaleString(Qt.locale(), "f", 0)
  }

  // "352,891 files · 43.7 GB". Either half can be missing -- a snapshot
  // restored from an older restic may carry no summary at all -- so the
  // separator only appears when there are two things to join.
  function snapshotDetail(s) {
    if (!s || !s.summary) return ""
    var parts = []
    var files = s.summary.total_files_processed
    if (files !== undefined && files !== null)
      parts.push(root.formatCount(files) + (Number(files) === 1 ? " file" : " files"))
    var bytes = s.summary.total_bytes_processed
    if (bytes !== undefined && bytes !== null)
      parts.push(BackItUpStore.humanBytes(bytes))
    return parts.join(" \u00b7 ")
  }

  // "4 snapshots · retention keeps 7 daily, 4 weekly, 12 monthly". This is
  // what stops a short list reading as backups going missing: the policy that
  // thinned it is on screen, in the same place as the count it explains.
  // Zero is skipped rather than printed, so a destination that keeps no
  // monthlies does not advertise "0 monthly".
  function retentionNote() {
    var count = BackItUpStore.snapshots.length
    if (count === 0) return ""
    var r = BackItUpStore.browseDest ? BackItUpStore.browseDest.retention : null
    if (!r) return ""
    var parts = []
    if (r.daily) parts.push(r.daily + " daily")
    if (r.weekly) parts.push(r.weekly + " weekly")
    if (r.monthly) parts.push(r.monthly + " monthly")
    if (r.yearly) parts.push(r.yearly + " yearly")
    if (parts.length === 0) return ""
    return count + (count === 1 ? " snapshot" : " snapshots")
           + " \u00b7 retention keeps " + parts.join(", ")
  }

  function requestDelete(s) {
    if (!s) return
    root.snapshotId = String(s.id)
    deleteConfirm.opened = true
  }

  // --- sizing --------------------------------------------------------------

  // The list is the one element that gives way. Panel.qml sizes the card from
  // desiredHeight -- what this view would like -- and the list then takes
  // whatever is left of the height actually granted. Everything else is
  // measured by its own Column, which never depends on the list, so the two
  // can be worked out in either order.
  //
  // A fixed 300px rather than the content height, for the same reason as the
  // restore listing: a destination with four snapshots and one with forty
  // should not be two different window sizes, and the panel must not resize
  // when a delete shortens the list by a row.
  readonly property real listMinHeight: Style.space(72)
  readonly property real listNaturalHeight: Style.space(300)
  readonly property real listHeight:
    Math.max(root.listMinHeight,
             Math.min(root.listNaturalHeight, root.height - column.chromeHeight))
  readonly property real desiredHeight: column.chromeHeight + root.listNaturalHeight

  implicitHeight: column.chromeHeight + root.listHeight

  Column {
    id: column
    // Anchored in width only. anchors.fill would take the height from the
    // parent as well, while the parent takes its implicitHeight from this
    // Column -- the kind of circular sizing where nothing decides the layout.
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(10)

    // --- header and the lines above the list --------------------------------

    Column {
      id: upper
      width: parent.width
      spacing: column.spacing

      Item {
        width: parent.width
        implicitHeight: Style.space(30)

        PanelActionButton {
          id: backButton
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: BackItUpStore.iconArrowLeft
          tooltipText: "Back"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.back()
        }

        Text {
          anchors.left: backButton.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Manage backups"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        // Which destination's history this is. A pill when there is only one,
        // because a control with a single option is a label that costs a click.
        StatusPill {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: BackItUpStore.destinations.length <= 1
          text: BackItUpStore.browseName
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Dropdown {
          width: Style.space(130)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: BackItUpStore.destinations.length > 1
          label: ""
          showLabel: false
          foreground: root.foreground
          fontFamily: root.fontFamily
          value: BackItUpStore.browseName
          options: {
            var list = []
            for (var i = 0; i < BackItUpStore.destinations.length; i++) {
              var d = BackItUpStore.destinations[i]
              list.push({ value: String(d.name),
                          label: BackItUpStore.destinationLabel(d) })
            }
            return list
          }
          onChanged: function(value) {
            // The armed snapshot belonged to the destination we were looking
            // at, which is not the one being switched to. Clearing it stops a
            // confirm from naming a backup this destination does not have.
            root.snapshotId = ""
            BackItUpStore.browseDestination(value)
            root.takeFocus()
          }
          onPopupOpenChanged: if (!popupOpen) root.takeFocus()
        }
      }

      Text {
        width: parent.width
        visible: BackItUpStore.snapshotsBusy || BackItUpStore.snapshotsError !== ""
        text: BackItUpStore.snapshotsBusy ? "Loading backups\u2026" : BackItUpStore.snapshotsError
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: BackItUpStore.snapshotsError !== "" ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // --- the list ------------------------------------------------------------

    Rectangle {
      id: listBox
      width: parent.width
      height: root.listHeight
      // Always in the layout, even with nothing in it: hiding it would drop
      // 300px out of the column and resize the panel whenever the list
      // emptied or filled.
      color: "transparent"

      ListView {
        id: listView
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        model: BackItUpStore.snapshots

        delegate: SnapshotRow {
          width: listView.width
          name: BackItUpStore.menuDate(modelData.time)
          detail: root.snapshotDetail(modelData)
          // The CLI lists snapshots newest first, so the first row is the
          // newest backup -- the one retention keeps longest and the one a
          // restore is usually after.
          latest: index === 0
          showHairline: index > 0
          deleteEnabled: !BackItUpStore.deleteBusy
          foreground: root.foreground
          dim: root.dim
          accent: root.accent
          fontFamily: root.fontFamily
          onDeleteRequested: root.requestDelete(modelData)
        }
      }

      // What the region says when it has nothing to show. Inside the box
      // rather than below it, so the message lands where the rows would be
      // instead of under 300px of empty space.
      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(9)
        visible: text !== ""
        text: {
          if (BackItUpStore.snapshotsBusy || BackItUpStore.snapshotsError !== "") return ""
          if (BackItUpStore.snapshots.length > 0) return ""
          return BackItUpStore.browseName === "" || BackItUpStore.destinations.length === 0
                 ? "No destination is configured yet."
                 : "No backups yet. The first one appears here after it runs."
        }
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // --- the lines below the list --------------------------------------------

    Column {
      id: lower
      width: parent.width
      spacing: column.spacing

      // Prune rewrites the repository to reclaim the space, and on a large one
      // that takes minutes. Saying so is the difference between a busy line
      // and a wedged-looking panel. The list above stays on screen, so you can
      // still see what is being worked on.
      Text {
        width: parent.width
        visible: BackItUpStore.deleteBusy
        text: "Deleting and pruning\u2026 this can take a few minutes"
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        width: parent.width
        visible: BackItUpStore.deleteError !== ""
        text: BackItUpStore.deleteError
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: root.retentionNote()
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // upper and lower are measured independently of the list, so this never
    // depends on the height it is used to compute.
    readonly property real chromeHeight:
      upper.implicitHeight + lower.implicitHeight + column.spacing * 2
  }

  ConfirmDialog {
    id: deleteConfirm
    anchors.fill: parent
    z: 10

    // The date, the destination and the file count are spelled out, because
    // the one thing worth confirming here is what is about to be gone for
    // good. ConfirmDialog carries only a message and renders it as one line of
    // text, so the question and the stakes share it -- there is no heading
    // slot to put "Delete this backup?" in.
    //
    // plain(): the destination name comes out of config.json, and
    // ConfirmDialog is a shell component that sets no textFormat -- its Text
    // falls back to Qt's AutoText, which renders anything tag-shaped as rich
    // text and would fetch what it points at. Same reason the bar tooltip goes
    // through plain().
    message: {
      if (root.snapshotId === "") return ""
      var s = root.currentSnapshot()
      if (!s) return ""
      var files = s.summary ? s.summary.total_files_processed : undefined
      var count = (files === undefined || files === null)
                  ? "" : root.formatCount(files)
                    + (Number(files) === 1 ? " file. " : " files. ")
      return "Delete the backup from " + BackItUpStore.menuDate(s.time)
             + " on " + BackItUpStore.plain(BackItUpStore.destinationLabel(BackItUpStore.browseDest))
             + "? " + count + "This cannot be undone."
    }
    confirmText: "Delete"
    fontFamily: root.fontFamily
    onConfirmed: root.confirmAccept()
    onCanceled: root.confirmCancel()
  }
}
