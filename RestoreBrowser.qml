import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Walking through a snapshot, one directory at a time, and queueing what to
// bring back.
//
// `restic ls` without --recursive returns only the direct children of a path,
// which is what makes this affordable: a home directory holds well over a
// million files, and a recursive listing would stall the panel for minutes.
// Each folder click is one call; visited paths are cached in the store, so
// walking back up is instant.
//
// Three things changed from the two-dropdown version this replaces. The date
// is a timeline you can read at rest instead of an option inside a menu; the
// path is a breadcrumb you can click instead of a grey string; and a click on
// a file queues it rather than restoring it immediately, so one footer can
// name everything that is about to happen and one confirmation can guard it.
//
// Restoring never writes in place. Everything lands in a dated folder under
// ~/Restored, so a restore cannot erase work created after the snapshot; the
// user moves it back themselves, seeing exactly what they overwrite.
FocusScope {
  id: root

  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  signal back()

  // What the confirmation is about. Held as the request itself, not as a
  // string assembled at the call site, so the dialog and the restore can never
  // disagree about the target -- the footer, the row and the dialog all read
  // the same list.
  property var restoreRequest: []

  readonly property bool confirmOpen: restoreConfirm.opened
  function confirmCancel() { restoreConfirm.opened = false }
  function confirmAccept() {
    if (root.restoreRequest.length > 0)
      BackItUpStore.restore(root.snapshotId, root.restoreRequest)
    restoreConfirm.opened = false
  }

  // The name the dialog shows. One item is named; several are counted. The
  // single item's name comes from the path, so a file and a folder read the
  // same way and neither can be a name that does not match its path.
  readonly property string restoreTargetName: {
    var n = root.restoreRequest.length
    if (n === 0) return ""
    if (n > 1) return n + " items"
    var path = String(root.restoreRequest[0])
    var cut = path.lastIndexOf("/")
    var tail = cut === -1 ? path : path.substring(cut + 1)
    return tail === "" ? path : tail
  }

  // The subject of the confirmation sentence. plain(): the name is a filename
  // out of the backup and ConfirmDialog is a shell component with no
  // textFormat, so its Text falls back to Qt's AutoText -- which renders
  // anything tag-shaped as rich text and fetches what it points at.
  readonly property string confirmSubject: root.restoreRequest.length === 1
    ? "\u201C" + BackItUpStore.plain(root.restoreTargetName) + "\u201D"
    : root.restoreTargetName

  // A dedicated focus sink, and this is not ceremony. forceActiveFocus() on a
  // FocusScope hands focus to whichever child held it last, so after you touch
  // a chip once, "give the keyboard back to the listing" would keep handing it
  // straight back. Down would then move the timeline instead of the listing,
  // forever. Focus goes to this item explicitly.
  Item {
    id: keySink
    focus: true

    // Owns the keyboard while it is on screen. PanelKeyCatcher cannot serve
    // here: it treats "h", "j", "k", "l" as movement and "x" as delete before
    // it ever reaches plain text, so typing to filter would steer the panel.
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        if (restoreConfirm.opened) root.confirmCancel()
        else if (root.filter !== "") root.clearFilter()
        else if (root.queue.length > 0) root.clearSelection()
        else root.back()
        event.accepted = true
      } else if (event.key === Qt.Key_Down) {
        root.moveCursor(1); event.accepted = true
      } else if (event.key === Qt.Key_Up) {
        root.moveCursor(-1); event.accepted = true
      } else if (event.key === Qt.Key_PageDown) {
        root.moveCursor(10); event.accepted = true
      } else if (event.key === Qt.Key_PageUp) {
        root.moveCursor(-10); event.accepted = true
      } else if (event.key === Qt.Key_Home) {
        root.moveCursor(-root.rows.length); event.accepted = true
      } else if (event.key === Qt.Key_End) {
        root.moveCursor(root.rows.length); event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        // Ctrl+Enter is the keyboard's way to the footer's button, because
        // choosing several rows and then reaching for the mouse is the one
        // place this flow still demanded it.
        if (restoreConfirm.opened) root.confirmAccept()
        else if (event.modifiers & Qt.ControlModifier) root.restoreQueued()
        else root.activateCursor()
        event.accepted = true
      } else if (event.key === Qt.Key_Space) {
        // Space is the keyboard's Ctrl-click: add or drop the row under the
        // cursor without opening it.
        if (root.cursorIndex >= 0 && root.cursorIndex < root.rows.length)
          root.toggleSelection(root.rows[root.cursorIndex], root.cursorIndex)
        event.accepted = true
      } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
        root.selectAllVisible()
        event.accepted = true
      } else if (event.key === Qt.Key_Backspace) {
        // Backspace edits the filter while there is one, and otherwise means
        // "up a level" -- which is what it does in every file manager.
        if (root.filter !== "") root.backspaceFilter()
        else root.goUp()
        event.accepted = true
      } else if (event.key === Qt.Key_Left) {
        root.goUp(); event.accepted = true
      } else if (event.text && event.text.length === 1 && event.text >= " ") {
        root.appendFilter(event.text); event.accepted = true
      }
    }
  }

  function takeFocus() { keySink.forceActiveFocus() }

  // Loads its own contents when it comes on screen, rather than trusting
  // whoever opened it to have done so. The click that opens this was the only
  // thing calling loadSnapshots, which meant any other route in showed an
  // empty timeline and nothing else.
  function ensureLoaded() {
    if (!visible) return
    if (BackItUpStore.destinations.length === 0) return
    takeFocus()
    if (!BackItUpStore.snapshotsLoaded && !BackItUpStore.snapshotsBusy)
      BackItUpStore.loadSnapshots()
  }

  // Three triggers, and each one covers a case the others miss.
  //
  // onVisibleChanged does not fire for the value an item is born with, so a
  // browser that starts out visible needs Component.onCompleted too. And at
  // that moment the destination list is usually still empty, because the first
  // status poll has not come back yet, so loadSnapshots would return without
  // doing anything and never try again. Opening the panel and going straight
  // to the browser is exactly how somebody in a hurry uses this.
  onVisibleChanged: ensureLoaded()
  Component.onCompleted: ensureLoaded()

  Connections {
    target: BackItUpStore
    function onDestinationsChanged() { root.ensureLoaded() }
  }

  property string snapshotId: ""
  property string rootPath: ""

  // Kept with the active snapshot so source selection stays stable while
  // snapshots update asynchronously.
  property var snapshotRoots: []
  property string filter: ""

  // The restore queue: what will be brought back, in the order it was picked.
  // A list rather than a flag, because the footer has to name a count and the
  // restore has to pass every path.
  property var queue: []

  readonly property var queuedPaths: {
    var out = []
    for (var i = 0; i < root.queue.length; i++) out.push(String(root.queue[i].path))
    return out
  }

  // Expanded by the "+N more" chip. Collapsed shows the four most recent
  // snapshots, which is what fits without turning the timeline into a scroll
  // area on a narrow panel.
  property bool timelineExpanded: false

  // --- sizing --------------------------------------------------------------
  //
  // The panel caps its content at 560px (Panel.qml) and this view wants more:
  // header, timeline, source chips, breadcrumb, filter and footer come to
  // roughly 250px before the listing gets a pixel. The old fixed 300px listing
  // on top of that pushed the footer past the panel's bottom edge, where it
  // was clipped mid-sentence and could not be clicked.
  //
  // So the listing is the one element that gives way. The panel sizes itself
  // from desiredHeight -- the height this view would like -- and the listing
  // then takes whatever is left of the height actually granted. Everything
  // else is measured by its own Column (chromeHeight), which never depends on
  // the listing, so the two can be worked out in either order.
  //
  // The listing asks for a fixed 300px rather than its content height, and
  // that is deliberate. listPath clears entries on a cache miss, so a
  // content-driven height made the whole panel snap small for the length of
  // every uncached folder and grow again -- a jump on each step through a
  // hierarchy, which is the one thing you do constantly here. A fixed region
  // also matches the mockup, and matches every file browser: short folders
  // leave space rather than resizing the window around them.
  readonly property real listMinHeight: Style.space(72)
  readonly property real listNaturalHeight: Style.space(300)
  readonly property real listHeight:
    Math.max(root.listMinHeight,
             Math.min(root.listNaturalHeight, root.height - column.chromeHeight))
  readonly property real desiredHeight: column.chromeHeight + root.listNaturalHeight

  implicitHeight: column.chromeHeight + root.listHeight

  function currentSnapshot() {
    for (var i = 0; i < BackItUpStore.snapshots.length; i++)
      if (BackItUpStore.snapshots[i].id === root.snapshotId)
        return BackItUpStore.snapshots[i]
    return null
  }

  function containsRoot(roots, path) {
    for (var i = 0; i < roots.length; i++)
      if (String(roots[i]) === path) return true
    return false
  }

  function isAtOrBelowRoot(path, base) {
    if (base === "/") return path.indexOf("/") === 0
    return path === base || path.indexOf(base + "/") === 0
  }

  // --- the timeline ------------------------------------------------------

  readonly property var visibleChips: {
    var list = BackItUpStore.snapshots || []
    if (root.timelineExpanded || list.length <= 4) return list
    return list.slice(0, 4)
  }

  readonly property int hiddenChipCount:
    Math.max(0, (BackItUpStore.snapshots || []).length - 4)

  // "Today" / "Yesterday" / "4 Oct", from the same helper the menu uses, so
  // the two never drift apart. Split on the comma rather than formatted twice:
  // there is one phrasing of a date in this widget.
  function chipDay(snap) {
    var phrase = BackItUpStore.menuDate(snap ? snap.time : "")
    var cut = phrase.indexOf(", ")
    return cut === -1 ? phrase : phrase.substring(0, cut)
  }

  // The second line: when it ran, and how much it holds. Per-snapshot size is
  // restic's own summary, which already arrives with the snapshot list -- no
  // extra call. Demo data carries only a file count, which is worth showing
  // rather than showing nothing.
  function chipDetail(snap) {
    if (!snap) return ""
    var phrase = BackItUpStore.menuDate(snap.time)
    var cut = phrase.indexOf(", ")
    var time = cut === -1 ? "" : phrase.substring(cut + 2)

    var summary = snap.summary || {}
    var size = ""
    if (summary.total_bytes_processed)
      size = BackItUpStore.humanBytes(summary.total_bytes_processed)
    else if (summary.total_files_processed)
      size = Number(summary.total_files_processed) + " files"

    if (time !== "" && size !== "") return time + " \u00b7 " + size
    return time !== "" ? time : size
  }

  // --- navigation --------------------------------------------------------

  function openRoot(path) {
    root.rootPath = String(path)
    root.cursorIndex = 0
    root.queue = []
    clearFilter()
    BackItUpStore.listPath(root.snapshotId, root.rootPath)
  }

  function clearFilter() { root.filter = ""; root.cursorIndex = 0 }

  function appendFilter(text) {
    if (text === undefined || text === null) return
    var ch = String(text)
    if (ch.length !== 1 || ch < " ") return
    root.filter += ch
    root.cursorIndex = 0
  }

  function backspaceFilter() {
    if (root.filter.length > 0) { root.filter = root.filter.slice(0, -1); root.cursorIndex = 0 }
  }

  // Switching snapshots keeps you where you were standing. Picking another
  // point in the timeline is nearly always "what did this folder look like
  // then", and being thrown back to the top of a million-file tree every time
  // makes comparing two dates a chore.
  //
  // A path that did not exist in the older snapshot comes back as an empty
  // listing, not an error -- restic cannot tell us the difference, and neither
  // can we without a second call on the parent. So we stay there and say the
  // folder is empty in this snapshot; ".." is one keystroke away.
  function openSnapshot(id) {
    var previous = BackItUpStore.currentPath
    var previousRoot = root.rootPath
    root.snapshotId = id
    root.cursorIndex = 0
    // The queue belonged to the snapshot you were looking at. A path from
    // another point in time may not exist in this one, and restoring it would
    // silently bring back an older copy of what you meant to bring back now.
    root.queue = []
    clearFilter()

    var snapshot = currentSnapshot()
    var roots = snapshot && snapshot.paths ? snapshot.paths : []
    root.snapshotRoots = roots
    root.rootPath = roots.length > 0 ? String(roots[0]) : "/"
    if (containsRoot(roots, previousRoot)) root.rootPath = previousRoot

    var target = root.rootPath
    if (previous !== "" && isAtOrBelowRoot(previous, root.rootPath)) target = previous
    BackItUpStore.listPath(id, target)
  }

  function enterDirectory(path) {
    root.cursorIndex = 0
    clearFilter()
    BackItUpStore.listPath(root.snapshotId, path)
  }

  function goUp() {
    var path = BackItUpStore.currentPath
    if (path === root.rootPath || path === "/") return
    var parent = path.substring(0, path.lastIndexOf("/"))
    if (parent === "") parent = "/"
    enterDirectory(parent)
  }

  readonly property bool atRoot: BackItUpStore.currentPath === root.rootPath
                                 || BackItUpStore.currentPath === ""

  readonly property string currentFolderName: {
    var path = BackItUpStore.currentPath
    if (path === "" || path === "/") return "/"
    return path.substring(path.lastIndexOf("/") + 1)
  }

  // The path as clickable steps from the snapshot's own root down to where you
  // are. Built from rootPath rather than from / so the first step is always a
  // place the snapshot actually contains.
  readonly property var crumbs: {
    var base = root.rootPath
    var current = BackItUpStore.currentPath
    if (base === "" || current === "") return []

    var out = []
    var baseLabel = base === "/" ? "/" : base.substring(base.lastIndexOf("/") + 1)
    out.push({ label: baseLabel, path: base })
    if (current === base || !isAtOrBelowRoot(current, base)) return out

    var rest = current.substring(base.length)
    var parts = rest.split("/")
    var walk = base === "/" ? "" : base
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] === "") continue
      walk += "/" + parts[i]
      out.push({ label: parts[i], path: walk })
    }
    return out
  }

  // --- the listing -------------------------------------------------------

  // The keyboard cursor. ".." lives in the model rather than in ListView's
  // header, so the cursor walks over it like any other row instead of jumping
  // past the one thing you reach for most.
  property int cursorIndex: 0

  readonly property var rows: {
    var out = []
    if (!root.atRoot) out.push({ name: "..", type: "up", path: "", size: null, mtime: null })
    var entries = root.visibleEntries
    for (var i = 0; i < entries.length; i++) out.push(entries[i])
    return out
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    var next = cursorIndex + delta
    // Clamped, not wrapped: running off the end of a long listing and landing
    // back at the top loses your place more often than it helps.
    if (next < 0) next = 0
    if (next > rows.length - 1) next = rows.length - 1
    cursorIndex = next
    listView.positionViewAtIndex(next, ListView.Contain)
  }

  function activateCursor() {
    root.openRow(root.cursorIndex)
  }

  onRowsChanged: if (cursorIndex > rows.length - 1) cursorIndex = Math.max(0, rows.length - 1)

  readonly property var visibleEntries: {
    var all = BackItUpStore.entries || []
    if (root.filter === "") return all
    var needle = root.filter.toLowerCase()
    var out = []
    for (var i = 0; i < all.length; i++)
      if (String(all[i].name).toLowerCase().indexOf(needle) !== -1) out.push(all[i])
    return out
  }

  // --- the queue ---------------------------------------------------------

  function isQueued(path) {
    var needle = String(path)
    for (var i = 0; i < root.queue.length; i++)
      if (String(root.queue[i].path) === needle) return true
    return false
  }

  property int anchorIndex: 0

  function _entry(row) {
    return { path: String(row.path), name: String(row.name), type: String(row.type) }
  }

  // Standard file-manager selection: a plain click picks one row, Ctrl-click
  // adds or drops a single row, Shift-click takes everything from the anchor.
  // Folders are picked exactly like files -- the whole row is a choice, and
  // the chevron or a double-click is what opens one -- so the list the restore
  // button commits is built the same way everywhere.
  function selectOnly(row, index) {
    if (String(row.path) === "") return
    root.queue = [root._entry(row)]
    root.anchorIndex = index
  }

  function toggleSelection(row, index) {
    var path = String(row.path)
    if (path === "") return
    var next = []
    var dropped = false
    for (var i = 0; i < root.queue.length; i++) {
      if (String(root.queue[i].path) === path) { dropped = true; continue }
      next.push(root.queue[i])
    }
    if (!dropped) next.push(root._entry(row))
    root.queue = next
    if (index !== undefined) root.anchorIndex = index
  }

  function selectRange(index) {
    var from = Math.min(root.anchorIndex, index)
    var to = Math.max(root.anchorIndex, index)
    var next = []
    for (var i = from; i <= to; i++) {
      var row = root.rows[i]
      if (!row || String(row.type) === "up" || String(row.path) === "") continue
      next.push(root._entry(row))
    }
    root.queue = next
  }

  function selectAllVisible() {
    var next = []
    for (var i = 0; i < root.rows.length; i++) {
      var row = root.rows[i]
      if (String(row.type) === "up" || String(row.path) === "") continue
      next.push(root._entry(row))
    }
    root.queue = next
  }

  function clearSelection() { root.queue = [] }

  // A click on a row. ".." walks up; everything else is a choice, with the
  // usual modifiers.
  function activateRow(index, modifiers) {
    if (index < 0 || index >= root.rows.length) return
    var row = root.rows[index]
    if (String(row.type) === "up") { root.goUp(); return }
    if (modifiers & Qt.ShiftModifier) root.selectRange(index)
    else if (modifiers & Qt.ControlModifier) root.toggleSelection(row, index)
    else root.selectOnly(row, index)
  }

  // A double-click or a chevron click: folders open. Enter reaches here too.
  function openRow(index, dropSelection) {
    if (index < 0 || index >= root.rows.length) return
    var row = root.rows[index]
    if (String(row.type) === "up") { root.goUp(); return }
    if (String(row.type) === "dir") {
      // A double-click's first click already selected the folder; entering it
      // drops that again, so walking down a tree does not silently add every
      // folder you passed through to the restore list. The chevron never
      // selected it, so it passes false.
      if (dropSelection === true) root.dropFromSelection(String(row.path))
      root.enterDirectory(String(row.path))
    } else {
      root.toggleSelection(row, index)
    }
  }

  function dropFromSelection(path) {
    var needle = String(path)
    var next = []
    for (var i = 0; i < root.queue.length; i++)
      if (String(root.queue[i].path) !== needle) next.push(root.queue[i])
    root.queue = next
  }

  function restoreQueued() {
    if (root.queue.length === 0) return
    root.restoreRequest = root.queuedPaths
    restoreConfirm.opened = true
  }

  // The folder you are standing in is restorable like anything else: select
  // the row for it after stepping up, or Ctrl+A to pick everything visible.

  Connections {
    target: BackItUpStore
    function onSnapshotsChanged() {
      // Also fires after switching destination, where snapshotId was cleared:
      // landing on the newest backup of whatever you just picked is the only
      // sensible place to start. And after a delete in Manage Backups, which
      // shares this list: an id that is no longer in it would leave the
      // timeline with nothing selected, so one that vanished re-picks the
      // newest remaining backup.
      var list = BackItUpStore.snapshots
      if (list.length === 0) {
        root.snapshotId = ""
        return
      }
      for (var i = 0; i < list.length; i++)
        if (String(list[i].id) === root.snapshotId) return
      root.openSnapshot(String(list[0].id))
    }
  }

  Column {
    id: column
    // Anchored in width only. anchors.fill would take the height from the
    // parent as well, while the parent takes its implicitHeight from this
    // Column -- the kind of circular sizing where nothing decides the layout.
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(10)

    // Everything above the listing, measured as one block so the listing's own
    // height can be worked out from what is left over.
    Column {
      id: upper
      width: parent.width
      spacing: column.spacing

        // --- header ------------------------------------------------------------

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
            text: "Restore"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          // Which backup set you are looking in. A pill when there is only one,
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
              root.snapshotId = ""
              // The roots belong to the snapshot we were looking at, which is not
              // in this destination. Without clearing them the source picker keeps
              // offering them while the new snapshots load, and picking one asks
              // the CLI to list a path under no snapshot at all.
              root.snapshotRoots = []
              root.queue = []
              BackItUpStore.browseDestination(value)
              root.takeFocus()
            }
            onPopupOpenChanged: if (!popupOpen) root.takeFocus()
          }
        }

        // --- snapshot timeline -------------------------------------------------

        Column {
          width: parent.width
          spacing: Style.space(5)
          visible: (BackItUpStore.snapshots || []).length > 0

          Text {
            text: "Backup"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.5
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.visibleChips

              SnapshotChip {
                day: root.chipDay(modelData)
                detail: root.chipDetail(modelData)
                selected: String(modelData.id) === root.snapshotId
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: {
                  root.openSnapshot(String(modelData.id))
                  root.takeFocus()
                }
              }
            }

            SnapshotChip {
              visible: !root.timelineExpanded && root.hiddenChipCount > 0
              day: "+" + root.hiddenChipCount
              detail: "more"
              muted: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                root.timelineExpanded = true
                root.takeFocus()
              }
            }
          }
        }

        // A snapshot can contain several configured source directories. Stay at
        // one source root while browsing, but make every root reachable instead
        // of silently treating the first path as the whole snapshot.
        Flow {
          width: parent.width
          visible: root.snapshotRoots.length > 1
          spacing: Style.space(6)

          Text {
            text: "Source"
            // No anchors here, and no anchors are possible: a Flow lays out its
            // children by top-left and ignores them, so centring is done with a
            // matching height instead of an anchor.
            height: Style.space(26)
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.snapshotRoots

            Rectangle {
              readonly property bool current: String(modelData) === root.rootPath
              implicitWidth: srcText.implicitWidth + Style.space(14)
              implicitHeight: srcText.implicitHeight + Style.space(7)
              radius: Style.space(6)
              color: current ? StatusPalette.tint(root.accent, 0.13)
                             : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              border.width: Style.space(1)
              border.color: current ? StatusPalette.line(root.accent, 0.5)
                                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

              Text {
                id: srcText
                anchors.centerIn: parent
                text: String(modelData)
                textFormat: Text.PlainText
                color: parent.current ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.openRoot(String(modelData))
                  root.takeFocus()
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: BackItUpStore.snapshotsBusy || BackItUpStore.snapshotsError !== ""
          text: BackItUpStore.snapshotsBusy ? "Loading snapshots\u2026" : BackItUpStore.snapshotsError
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: BackItUpStore.snapshotsError !== "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // --- breadcrumb --------------------------------------------------------

        Flow {
          width: parent.width
          visible: root.crumbs.length > 0
          spacing: Style.space(2)

          Repeater {
            model: root.crumbs

            Row {
              spacing: Style.space(2)

              Text {
                visible: index > 0
                text: "\u203A"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                // Both crumbs are caption-sized, so the Row's own top alignment
                // lines them up. Anchors here would break the Row's layout.
                // The last crumb is where you are, and is not a link to anywhere.
                readonly property bool here: index === root.crumbs.length - 1
                text: String(modelData.label)
                textFormat: Text.PlainText
                color: here ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(2)
                  enabled: !parent.here
                  hoverEnabled: true
                  cursorShape: parent.here ? Qt.ArrowCursor : Qt.PointingHandCursor
                  onClicked: {
                    root.enterDirectory(String(modelData.path))
                    root.takeFocus()
                  }
                }
              }
            }
          }
        }

        // --- filter ------------------------------------------------------------
        //
        // Shaped like a field, but not an input: a TextField would take the
        // keyboard away from the listing, and typing here is the listing's filter
        // (the key sink above owns the keys). The field only shows what was typed,
        // and says what happens if nothing has been.
        Rectangle {
          width: parent.width
          implicitHeight: Style.space(28)
          radius: Style.space(6)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
          border.width: Style.space(1)
          border.color: root.filter !== ""
                        ? StatusPalette.line(root.accent, 0.45)
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              id: searchGlyph
              anchors.verticalCenter: parent.verticalCenter
              text: BackItUpStore.iconSearch
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.filter !== ""
                    ? root.filter
                    : (BackItUpStore.currentPath !== "" ? "Filter this folder\u2026" : "")
              textFormat: Text.PlainText
              elide: Text.ElideRight
              width: parent.width - searchGlyph.width - parent.spacing
              color: root.filter !== "" ? root.foreground : Qt.darker(root.foreground, 1.9)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: root.takeFocus()
          }
        }

        Text {
          width: parent.width
          visible: text !== ""
          text: {
            var total = BackItUpStore.entries.length
            if (total === 0) return ""
            if (root.filter !== "")
              return root.visibleEntries.length + " of " + total + " shown"
            return total < 12 ? "" : total + " items \u00b7 type anything to filter"
          }
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.filter !== "" ? root.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // A caveat about the listing, so it belongs above it rather than
        // inside: when this shows, the rows fill the whole region.
        Text {
          width: parent.width
          visible: BackItUpStore.listTruncated
          text: "Showing the first entries only \u2014 use the filter, or open a subfolder."
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // --- listing -----------------------------------------------------------

        Text {
          width: parent.width
          visible: BackItUpStore.listBusy || BackItUpStore.listError !== ""
          text: BackItUpStore.listBusy ? "Reading folder\u2026" : BackItUpStore.listError
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: BackItUpStore.listError !== "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

    }

    Rectangle {
      id: listBox
      width: parent.width
      height: root.listHeight
      // Always in the layout, even with nothing in it: hiding it would drop
      // 300px out of the column and resize the panel on every folder change.
      color: "transparent"

      ListView {
        id: listView
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        model: root.rows

        delegate: RestoreRow {
          width: listView.width
          entryName: String(modelData.name)
          entryType: String(modelData.type)
          entrySize: modelData.size
          entryTime: modelData.mtime
          queued: String(modelData.type) !== "up" && root.isQueued(modelData.path)
          hasCursor: index === root.cursorIndex
          foreground: root.foreground
          dim: root.dim
          accent: root.accent
          fontFamily: root.fontFamily
          onActivated: function(modifiers) {
            root.takeFocus()
            root.cursorIndex = index
            root.activateRow(index, modifiers)
          }
          onOpened: function(viaDoubleClick) {
            root.takeFocus()
            root.cursorIndex = index
            root.openRow(index, viaDoubleClick)
          }
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
          if (BackItUpStore.listBusy || BackItUpStore.listError !== "") return ""
          if (BackItUpStore.entries.length === 0)
            return root.atRoot ? "" : "This folder is empty in this snapshot."
          if (root.visibleEntries.length === 0) return "Nothing here matches the filter."
          return ""
        }
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // The status lines and the footer. Below the listing rather than inside it,
    // so the footer stays reachable no matter how long the folder is.
    Column {
      id: lower
      width: parent.width
      spacing: column.spacing

        // --- footer ------------------------------------------------------------

        PanelSeparator { width: parent.width }

        Rectangle {
          width: parent.width
          implicitHeight: footerRow.implicitHeight + Style.space(9) * 2
          radius: Style.space(8)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
          border.width: Style.space(1)
          border.color: StatusPalette.line(root.accent, 0.22)

          Row {
            id: footerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(9)
            anchors.rightMargin: Style.space(9)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(Style.space(60),
                              parent.width - restoreButton.width - parent.spacing)
              spacing: 0

              Text {
                width: parent.width
                text: {
                  if (BackItUpStore.restoreBusy) return "Restoring\u2026"
                  var n = root.queue.length
                  if (n === 0) return "Nothing picked"
                  return "Restore " + n + (n === 1 ? " item" : " items")
                }
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: root.queue.length > 0
              }

              Text {
                width: parent.width
                // The dated folder is the safety property: a restore never writes
                // over your work, it lands somewhere you then move from. The name
                // is the CLI's to choose, so this says where rather than guessing
                // which date it will pick.
                text: {
                  if (BackItUpStore.restoreError !== "") return BackItUpStore.restoreError
                  if (BackItUpStore.restoreTarget !== "") return "Restored into " + BackItUpStore.restoreTarget
                  if (root.queue.length === 0) return "Click files or folders to choose what to restore"
                  return "into a new folder under ~/Restored/"
                }
                textFormat: Text.PlainText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                color: BackItUpStore.restoreError !== "" ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // One button, and it commits the selection. Rows are chosen in the
            // list -- folders included, since a click now selects rather than
            // opens -- so there is no second, hidden way to name a target and
            // nothing for this button to guess.
            PanelButton {
              id: restoreButton
              anchors.verticalCenter: parent.verticalCenter
              // Bare "Restore", not "Restore 2": the footer sentence above
              // already carries the count, and a button that changes width with
              // the selection moves under the pointer that is about to click it.
              label: "Restore"
              glyph: BackItUpStore.iconRestore
              variant: "primary"
              enabled: !BackItUpStore.restoreBusy && root.queue.length > 0
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.restoreQueued()
            }
          }
        }    }

    // upper and lower are measured independently of the listing, so this never
    // depends on the height it is used to compute.
    readonly property real chromeHeight:
      upper.implicitHeight + lower.implicitHeight + column.spacing * 2

  }

  ConfirmDialog {
    id: restoreConfirm
    anchors.fill: parent
    z: 10
    // The full destination is spelled out, because the one thing worth
    // confirming here is where the files land -- never on top of the original.
    // plain(): the name is a filename out of the backup, and ConfirmDialog is a
    // shell component that sets no textFormat -- so its Text falls back to
    // Qt's AutoText, which renders anything tag-shaped as rich text and would
    // fetch what it points at. Same reason the bar tooltip goes through plain().
    message: root.restoreTargetName !== ""
             ? "Restore " + root.confirmSubject
               + " into a new folder under ~/Restored? Nothing outside it is touched."
             : ""
    confirmText: "Restore"
    fontFamily: root.fontFamily
    onConfirmed: root.confirmAccept()
    onCanceled: root.confirmCancel()
  }
}
