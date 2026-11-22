import QtQuick
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
  // Compact footprint: the pill lives in a row of ~26px icon widgets, so it
  // has to read as one compact control, not a banner. At 168px it still has
  // room for the disc, a short elided label and the play control, with the
  // progress hairline running the inner width.
  readonly property real pillWidth: Style.space(168)
  readonly property real padX: Style.space(7)
  readonly property real artSize: Style.space(18)
  readonly property real controlSize: Style.space(16)
  readonly property real gap: Style.space(5)
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

  readonly property string glyphHeart: "\uF004"

  property bool popupOpen: false

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
    anchors.fill: parent
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

    onClicked: function (mouse) {
      if (mouse.button === Qt.MiddleButton) root.service.toggleLike()
      else root.popupOpen = !root.popupOpen
    }

    onEntered: if (root.bar) root.bar.showTooltip(root, root.label)
    onExited: if (root.bar) root.bar.hideTooltip(root)
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

      Rectangle {
        id: disc
        anchors.fill: parent
        // A half-circle, not a square: the album art reads as a disc in the bar
        // instead of a second little card next to the label.
        radius: width / 2
        color: root.bar && root.bar.hoverBackground !== undefined
          ? root.bar.hoverBackground : Commons.Color.popups.background
        clip: true

        Image {
          anchors.fill: parent
          asynchronous: true
          cache: true
          smooth: true
          fillMode: Image.PreserveAspectCrop
          source: root.online && root.service.artUrl !== "" ? root.service.artUrl : ""
          sourceSize.width: 40
          sourceSize.height: 40
          visible: status === Image.Ready
        }

        Text {
          anchors.centerIn: parent
          visible: !(root.online && root.service.artUrl)
          text: "\uF001"
          color: root.barForeground
          opacity: root.online ? 1 : 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
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

      // The album art is the Omatunes window: no second button, no branding.
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.service.showApp()
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
        color: controlArea.containsMouse ? root.withAlpha(root.barForeground, 0.12) : "transparent"
        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
      }

      Text {
        anchors.centerIn: parent
        text: root.statusGlyph
        color: root.barForeground
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.body * 0.95)
      }

      MouseArea {
        id: controlArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // One control, two meanings: transport when the app is up, a hidden
        // start when it is not.
        onClicked: root.service.toggleOrLaunch()
      }
    }
  }

  // A hairline of elapsed time along the bottom of the pill. Two pixels is
  // enough to read the song moving without turning the bar into a dashboard.
  Rectangle {
    id: progressLine
    x: root.padX
    y: root.height - height - Math.max(1, Math.round(Style.space(2)))
    height: Math.max(1, Math.round(Style.space(2)))
    width: Math.max(0, (root.pillWidth - root.padX * 2) * root.progress)
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
