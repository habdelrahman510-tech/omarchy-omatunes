pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import "Colors.js" as Colors

// The companion's persistent brain.
//
// A QML singleton belongs to the shell's QQmlEngine, which outlives the bar
// widget and every popup window built from it. `Service.qml` touches this
// object at shell start-up (the plugin declares the `service` kind), so MPRIS
// subscriptions, the queue snapshot and the artwork identity are live from
// login — opening the popup later only *renders* what is already here. Closing
// it cannot disconnect anything, because nothing it needs lives in the popup.
//
// Two contracts feed it, both read-only and both owned by Omatunes:
//
//   * MPRIS (`org.mpris.MediaPlayer2.omatunes`) — metadata, status, transport,
//     position/seek, shuffle and loop.
//   * `~/.cache/omatunes_companion.json` (schema 1) — the things MPRIS cannot
//     carry: the actual upcoming queue order, the real repeat mode, the
//     equalizer's real state and the playing context.
//
// Nothing here polls the player. State arrives as D-Bus signals; the only timer
// is the visible-only position estimate the popup asks for while it is open.
QtObject {
  id: root

  readonly property string busName: "org.mpris.MediaPlayer2.omatunes"
  readonly property string stateFilePath: (Quickshell.env("HOME") || "") + "/.cache/omatunes_current_state.json"
  readonly property string companionPath: (Quickshell.env("HOME") || "") + "/.cache/omatunes_companion.json"

  // ----------------------------------------------------------------- player

  readonly property var players: Mpris.players ? Mpris.players.values : []

  // Strict, never "the first active player": a browser playing a video must not
  // become the widget's subject.
  readonly property var player: {
    var list = root.players || []
    for (var i = 0; i < list.length; i++) {
      var exact = list[i]
      if (exact && String(exact.dbusName || "") === root.busName) return exact
    }
    // A second instance is the only legitimate variant of the same app.
    for (var j = 0; j < list.length; j++) {
      var instance = list[j]
      if (instance && String(instance.dbusName || "").indexOf(root.busName + ".") === 0) return instance
    }
    // Older builds may register under the desktop entry instead of the id.
    for (var k = 0; k < list.length; k++) {
      var named = list[k]
      if (!named) continue
      if (String(named.identity || "") === "Omatunes" || String(named.desktopEntry || "") === "omatunes") return named
    }
    return null
  }

  readonly property bool available: root.player !== null
  readonly property bool hasTrack: root.available && !!(root.title || root.artist)
  readonly property bool isPlaying: root.available && !!root.player.isPlaying
  readonly property bool isPaused: root.available && root.player.playbackState === MprisPlaybackState.Paused

  readonly property string title: root.available ? (root.player.trackTitle || "") : ""
  readonly property string artist: root.available ? (root.player.trackArtist || "") : ""
  readonly property string album: root.available ? (root.player.trackAlbum || "") : ""
  readonly property string artUrl: root.available ? root.cleanArtUrl(root.player.trackArtUrl) : ""

  readonly property real length: root.available ? Math.max(0, Number(root.player.length) || 0) : 0
  readonly property real rate: root.available ? Math.max(0.1, Number(root.player.rate) || 1) : 1
  readonly property int uniqueId: root.available ? Number(root.player.uniqueId) : -1
  readonly property bool canSeek: root.available && !!root.player.canSeek && root.player.positionSupported
  readonly property bool hasTimeline: root.available && root.length > 0
  readonly property bool canNext: root.available && !!root.player.canGoNext
  readonly property bool canPrevious: root.available && !!root.player.canGoPrevious
  readonly property bool canToggle: root.available && !!root.player.canTogglePlaying
  readonly property bool canStop: root.available && !!root.player.canControl
  readonly property bool shuffle: root.available && !!root.player.shuffle
  readonly property bool shuffleSupported: root.available && !!root.player.shuffleSupported

  // MPRIS loop state, used only as a fallback when the companion snapshot is
  // not being published (older Omatunes builds).
  readonly property string mprisRepeat: !root.available ? "off"
    : root.player.loopState === MprisLoopState.Track ? "track"
    : root.player.loopState === MprisLoopState.Playlist ? "queue"
    : "off"

  // Only file-backed artwork is ever fed to an Image: a remote URL from
  // metadata must not turn into a network request, and the URL's query is not
  // part of the path — so the check runs against the path alone. The query
  // itself is kept: Omatunes appends the track id there so that a new track's
  // art, written to the same cache file, is a new key in Qt's image cache
  // instead of a stale picture.
  function cleanArtUrl(value) {
    var url = String(value || "").trim()
    if (!url) return ""
    var query = url.indexOf("?")
    var path = query >= 0 ? url.substring(0, query) : url
    if (path.indexOf("file://") === 0 || path.charAt(0) === "/") return url
    return ""
  }

  // ------------------------------------------------- companion snapshot (app)
  //
  // Only Omatunes may decide these values. When the file is absent or not a
  // valid schema-1 payload the properties say "unknown" rather than guessing,
  // and the popup hides the controls instead of faking them.

  property var companion: null

  readonly property bool hasCompanion: root.companion !== null
  readonly property string repeatMode: root.hasCompanion ? String(root.companion.repeat || "off") : root.mprisRepeat
  readonly property bool repeatKnown: root.hasCompanion
  readonly property string contextName: root.hasCompanion && root.companion.context ? String(root.companion.context.name || "") : ""
  readonly property string contextKind: root.hasCompanion && root.companion.context ? String(root.companion.context.kind || "") : ""
  readonly property int queueLength: root.hasCompanion && root.companion.context ? Number(root.companion.context.queue_length) || 0 : 0
  readonly property var upcoming: root.hasCompanion && Array.isArray(root.companion.upcoming) ? root.companion.upcoming : []
  readonly property bool eqKnown: root.hasCompanion && !!root.companion.eq
  readonly property bool eqEnabled: root.eqKnown && root.companion.eq.enabled === true
  readonly property string eqPreset: root.eqKnown ? String(root.companion.eq.preset || "") : ""
  readonly property var eqPresets: root.eqKnown && Array.isArray(root.companion.eq.presets) ? root.companion.eq.presets : []

  property FileView companionFile: FileView {
    path: root.companionPath
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.readCompanion()
    onLoadFailed: root.companion = null
    onFileChanged: {
      root.companionFile.reload()
      root.readCompanion()
    }
  }

  function readCompanion() {
    var raw = ""
    try {
      raw = root.companionFile.text() || ""
    } catch (error) {
      return
    }
    if (!raw) {
      root.companion = null
      return
    }
    var data = null
    try {
      data = JSON.parse(raw)
    } catch (error) {
      // A half-written snapshot is an absent snapshot: keep the last good one
      // so a race never blanks the queue mid-update.
      return
    }
    if (!data || typeof data !== "object") return
    if (Number(data.schema) !== 1 || String(data.product || "") !== "omatunes") return
    root.companion = data
  }

  // Re-read on demand. The popup calls this when it opens: it is the
  // reconciliation step that makes a missed file-watch event harmless.
  function refreshCompanion() {
    root.companionFile.reload()
    root.readCompanion()
  }

  // ------------------------------------------------------------------ liked
  //
  // A build that publishes xesam:userRating is the authority; the installed
  // release does not, so the app's own state cache is the supported read-only
  // fallback, watched rather than guessed at.

  property bool likedFromState: false

  readonly property var rating: root.available && root.player.metadata ? root.player.metadata["xesam:userRating"] : undefined
  readonly property bool ratingPublished: root.rating !== undefined && root.rating !== null
  readonly property bool liked: root.ratingPublished ? Number(root.rating) >= 0.5 : root.likedFromState

  property FileView stateFile: FileView {
    path: root.stateFilePath
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.readStateFile()
    onFileChanged: {
      root.stateFile.reload()
      root.readStateFile()
    }
  }

  function readStateFile() {
    var raw = ""
    try {
      raw = root.stateFile.text() || ""
    } catch (error) {
      return
    }
    if (!raw) return
    try {
      var data = JSON.parse(raw)
      if (!data || typeof data !== "object") return
      if (data.liked !== undefined) root.likedFromState = data.liked === true
    } catch (error) {
      // A half-written cache is an empty answer, never a broken widget.
    }
  }

  function refreshState() {
    root.stateFile.reload()
    root.readStateFile()
  }

  // --------------------------------------------------------------- position
  //
  // MPRIS `Position` is not a pushed clock in the Qt sense. Quickshell's
  // MprisPlayer.position getter, however, is live: it advances the last
  // published base by wall time and the playback rate on every read, and it
  // freezes correctly on pause. Reading that getter on a tick is the only
  // source of truth here — no second estimate, no re-anchoring from stale
  // `positionChanged` notifications (Quickshell deliberately emits those only
  // for nonlinear jumps, so an anchor taken from one can be hundreds of ms
  // behind the getter).

  property real position: 0
  // Omatunes publishes the *new* track's metadata before its zero position.
  // For a few hundred milliseconds the MPRIS clock therefore still reads the
  // old track's position; hold at zero until the player's reset arrives.
  property bool awaitingTrackReset: false
  property double trackResetDeadline: 0

  function syncPosition() {
    if (!root.available || !root.hasTimeline) {
      root.position = 0
      return
    }
    var reported = Math.max(0, Number(root.player.position) || 0)
    if (root.awaitingTrackReset) {
      if (reported > 1.5 && Date.now() < root.trackResetDeadline) {
        root.position = 0
        return
      }
      root.awaitingTrackReset = false
    }
    root.position = Math.min(reported, root.length)
  }

  // ------------------------------------------------------------------ verbs

  // Resolved against this file's directory (`lib/`), not the plugin root.
  readonly property string ctlPath: root.pluginPath("../bin/omatunes-ctl")

  function pluginPath(relative) {
    var url = String(Qt.resolvedUrl(relative))
    var path = url.replace(/^file:\/\//, "")
    try {
      return decodeURIComponent(path)
    } catch (error) {
      return path
    }
  }

  property var pendingVerbs: []

  property Process control: Process {
    onExited: function (code) {
      if (code !== 0) console.warn("omatunes: control helper exited with", code)
      if (root.pendingVerbs.length > 0) {
        var next = root.pendingVerbs.shift()
        root.pendingVerbs = root.pendingVerbs.slice()
        root.send(next)
        return
      }
      root.refreshState()
    }
  }

  function send(args) {
    if (!root.available) return
    if (root.control.running) {
      // Rapid clicks must not be swallowed by the send in flight.
      if (root.pendingVerbs.length < 4) root.pendingVerbs = root.pendingVerbs.concat([args])
      return
    }
    root.control.command = [root.ctlPath].concat(args)
    root.control.running = true
  }

  function togglePlaying() {
    if (root.canToggle) root.player.togglePlaying()
  }

  function next() {
    if (root.canNext) root.player.next()
  }

  function previous() {
    if (root.canPrevious) root.player.previous()
  }

  function stop() {
    if (root.canStop) root.player.stop()
  }

  function toggleLike() {
    if (root.available) root.send(["like"])
  }

  // Shuffle is the app's own, and its only verb is a toggle; the resulting
  // state comes back on MPRIS `Shuffle`, so the button never guesses.
  function toggleShuffle() {
    if (!root.shuffleSupported) return
    root.send(["shuffle"])
  }

  // Repeat is app-owned: ask for the absolute mode, never a toggle, so a stale
  // read cannot leave the UI one step behind the application.
  function setRepeat(mode) {
    if (!root.available) return
    if (mode !== "off" && mode !== "queue" && mode !== "track") return
    root.send(["repeat", mode])
  }

  function setEqualizer(enabled) {
    if (!root.available || !root.eqKnown) return
    root.send(["eq", enabled ? "on" : "off"])
  }

  function setEqualizerPreset(name) {
    if (!root.available || !root.eqKnown) return
    // Only a name the application itself advertised is ever sent.
    if (root.eqPresets.indexOf(String(name)) < 0) return
    root.send(["eq-preset", String(name)])
  }

  // Seeking through the position property is SetPosition under the hood; the
  // app ignores the track id, so a stale drag can only be discarded by the
  // caller comparing uniqueId. Seek-by-offset is the fallback.
  function seekTo(seconds, trackId) {
    if (!root.canSeek || !root.player) return
    if (trackId !== undefined && Number(trackId) !== root.uniqueId) return
    var target = Math.max(0, Math.min(Number(seconds) || 0, root.length))
    var current = Math.max(0, Number(root.position) || 0)
    // Draw the requested position immediately; MPRIS may take a moment to
    // acknowledge the seek, and the next tick re-reads the authoritative clock.
    root.position = target
    root.awaitingTrackReset = false
    if (root.player.positionSupported) root.player.position = target
    else root.player.seek(target - current)
  }

  // The playback clock runs while something is playing — the bar's elapsed
  // hairline needs it too, not just the open popup — and stops on pause, so a
  // silent desktop does no work. 200 ms keeps a bar-sized line moving smoothly
  // without turning the shell into a 60 Hz animation bench.
  property Timer positionTicker: Timer {
    interval: 200
    repeat: true
    // Declarative, not switched by hand: every path that starts or stops
    // playback converges here, and a manual restart() would break the binding.
    running: root.isPlaying
    onTriggered: root.syncPosition()
  }

  function beginTracking() {
    root.syncPosition()
  }

  function endTracking() {
    // Leave the last authoritative reading on screen; the MPRIS getter itself
    // freezes on pause, so nothing needs to be rewound here.
    root.syncPosition()
  }

  // -------------------------------------------------------------- reconnection

  property Connections playerWatch: Connections {
    target: root.player
    // Quickshell emits this when MPRIS makes a nonlinear jump (a seek from
    // another client, or a track reset). It is not a periodic clock, but it is
    // the fastest way to repaint a paused bar after such a jump.
    function onPositionChanged() {
      root.syncPosition()
    }
    function onTrackChanged() {
      root.position = 0
      root.awaitingTrackReset = true
      root.trackResetDeadline = Date.now() + 1500
      root.refreshState()
    }
    function onPlaybackStateChanged() {
      root.syncPosition()
    }
    function onMetadataChanged() {
      root.refreshState()
    }
  }

  onAvailableChanged: {
    root.position = 0
    root.awaitingTrackReset = false
    if (root.available) {
      root.refreshState()
      root.refreshCompanion()
      if (root.pendingPlay) root.autoplay.restart()
    }
  }

  Component.onCompleted: {
    root.readStateFile()
    root.readCompanion()
  }

  property Process focus: Process {}

  // ------------------------------------------------------- launching the app
  //
  // The pill exists whether or not Omatunes is running, so it has two doors:
  //
  //   * play, with no instance — start one hidden (`--background`) and begin
  //     playback. The desktop must not be interrupted by a window just because
  //     someone pressed play in the bar.
  //   * the album art — ask the *running* instance for its window over the
  //     control socket (`show`). Hyprland's focus-by-class cannot help: a
  //     hidden instance owns a window that was never mapped, so there is
  //     nothing for `focuswindow` to focus.

  property bool pendingPlay: false

  property Process launcher: Process {
    onExited: function (code) {
      if (code !== 0) root.pendingPlay = false
    }
  }

  // A hidden start has no track for a moment, so the first play waits for one
  // instead of firing into an empty player.
  property Timer autoplay: Timer {
    interval: 900
    repeat: false
    onTriggered: {
      if (!root.pendingPlay) return
      if (!root.available) return
      if (root.hasTrack) {
        if (root.isPaused) root.togglePlaying()
        root.pendingPlay = false
      } else {
        root.autoplay.restart()
      }
    }
  }

  function launchBackground() {
    if (root.available || root.launcher.running) return
    root.pendingPlay = true
    root.launcher.command = ["setsid", "omatunes", "--background"]
    root.launcher.running = true
  }

  // omarchy-launch-or-focus matches the window class and launches the app only
  // when no window exists, so a second instance is never started.
  function launchForeground() {
    if (root.focus.running) return
    root.focus.command = ["omarchy-launch-or-focus", "omatunes"]
    root.focus.running = true
  }

  function showApp() {
    if (root.available) root.send(["show"])
    else root.launchForeground()
  }

  // What the pill's one control means: play/pause when there is a player, a
  // hidden start when there is not.
  function toggleOrLaunch() {
    if (root.available) root.togglePlaying()
    else root.launchBackground()
  }
}
