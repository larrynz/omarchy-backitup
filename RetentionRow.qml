import QtQuick
import QtQuick.Controls
import qs.Commons

// How many copies of each tier to keep, as four editable counts.
//
// Four counts rather than a sentence ("keep 7 daily, 4 weekly, ..."):
// retention is the one setting on this screen whose value is a number, and
// the numbers are what restic forget is actually given, so showing them in
// the same grid they are read in makes the policy arguable at a glance.
//
// `retention` may be null, partial, or complete. Null and missing keys fall
// back to `defaults`, which mirrors the CLI's own fall-through -- what you
// see here is the policy that would actually be kept, not just what the
// destination happens to spell out.
Row {
  id: root

  property var retention: null
  property var defaults: ({ daily: 7, weekly: 4, monthly: 12, yearly: 3 })
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal changed(var retention)

  readonly property var tiers: [
    { key: "daily",   label: "Daily" },
    { key: "weekly",  label: "Weekly" },
    { key: "monthly", label: "Monthly" },
    { key: "yearly",  label: "Yearly" }
  ]

  spacing: Style.space(7)

  // What the field should show for a tier: the destination's own count, else
  // the fall-through. Kept separate from the field so `retention` can stay
  // null and still render a sensible, complete grid.
  function _valueFor(key) {
    var r = root.retention
    if (r) {
      var v = r[key]
      if (v !== undefined && v !== null && isFinite(Number(v)))
        return Math.round(Number(v))
    }
    var d = root.defaults ? root.defaults[key] : undefined
    return (d === undefined || d === null) ? 0 : Math.round(Number(d))
  }

  // Emits a complete block: the counts already set, plus the one just typed.
  // Complete rather than a patch, because the CLI merges key by key and a
  // patch would leave it unable to tell "set this to the default" from "leave
  // this alone" -- and the field now shows a default the user may have edited
  // on purpose.
  function _emit(key, text) {
    var n = parseInt(String(text), 10)
    if (!isFinite(n) || n < 0) return
    var next = ({})
    for (var i = 0; i < root.tiers.length; i++) {
      var k = root.tiers[i].key
      next[k] = (k === key) ? n : root._valueFor(k)
    }
    root.changed(next)
  }

  // Push external changes (edit-config seeding the form) into the fields.
  // Skipped for the field being typed in: the edit is already there, and
  // rewriting it mid-keystroke would jump the caret and drop a digit.
  function _sync() {
    for (var i = 0; i < cells.count; i++) {
      var cell = cells.itemAt(i)
      if (!cell || !cell.field) continue
      if (cell.field.activeFocus) continue
      var want = String(root._valueFor(cell.tierKey))
      if (cell.field.text !== want) cell.field.text = want
    }
  }

  onRetentionChanged: root._sync()
  Component.onCompleted: root._sync()

  Repeater {
    id: cells
    model: root.tiers

    delegate: Rectangle {
      id: cell

      required property var modelData
      readonly property string tierKey: modelData.key
      readonly property alias field: entry

      width: Math.max(Style.space(40),
                      (root.width - root.spacing * Math.max(0, cells.count - 1))
                      / Math.max(1, cells.count))
      height: Style.space(46)
      radius: Style.space(7)
      color: "transparent"
      border.width: Style.space(1)
      border.color: entry.activeFocus ? root.accent
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

      Column {
        anchors.centerIn: parent
        spacing: 0

        TextField {
          id: entry
          width: cell.width - Style.space(10)
          text: String(root._valueFor(cell.tierKey))
          horizontalAlignment: TextInput.AlignHCenter
          // Digits only, and the validator refuses a value the CLI would too:
          // a negative or fractional count must not be typeable, or the error
          // would only surface on Apply.
          inputMethodHints: Qt.ImhDigitsOnly
          validator: IntValidator { bottom: 0; top: 9999 }
          selectByMouse: true
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          color: root.foreground
          topPadding: 0
          bottomPadding: 0

          background: Rectangle { color: "transparent" }

          onTextEdited: root._emit(cell.tierKey, text)
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: cell.modelData.label.toUpperCase()
          textFormat: Text.PlainText
          color: Qt.darker(root.foreground, 1.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
