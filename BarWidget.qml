import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "lib"
import "lib/Colors.js" as Colors

// Omatunes companion — the standalone bar pill.
//
// Fixed footprint: the pill occupies exactly the same box whether it is showing
// a track, waiting for one, or reporting that Omatunes is not running. A track
// title longer than the box elides inside it; nothing about the music moves the
// rest of the bar.
//
// It is also always there. With no player the disc goes quiet, the label says
// so, and the single control becomes a play button that starts Omatunes hidden
// (`--background`) and begins playback — no window steals the desktop. The
// album art is the other door: it asks the running instance for its window (or
// launches a visible one when there is nothing to ask).
//
// All state comes from the persistent `OmatunesService` singleton, which lives
// for the whole shell session whether this pill exists or not.
BarWidget {
  id: root
  moduleName: "omatunes"

  readonly property var service: OmatunesService
  readonly property var theme: ThemeAdapter.tokens

  readonly property color barForeground: bar && bar.barForeground !== undefined ? bar.barForeground : Commons.Color.foreground
  readonly property color accent: bar && bar.accent !== undefined ? bar.accent : Commons.Color.accent
  readonly property string fontFamily: bar && bar.fontFamily ? bar.fontFamily : Style.font.family

  // ------------------------------------------------------------ geometry
  //
  // The whole point of the fixed width: every track — a one-word title or a
  // 60-character one — lands in the same box. The label owns whatever is left
  // after the disc, the control and the gaps, and elides there.
  readonly property real pillWidth: Style.space(238)
  readonly property real padX: Style.space(9)
  readonly property real artSize: Style.space(20)
  readonly property real controlSize: Style.space(18)
  readonly property real gap: Style.space(6)
  // The shell's own workspaces pill is inset inside the bar, not flush with
  // it: barSize - 6, centred with an equal margin above and below. Our
  // capsule used to fill the whole bar and stood proud of every neighbour.
  readonly property int pillThickness: Math.max(16, barSize - Style.space(6))
  readonly property real labelWidth: Math.max(0, pillWidth - padX * 2 - artSize - controlSize - gap * 2)

  readonly property bool online: root.service.available
  readonly property string label: {
    if (!root.online) return "Omatunes"
    var artist = root.service.artist
    var title = root.service.title
    if (artist && title) return artist + " — " + title
    return title || artist || "Omatunes"
  }
  readonly property string statusGlyph: root.service.isPlaying ? "\uF04C" : "\uF04B"
  readonly property real progress: root.online && root.service.length > 0
    ? Math.max(0, Math.min(1, root.service.position / root.service.length))
    : 0

  // The MPRIS clock is sampled five times a second. Glide between samples so
  // the hairline creeps forward instead of stepping once per tick.
  property real shownProgress: root.progress
  Behavior on shownProgress {
    id: progressBehavior
    NumberAnimation { duration: 200; easing.type: Easing.Linear }
  }

  // A new track starts at zero; snap there on the identity change instead of
  // sliding the hairline backwards through the old track's position.
  Connections {
    target: root.service
    function onUniqueIdChanged() {
      progressBehavior.enabled = false
      root.shownProgress = 0
      root.shownProgress = Qt.binding(function() { return root.progress })
      progressBehavior.enabled = true
    }
  }

  readonly property string glyphHeart: "\uF004"

  property bool popupOpen: false

  // The shell's panel hotkey path finds bar widgets by these three members.
  // Without open()/opened, `omarchy-shell shell summon omatunes` silently
  // skips the pill, so a shortcut cannot raise the card while the bar is away.
  readonly property bool opened: root.popupOpen

  function open() {
    root.popupOpen = true
  }

  function close() {
    root.popupOpen = false
  }

  visible: true
  implicitWidth: root.pillWidth
  implicitHeight: barSize

  // Its own capsule: the bar's section background does not extend under a
  // third-party widget, so without this the contents float. Rest, hover and
  // playing each get a slightly different tint — the same language the
  // workspaces pill uses.
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: root.pillThickness
    radius: height / 2
    color: root.withAlpha(root.barForeground, bodyArea.containsMouse ? 0.12 : 0.06)
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
  }

  Connections {
    target: root.service
    // A player that quits while its card is open must not leave a dead card.
    function onAvailableChanged() {
      if (!root.service.available) root.popupOpen = false
    }
  }

  // The body is the popup surface; middle-click is still the like.
  MouseArea {
    id: bodyArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor

    property bool controlHovered: false

    // One hit area owns every click. Nested MouseAreas inside the Row sit in
    // the bar's own coordinate system and are not reliably under the pointer;
    // dispatching from here against the real item geometry always lands.
    function hitTest(x, y) {
      var p = content.mapFromItem(bodyArea, x, y)
      var cx = controlFrame.mapToItem(content, 0, 0)
      var ax = artFrame.mapToItem(content, 0, 0)
      if (p.x >= cx.x && p.x <= cx.x + controlFrame.width
        && p.y >= cx.y && p.y <= cx.y + controlFrame.height) return "control"
      if (p.x >= ax.x && p.x <= ax.x + artFrame.width
        && p.y >= ax.y && p.y <= ax.y + artFrame.height) return "art"
      return "body"
    }

    onPositionChanged: function (mouse) {
      controlHovered = hitTest(mouse.x, mouse.y) === "control"
    }

    onClicked: function (mouse) {
      if (mouse.button === Qt.MiddleButton) {
        root.service.toggleLike()
        return
      }
      var hit = hitTest(mouse.x, mouse.y)
      if (hit === "control") root.service.toggleOrLaunch()
      else if (hit === "art") root.service.showApp()
      else root.popupOpen = !root.popupOpen
    }

    onEntered: if (root.bar) root.bar.showTooltip(root, root.label)
    onExited: {
      controlHovered = false
      if (root.bar) root.bar.hideTooltip(root)
    }
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.gap

    // ------------------------------------------------------------- artwork
    Item {
      id: artFrame
      width: root.artSize
      height: root.artSize
      anchors.verticalCenter: parent.verticalCenter

      // The resting disc is a real circle, so even before artwork decodes the
      // pill never shows a square corner.
      Rectangle {
        id: disc
        anchors.fill: parent
        radius: width / 2
        color: root.bar && root.bar.hoverBackground !== undefined
          ? root.bar.hoverBackground : Commons.Color.popups.background
      }

      Image {
        id: cover
        anchors.fill: parent
        visible: false
        asynchronous: true
        cache: true
        smooth: true
        fillMode: Image.PreserveAspectCrop
        source: root.online && root.service.artUrl !== "" ? root.service.artUrl : ""
        sourceSize.width: 40
        sourceSize.height: 40
      }

      // Qt clips a rounded Rectangle to its bounding box, not to the radius —
      // the old `clip: true` left the artwork square. Mask it through the
      // shell's own pattern instead: an invisible circular item as alpha mask.
      Item {
        id: discMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "black"
        }
      }

      MultiEffect {
        anchors.fill: parent
        visible: cover.status === Image.Ready
        source: cover
        maskEnabled: true
        maskSource: discMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      Text {
        anchors.centerIn: parent
        visible: cover.status !== Image.Ready
        text: "\uF001"
        color: root.barForeground
        opacity: root.online ? 1 : 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      // A quiet ring that only lights while something is actually playing.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, Style.space(1))
        border.color: root.accent
        opacity: root.online && root.service.isPlaying ? 0.75 : 0
        Behavior on opacity { NumberAnimation { duration: Style.duration(220) } }
      }

      // Liked: a small heart riding the disc rather than a glyph in the row,
      // so liking a track cannot change the pill's width.
      Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -Math.round(Style.space(2))
        anchors.bottomMargin: -Math.round(Style.space(2))
        visible: root.online && root.service.liked
        text: root.glyphHeart
        color: root.bar && root.bar.urgent !== undefined ? root.bar.urgent : Commons.Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.bodySmall * 0.85)
      }
    }

    // -------------------------------------------------------------- label
    Text {
      id: labelText
      anchors.verticalCenter: parent.verticalCenter
      width: root.labelWidth
      textFormat: Text.PlainText
      text: root.label
      color: root.barForeground
      opacity: root.online ? 1 : 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    // ------------------------------------------------------------- control
    Item {
      id: controlFrame
      width: root.controlSize
      height: root.controlSize
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: bodyArea.controlHovered ? root.withAlpha(root.barForeground, 0.12) : "transparent"
        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
      }

      Text {
        anchors.centerIn: parent
        text: root.statusGlyph
        color: root.barForeground
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.body * 0.95)
      }
    }
  }

  // A hairline of elapsed time along the bottom of the pill. Two pixels is
  // enough to read the song moving without turning the bar into a dashboard.
  Rectangle {
    id: progressLine
    x: root.padX
    // Sit on the bottom edge of the inset capsule, not the bottom of the bar.
    y: (root.height + root.pillThickness) / 2 - height
    height: Math.max(1, Math.round(Style.space(2)))
    width: Math.max(0, (root.pillWidth - root.padX * 2) * root.shownProgress)
    radius: height / 2
    color: root.accent
    opacity: root.online && root.service.length > 0 ? 0.75 : 0
  }

  function withAlpha(value, alpha) {
    return Colors.withAlpha(value, alpha)
  }

  PlayerPopup {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    state: root.service
    theme: root.theme
    motionEnabled: root.bar ? root.bar.animationsEnabled !== false : true
  }
}
