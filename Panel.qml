import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
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
  // Which of the five wizard steps is showing. One decision per screen: the
  // old form was nine labels, four inputs, a list and two toggles in a single
  // column, which is why it read as a wall rather than as a set of questions.
  property int setupStep: 1
  readonly property var setupStepLabels: ["Destination", "Folders", "Password", "Schedule", "Review"]
  // How many copies of each tier to keep. Seeded complete -- the CLI's own
  // defaults -- rather than null, so the review grid always shows the policy
  // that would actually be kept, not a blank waiting to be filled.
  property var setupRetention: ({ daily: 7, weekly: 4, monthly: 12, yearly: 3 })
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

  // Colour is no longer the bar's vocabulary -- motion is. The bar is
  // transparent, so the glyph is drawn straight onto whatever wallpaper is
  // behind it, and every hue except red is at the mercy of that background: an
  // amber or cyan glyph reads over a dark wallpaper and vanishes over a bright
  // one. Red survives because "wrong" is the one message worth spending
  // contrast on, and it is backed by the ! badge so it does not rest on colour
  // alone. A static glyph is drawn in `barForeground`, the shell's own
  // contrast colour (it runs omarchy-bar-text-color against what is behind the
  // bar), so it is dark over a bright wallpaper and light over a dark one --
  // the only way a glyph stays legible on every background.
  //
  // So three states, not four: still, working, wrong. "Working" carries itself
  // as rotation rather than as a third hue. It used to be an opacity pulse,
  // which faded the glyph to 45% -- disappearing on a busy wallpaper at exactly
  // the moment it was trying to say something, and dimming the one thing in the
  // bar that has to be legible at all times.
  //
  // "Worth a look" stays neutral, so it is signalled in the panel and the
  // tooltip but not in the bar. That is the one deliberate gap: warn cannot
  // afford a colour of its own here, and it is not worth a motion channel.
  readonly property color barIconColor: {
    var s = BackItUpStore.overallStatus
    if (!BackItUpStore.configured) return Qt.darker(barForeground, 1.9)
    if (s === "bad") return urgent
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

  // Move between steps. The validation message belongs to the step that is
  // being left, so it goes with it: carrying "a repository path is required"
  // onto the schedule screen would blame the wrong question.
  function setupGo(delta) {
    root.setupStep = Math.max(1, Math.min(root.setupStepLabels.length,
                                          root.setupStep + delta))
    root.setupValidationError = ""
  }

  // Put the keyboard where the typing is. Only the steps with a text field
  // take focus; the rest leave it with the panel so the arrow keys still
  // scroll and the wheel still works.
  function setupFocusStep() {
    if (root.setupStep === 1) setupName.forceActiveFocus()
    else if (root.setupStep === 3) setupPassword.forceActiveFocus()
  }

  // Status resolves a destination's policy to a complete block -- its own
  // counts, then the global block, then the built-in defaults -- so seeding the
  // review grid is a straight copy, with a fallback for the moment before the
  // first status lands and retention is still null.
  function retentionBlock(d) {
    var r = (d && d.retention) ? d.retention : null
    function pick(k, fallback) {
      if (r && r[k] !== undefined && r[k] !== null) return Math.round(Number(r[k]))
      return fallback
    }
    return { daily: pick("daily", 7), weekly: pick("weekly", 4),
             monthly: pick("monthly", 12), yearly: pick("yearly", 3) }
  }

  // What the step still needs before it can be left. Checked per step rather
  // than once at the end: an error about the repository is useless on the
  // schedule screen, where the field that caused it is two screens back.
  function setupStepError(step) {
    var name = setupName.text.trim()
    if (step === 1) {
      if (name === "")
        return "A name is required \u2014 it is how this destination is referred to"
      if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name))
        return "Name must start with a letter or digit, and contain only letters, digits, dashes, dots and underscores"
      if (setupRepo.text.trim() === "")
        return "A repository path is required"
      return ""
    }
    if (step === 2) {
      if (root.setupSources.length === 0)
        return "At least one folder to back up is required"
      return ""
    }
    if (step === 3) {
      if (setupPassword.text === "" && !root.editHasPasswordSource)
        return root.setupPassIsCommand
          ? "A password command is required \u2014 for example: pass show <entry> or op read <secret>"
          : "A password is required \u2014 it is stored in a 600 file, never in the configuration"
      return ""
    }
    return ""
  }

  // The schedule as the CLI will record it. An unaltered preset field means the
  // preset itself; an altered one is a custom expression, which the CLI
  // validates and records; an emptied one means no schedule at all, and backups
  // then run only from the panel.
  function scheduleValue() {
    var t = setupScheduleCustom.text.trim()
    if (root.setupSchedule !== "custom" && t === root.presetExpression(root.setupSchedule))
      return root.setupSchedule
    if (t === "") return "manual"
    return t
  }

  // The same schedule in words, for the review read-back. Spelled out rather
  // than echoing the stored value, because the point of reading it back is to
  // catch a schedule that is not what you meant.
  function scheduleSummary() {
    if (root.setupSchedule !== "custom") {
      var when = { daily: "at 03:00", weekly: "Mondays at 03:00",
                   monthly: "on the 1st at 03:00", hourly: "every hour" }
      return root.setupSchedule + " \u2014 " + (when[root.setupSchedule] || "as scheduled")
    }
    var t = setupScheduleCustom.text.trim()
    return t === "" ? "only when run by hand" : t
  }

  // Folders worth suggesting: the usual ones that actually exist here and are
  // not already listed. Listing ~ is what makes them real -- a suggestion for a
  // folder that is not there only fails later, at backup time.
  function suggestedSources() {
    var home = Quickshell.env("HOME") || ""
    // The listing arrives asynchronously, so reading count here is what makes
    // the suggestions appear when it does instead of staying empty forever.
    if (homeDirs.count === 0) return []
    var names = ["Documents", "Pictures", "Projects", "Music", "Videos"]
    var out = []
    for (var i = 0; i < names.length; i++) {
      var full = home + "/" + names[i]
      if (homeDirs.indexOf(full) < 0) continue
      if (root.setupSources.indexOf(full) >= 0) continue
      out.push(full)
    }
    return out
  }

  // The one place that writes. Everything is validated against the same rules
  // the units get, and the CLI refuses loudly before anything is written, so a
  // half-created destination is not a state this can leave behind.
  function setupApply() {
    if (BackItUpStore.setupBusy) return
    for (var step = 1; step < root.setupStepLabels.length; step++) {
      var err = root.setupStepError(step)
      if (err !== "") {
        root.setupValidationError = "Step " + step + " (" + root.setupStepLabels[step - 1] + "): " + err
        return
      }
    }
    root.setupValidationError = ""
    BackItUpStore.applySetup({
      name: setupName.text.trim(),
      display_name: setupName.text.trim(),
      repository: setupRepo.text.trim(),
      schedule: root.scheduleValue(),
      password: root.setupPassIsCommand ? undefined : setupPassword.text,
      password_command: root.setupPassIsCommand ? setupPassword.text.trim() : undefined,
      source: root.setupSources.slice(),
      system_snapshot: root.setupSystemSnapshot,
      // Only when it is not the stock policy. The review grid always shows all
      // four numbers, but a destination left at 7/4/12/3 should keep following
      // the global block and the built-in defaults rather than being pinned to
      // today's numbers -- sending the block unconditionally would freeze every
      // new destination at whatever the defaults happened to be, and a later
      // change to the global policy would quietly skip it. Tuning any tier
      // writes the whole block, which is what the grid showed.
      retention: root.retentionIsStock() ? undefined : root.setupRetention
    })
  }

  // Is the review's grid still the stock policy? Compared against the same
  // defaults retentionBlock falls back to, so the two cannot drift apart.
  function retentionIsStock() {
    var stock = root.retentionBlock(null)
    var r = root.setupRetention || {}
    for (var k in stock) {
      if (Math.round(Number(r[k])) !== stock[k]) return false
    }
    return true
  }

  // The default calendar expression each schedule preset expands to, so the
  // setup form can show it in an editable field: the presets stay short words
  // to pick between, and the exact time they fire is right there to alter.
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
    // Editing reuses the same five screens instead of keeping a second form
    // in step with this one, and opens on the review with every earlier step
    // already walked: the values are all filled in, so the only thing left to
    // do is check them before saving. The stepper marks 1-4 done because they
    // are -- there is nothing to ask.
    root.setupRetention = root.retentionBlock(d)
    root.setupStep = root.setupStepLabels.length
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
      // A fresh wizard starts at the beginning; editConfig sets its own step
      // and re-focuses immediately after this fires.
      if (!root.editingConfig) root.setupStep = 1
      root.setupFocusStep()
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

  // Stepping into a text step should put the caret in the field rather than
  // make the user click it -- the step is a question and the field is the
  // answer.
  onSetupStepChanged: root.setupFocusStep()

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
        // The one glyph, at full opacity in every state. Rotation while a
        // backup runs is the whole "busy" signal: motion reads on any
        // wallpaper, a faded glyph does not, and it costs no colour. The angle
        // is the only thing that moves -- nothing here dims, scales or changes
        // hue, so the glyph is as legible mid-run as at rest. Deliberately not
        // a percentage either: a number in the bar would demand to be read,
        // where a turn only says "working" and the panel carries the detail.
        // The spinner. The stock glyph is fa-history: a clock with a *rewind*
        // arrow, so it is drawn counter-clockwise, and an arrow that turns
        // against its own head reads as wrong even when you cannot say why.
        // Mirroring it leaves a clock with a forward arrow, which then turns
        // clockwise to match. Cheaper than hunting for a codepoint that does
        // not exist -- Font Awesome has no clock-with-forward-arrow.
        //
        // Mirror and rotation sit on separate items deliberately. A Scale in an
        // item's transform list and that same item's own rotation compose in an
        // order that is easy to get subtly wrong, and the wrong order turns
        // this straight back into a counter-clockwise spin. Nesting makes the
        // order explicit: mirror the glyph, then turn the mirrored glyph.
        Item {
          id: glyphPivot
          anchors.centerIn: parent
          width: Style.bar.iconFont
          height: Style.bar.iconFont

          // Vector, not a font glyph. Qt rasterises a Text once into a glyph
          // cache and resamples that bitmap whenever the item is rotated, which
          // at bar sizes is exactly what makes a spinning icon look soft and
          // pixelated; no choice of renderType rescues it. A Shape hands the
          // scene graph real geometry instead, so every angle is rasterised
          // fresh and the turn stays as crisp as the rest state.
          //
          // The path is icon.svg's, with that file's own font-units-to-box
          // transform and the mirror already folded in. The coordinates below
          // are the same outline in icon.svg's 64-unit document box, so the two
          // files still describe one shape -- and being box-sized, there is no
          // oversized geometry left for Qt to cull against a 64px item.
          Item {
            id: glyphBox
            anchors.centerIn: parent
            width: 64
            height: 64

            // A font unit is iconFont/1024 px and one unit of the 64-unit box
            // is 0.040173 of a font unit, so this scale lands the em on the
            // bar's icon size -- the same optical size the font glyph had.
            readonly property real boxScale: Style.bar.iconFont / 1024 / 0.040173
            transform: Scale {
              origin.x: 32
              origin.y: 32
              xScale: glyphBox.boxScale
              yScale: glyphBox.boxScale
            }

            Shape {
              id: barGlyph
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer

              ShapePath {
                fillColor: root.barIconColor
                strokeColor: "transparent"

                PathSvg { path: "M45.117 18.903 Q42.586 16.332 39.171 14.886 Q35.756 13.44 31.98 13.44 Q24.307 13.44 18.884 18.863 Q13.46 24.287 13.46 32 Q13.46 39.633 18.884 45.096 Q24.307 50.56 31.98 50.56 Q37.765 50.56 42.586 47.185 Q43.389 46.623 43.55 45.699 Q43.711 44.775 43.188 43.971 Q42.666 43.168 41.702 43.007 Q40.738 42.846 39.934 43.409 Q36.359 45.9 31.98 45.9 Q26.276 45.9 22.178 41.802 Q18.08 37.704 18.08 32 Q18.08 26.295 22.178 22.198 Q26.276 18.1 31.98 18.1 Q37.765 18.1 41.822 22.117 L39.613 24.367 Q38.809 25.17 39.211 26.255 Q39.613 27.34 40.818 27.34 H48.813 Q49.576 27.34 50.058 26.858 Q50.54 26.376 50.54 25.652 V17.618 Q50.54 16.493 49.455 16.051 Q48.371 15.609 47.567 16.413 Z M31.98 22.76 H32.02 Q31.297 22.76 30.775 23.242 Q30.253 23.724 30.253 24.447 V31.277 L25.552 36.017 Q25.03 36.499 25.03 37.222 Q25.03 37.945 25.552 38.427 Q26.034 38.99 26.758 38.99 Q27.481 38.99 28.003 38.427 L33.225 33.205 Q33.748 32.723 33.748 32 V24.447 Q33.748 23.724 33.225 23.242 Q32.703 22.76 31.98 22.76 Z" }
              }
            }
          }

          // RotationAnimator rather than NumberAnimation: it drives the angle
          // on the render thread, so the turn stays smooth at the bar's repaint
          // rate instead of stepping with the GUI thread. Same idiom the shell's
          // own weather panel uses for its spinning glyph. Positive is
          // clockwise in Qt, which is the direction the mirror now asks for.
          RotationAnimator on rotation {
            running: BackItUpStore.anyRunning
            from: 0
            to: 360
            duration: 1600
            loops: Animation.Infinite
            // Come to rest upright. Without this the glyph freezes at whatever
            // angle the run happened to end on and stays there, which reads as
            // a rendering fault rather than as idle. Reset the pivot, so the
            // mirrored text is not left tilted either.
            onRunningChanged: if (!running) glyphPivot.rotation = 0
          }
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
    // The wizard runs wider than the status view because it is a form, not a
    // read-out: step 3's toggle label and step 4's five-segment picker both
    // elide at 420, and a form that hides its own option names is worse than a
    // wide one. Matches the browse/manage width, so it is a width this panel
    // already wears.
    readonly property int desiredWidth:
      Style.space(root.browsing || root.managing || root.settingUp ? 460
                  : 332)
    contentWidth: Math.min(desiredWidth,
                           panel.availableCardWidth > 0 ? panel.availableCardWidth : desiredWidth)
    contentHeight: panel.fittedContentHeight(
                     root.browsing ? browser.desiredHeight
                                   : (root.managing ? manageBrowser.desiredHeight
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

          // --- head -----------------------------------------------------------
          //
          // The count is repeated from the stepper even though the dots already
          // show it: the dots are a shape and "3 / 5" is the number. The left
          // control is Back on steps 2-5 and Close on step 1 -- never a
          // disabled Back, because a dead control at the top of a form is a
          // worse landmark than no control at all.
          Item {
            width: parent.width
            height: Style.space(28)

            Rectangle {
              id: setupHeadButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(24)
              height: width
              radius: Style.space(6)
              color: setupHeadArea.containsMouse
                     ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                     : "transparent"

              Text {
                anchors.centerIn: parent
                text: root.setupStep > 1 ? BackItUpStore.iconArrowLeft : BackItUpStore.iconX
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: setupHeadArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setupStep > 1 ? root.setupGo(-1) : (root.settingUp = false)
              }
            }

            Text {
              anchors.left: setupHeadButton.right
              anchors.leftMargin: Style.space(10)
              anchors.right: stepPill.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              // The title names the screen, so it changes with the step: the
              // last one is not "set up backups", it is reading back what you
              // are about to set up.
              text: root.setupStep === root.setupStepLabels.length
                    ? "Review"
                    : (root.editingConfig ? "Edit configuration" : "Set up backups")
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            StatusPill {
              id: stepPill
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.setupStep + " / " + root.setupStepLabels.length
              state: "idle"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
          }

          Item { width: 1; height: Style.space(10) }

          Stepper {
            width: parent.width
            count: root.setupStepLabels.length
            current: root.setupStep
            labels: root.setupStepLabels
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
          }

          Item { width: 1; height: Style.space(14) }

          // --- step 1: destination --------------------------------------------

          Column {
            width: parent.width
            visible: root.setupStep === 1
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: "Where should backups go?"
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              width: parent.width
              bottomPadding: Style.space(6)
              text: "A folder or mounted drive. Restic writes an encrypted repository into it, so the folder may start out empty."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Column {
            width: parent.width
            visible: root.setupStep === 1
            spacing: 0

            Text {
              width: parent.width
              bottomPadding: Style.space(3)
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
              topPadding: Style.space(8)
              bottomPadding: Style.space(3)
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
          }

          // --- step 2: folders ------------------------------------------------

          Column {
            width: parent.width
            visible: root.setupStep === 2
            spacing: Style.space(7)

            Text {
              width: parent.width
              text: "What should be backed up?"
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              width: parent.width
              bottomPadding: Style.space(2)
              text: "Every folder here goes into the same repository. Hidden folders are included."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            // Each source is an object you can point at, not a line in a list:
            // the chip carries its own remove target, so there is no doubt
            // which folder the x belongs to.
            Repeater {
              model: root.setupSources

              delegate: SourceChip {
                width: parent.width
                path: String(modelData)
                foreground: root.foreground
                fontFamily: root.fontFamily
                onRemoveRequested: {
                  var i = index
                  root.setupSources = root.setupSources.filter(function(_, j) { return j !== i })
                }
              }
            }

            // Nothing to back up is a state worth showing rather than an empty
            // gap: an empty list and a list that failed to load look identical
            // otherwise, and this is the one step that cannot be skipped.
            Text {
              width: parent.width
              visible: root.setupSources.length === 0
              text: "No folders yet. Add at least one \u2014 the home folder is a good start."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // The add action is a dashed slot rather than another chip: it is
            // where a folder would go, not a folder. Drawn as a Shape because
            // Rectangle borders cannot be dashed.
            Item {
              id: addFolderButton
              width: parent.width
              height: Style.space(32)

              Rectangle {
                anchors.fill: parent
                radius: Style.space(7)
                color: addFolderArea.containsMouse
                       ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                       : "transparent"
              }

              Shape {
                anchors.fill: parent
                ShapePath {
                  strokeColor: root.dim
                  strokeWidth: Style.space(1)
                  strokeStyle: ShapePath.DashLine
                  dashPattern: [4, 3]
                  fillColor: "transparent"
                  startX: 0.5
                  startY: 0.5
                  PathLine { x: addFolderButton.width - 0.5; y: 0.5 }
                  PathLine { x: addFolderButton.width - 0.5; y: addFolderButton.height - 0.5 }
                  PathLine { x: 0.5; y: addFolderButton.height - 0.5 }
                  PathLine { x: 0.5; y: 0.5 }
                }
              }

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: BackItUpStore.iconPlus
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Add a folder\u2026"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              MouseArea {
                id: addFolderArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.pickerPath = Quickshell.env("HOME") || "/"
                  root.pickerTarget = "source"
                  root.pickingRepo = true
                }
              }
            }

            // Suggestions lower the cost of the blank page: the folders worth
            // backing up are the same on almost every machine, so naming them
            // turns a path-typing exercise into a click. Only folders that
            // actually exist, and that are not already listed.
            Row {
              width: parent.width
              visible: root.suggestedSources().length > 0
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Add:"
                textFormat: Text.PlainText
                color: root.dimmer
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: root.suggestedSources()

                delegate: PanelButton {
                  label: String(modelData)
                  variant: "ghost"
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onClicked: {
                    var next = root.setupSources.slice()
                    next.push(String(modelData))
                    root.setupSources = next
                  }
                }
              }
            }
          }

          // --- step 3: password -----------------------------------------------

          Column {
            width: parent.width
            visible: root.setupStep === 3
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: "How is the repository unlocked?"
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              width: parent.width
              bottomPadding: Style.space(8)
              text: "The key is written to a 600 file beside the configuration, never into it. Without it the repository cannot be opened \u2014 by you or by anyone else."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Column {
            width: parent.width
            visible: root.setupStep === 3
            spacing: 0

            Text {
              width: parent.width
              bottomPadding: Style.space(3)
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

            // A command is not a secret -- the config holds it in plain text --
            // so switching to that mode reveals the field rather than reusing
            // the masked one.
            // Both states lead with the mode they are in, then the action --
            // the shape "Advanced -- edit the systemd expression" already uses
            // one step down. Spelled out as sentences these ran long enough to
            // elide, and a toggle whose label does not fit is a toggle that
            // does not say what it is.
            MenuRow {
              width: parent.width
              label: root.setupPassIsCommand
                     ? "Command \u2014 click to store in a key file instead"
                     : "Key file \u2014 click to fetch with a command instead"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.setupPassIsCommand = !root.setupPassIsCommand
            }
          }

          // --- step 4: schedule -----------------------------------------------

          Column {
            width: parent.width
            visible: root.setupStep === 4
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: "When should this run?"
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              width: parent.width
              bottomPadding: Style.space(8)
              text: "The timer runs as your user, so it only fires while you are logged in. A run missed while the machine was off is caught up afterwards."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Column {
            width: parent.width
            visible: root.setupStep === 4
            spacing: Style.space(7)

            SegmentedControl {
              width: parent.width
              options: [
                { value: "daily",   label: "daily" },
                { value: "weekly",  label: "weekly" },
                { value: "monthly", label: "monthly" },
                { value: "hourly",  label: "hourly" },
                { value: "custom",  label: "custom" }
              ]
              value: root.setupSchedule
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              // Selecting a preset also fills the expression, which is what the
              // apply step reads: the field stays the one source of truth, and
              // the picker is only a faster way to write into it.
              onSelected: function(v) {
                root.setupSchedule = v
                if (v !== "custom")
                  setupScheduleCustom.text = root.presetExpression(v)
              }
            }

            Text {
              width: parent.width
              text: root.setupSchedule === "custom"
                    ? "A systemd OnCalendar expression. Leave it empty to run only when you ask."
                    : "Next run: " + (root.setupSchedule === "hourly" ? "every hour"
                                      : root.setupSchedule + " at 03:00")
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // The raw expression lives behind a disclosure: it is the real
            // setting, but reading it is not required to choose a schedule, and
            // it is the part most people should never have to look at.
            MenuRow {
              width: parent.width
              label: root.setupSchedule === "custom"
                     ? "Custom schedule shown \u2014 click a preset above to hide it"
                     : "Advanced \u2014 edit the systemd expression\u2026"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                if (root.setupSchedule === "custom") {
                  root.setupSchedule = "daily"
                  setupScheduleCustom.text = root.presetExpression("daily")
                } else {
                  root.setupSchedule = "custom"
                }
              }
            }

            TextField {
              id: setupScheduleCustom
              width: parent.width
              visible: root.setupSchedule === "custom"
              placeholderText: "*-*-* 03:00:00"
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
          }

          // --- step 5: review -------------------------------------------------

          Column {
            width: parent.width
            visible: root.setupStep === root.setupStepLabels.length
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: "Does this look right?"
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              width: parent.width
              bottomPadding: Style.space(4)
              text: root.editingConfig
                    ? "Applying writes these values back over the existing configuration."
                    : "Nothing has been written yet. Applying creates the repository and switches on the schedule."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Column {
            width: parent.width
            visible: root.setupStep === root.setupStepLabels.length
            spacing: Style.space(9)

            // The read-back: every value that will be written, in the words the
            // configuration uses, so a wrong path is caught here rather than in
            // a repository that was just created.
            Rectangle {
              width: parent.width
              height: reviewColumn.implicitHeight
              radius: Style.space(8)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              border.width: Style.space(1)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

              Column {
                id: reviewColumn
                width: parent.width
                spacing: 0

                ReviewRow {
                  width: parent.width
                  separator: false
                  key: "Name"
                  value: setupName.text.trim() === "" ? "\u2014" : setupName.text.trim()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                ReviewRow {
                  width: parent.width
                  key: "Repository"
                  value: setupRepo.text.trim() === "" ? "\u2014" : setupRepo.text.trim()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                ReviewRow {
                  width: parent.width
                  key: "Folders"
                  value: root.setupSources.length === 0
                         ? "\u2014"
                         : root.setupSources.join("  \u00b7  ")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                ReviewRow {
                  width: parent.width
                  key: "Schedule"
                  value: root.scheduleSummary()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                ReviewRow {
                  width: parent.width
                  key: "Password"
                  value: root.setupPassIsCommand
                         ? (setupPassword.text.trim() === ""
                            ? "the existing command" : setupPassword.text.trim() + "  (command)")
                         : (setupPassword.text === ""
                            ? "the existing key file" : "stored in a 600 key file")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                ReviewRow {
                  width: parent.width
                  key: "Snapshot"
                  value: !BackItUpStore.systemSnapshotAvailable
                         ? "not available on this system"
                         : (root.setupSystemSnapshot
                            ? "on \u2014 a bootable rollback point"
                            : "off")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
              }
            }

            Text {
              width: parent.width
              text: "Keep this many copies"
              textFormat: Text.PlainText
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            RetentionRow {
              width: parent.width
              retention: root.setupRetention
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: root.setupRetention = block
            }
          }

          // --- messages and footer --------------------------------------------

          Item { width: 1; height: Style.space(14) }

          Text {
            width: parent.width
            visible: root.setupValidationError !== ""
            bottomPadding: visible ? Style.space(8) : 0
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
            bottomPadding: visible ? Style.space(8) : 0
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
            bottomPadding: visible ? Style.space(8) : 0
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
            bottomPadding: visible ? Style.space(8) : 0
            text: BackItUpStore.plain(BackItUpStore.setupDone)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Back and Continue rather than Cancel and Apply: the verbs say where
          // you are going, and the only step that writes anything says what it
          // writes. The row is always two halves so the buttons do not move
          // around under the pointer as the wizard advances.
          Row {
            width: parent.width
            spacing: Style.space(8)

            PanelButton {
              width: (parent.width - parent.spacing) / 2
              label: "Back"
              variant: "default"
              enabled: root.setupStep > 1 && !BackItUpStore.setupBusy
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.setupGo(-1)
            }

            PanelButton {
              width: (parent.width - parent.spacing) / 2
              label: root.setupStep === root.setupStepLabels.length
                     ? (root.editingConfig ? "Save changes" : "Set up backups")
                     : "Continue"
              variant: root.setupStep === root.setupStepLabels.length ? "primary" : "default"
              glyph: root.setupStep === root.setupStepLabels.length ? BackItUpStore.iconCheck : ""
              enabled: !BackItUpStore.setupBusy
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                var err = root.setupStepError(root.setupStep)
                if (err !== "") { root.setupValidationError = err; return }
                root.setupValidationError = ""
                if (root.setupStep < root.setupStepLabels.length) {
                  root.setupGo(1)
                  return
                }
                root.setupApply()
              }
            }
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

        // Lists the home folder once, so the setup form's suggestions can only
        // offer folders that are really there. Never shown: it is a probe.
        FolderListModel {
          id: homeDirs
          showDirs: true
          showFiles: false
          showHidden: false
          folder: "file://" + (Quickshell.env("HOME") || "/")
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
