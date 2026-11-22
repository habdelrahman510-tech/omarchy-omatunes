pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "Colors.js" as Colors

// Omatunes' design system, translated for QML.
//
// Omatunes publishes the palette it actually resolved (all eleven roles, for
// every theme source: the Omarchy theme, its own presets, or a custom palette)
// to `~/.cache/omatunes_theme.json`, replaced atomically whenever a palette is
// installed. This adapter is a *translation layer* over that contract — it owns
// no colours of its own beyond the fallback below, so the companion cannot
// drift away from the application it belongs to.
//
// Contract (schema 1, written by `src/ui/theme.rs::publish_theme_export`):
//
//   {"schema":1,"product":"omatunes","source":"System|Preset|Custom",
//    "name":"last-horizon","palette":{"base":"#0c0b0c","mantle":"#…",
//    "surface":"#…","overlay":"#…","text":"#…","subtext":"#…","accent":"#…",
//    "green":"#…","red":"#…","yellow":"#…","blue":"#…"}}
//
// Fallback: a build that predates the export (2.0.2 and earlier) has no file.
// The adapter then derives the same roles from the shell's own theme colours,
// which are read from the very same Omarchy `colors.toml` Omatunes uses for its
// `System` source — a close surrogate, explicitly not the source of truth.
QtObject {
  id: root

  readonly property string exportPath: (Quickshell.env("HOME") || "") + "/.cache/omatunes_theme.json"

  // Parsed payload, or null while Omatunes has not published one.
  property var published: null

  readonly property bool fromApp: root.published !== null
  readonly property string sourceName: root.fromApp ? String(root.published.source || "") : "shell"
  readonly property string themeName: root.fromApp ? String(root.published.name || "") : ""

  property FileView file: FileView {
    path: root.exportPath
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.read()
    onLoadFailed: root.published = null
    onFileChanged: {
      root.file.reload()
      root.read()
    }
  }

  function read() {
    var raw = ""
    try {
      raw = root.file.text() || ""
    } catch (error) {
      return
    }
    root.published = root.parse(raw)
  }

  // Exposed so the companion's other read-only contract (the queue snapshot)
  // validates payloads exactly the same way.
  function parse(raw) {
    if (!raw) return null
    var data = null
    try {
      data = JSON.parse(raw)
    } catch (error) {
      // A half-written export is an absent export, never a broken popup.
      return null
    }
    if (!data || typeof data !== "object") return null
    if (Number(data.schema) !== 1 || String(data.product || "") !== "omatunes") return null
    var palette = data.palette
    if (!palette || typeof palette !== "object") return null
    // Refuse a payload that is missing the roles the surfaces are built from.
    var required = ["base", "text", "accent"]
    for (var i = 0; i < required.length; i++) {
      if (!Colors.valid(palette[required[i]])) return null
    }
    return data
  }

  Component.onCompleted: root.read()

  // --------------------------------------------------------------- tokens
  //
  // Semantic roles, mapped from Omatunes' own vocabulary:
  //   base    -> background      mantle  -> surface
  //   surface -> raised          overlay -> quiet ink / hairlines
  //   text    -> ink             subtext -> secondary ink
  function tokensFrom(palette) {
    var background = Colors.valid(palette.base) ? palette.base : Commons.Color.popups.background
    var ink = Colors.valid(palette.text) ? palette.text : Commons.Color.popups.text
    var raised = Colors.valid(palette.surface) ? palette.surface : Colors.mix(background, ink, 0.12)
    var surface = Colors.valid(palette.mantle) ? palette.mantle : Colors.mix(background, ink, 0.06)
    var quiet = Colors.valid(palette.overlay) ? palette.overlay : Colors.mix(ink, background, 0.45)
    var secondary = Colors.valid(palette.subtext) ? palette.subtext : Colors.mix(ink, background, 0.28)
    var accent = Colors.valid(palette.accent) ? palette.accent : Commons.Color.accent
    return {
      fromApp: true,
      background: background,
      surface: surface,
      raised: raised,
      text: ink,
      muted: secondary,
      faint: quiet,
      accent: accent,
      isDark: Colors.luminance(background) < 0.5
    }
  }

  function fallback() {
    var background = Commons.Color.popups.background
    var ink = Commons.Color.popups.text
    var accent = Commons.Color.accent
    return {
      fromApp: false,
      background: background,
      surface: Colors.mix(background, ink, 0.06),
      raised: Colors.mix(background, ink, 0.13),
      text: ink,
      muted: Colors.mix(ink, background, 0.3),
      faint: Colors.mix(ink, background, 0.48),
      accent: accent,
      isDark: Colors.luminance(background) < 0.5
    }
  }

  // Recomputed whenever the export changes: this is what makes a theme switch
  // in Omatunes repaint the companion without a restart.
  readonly property var tokens: root.fromApp ? root.tokensFrom(root.published.palette) : root.fallback()
}
