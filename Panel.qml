import Quickshell
import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui

// BackIt Up: scheduled restic backups, with the state of the last one a
// glance away and a snapshot browser one click further.
//
// The bar shows the icon and nothing else. Bar space is scarce and the age of
// a backup is not a number anyone wants to read continuously -- you only want
// to be disturbed when something is wrong, which is what the colour is for.
// The relative time lives in the tooltip and at the top of the panel.
//
// Everything with state lives in BackItUpStore, a singleton: a bar widget
// is instantiated once per monitor, so timers and processes declared here
// would run twice on a two-monitor setup.
Panel {
  id: root

  moduleName: "larrynz.backitup"
  ipcTarget: "larrynz.backitup"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color dimmer: Qt.darker(foreground, 2.2)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Which view the panel is showing. The restore browser reuses the same
  // KeyboardPanel and simply swaps the content, because a second window would
  // lose keyboard focus on Wayland the moment the first one closed.
  property bool browsing: false
  property bool managing: false

  // The guided first run. Separate from browsing: browsing is reading history
  // and hands the keyboard to the listing, setting up is typing and hands it
  // to the form.
  property bool settingUp: false
  // The folder picker: a sub-state of setting up. The picker replaces the
  // form while it is open and hands the chosen path back to the field.
  property bool pickingRepo: false
  // What the picker is for: "repo" fills the repository field, "source"
  // adds a folder to the backup list.
  property string pickerTarget: "repo"
  // The folders to back up, edited in the setup form's list.
  property var setupSources: []
  property string pickerPath: "/run/media"
  property string setupValidationError: ""
  property string setupSchedule: "daily"
  // The system-snapshot toggle: pairs a bootable rollback point with each
  // backup. Seeded from the destination on edit, kept as a draft like every
  // other field once set.
  property bool setupSystemSnapshot: false
  // The setup form is editing an existing destination (opened from the main
  // view's "Edit configuration..."). The password field may then stay empty:
  // the destination keeps its password source unless the user types a new
  // one, and editHasPasswordSource records whether there is one to keep.
  property bool editingConfig: false
  property bool editHasPasswordSource: false
  // The password field's meaning: off, the text is the literal password (a
  // 600 key file); on, the text is a command that prints it -- pass show
  // <entry>, op read <secret>, anything that works where the backups run.
  property bool setupPassIsCommand: false
  // The setup form seeds its source list from the configuration, but the
  // status that carries the list is fetched asynchronously: the form can be
  // open before it arrives. Seed once on the first entry per panel lifetime
  // and re-seed when the fetch lands; after that the list is a draft like
  // every other field -- re-seeding on every entry would clobber folders
  // the user added but has not applied yet.
  property bool setupSeeded: false
  property bool setupEverOpened: false

  // Colour is the bar's whole vocabulary -- the icon carries nothing else --
  // so each state gets its own hue rather than borrowing the accent. Running
  // used to paint the same red as failed, which made "busy" and "broken"
  // indistinguishable at a glance, the one thing the bar exists to prevent.
  readonly property color barIconColor: {
    var s = BackItUpStore.overallStatus
    if (s === "busy") return StatusPalette.busy
    if (s === "bad") return urgent
    if (s === "warn") return StatusPalette.warn
    if (!BackItUpStore.configured) return Qt.darker(barForeground, 1.9)
    return barForeground
  }

  // --- the verdict ------------------------------------------------------
  //
  // One sentence at the top of the panel answers "am I safe?" before any
  // number appears. Derived here rather than inside the hero, so the rule --
  // which state outranks which -- sits in one place beside the store's own
  // classification, and the view only paints what it is handed.
  function failedCount() {
    var n = 0
    for (var i = 0; i < BackItUpStore.destinations.length; i++)
      if (BackItUpStore.destinationFailed(BackItUpStore.destinations[i])) n++
    return n
  }

  function compositeVerdict() {
    var S = BackItUpStore

    if (S.configInvalid) {
      return { state: "bad", title: "Configuration problem",
               sub: S.configError, subStrong: "", meta: "", glyph: S.iconAlert }
    }
    if (!S.configured || S.destinations.length === 0) {
      return { state: "idle", title: "No backups yet",
               sub: "Set one up and the panel walks you through it",
               subStrong: "", meta: "", glyph: S.iconShield }
    }

    if (S.anyRunning) {
      var run = S.runningDestination
      var pr = run ? run.progress : null
      var bytes = (pr && pr.total_bytes)
        ? S.humanBytes(pr.bytes_done) + " / " + S.humanBytes(pr.total_bytes)
        : ""
      return { state: "busy", title: "Backing up",
               sub: run ? S.destinationLabel(run) + (bytes ? " \u00b7 " : "") : "",
               subStrong: bytes,
               meta: run ? S.workingPhrase(run.name) + "\u2026" : "",
               glyph: S.iconPlay }
    }

    if (S.anyFailed) {
      var n = root.failedCount()
      var fail = S.failedDestination
      return { state: "bad",
               title: S.multiple ? n + " of " + S.destinations.length + " need attention"
                                 : "Backup failed",
               sub: fail ? S.destinationLabel(fail) : "",
               subStrong: "",
               meta: fail && fail.last_run ? S.menuDate(fail.last_run.finished_at) : "",
               glyph: S.iconAlert }
    }

    if (S.overallStatus === "warn") {
      var warn = S.attentionDestination
      var when = S.active && S.active.last_run ? S.active.last_run.finished_at : ""
      return { state: "warn", title: "Needs a look",
               sub: warn ? S.destinationLabel(warn) : "",
               subStrong: "",
               meta: "Last backup " + S.relativeTime(when),
               glyph: S.iconAlert }
    }

    var latest = S.active && S.active.last_run ? S.active.last_run.finished_at : ""
    return { state: "ok", title: "Protected",
             sub: S.multiple ? "All " + S.destinations.length + " destinations up to date"
                             : "Last backup ",
             subStrong: S.multiple ? "" : S.relativeTime(latest),
             meta: S.multiple ? "" : S.menuDate(latest),
             glyph: S.iconShield }
  }

  readonly property var verdict: root.compositeVerdict()

  // Panel is a bare Item with no size of its own, so without this the bar
  // hands the widget zero width -- and a zero-width widget still paints its
  // children, so it looks fine and is simply not clickable. Derive the size
  // from the content, never from a child that fills this item.
  // A failed backup gets a mark, not just a colour: colour alone is the one
  // signal a bar full of coloured glyphs cannot carry, and it is invisible to
  // anyone who does not distinguish red from the foreground.
  readonly property bool showBadge: BackItUpStore.anyFailed
  readonly property int badgeSize: showBadge ? Style.space(9) : 0
  readonly property int barContentWidth:
    Style.bar.iconFont + (showBadge ? badgeSize - Style.space(3) : 0)

  readonly property int barSlot: barContentWidth + Style.space(10)
  readonly property real openPanelIndicatorWidth: barContentWidth
  readonly property real openPanelIndicatorHeight: barContentWidth
  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  function applySettings() {
    BackItUpStore.fontFamily = root.fontFamily
    BackItUpStore.timeFormat = String(root.setting("timeFormat", "HH:mm"))
    BackItUpStore.dateFormat = String(root.setting("dateFormat", "d MMM"))
  }

  // The default calendar expression each schedule preset expands to, so the
  // setup form can show it in an editable field: the presets stay short
  // words to cycle through, and the exact time they fire is right there to
  // alter. Empty for manual (no field) and custom (type from scratch).
  function presetExpression(sched) {
    if (sched === "daily") return "*-*-* 03:00:00"
    if (sched === "weekly") return "Mon *-*-* 03:00:00"
    if (sched === "monthly") return "*-*-01 03:00:00"
    if (sched === "hourly") return "*-*-* *:00:00"
    return ""
  }

  // Fills the setup form from the first configured destination, so small
  // changes (a new schedule, another folder) do not mean retyping everything.
  // Apply merges by name, so unchanged fields survive. The password field is
  // left empty on purpose: it is never shown back, and the existing password
  // source is kept unless the user types a replacement.
  function editConfig() {
    var d = BackItUpStore.destinations && BackItUpStore.destinations.length > 0
            ? BackItUpStore.destinations[0] : null
    if (!d) return
    root.editingConfig = true
    root.settingUp = true
    setupName.text = d.name || ""
    setupRepo.text = d.repository_display || ""
    var sched = d.schedule || ""
    if (["daily", "weekly", "monthly", "hourly"].indexOf(sched) >= 0) {
      setupSchedule = sched
      setupScheduleCustom.text = root.presetExpression(sched)
    } else if (sched !== "") {
      // An OnCalendar expression the presets cannot name: show it in the
      // custom field, where the CLI validates it again on apply.
      setupSchedule = "custom"
      setupScheduleCustom.text = sched
    } else {
      // No schedule in the config: the custom field, empty. An empty field
      // means no schedule, so the round-trip is faithful.
      setupSchedule = "custom"
      setupScheduleCustom.text = ""
    }
    root.setupPassIsCommand = d.password_mode === "command"
    root.editHasPasswordSource = d.password_mode === "command" || d.password_mode === "key"
    root.setupSystemSnapshot = d.system_snapshot_enabled === true
    // A password_command is not a secret -- the config holds it in plain
    // text -- so it is shown back in the field, editable. A key file's
    // contents are a secret: the field stays empty, and the stored password
    // is kept unless the user types a replacement.
    setupPassword.text = d.password_mode === "command" ? (d.password_command || "") : ""
    var src = BackItUpStore.sources && BackItUpStore.sources.length > 0
              ? BackItUpStore.sources.slice() : [Quickshell.env("HOME") || "/"]
    root.setupSources = src
    root.setupValidationError = ""
  }

  // Applied on settingsChanged as well as on completion: the host assigns
  // `settings` after constructing the widget, so reading them only in
  // onCompleted means reading an empty object.
  onSettingsChanged: root.applySettings()
  Component.onCompleted: root.applySettings()

  onOpenedChanged: {
    if (!opened) {
      root.browsing = false
      root.managing = false
      // The picker is a sub-state of setting up, but the close reset above
      // did not cover it: click away while picking and the picker was still
      // visible when the panel reopened -- drawing over the main view until
      // the setup flow was re-entered.
      root.pickingRepo = false
      root.editingConfig = false
      root.settingUp = false
      return
    }
    BackItUpStore.refresh()
  }

  // With the key catcher blocked, nothing else claims the keyboard: the
  // listing has to take it, and give it back on the way out.
  onBrowsingChanged: {
    if (browsing) browser.takeFocus()
    else if (!settingUp) keyCatcher.forceActiveFocus()
  }

  onManagingChanged: {
    if (managing) manageBrowser.takeFocus()
    else if (!settingUp && !browsing) keyCatcher.forceActiveFocus()
  }

  onSettingUpChanged: {
    if (settingUp) {
      setupName.forceActiveFocus()
      // The schedule field shows the selected preset's default on entry: the
      // first open selects daily while the field starts out empty. Only when
      // it is empty, though -- a draft the user typed survives closing the
      // panel, like the other fields. editConfig re-populates it right after
      // this fires, so an edited expression is not clobbered either.
      if (setupScheduleCustom.text === "")
        setupScheduleCustom.text = root.presetExpression(setupSchedule)
      // Seed only on the first entry: afterwards the source list is a draft
      // that survives closing the panel, like the name, repo and password
      // fields. Re-seeding here would wipe folders the user added but has
      // not applied yet.
      if (!root.setupEverOpened) {
        root.setupEverOpened = true
        root.setupSeeded = false
        var src = BackItUpStore.sources && BackItUpStore.sources.length > 0
                  ? BackItUpStore.sources : []
        root.setupSources = src.length > 0 ? src.slice() : [Quickshell.env("HOME") || "/"]
      }
    } else if (!browsing) {
      keyCatcher.forceActiveFocus()
    }
  }

  Connections {
    target: BackItUpStore
    function onSourcesChanged() {
      if (!root.settingUp || root.setupSeeded) return
      root.setupSeeded = true
      var src = BackItUpStore.sources && BackItUpStore.sources.length > 0
                ? BackItUpStore.sources.slice() : []
      root.setupSources = src.length > 0 ? src : [Quickshell.env("HOME") || "/"]
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    // iconComponent is loaded into a square canvas of opticalSize, sized for a
    // single glyph. Widen it too, or the badge falls outside it.
    opticalSize: root.barContentWidth
    // The shared bar tooltip is a shell component, so its textFormat is not
    // ours to set: strip anything that could be read as markup before it goes
    // in. Our own strings are safe, but a destination name comes from
    // config.json and an error message comes from restic.
    tooltipText: BackItUpStore.plain(BackItUpStore.tooltip)

    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: BackItUpStore.iconBackItUp
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering
          color: root.barIconColor

          // A slow pulse while a backup runs. Deliberately not a percentage in
          // the bar: the number would demand to be read, where the pulse only
          // says "busy" and the panel carries the detail.
          SequentialAnimation on opacity {
            running: BackItUpStore.anyRunning
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { from: 1.0; to: 0.45; duration: 900; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.45; to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
          }
          onVisibleChanged: if (!BackItUpStore.anyRunning) opacity = 1.0
        }

        // Exclamation badge, pinned to the glyph's top right.
        Rectangle {
          visible: root.showBadge
          width: root.badgeSize
          height: root.badgeSize
          radius: width / 2
          color: root.urgent
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.horizontalCenterOffset: Style.bar.iconFont / 2
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: -Style.bar.iconFont / 2.6

          Text {
            anchors.centerIn: parent
            text: "!"
            textFormat: Text.PlainText
            color: Color.background
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.badgeSize * 0.8)
            font.bold: true
            renderType: Text.NativeRendering
          }
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) BackItUpStore.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher

    // Computed from plain property reads rather than through
    // fittedContentWidth inside the binding: that form evaluates once at open
    // and never re-runs, so the panel would keep the width of whichever view
    // happened to be showing when it opened.
    readonly property int desiredWidth:
      Style.space(root.browsing || root.managing ? 460
                  : (root.settingUp ? 420 : 332))
    contentWidth: Math.min(desiredWidth,
                           panel.availableCardWidth > 0 ? panel.availableCardWidth : desiredWidth)
    contentHeight: panel.fittedContentHeight(
                     root.browsing ? browser.implicitHeight
                                   : (root.managing ? manageBrowser.implicitHeight
                                   : (root.pickingRepo ? pickerColumn.implicitHeight
                                   : (root.settingUp ? setupColumn.implicitHeight
                                                     : mainColumn.implicitHeight))),
                     Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // Blocked while browsing, and that is not a detail: this component bakes
      // in vim navigation -- "j", "k", "l", "h" move the cursor and "x" is
      // delete, all checked before the plain-text fallback. Typing to filter a
      // listing is impossible under it; any word containing one of those
      // letters would steer the panel instead. While browsing or managing,
      // those views handle their own keys.
      blocked: root.browsing || root.managing || root.settingUp

      // ConfirmDialog handles the mouse itself but nothing else: without this
      // an open dialog would swallow Escape and Enter, and the only way out
      // would be to reach for the trackpad. Innermost dialog first, so Escape
      // dismisses the confirmation rather than the whole panel.
      onCloseRequested: {
        if (stopConfirm.opened) stopConfirm.opened = false
        else if (root.browsing && browser.confirmOpen) browser.confirmCancel()
        else if (root.browsing && browser.filter !== "") browser.clearFilter()
        else if (root.browsing) root.browsing = false
        else if (root.managing && manageBrowser.confirmOpen) manageBrowser.confirmCancel()
        else if (root.managing) root.managing = false
        else if (root.pickingRepo) root.pickingRepo = false
        else if (root.settingUp) root.settingUp = false
        else root.close()
      }

      onActivateRequested: {
        if (stopConfirm.opened) {
          BackItUpStore.stopBackup()
          stopConfirm.opened = false
        } else if (root.browsing && browser.confirmOpen) {
          browser.confirmAccept()
        } else if (root.managing && manageBrowser.confirmOpen) {
          manageBrowser.confirmAccept()
        }
      }

      onTabRequested: function(direction) { root.switchPanel(direction) }

      // --- main view ------------------------------------------------------

      Flickable {
        id: mainScroll
        anchors.fill: parent
        // Hidden while browsing AND while setting up: neither of those views
        // hides itself, so a setup form that forgot this line drew straight
        // over the main view -- both visible, overlapping text, unreadable.
        visible: !root.browsing && !root.managing && !root.settingUp
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: mainScroll.contentHeight > mainScroll.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded }

        Column {
          id: mainColumn
          width: mainScroll.width
          spacing: Style.space(12)
          topPadding: Style.space(2)
          bottomPadding: Style.space(2)

          // --- the verdict ------------------------------------------------

          StatusHero {
            width: parent.width
            state: root.verdict.state
            verdict: root.verdict.title
            sub: root.verdict.sub
            subStrong: root.verdict.subStrong
            meta: root.verdict.meta
            glyph: root.verdict.glyph
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // --- destinations -----------------------------------------------

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: BackItUpStore.destinations.length > 0

            Repeater {
              model: BackItUpStore.destinations

              DestinationCard {
                width: parent.width
                destination: modelData
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
            }
          }

          // --- progress for a run in flight --------------------------------

          Rectangle {
            width: parent.width
            visible: BackItUpStore.anyRunning
            height: visible ? Style.space(3) : 0
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

            Rectangle {
              height: parent.height
              radius: parent.radius
              color: StatusPalette.busy
              width: {
                var pr = BackItUpStore.progress
                if (!pr || pr.percent === undefined || pr.percent === null) return 0
                return Math.max(0, Math.min(1, Number(pr.percent))) * parent.width
              }
              Behavior on width { NumberAnimation { duration: 300 } }
            }
          }

          // Rather than an action that silently does nothing, say what is
          // missing. This is the state every fresh install starts in.
          Text {
            width: parent.width
            visible: BackItUpStore.configured && !BackItUpStore.unitsInstalled
            text: "Run \u2018omarchy-backitup install\u2019 once to enable backups"
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // --- actions ----------------------------------------------------

          PanelButton {
            width: parent.width
            visible: !BackItUpStore.configInvalid
                     && (!BackItUpStore.configured || BackItUpStore.unitsInstalled)
            variant: (BackItUpStore.configured && BackItUpStore.anyRunning)
                     ? "danger" : "primary"
            glyph: {
              if (!BackItUpStore.configured) return BackItUpStore.iconShield
              if (BackItUpStore.anyRunning) return BackItUpStore.iconStop
              return BackItUpStore.iconPlay
            }
            label: {
              if (!BackItUpStore.configured) return "Set Up Backups"
              if (BackItUpStore.anyRunning) return "Stop This Backup"
              return BackItUpStore.multiple ? "Back Up All" : "Back Up Now"
            }
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: {
              if (!BackItUpStore.configured) {
                root.settingUp = true
              } else if (BackItUpStore.anyRunning) {
                stopConfirm.opened = true
              } else if (BackItUpStore.multiple) {
                BackItUpStore.startAllBackups()
              } else {
                BackItUpStore.startBackup()
              }
            }
          }

          // A configuration the CLI will reject has no "back up now" to offer:
          // the one useful thing left is to open it and fix it.
          PanelButton {
            width: parent.width
            visible: BackItUpStore.configInvalid
            variant: "danger"
            glyph: BackItUpStore.iconSliders
            label: "Open Configuration"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: {
              BackItUpStore.openConfig()
              root.close()
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: BackItUpStore.configured

            PanelButton {
              width: (parent.width - parent.spacing) / 2
              glyph: BackItUpStore.iconRestore
              label: "Restore"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                root.browsing = true
                if (!BackItUpStore.snapshotsLoaded || BackItUpStore.snapshotsStale())
                  BackItUpStore.loadSnapshots()
              }
            }

            PanelButton {
              width: (parent.width - parent.spacing) / 2
              glyph: BackItUpStore.iconList
              label: "Manage"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                root.managing = true
                if (!BackItUpStore.snapshotsLoaded || BackItUpStore.snapshotsStale())
                  BackItUpStore.loadSnapshots()
              }
            }
          }

          // The sideways errands: changing the setup and reading the last
          // log. Set apart by a hairline and drawn as ghosts, so they never
          // look like the decision the primary button is.
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: (BackItUpStore.configured && BackItUpStore.destinations.length > 0)
                     || (BackItUpStore.configured && BackItUpStore.lastRun
                         && BackItUpStore.lastRun.log_file)

            Rectangle {
              width: parent.width
              height: Style.space(1)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              PanelButton {
                id: editConfigButton
                variant: "ghost"
                glyph: BackItUpStore.iconSliders
                label: "Edit configuration"
                visible: BackItUpStore.configured && BackItUpStore.destinations.length > 0
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.editConfig()
              }

              Item {
                width: Math.max(0, parent.width
                                   - (editConfigButton.visible ? editConfigButton.width : 0)
                                   - (logButton.visible ? logButton.width : 0)
                                   - parent.spacing * 2)
                height: 1
              }

              PanelButton {
                id: logButton
                variant: "ghost"
                label: "Log"
                glyph: BackItUpStore.iconChevronRight
                visible: BackItUpStore.configured && BackItUpStore.lastRun
                         && BackItUpStore.lastRun.log_file
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: BackItUpStore.openLog()
              }
            }
          }
        }
      }

      // --- restore view ------------------------------------------------------

      RestoreBrowser {
        id: browser
        anchors.fill: parent
        visible: root.browsing
        foreground: root.foreground
        dim: root.dim
        accent: root.accent
        urgent: root.urgent
        fontFamily: root.fontFamily
        onBack: root.browsing = false
      }

      ManageBrowser {
        id: manageBrowser
        anchors.fill: parent
        visible: root.managing
        foreground: root.foreground
        dim: root.dim
        accent: root.accent
        urgent: root.urgent
        fontFamily: root.fontFamily
        onBack: root.managing = false
      }

      // --- setup view --------------------------------------------------------

      // The guided first run. The old path was "open config.json in your
      // editor", which is how all six setup snags happened: each was caught
      // too late or pointed at the wrong fix. This form asks the same
      // questions where the user is, and runs one command that validates
      // everything against the same rules the units will get and refuses
      // loudly before anything is written.
      Flickable {
        id: setupScroll
        anchors.fill: parent
        visible: root.settingUp && !root.pickingRepo
        contentWidth: width
        contentHeight: setupColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        // Same scrollbar treatment as the picker: visible while the form is
        // taller than the view, draggable even where the wheel is not.
        ScrollBar.vertical: ScrollBar { policy: setupScroll.contentHeight > setupScroll.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded }

        Column {
          id: setupColumn
          width: setupScroll.width
          spacing: 0

          Text {
            width: parent.width
            bottomPadding: Style.space(8)
            text: "Set up backups"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            bottomPadding: Style.space(8)
            text: "One destination, one repository, one schedule. The password is stored in a 600 file next to the configuration, never in the configuration itself."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            bottomPadding: Style.space(2)
            text: "Name"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          TextField {
            id: setupName
            width: parent.width
            placeholderText: "backup"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.foreground
            placeholderTextColor: root.dimmer
            selectByMouse: true
            background: Rectangle {
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              radius: Style.space(4)
              border.width: 1
              border.color: setupName.activeFocus ? root.accent
                            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
            }
          }

          Text {
            width: parent.width
            topPadding: Style.space(6)
            bottomPadding: Style.space(2)
            text: "Folders to back up"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // The backup folders, one row each with a remove button. Seeded
          // with the home folder (or the existing configuration's list), so
          // the first run has something to back up.
          Repeater {
            model: root.setupSources

            delegate: Item {
              width: parent.width
              height: sourceRowBg.height

              Rectangle {
                id: sourceRowBg
                width: parent.width
                height: Math.max(pathText.implicitHeight + Style.space(6), Style.space(26))
                radius: Style.space(4)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                Text {
                  id: pathText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.right: removeButton.left
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData
                  textFormat: Text.PlainText
                  elide: Text.ElideMiddle
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  id: removeButton
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\u00d7"
                  textFormat: Text.PlainText
                  color: root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                TapHandler {
                  onTapped: {
                    var i = index
                    root.setupSources = root.setupSources.filter(function(_, j) { return j !== i })
                  }
                }
              }
            }
          }

          MenuRow {
            width: parent.width
            label: "Add folder\u2026"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              root.pickerPath = Quickshell.env("HOME") || "/"
              root.pickerTarget = "source"
              root.pickingRepo = true
            }
          }

          Text {
            width: parent.width
            topPadding: Style.space(6)
            bottomPadding: Style.space(2)
            text: "Repository"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item {
            width: parent.width
            height: setupRepo.height

            TextField {
              id: setupRepo
              width: parent.width - repoBrowseButton.width - Style.space(6)
              placeholderText: "/run/media/\u2026/restic"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: root.foreground
              placeholderTextColor: root.dimmer
              selectByMouse: true
              background: Rectangle {
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                radius: Style.space(4)
                border.width: 1
                border.color: setupRepo.activeFocus ? root.accent
                              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
              }
            }

            // The folder picker: opens the browse view rooted at the mounted
            // drives for this user, so picking the repository is a click, not
            // a typed path.
            Rectangle {
              id: repoBrowseButton
              anchors.right: parent.right
              width: Style.space(64)
              height: parent.height
              radius: Style.space(4)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

              Text {
                anchors.centerIn: parent
                text: "Browse\u2026"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              TapHandler {
                onTapped: {
                  root.pickerPath = "/run/media/" + (Quickshell.env("USER") || "")
                  root.pickerTarget = "repo"
                  root.pickingRepo = true
                }
              }
            }
          }

          Text {
            width: parent.width
            topPadding: Style.space(6)
            bottomPadding: Style.space(2)
            text: "Password"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            topPadding: Style.space(6)
            bottomPadding: Style.space(2)
            text: root.setupPassIsCommand
                  ? "Command that prints the password"
                  : "Password (stored in a 600 file)"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          TextField {
            id: setupPassword
            width: parent.width
            echoMode: root.setupPassIsCommand ? TextInput.Normal : TextInput.Password
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.foreground
            selectByMouse: true
            background: Rectangle {
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              radius: Style.space(4)
              border.width: 1
              border.color: setupPassword.activeFocus ? root.accent
                            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
            }
          }

          MenuRow {
            width: parent.width
            label: root.setupPassIsCommand
                   ? "Fetched with a command \u2014 click to store in a key file instead"
                   : "Stored in a key file \u2014 click to fetch with a command instead"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.setupPassIsCommand = !root.setupPassIsCommand
          }

          Text {
            width: parent.width
            topPadding: Style.space(6)
            bottomPadding: Style.space(2)
            text: "Schedule"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          MenuRow {
            width: parent.width
            label: setupSchedule === "custom"
                   ? "custom \u2014 empty means no schedule"
                   : setupSchedule + " \u2014 click to change"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              var presets = ["daily", "weekly", "monthly", "hourly", "custom"]
              var i = presets.indexOf(setupSchedule)
              setupSchedule = presets[(i + 1) % presets.length]
              // The field always shows the selected preset's default time,
              // editable in place. Cycling away and back resets it, which is
              // the point: the presets are starting points, not commitments.
              // Custom comes with an empty field: an empty field means no
              // schedule, so it doubles as the manual option.
              setupScheduleCustom.text = root.presetExpression(setupSchedule)
            }
          }

          // The exact time the schedule fires, as a systemd OnCalendar
          // expression. Pre-filled with the selected preset's default and
          // editable in place: weekdays only, several times a day, the first
          // of the month -- whatever the presets cannot name, type here. The
          // CLI validates it with check_unit_values on apply.
          TextField {
            id: setupScheduleCustom
            visible: setupSchedule !== "manual"
            width: parent.width
            placeholderText: "systemd OnCalendar, e.g. Mon..Fri *-*-* 09,17:00:00"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.foreground
            placeholderTextColor: root.dimmer
            selectByMouse: true
            background: Rectangle {
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              radius: Style.space(4)
              border.width: 1
              border.color: setupScheduleCustom.activeFocus ? root.accent
                            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
            }
          }

          MenuRow {
            width: parent.width
            visible: BackItUpStore.systemSnapshotAvailable
            label: root.setupSystemSnapshot
                   ? "Also take a system snapshot \u2014 click to turn off"
                   : "Also take a system snapshot \u2014 click to turn on"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.setupSystemSnapshot = !root.setupSystemSnapshot
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Text {
            width: parent.width
            visible: root.setupValidationError !== ""
            topPadding: visible ? Style.space(6) : 0
            bottomPadding: visible ? Style.space(6) : 0
            text: root.setupValidationError
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: BackItUpStore.setupError !== ""
            topPadding: visible ? Style.space(6) : 0
            bottomPadding: visible ? Style.space(6) : 0
            text: BackItUpStore.plain(BackItUpStore.setupError)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: BackItUpStore.setupBusy
            topPadding: Style.space(4)
            bottomPadding: Style.space(4)
            text: "Applying \u2014 creating the repository and switching on the schedule\u2026"
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: !BackItUpStore.setupBusy && BackItUpStore.setupDone !== ""
                     && root.setupValidationError === "" && BackItUpStore.setupError === ""
            text: BackItUpStore.plain(BackItUpStore.setupDone)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          MenuRow {
            width: parent.width
            label: "Apply"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              if (BackItUpStore.setupBusy) return
              var name = setupName.text.trim()
              var repo = setupRepo.text.trim()
              if (name === "" || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) {
                root.setupValidationError =
                  "Name must start with a letter or digit, and contain only letters, digits, dashes, dots and underscores"
                return
              }
              if (repo === "") {
                root.setupValidationError = "A repository path is required"
                return
              }
              if (setupPassword.text === "" && !root.editHasPasswordSource) {
                root.setupValidationError = root.setupPassIsCommand
                  ? "A password command is required \u2014 for example: pass show <entry> or op read <secret>"
                  : "A password is required \u2014 it is stored in a 600 file, never in the configuration"
                return
              }
              if (root.setupSources.length === 0) {
                root.setupValidationError = "At least one folder to back up is required"
                return
              }
              root.setupValidationError = ""
              // An unaltered field means the preset itself; an altered one is
              // a custom expression, which the CLI validates and records. An
              // emptied field means no schedule at all: backups then run only
              // from the panel.
              var schedText = setupScheduleCustom.text.trim()
              var schedule
              if (setupSchedule !== "custom" && schedText === root.presetExpression(setupSchedule)) {
                schedule = setupSchedule
              } else if (schedText === "") {
                schedule = "manual"
              } else {
                schedule = schedText
              }
              BackItUpStore.applySetup({
                name: name,
                display_name: name,
                repository: repo,
                schedule: schedule,
                password: root.setupPassIsCommand ? undefined : setupPassword.text,
                password_command: root.setupPassIsCommand ? setupPassword.text.trim() : undefined,
                source: root.setupSources.slice(),
                system_snapshot: root.setupSystemSnapshot
              })
            }
          }

          MenuRow {
            width: parent.width
            label: "Cancel"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.settingUp = false
          }
        }
      }

      // --- repository folder picker -----------------------------------------

      // A fourth view: the picker replaces the setup form while it is open.
      // A FolderDialog would be a second window, and this plugin avoids second
      // windows -- keyboard focus on Wayland is lost the moment the first one
      // closes. FolderListModel lists the directory in place: click to
      // descend, Up to go back, Use this folder to hand the path to the field.
      Flickable {
        id: repoPicker
        anchors.fill: parent
        visible: root.pickingRepo
        contentWidth: width
        contentHeight: pickerColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        // Always visible while the list is taller than the view: the bar is
        // a way to scroll that works even where the wheel does not.
        ScrollBar.vertical: ScrollBar { policy: repoPicker.contentHeight > repoPicker.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded }

        FolderListModel {
          id: repoDirs
          // Qt6's FolderListModel has showDirs, not showDirsOnly: files stay
          // in the model and the delegate hides them instead. The folder
          // property needs a file:// scheme: a bare path fails silently and
          // the model keeps listing its default -- the working directory --
          // so the user sees no folders at all. Verified against Qt 6.11:
          // a file:// URL works both at parse time and when the path changes.
          // showHidden so the picker can reach ~/.config and the rest: hidden
          // folders are backed up too, so hiding them here hides real
          // destinations.
          showDirs: true
          showHidden: true
          folder: "file://" + root.pickerPath
        }

        Column {
          id: pickerColumn
          width: repoPicker.width
          spacing: 0

          // The row MouseAreas swallow drags, and wheel events that route
          // through a layer surface do not always reach the Flickable's own
          // handling. This handler scrolls the list directly: it accepts the
          // wheel, so the Flickable never double-scrolls, and the Flickable's
          // StopAtBounds clamping still applies.
          WheelHandler {
            target: repoPicker
            property: "contentY"
            targetTransformAroundCursor: false
          }

          Text {
            width: parent.width
            bottomPadding: Style.space(4)
            text: root.pickerTarget === "source" ? "Add a folder to back up" : "Choose the repository folder"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            bottomPadding: Style.space(8)
            text: root.pickerPath
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Up: the parent directory. The safety net when the default root
          // does not exist or the user went one level too far.
          MenuRow {
            width: parent.width
            label: "Up"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              var i = root.pickerPath.lastIndexOf("/")
              root.pickerPath = i <= 0 ? "/" : root.pickerPath.substring(0, i)
            }
          }

          Repeater {
            model: repoDirs

            delegate: MenuRow {
              width: parent.width
              visible: fileIsDir
              label: fileName
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.pickerPath = filePath
            }
          }

          MenuRow {
            width: parent.width
            label: "Use this folder"
            foreground: root.accent
            fontFamily: root.fontFamily
            onClicked: {
              if (root.pickerTarget === "source") {
                var next = root.setupSources.slice()
                if (next.indexOf(root.pickerPath) === -1) next.push(root.pickerPath)
                root.setupSources = next
              } else {
                setupRepo.text = root.pickerPath
              }
              root.pickingRepo = false
            }
          }
        }
      }
    }

    ConfirmDialog {
      id: stopConfirm
      anchors.fill: parent
      z: 10
      message: "Stop this backup? Nothing is lost, but no snapshot is created for this run."
      confirmText: "Stop"
      cancelText: "Keep running"
      fontFamily: root.fontFamily
      onConfirmed: {
        BackItUpStore.stopBackup()
        stopConfirm.opened = false
      }
      onCanceled: stopConfirm.opened = false
    }
  }
}
