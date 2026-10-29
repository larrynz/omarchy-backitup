pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// All BackIt Up state lives here, and there is a concrete reason for that:
// a bar widget is instantiated once per monitor, so anything owning a Process
// or a Timer in Panel.qml would exist twice on a two-monitor setup and poll
// twice. This file is the model; Panel.qml and RestoreBrowser.qml are views.
//
// The rule this store is built around: showing "3 hours ago" must never cost a
// password, a network round trip, or a wait on a sleeping NAS. `status --json`
// reads nothing but local files, so the idle poll is free. Everything that
// does touch the repository -- snapshots, ls, restore -- runs only in response
// to a click.
Singleton {
  id: root

  // The CLI sits next to this file, so the plugin works from wherever it was
  // installed without putting anything on $PATH.
  readonly property string cli:
    Qt.resolvedUrl("bin/omarchy-backitup").toString().replace(/^file:\/\//, "")

  // Written as \u escapes on purpose: a literal private-use glyph does not
  // always survive the trip from editor to disk, and the failure is silent --
  // an empty string, an invisible icon, and no error anywhere.
  readonly property string iconBackItUp: "\uf1da"  // clock with a rewind arrow
  readonly property string iconFolder: "\uf07b"
  readonly property string iconFile: "\uf15b"
  readonly property string iconUp: "\uf148"           // level up
  readonly property string iconShield: "\uf132"       // a healthy backup
  readonly property string iconCheck: "\uf00c"        // a verified tag
  readonly property string iconAlert: "\uf071"        // a failed run
  readonly property string iconPlay: "\uf04b"         // start a backup
  readonly property string iconStop: "\uf04d"         // stop the run in flight
  readonly property string iconRestore: "\uf019"      // download
  readonly property string iconList: "\uf0ca"         // a listing
  readonly property string iconSliders: "\uf1de"      // configuration
  readonly property string iconChevronRight: "\uf054"
  readonly property string iconPlus: "\uf067"           // add a queue item / a folder
  readonly property string iconSearch: "\uf002"         // the filter field
  readonly property string iconTrash: "\uf1f8"          // delete a snapshot
  readonly property string iconBox: "\uf187"             // a snapshot in the manage list
  readonly property string iconX: "\uf00d"               // drop a chosen folder
  readonly property string iconClock: "\uf017"           // idle: nothing scheduled
  readonly property string iconRefresh: "\uf021"         // a backup in flight
  readonly property string iconArrowLeft: "\uf060"       // back out of a view

  property string fontFamily: ""

  // How times are drawn. Not the system locale, on purpose: this machine is
  // en_US, which would mean "9:54 PM", while the Omarchy clock beside us is
  // set to 24-hour. Following the locale would make the two widgets disagree
  // on the same bar. Omarchy's convention is an explicit format string per
  // widget, so that is what this takes, with the clock's own default.
  property string timeFormat: "HH:mm"
  property string dateFormat: "d MMM"


  // --- status -------------------------------------------------------------

  property bool configured: false
  // "Back Up Now" starts a systemd unit. Until `install` has run that unit
  // does not exist and the button would do nothing at all, with no feedback --
  // the plugin would simply look broken.
  property bool unitsInstalled: false
  // A configuration that exists but is wrong is a different problem from one
  // that isn't there, and needs a different thing said about it.
  property bool configInvalid: false
  property string configError: ""
  property var destinations: []
  // The folders to back up, from the status's `source` array. The setup form
  // seeds its folder list from this, so a re-setup shows what is really
  // configured instead of silently replacing it with just the home folder.
  property var sources: []
  // Whether this machine has omarchy-snapshot at all: the setup form offers
  // the snapshot toggle only when this is true, so on a plain Arch box the
  // plugin never shows a control that cannot work.
  property bool systemSnapshotAvailable: false
  // The first destination, used where something has to pick one on its own.
  // There is no "active" destination any more: with several of them they all
  // run on their own schedule and they all matter.
  property bool loaded: false

  readonly property var active: destinations.length > 0 ? destinations[0] : null

  readonly property var lastRun: active && active.last_run ? active.last_run : null
  readonly property string lastSuccessAt: active && active.last_success_at
                                          ? String(active.last_success_at) : ""
  readonly property bool running: active ? (active.running === true || isStarting(active)) : false
  readonly property var progress: active && active.progress ? active.progress : null
  readonly property bool failed: lastRun ? lastRun.result === "failed" : false
  readonly property bool everRan: lastRun !== null

  // Ticks once a minute so "3 hours ago" ages without a status call. Bumping
  // this property is what re-evaluates the relative-time bindings; the value
  // itself is never read.
  property int clockTick: 0

  // --- polling ------------------------------------------------------------

  // Fast while a run is in progress, lazy otherwise. A backup that starts from
  // the timer at 03:00 is picked up within thirty seconds, which is soon
  // enough for something nobody is watching.
  readonly property int pollInterval: anyRunning ? 500 : 30000

  function refresh() { statusProc.running = true }

  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.applyStatus(text)
    }
  }

  function applyStatus(text) {
    var payload
    try {
      payload = JSON.parse(text)
    } catch (e) {
      // A crashing CLI must not blank the widget: keep whatever was on screen
      // and let the next poll try again.
      root.loaded = true
      return
    }

    root.configured = payload.configured === true
    root.unitsInstalled = payload.units_installed === true
    root.configInvalid = payload.invalid === true
    root.configError = payload.error ? String(payload.error) : ""
    root.destinations = payload.destinations || []
    root.sources = payload.source || []
    root.systemSnapshotAvailable = payload.system_snapshot_available === true

    root.reconcileStarting()
    root.loaded = true
  }

  Timer {
    interval: root.pollInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.clockTick++
  }

  // --- actions ------------------------------------------------------------

  // systemd owns every backup, including this one. Two reasons: the shell
  // restarts on a theme change or a plugin update, and a Process started here
  // would die with it halfway through a run; and the nightly timer and this
  // button start the same unit instance, so systemd serialises them without
  // any locking of our own.
  Process { id: startProc }
  Process { id: stopProc }
  Process { id: useProc; stdout: StdioCollector { onStreamFinished: root.refresh() } }

  readonly property bool multiple: destinations.length > 1

  // Every destination with a unit, not just one. There is no "current" backup
  // to a user with three of them: they all matter, and the nightly timers run
  // them all anyway, so the button does what the schedule does.
  function startAllBackups() {
    for (var i = 0; i < destinations.length; i++) {
      var d = destinations[i]
      if (d.running) continue
      startOne(String(d.name))
    }
    kickPoll.restart()
  }

  function startOne(name) {
    startProc.command = ["systemctl", "--user", "start", "--no-block",
                         "omarchy-backitup@" + name + ".service"]
    startProc.running = true
    markStarting(String(name))
  }

  // Names the user just started, before systemd reports the unit active.
  // `systemctl start --no-block` returns at once and the unit is only
  // `activating` for a beat after that, so "Back Up Now" would sit unchanged
  // after being pressed and read as a dead click. These names count as running
  // until the status confirms them, or a short grace expires so a start that
  // fails does not lie forever.
  property var startingNames: []

  function markStarting(name) {
    var list = startingNames.slice()
    if (list.indexOf(String(name)) === -1) list.push(String(name))
    startingNames = list
    startGrace.restart()
  }

  function clearStarting(name) {
    var list = []
    for (var i = 0; i < startingNames.length; i++)
      if (String(startingNames[i]) !== String(name)) list.push(startingNames[i])
    startingNames = list
  }

  function isStarting(d) {
    if (!d || d.name === undefined) return false
    return startingNames.indexOf(String(d.name)) !== -1
  }

  // Hand a name over to the status once it reports the unit running; drop
  // names the status never confirms when the grace expires.
  function reconcileStarting() {
    if (startingNames.length === 0) return
    var keep = []
    for (var i = 0; i < startingNames.length; i++) {
      var name = startingNames[i]
      var live = false
      for (var j = 0; j < destinations.length; j++) {
        if (String(destinations[j].name) === name) {
          if (destinations[j].running === true) live = true
          break
        }
      }
      if (!live) keep.push(name)
    }
    if (keep.length !== startingNames.length) startingNames = keep
  }

  Timer {
    id: startGrace
    interval: 10000
    repeat: false
    onTriggered: startingNames = []
  }

  readonly property bool anyRunning: {
    if (startingNames.length > 0) return true
    for (var i = 0; i < destinations.length; i++)
      if (destinations[i].running) return true
    return false
  }

  readonly property bool anyFailed: {
    for (var i = 0; i < destinations.length; i++) {
      var run = destinations[i].last_run
      if (run && run.result === "failed") return true
    }
    return false
  }

  // The destination a one-line verdict should name. `active` is only the
  // first destination, which is the wrong one to describe the moment a
  // second drive is the one that broke or the one working.
  readonly property var runningDestination: {
    for (var i = 0; i < destinations.length; i++)
      if (destinations[i].running || isStarting(destinations[i])) return destinations[i]
    return null
  }

  readonly property var failedDestination: {
    for (var i = 0; i < destinations.length; i++)
      if (destinationFailed(destinations[i])) return destinations[i]
    return null
  }

  // The first destination that is not simply fine: a failed run, a broken
  // audit, a system snapshot that did not happen.
  readonly property var attentionDestination: {
    for (var i = 0; i < destinations.length; i++) {
      var s = destinationStatus(destinations[i])
      if (s === "bad" || s === "warn") return destinations[i]
    }
    return null
  }

  // What one destination says about itself in the list.
  function destinationLabel(d) {
    return d.display_name ? String(d.display_name) : String(d.name)
  }

  // Something to read while it works. A progress bar that says "Backing up"
  // for four minutes tells you nothing you did not already know, and the
  // Dropbox widget in this shell has been doing this for ages, so it is a
  // house habit rather than a novelty.
  //
  // Tied to the destination name and the minute, so it changes as the run goes
  // on but does not flicker every time the percentage ticks over.
  readonly property var workingPhrases: [
    "Pushing bytes",
    "Hoarding your files",
    "Packing memories",
    "Filing everything away",
    "Squirrelling things away",
    "Bottling the moment",
    "Making yesterday reachable",
    "Copying, deduplicating, encrypting",
    "Freezing time",
    "Keeping the past around",
    "Boxing up the present",
    "Talking to the other end"
  ]

  // Advances on its own clock rather than riding clockTick, which only moves
  // once a minute: a backup that finishes in ninety seconds would have shown
  // one phrase and looked stuck.
  property int phraseIndex: 0

  Timer {
    interval: 4000
    running: root.anyRunning
    repeat: true
    onTriggered: root.phraseIndex++
  }

  function workingPhrase(seed) {
    // Offset per destination, so two running at once are not in lockstep.
    var offset = 0
    var key = String(seed)
    for (var i = 0; i < key.length; i++) offset = (offset * 31 + key.charCodeAt(i)) & 0x7fffffff
    return workingPhrases[(phraseIndex + offset) % workingPhrases.length]
  }

  function destinationState(d) {
    clockTick
    if (d.running || isStarting(d)) {
      var p = d.progress
      if (p && p.percent !== undefined && p.percent !== null)
        return Math.round(Number(p.percent) * 100) + "%"
      return "Working\u2026"
    }
    if (!d.last_run) return "Never"
    if (d.last_run.result === "unreachable") return "Not connected"
    if (d.last_run.result === "failed")
      return "Failed " + menuDate(d.last_run.finished_at)
               .replace(/^Today/, "today").replace(/^Yesterday/, "yesterday")
    return menuDate(d.last_run.finished_at)
  }

  // The second line under a destination. After a failure that is how old your
  // newest good copy is, which is the thing you actually need to know. The
  // rest of the time it is how much is stored and what last night added, so
  // you can see the backup is still incremental and the disk is not filling.
  function destinationDetail(d) {
    clockTick
    if (d.running || isStarting(d)) {
      var p = d.progress
      var phase = p ? String(p.phase) : ""
      if (phase === "pre") return "Waking up the destination\u2026"
      if (phase === "unlock") return "Unlocking\u2026"
      if (phase === "prune") return "Tidying up old backups\u2026"

      var phrase = workingPhrase(d.name)
      if (!p || !p.total_bytes) return phrase + "\u2026"
      return phrase + "\u2026 " + humanBytes(p.bytes_done) + " of " + humanBytes(p.total_bytes)
    }

    if (d.last_run && d.last_run.result === "unreachable") {
      if (d.last_success_at)
        return "Not connected \u00b7 Last good backup: " + menuDate(d.last_success_at)
      return "Not connected \u00b7 no successful backup yet"
    }

    if (destinationFailed(d)) {
      if (d.last_success_at)
        return "Last good backup: " + menuDate(d.last_success_at)
      return "No successful backup yet"
    }

    if (!d.last_run) return ""
    var parts = []
    if (d.repo_size_bytes)
      parts.push(humanBytes(d.repo_size_bytes)
                 + (d.snapshot_count ? " in " + d.snapshot_count + " snapshots" : ""))
    if (d.last_run.data_added_bytes)
      parts.push(humanBytes(d.last_run.data_added_bytes) + " added")
    return parts.join(" \u00b7 ")
  }

  // The quantities under a destination name, as value/label pairs. Split
  // rather than one string so a view can set the numbers in a brighter
  // weight than the words around them -- the numbers are what you scan for.
  // Empty after a failure or a run in flight: there the useful line is how
  // old the newest good copy is, which destinationDetail already says. Same
  // for a destination that could not be reached: the numbers are from the
  // last time the drive was in, and painting them under "Not connected"
  // would read as a health report it is not.
  function destinationMetrics(d) {
    var out = []
    if (!d || d.running || isStarting(d) || destinationFailed(d) || !d.last_run) return out
    if (d.last_run.result === "unreachable") return out
    if (d.repo_size_bytes)
      out.push({ value: humanBytes(d.repo_size_bytes), label: "stored" })
    if (d.snapshot_count)
      out.push({ value: String(d.snapshot_count),
                 label: Number(d.snapshot_count) === 1 ? "snapshot" : "snapshots" })
    if (d.last_run.data_added_bytes)
      out.push({ value: humanBytes(d.last_run.data_added_bytes), label: "added" })
    return out
  }

  function destinationFailed(d) {
    return d.last_run ? d.last_run.result === "failed" : false
  }

  // The semantic state of one destination: "ok", "busy", "warn", "bad", or
  // "idle". Every view paints from this, so the bar, the hero and the card
  // can never disagree about whether a destination is fine. A run that is
  // happening now outranks a stale failure from before it: the newest word
  // wins. An audit or a system snapshot that went wrong is a warning, not a
  // failure -- the files are safe, one promise is not. And a destination the
  // backup could not reach is not a failure at all: nothing ran, the last
  // good copy is as good as it ever was, and red is spent only on runs that
  // actually failed. It reads as idle, with the reason on the card.
  function destinationStatus(d) {
    if (d.running || isStarting(d)) return "busy"
    if (d.last_run && d.last_run.result === "unreachable") return "idle"
    if (destinationFailed(d)) return "bad"
    if (!d.last_run) return "idle"
    if (auditHasProblems(d)) return "warn"
    if (destinationSnapshotProblem(d)) return "warn"
    return "ok"
  }

  // The worst state across every destination, for the single verdict at the
  // top and the bar icon. Severity order: bad > warn > busy > ok > idle.
  readonly property string overallStatus: {
    if (configInvalid) return "bad"
    if (!configured || destinations.length === 0) return "idle"
    var rank = { idle: 0, ok: 1, busy: 2, warn: 3, bad: 4 }
    var worst = "ok"
    for (var i = 0; i < destinations.length; i++) {
      var s = destinationStatus(destinations[i])
      if (rank[s] > rank[worst]) worst = s
    }
    return worst
  }

  // The audit's verdict on the newest backup: what comparing the disk with
  // the snapshot found. Only unreadable paths are a problem, so the message
  // says either that everything checked out or how much did not. Written by
  // the audit that runs after every backup, so it always describes the most
  // recent one -- a clean verdict after a failed run means the failure was
  // not unreadable files.
  function destinationAudit(d) {
    if (!d.last_audit) return ""
    var n = d.last_audit.unreadable
    if (n === undefined || n === null) return ""
    if (Number(n) === 0) return "Audit: every file verified"
    return "Audit: " + n + (Number(n) === 1 ? " file" : " files") + " unreadable"
  }

  function auditHasProblems(d) {
    if (!d.last_audit) return false
    var n = d.last_audit.unreadable
    return n !== undefined && n !== null && Number(n) > 0
  }

  // The system snapshot paired with the newest backup, when the destination
  // asked for one. Every verdict except "created" explains itself: a toggle
  // that looks on must say why nothing was taken, or the user stops believing
  // the line. Reads from last_run, so a run that crashed before record_status
  // leaves the previous verdict standing, like every other last_run field.
  function destinationSnapshot(d) {
    if (!d.last_run || !d.last_run.system_snapshot) return ""
    var s = d.last_run.system_snapshot
    var word = s.result === "created" ? "taken" : s.result
    if (s.reason) return "System snapshot: " + word + " \u2014 " + s.reason
    return "System snapshot: " + word
  }

  // Urgent when the newest run wanted a snapshot and did not get one, or
  // when the copy of it into the backup was skipped: a toggle that looks on
  // must explain what did not happen, and the reason string names the fix.
  function destinationSnapshotProblem(d) {
    if (!d.last_run || !d.last_run.system_snapshot) return false
    var s = d.last_run.system_snapshot
    return s.result !== "created" || s.reason != null
  }

  function startBackup() {
    if (!active || running) return
    startProc.command = ["systemctl", "--user", "start", "--no-block",
                         "omarchy-backitup@" + active.name + ".service"]
    startProc.running = true
    markStarting(String(active.name))
    // Do not wait for the next tick: the unit takes a moment to report itself
    // as active, and an unresponsive button reads as a broken one.
    kickPoll.restart()
  }

  function stopBackup() {
    if (!active) return
    stopProc.command = ["systemctl", "--user", "stop",
                        "omarchy-backitup@" + active.name + ".service"]
    stopProc.running = true
    clearStarting(String(active.name))
    kickPoll.restart()
  }



  Timer {
    id: kickPoll
    interval: 400
    repeat: false
    onTriggered: root.refresh()
  }

  // omarchy-launch-editor honours whatever the user set as their default
  // editor and opens it in a terminal, which is what a JSON file wants.
  // xdg-open would hand a .json to whatever claims the mime type.
  // Writes a starter configuration if there isn't one, then opens whatever is
  // there. Editing a file that does not exist yet means a blank buffer and a
  // trip to the README; this way the first thing you see already works once
  // you change one path.
  function createConfig() {
    createProc.command = [root.cli, "config", "create"]
    createProc.running = true
  }

  Process {
    id: createProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.openConfig()
        root.refresh()
      }
    }
  }

  function openConfig() {
    configProc.command = ["omarchy-launch-editor",
                          homeDir + "/.config/omarchy-backitup/config.json"]
    configProc.running = true
  }

  Process { id: configProc }

  readonly property string homeDir: Quickshell.env("HOME")

  function openLog() {
    if (!lastRun || !lastRun.log_file) return
    logProc.command = ["xdg-open", String(lastRun.log_file)]
    logProc.running = true
  }

  Process { id: logProc }

  // --- guided setup ---------------------------------------------------------

  // The setup screen runs one command: apply-setup validates its document
  // against the same rules the units will get, and does everything a first
  // run needs -- config, key, repository, timers. The document is staged to
  // a 0600 temp file under XDG_RUNTIME_DIR and handed over with --file.
  // Earlier it traveled on stdin via Process.write(), but Quickshell has no
  // closeStdin(): the pipe's write end stays open, the CLI's `cat` never
  // sees EOF, and apply-setup hangs forever -- the panel sat on "Applying…"
  // with the CLI blocked in anon_pipe_read. A file keeps the password off
  // the command line either way: the short-lived writer receives it through
  // its environment (same-user readable only, milliseconds of life) and the
  // file is removed the moment the CLI exits.
  property bool setupBusy: false
  property string setupError: ""
  property string setupDone: ""
  property string setupPendingDoc: ""
  // XDG_RUNTIME_DIR is a 0700 directory owned by the user, which is exactly
  // what the staged document needs; ~/.cache is the fallback when a session
  // did not set it. Never /tmp: it is world-writable, and a fixed name there
  // is a symlink waiting to be planted. Writer and reader both derive the
  // path from this one property, so they cannot disagree.
  readonly property string applyDir: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    if (runtime) return runtime + "/omarchy-backitup"
    var home = Quickshell.env("HOME")
    return home ? home + "/.cache/omarchy-backitup" : ""
  }
  readonly property string applyTmpFile: applyDir ? applyDir + "/apply.json" : ""

  function applySetup(doc) {
    if (setupBusy) return
    if (!applyTmpFile) {
      setupError = "no runtime directory is available to stage the setup document"
      return
    }
    setupBusy = true
    setupError = ""
    setupDone = ""
    setupPendingDoc = JSON.stringify(doc)
    applyFileProc.running = true
  }

  // Stages the pending document, then hands off to the CLI. The document
  // travels in an environment variable, never on a command line.
  Process {
    id: applyFileProc
    environment: ({ TM_DOC: setupPendingDoc })
    command: ["bash", "-c", "d=\"${XDG_RUNTIME_DIR:-$HOME/.cache}/omarchy-backitup\"; [ -n \"$TM_DOC\" ] && [ -n \"${XDG_RUNTIME_DIR:-$HOME}\" ] || exit 4; umask 077; mkdir -p -m 700 -- \"$d\" || exit 4; [ -d \"$d\" ] && [ ! -L \"$d\" ] || exit 4; rm -f -- \"$d/apply.json\" || exit 4; set -o noclobber; printf '%s' \"$TM_DOC\" > \"$d/apply.json\""]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.setupBusy = false
        root.setupError = "could not stage the setup document"
        return
      }
      applyProc.command = [root.cli, "apply-setup", "--file", root.applyTmpFile]
      applyProc.running = true
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      onStreamFinished: {
        // The install step prints systemctl's timer table, which wrapped at
        // panel width is unreadable. Keep the lines that say what happened,
        // drop the table, keep the final line that says it worked.
        var t = text
        var i = t.indexOf("Next run:")
        if (i !== -1) {
          var j = t.indexOf("Setup complete")
          t = t.substring(0, i) + (j !== -1 ? t.substring(j) : "")
        }
        root.setupDone = t.trim()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: if (text !== "") root.setupError = text
    }
    // quickshell's Process signal is exited: onFinished is a method the C++
    // side calls itself, and assigning to it is a QML error that kills the
    // whole plugin load -- bar glyph, panel, everything. qmllint does not
    // catch it; the journal does.
    onExited: function(exitCode, exitStatus) {
      cleanupProc.running = true
      root.setupBusy = false
      root.refresh()
    }
  }

  // Removes the staged document as soon as the CLI is done with it: the file
  // carries the password, so it must not outlive the apply, whichever way
  // the apply ends.
  Process {
    id: cleanupProc
    command: ["rm", "-f", "--", root.applyTmpFile]
  }

  // --- snapshots ----------------------------------------------------------

  // Which destination the restore browser is looking at. Separate from
  // anything the main panel does: browsing another destination's history is
  // reading, and should not change what the next backup writes to.
  property string browseName: ""

  readonly property var browseDest: {
    for (var i = 0; i < destinations.length; i++)
      if (destinations[i].name === browseName) return destinations[i]
    return active
  }

  function browseDestination(name) {
    if (name === browseName) return
    browseName = name
    snapshots = []
    snapshotsLoaded = false
    clearListCache()
    loadSnapshots()
  }

  property var snapshots: []
  property bool snapshotsLoaded: false
  property bool snapshotsBusy: false
  property string snapshotsError: ""

  // The last success and the last run the list was loaded after. A session
  // cache that never re-checks is how an empty listing outlives the backups
  // that filled the repository: open the browser before the first run
  // finishes and the empty list is held until the plugin reloads -- an hour
  // later, after a reboot. Two keys, because the list changes on more than a
  // success: a failed run that still wrote a snapshot (gaps) adds one while
  // last_success_at stays put -- it means "last good backup", and the panel
  // promises that. The run's own finish time moves on every run, success or
  // not, so it is the key that cannot miss. A delete moves neither, but the
  // delete reloads the list itself the moment it finishes.
  property string snapshotsLoadedAtSuccess: ""
  property string snapshotsLoadedAtRun: ""

  function snapshotsStale() {
    var d = browseDest
    if (!d) return false
    var runAt = d.last_run && d.last_run.finished_at ? String(d.last_run.finished_at) : ""
    return String(d.last_success_at || "") !== snapshotsLoadedAtSuccess
        || runAt !== snapshotsLoadedAtRun
  }

  function loadSnapshots() {
    var d = browseDest
    if (!d || snapshotsBusy) return
    if (browseName === "") browseName = String(d.name)
    snapshotsBusy = true
    snapshotsError = ""
    snapshotsLoadedAtSuccess = String(d.last_success_at || "")
    snapshotsLoadedAtRun = d.last_run && d.last_run.finished_at ? String(d.last_run.finished_at) : ""
    snapshotsProc.command = [root.cli, "snapshots", "--dest", String(d.name), "--json"]
    snapshotsProc.running = true
  }

  Process {
    id: snapshotsProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.snapshotsBusy = false
        var payload
        try {
          payload = JSON.parse(text)
        } catch (e) {
          root.snapshotsError = "could not read snapshots"
          return
        }
        if (payload.ok !== true) {
          root.snapshotsError = payload.error ? String(payload.error) : "could not read snapshots"
          return
        }
        root.snapshots = payload.snapshots || []
        root.snapshotsLoaded = true
      }
    }
  }

  // --- directory listing --------------------------------------------------
  //
  // One `restic ls` per directory, never a recursive walk: a home directory
  // holds well over a million files and listing it whole would stall the panel
  // for minutes. Visited paths are cached for the session so walking back up
  // is instant.

  property var listCache: ({})
  property bool listBusy: false
  property string listError: ""
  property var entries: []
  property bool listTruncated: false
  property string currentPath: ""
  property string currentSnapshot: ""

  function cacheKey(snapshot, path) { return snapshot + " " + path }

  function listPath(snapshot, path) {
    var d = browseDest
    if (!d) return
    currentSnapshot = snapshot
    currentPath = path
    listError = ""

    var key = cacheKey(snapshot, path)
    if (listCache[key] !== undefined) {
      entries = listCache[key].entries
      listTruncated = listCache[key].truncated
      return
    }

    entries = []
    listTruncated = false
    listBusy = true
    // The browsed path travels in an environment variable, never on a
    // command line: the CLI's own /proc entry is world-readable for as long
    // as the listing runs, and the path can sit inside a private directory.
    lsProc.environment = ({ BACKITUP_LS_PATH: String(path) })
    lsProc.command = [root.cli, "ls", "--dest", String(d.name),
                      "--snapshot", snapshot, "--json"]
    lsProc.running = true
  }

  Process {
    id: lsProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.listBusy = false
        var payload
        try {
          payload = JSON.parse(text)
        } catch (e) {
          root.listError = "could not read this folder"
          return
        }
        if (payload.ok !== true) {
          root.listError = payload.error ? String(payload.error) : "could not read this folder"
          return
        }
        // Cache under the path the CLI reports, not the one that was asked
        // for: they are the same today, and a mismatch would silently poison
        // the cache if that ever changed.
        var key = root.cacheKey(root.currentSnapshot, String(payload.path))
        var record = { entries: payload.entries || [], truncated: payload.truncated === true }
        root.listCache[key] = record
        if (String(payload.path) === root.currentPath) {
          root.entries = record.entries
          root.listTruncated = record.truncated
        }
      }
    }
  }

  function clearListCache() {
    listCache = ({})
    entries = []
    currentPath = ""
  }

  // --- restore ------------------------------------------------------------
  //
  // Never in place. Everything lands in a dated folder under ~/Restored, so a
  // restore can never erase work created after the snapshot; moving it back is
  // a deliberate act the user performs in a file manager, seeing what they
  // overwrite.

  property bool restoreBusy: false
  property string restoreTarget: ""
  property string restoreError: ""

  // `paths` is what to bring back: one path or several. restic takes
  // --include once per path and they share a single repository unlock, a
  // single target and a single progress stream, so ticking five files in the
  // browser is one restore rather than five. A bare string still works,
  // because the browser was written against that and a one-item queue should
  // not need a different call site.
  function restore(snapshot, paths) {
    var d = browseDest
    if (!d || restoreBusy) return

    var list = []
    if (paths instanceof Array) list = paths
    else if (paths !== undefined && paths !== null && String(paths) !== "") list = [String(paths)]
    if (list.length === 0) return

    restoreBusy = true
    restoreError = ""
    restoreTarget = ""

    var command = [root.cli, "restore", "--dest", String(d.name),
                   "--snapshot", String(snapshot)]
    // The paths travel in an environment variable, never on a command line:
    // a restore runs for minutes with its /proc entry world-readable, and
    // the paths can name files the user keeps private.
    restoreProc.environment = ({ BACKITUP_RESTORE_PATHS: list.join("\n") })
    restoreProc.command = command
    restoreProc.running = true
  }

  Process {
    id: restoreProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.restoreBusy = false
        var payload
        try {
          payload = JSON.parse(text)
        } catch (e) {
          root.restoreError = "restore failed"
          return
        }
        if (payload.ok === true) root.restoreTarget = String(payload.target)
        else root.restoreError = payload.error ? String(payload.error) : "restore failed"
      }
    }
  }

  // --- delete ---------------------------------------------------------------
  //
  // The one operation here that cannot be undone, and the picker keeps it
  // two interactions away: pick a date, confirm, gone. The command runs
  // forget with --prune, so the space comes back immediately and the work
  // can take minutes on a large repository; the busy line says so rather
  // than looking wedged.

  property bool deleteBusy: false
  property string deleteError: ""

  function startDelete(d, snapshotId) {
    if (!d || deleteBusy) return
    deleteBusy = true
    deleteError = ""
    deleteProc.command = [root.cli, "delete", "--dest", String(d.name),
                          "--snapshot", snapshotId]
    deleteProc.running = true
  }

  Process {
    id: deleteProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.deleteBusy = false
        var payload
        try {
          payload = JSON.parse(text)
        } catch (e) {
          root.deleteError = "delete failed"
          return
        }
        if (payload.ok !== true) {
          root.deleteError = payload.error ? String(payload.error) : "delete failed"
          return
        }
        // The deleted snapshot is gone from the repository, but the list was
        // loaded earlier and the staleness key, last_success_at, does not
        // move on a delete. Reload it now, or the date the user just deleted
        // would sit in the picker until the next backup.
        root.loadSnapshots()
        // The delete also changed the two numbers the main panel reads from
        // status.json -- the snapshot count and the repository size, which the
        // CLI rewrites after the prune. Pull the new status in now rather than
        // leaving the pre-delete figures on screen until the next poll.
        root.refresh()
      }
    }
  }

  // --- formatting ---------------------------------------------------------

  function plain(value) {
    // Anything heading for a shell component whose textFormat is not ours to
    // set -- the bar tooltip, ConfirmDialog. Our own strings are safe, but a
    // destination name comes out of config.json, a message comes out of
    // restic, and a filename comes out of the backup itself.
    return String(value === undefined || value === null ? "" : value).replace(/[<>]/g, "")
  }

  function parseTime(value) {
    if (!value) return null
    var date = new Date(String(value))
    return isNaN(date.getTime()) ? null : date
  }

  function relativeTime(value) {
    var date = parseTime(value)
    if (!date) return "never"

    var seconds = Math.floor((Date.now() - date.getTime()) / 1000)
    if (seconds < 0) seconds = 0
    if (seconds < 60) return "just now"

    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + (minutes === 1 ? " minute ago" : " minutes ago")

    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + (hours === 1 ? " hour ago" : " hours ago")

    var days = Math.floor(hours / 24)
    if (days < 30) return days + (days === 1 ? " day ago" : " days ago")

    var months = Math.floor(days / 30)
    if (months < 12) return months + (months === 1 ? " month ago" : " months ago")

    var years = Math.floor(days / 365)
    return years + (years === 1 ? " year ago" : " years ago")
  }

  function shortDate(value) {
    var date = parseTime(value)
    if (!date) return ""
    return Qt.formatDateTime(date, root.dateFormat + " " + root.timeFormat)
  }

  // "Today, 21:52" / "Yesterday, 03:09" / "24 Aug, 03:09" -- the menu-bar
  // phrasing, where the day matters more than how many hours ago it was.
  function menuDate(value) {
    var date = parseTime(value)
    if (!date) return "Never"

    var now = new Date()
    var midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    var time = Qt.formatDateTime(date, root.timeFormat)

    // "Today" and "Yesterday" beat any date format for the two days you look
    // at most, which is why every calendar app does it.
    if (date >= midnight) return "Today, " + time
    if (date >= new Date(midnight.getTime() - 86400000)) return "Yesterday, " + time

    return Qt.formatDateTime(date, root.dateFormat) + ", " + time
  }

  function humanBytes(value) {
    var bytes = Number(value)
    if (!isFinite(bytes) || bytes <= 0) return "0 B"
    var units = ["B", "KB", "MB", "GB", "TB"]
    var unit = 0
    while (bytes >= 1024 && unit < units.length - 1) { bytes /= 1024; unit++ }
    return (bytes >= 100 || unit === 0 ? Math.round(bytes) : bytes.toFixed(1)) + " " + units[unit]
  }

  function humanDuration(seconds) {
    var total = Number(seconds)
    if (!isFinite(total) || total < 0) return ""
    if (total < 60) return Math.round(total) + "s"
    var minutes = Math.floor(total / 60)
    if (minutes < 60) return minutes + "m " + Math.round(total % 60) + "s"
    return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m"
  }

  // What the bar tooltip says. The bar shows the icon alone, so this is the
  // only place the age of a backup is legible without opening the panel.
  readonly property string tooltip: {
    clockTick // re-evaluate as time passes
    if (!configured) return "BackIt Up — not configured yet"
    if (anyRunning) {
      var d = null
      for (var i = 0; i < destinations.length; i++)
        if (destinations[i].running) { d = destinations[i]; break }
      if (d) return destinationLabel(d) + ": " + destinationDetail(d)
      return "Backing up…"
    }
    if (failed) {
      var when = menuDate(lastRun.finished_at)
      var since = lastSuccessAt !== "" ? ", last good one " + relativeTime(lastSuccessAt) : ""
      return "Backup failed " + when.charAt(0).toLowerCase() + when.slice(1) + since
    }
    if (!everRan) return "BackIt Up — no backup yet"
    return "Last backup: " + relativeTime(lastRun.finished_at)
  }
}
