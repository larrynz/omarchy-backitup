pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// The semantic status palette.
//
// The shell's Color singleton surfaces foreground, background, accent and
// urgent -- and nothing else. This redesign rests on one rule: a state gets
// its own hue, so "running" stops wearing the same red as "failed". That
// needs green, yellow and cyan, which the shell does not expose but every
// Omarchy theme does carry in colors.toml (the terminal palette behind
// foreground/accent/urgent). So this reads that same file -- the one the
// shell itself reads for the other roles -- and picks the rest up.
//
// The bright variants win where a theme has them: they are the ones that
// read on the dark popup surface. None of the shipped themes omit a colour
// this asks for, so the fallbacks are only a floor.
QtObject {
  id: root

  readonly property string themeDir:
    Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"

  // ok / working / attention / failed, plus idle for "no state yet".
  property color ok: "#9ab57e"      // bright green
  property color busy: "#7ec4d2"    // bright cyan
  property color warn: "#f0b45a"    // yellow
  property color bad: "#f06a58"     // bright red
  readonly property color idle: Color.muted

  function loadColors(raw) {
    var found = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!m) continue
      var key = m[1]
      if (key === "green" || key === "bright_green"
          || key === "yellow" || key === "bright_yellow"
          || key === "cyan" || key === "bright_cyan"
          || key === "red" || key === "bright_red") {
        found[key] = m[2]
      }
    }
    if (found.green || found.bright_green) ok = found.bright_green || found.green
    if (found.cyan || found.bright_cyan) busy = found.bright_cyan || found.cyan
    if (found.yellow || found.bright_yellow) warn = found.yellow || found.bright_yellow
    if (found.red || found.bright_red) bad = found.bright_red || found.red
  }

  property FileView colorsFile: FileView {
    path: root.themeDir + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadColors(text())
    onFileChanged: reload()
  }

  // The colour for a status state. One function, so every view agrees on
  // what "ok" looks like, and a state can never silently pick the wrong hue.
  function color(state) {
    if (state === "ok") return ok
    if (state === "busy") return busy
    if (state === "warn") return warn
    if (state === "bad") return bad
    return idle
  }

  // A translucent wash of a status colour, for a badge or pill fill. `alpha`
  // is the composited alpha over the card underneath.
  function tint(c, alpha) {
    return Qt.rgba(c.r, c.g, c.b, alpha)
  }

  // The same colour at full strength, for a border or a stripe.
  function line(c, alpha) {
    return Qt.rgba(c.r, c.g, c.b, alpha)
  }
}
