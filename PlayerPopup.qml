import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "lib" as Lib
import "lib/Colors.js" as Colors

// The expanded companion — a compact now-playing card.
//
// It keeps the reference's own metrics (artwork tile, type sizes, control
// diameters, timeline length) and its left-to-right composition, but drops the
// mockup's right-hand partition entirely: there is no queue column, no context
// heading and no divider, only what is playing and the controls for it. The
// canvas is cut down to that content and the whole thing is laid out in a fixed
// design space and scaled as one piece, so every margin and diameter keeps its
// proportion at any popup size. The only departure from the mockup's surface is
// the background: one blurred, cropped copy of the current artwork with a single
// uniform veil, replacing its stacked glass panels.
//
// All state comes in through `state` (the persistent OmatunesService), all
// colours through `theme` (ThemeAdapter.tokens). Nothing here subscribes to
// D-Bus, starts timers that outlive visibility, or talks to Omatunes directly
// except for the click handlers that forward to the service.
KeyboardPanel {
  id: popup

  required property var state
  required property var theme

  property bool motionEnabled: true
  property bool menuOpen: false
  property int seekTrackId: -1

  readonly property var strings: Commons.Translations {
    directory: Qt.resolvedUrl("i18n")
  }

  // Design space: the reference's left-hand composition, cropped to a 30px
  // margin on all four sides. Artwork 30,30 308²; identity and timeline start
  // at x372 and end at 868; the transport row bottoms out at 341.
  readonly property int designWidth: 898
  readonly property int designHeight: 371
  readonly property real unit: popup.contentWidth / popup.designWidth

  readonly property color ink: popup.theme.text
  readonly property color inkMuted: popup.theme.muted
  readonly property color inkFaint: popup.theme.faint
  readonly property color accent: popup.theme.accent
  readonly property color surface: popup.theme.background
  readonly property color interior: popup.theme.background
  readonly property real radius: Style.cornerRadius
  readonly property string fontFamily: popup.bar && popup.bar.fontFamily ? popup.bar.fontFamily : Style.font.family

  readonly property bool online: !!popup.state.available
  readonly property bool hasArt: popup.state.artUrl !== ""
  readonly property bool hasTimeline: popup.state.hasTimeline
  readonly property real progress: popup.state.length > 0
    ? Math.max(0, Math.min(1, popup.state.position / popup.state.length))
    : 0
  readonly property real displayPosition: popup.state.length > 0
    ? Math.max(0, Math.min(popup.state.position, popup.state.length))
    : 0

  // Compact by design: the card is a now-playing tile, not a panel. 760px is
  // deliberately far below the old full-width card, so the popup reads as a
  // companion rather than a second window.
  contentWidth: {
    var byWidth = Math.min(760, popup.availableCardWidth)
    var byHeight = popup.availableCardHeight > 0
      ? popup.availableCardHeight * popup.designWidth / popup.designHeight
      : byWidth
    return popup.fittedContentWidth(Math.min(byWidth, byHeight))
  }
  // The panel already animates its own drawnHeight toward contentHeight with
  // a 200ms ease-out. A second, overshooting height tween here fought it and
  // made the menu stutter. The panel owns the height; the menu gets one
  // matching fade/slide instead.
  contentHeight: {
    var base = Math.round(popup.contentWidth * popup.designHeight / popup.designWidth)
    var desired = popup.menuOpen
      ? Math.round(popup.menuTop + (menu ? menu.height : 0) + popup.unit * 10)
      : base
    return popup.availableCardHeight > 0
      ? Math.min(desired, Math.round(popup.availableCardHeight))
      : desired
  }

  // The card's target height jumps, while the panel animates its own drawn
  // height toward it. Mirror that 200ms curve on the backdrop alone: the
  // blurred artwork then stretches with the card as the menu opens and closes
  // instead of snapping to the final crop on the first frame.
  property real backdropHeight: popup.contentHeight
  Behavior on backdropHeight {
    enabled: popup.motionEnabled
    NumberAnimation {
      duration: Style.duration(200)
      easing.type: Easing.Bezier
      easing.bezierCurve: Style.easeOut
    }
  }

  // One value drives the menu's fade and slide, on the panel's own timeline.
  property real menuProgress: popup.menuOpen ? 1 : 0
  Behavior on menuProgress {
    enabled: popup.motionEnabled
    NumberAnimation {
      duration: Style.duration(200)
      easing.type: Easing.Bezier
      easing.bezierCurve: Style.easeOut
    }
  }

  // Where the menu starts, in card pixels: just under the transport row.
  readonly property real menuTop: popup.unit * (popup.designHeight + 4)

  padding: 0
  borderSpec: Border.flat(popup.withAlpha(popup.ink, 0.12), 1)

  // Smooth in/out, matching the desktop's own switching transition: the
  // `smooth` bezier from ~/.config/hypr/looknfeel.lua — cubic-bezier(0.22, 1,
  // 0.1, 1.1) — at the speed it is used there (5.5), which Hyprland turns into
  // the same curve. The card's own envelope is the panel's (180 ms in, 120 ms
  // out, 3% scale); this adds the part the card controls — the content drops
  // out of the bar by 24 design pixels and fades, long enough to be seen.
  readonly property var motionBezier: [0.22, 1.0, 0.1, 1.1, 1.0, 1.0]
  readonly property int motionDuration: 240

  property real reveal: popup.open ? 1 : 0
  Behavior on reveal {
    enabled: popup.motionEnabled
    NumberAnimation {
      duration: popup.motionDuration
      easing.type: Easing.Bezier
      easing.bezierCurve: popup.motionBezier
    }
  }

  function withAlpha(value, alpha) {
    return Colors.withAlpha(value, alpha)
  }

  function formatTime(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var secs = total % 60
    var pad = function (value) { return value < 10 ? "0" + value : "" + value }
    return hours > 0 ? hours + ":" + pad(minutes) + ":" + pad(secs) : minutes + ":" + pad(secs)
  }

  onOpenChanged: {
    if (popup.open) {
      popup.state.refreshCompanion()
      popup.state.beginTracking()
    } else {
      popup.menuOpen = false
      popup.state.endTracking()
    }
  }

  // PopupCard's default property is a list of visual children, so the shortcut
  // lives inside one rather than at the card's top level.
  Item {
    width: 0
    height: 0

    Shortcut {
      sequence: "Escape"
      enabled: popup.open
      onActivated: {
        if (popup.menuOpen) popup.menuOpen = false
        else popup.close()
      }
    }
  }

  // -------------------------------------------------------------- backdrop
  //
  // One image, cropped to cover, blurred once and held until the next artwork
  // is decoded. The theme's plain surface sits underneath for the no-artwork
  // case; nothing is fetched or invented.

  Rectangle {
    id: backdropClip
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    // Not anchors.fill: the holder's height jumps to the menu's target, but
    // the art backdrop has to grow with the card's own 200ms height tween.
    height: popup.backdropHeight
    radius: popup.radius
    color: popup.surface
    clip: true

    Lib.ArtworkBackground {
      anchors.fill: parent
      url: popup.hasArt ? popup.state.artUrl : ""
      tint: popup.surface
      animate: popup.motionEnabled
    }

    Rectangle {
      anchors.fill: parent
      color: popup.withAlpha(popup.surface, 0.6)
    }
  }

  // ----------------------------------------------------------------- stage

  Item {
    id: contentReveal
    anchors.fill: parent
    opacity: Math.max(0, Math.min(1, popup.reveal))
    // The slide half of slidefade: 12 design pixels, in the same units as the
    // rest of the card, so it scales with it.
    transform: Translate {
      y: (1 - popup.reveal) * Math.round(popup.unit * 24)
    }

    Item {
      id: stage
      width: popup.designWidth
      height: popup.designHeight
      transformOrigin: Item.TopLeft
      scale: popup.unit

    // ----------------------------------------------------------- artwork
    // A disc, not a tile. The old 308px rounded square swallowed most of the
    // card and its radius never actually clipped the image; 224px centered in
    // the left column reads as album art without bloating the popup.
    Item {
      id: artwork
      x: 57
      y: 74
      width: 224
      height: 224

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: popup.withAlpha(popup.ink, 0.06)
        border.width: 2
        border.color: popup.withAlpha(popup.ink, popup.online ? 0.85 : 0.35)
      }

      Image {
        id: cover
        anchors.fill: parent
        anchors.margins: 2
        visible: false
        asynchronous: true
        cache: true
        smooth: true
        fillMode: Image.PreserveAspectCrop
        source: popup.hasArt ? popup.state.artUrl : ""
        sourceSize.width: 448
        sourceSize.height: 448
      }

      // The Rectangle's radius only rounds its own paint; masking the decoded
      // image through an alpha item is what actually makes the art a circle.
      Item {
        id: discMask
        anchors.fill: cover
        visible: false
        layer.enabled: true

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "black"
        }
      }

      MultiEffect {
        anchors.fill: cover
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
        color: popup.inkFaint
        font.family: popup.fontFamily
        font.pixelSize: 44
      }

      // Hover feedback only: the artwork is the Omatunes launch surface.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: popup.withAlpha(popup.ink, 0.08)
        opacity: artworkHover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }
      }

      HoverHandler {
        id: artworkHover
        cursorShape: Qt.PointingHandCursor
      }

      TapHandler {
        onTapped: popup.state.showApp()
      }
    }

    // ------------------------------------------------------------ identity
    Text {
      id: title
      x: 372
      y: 128
      width: 496
      textFormat: Text.PlainText
      text: popup.online ? (popup.state.title || popup.strings.t("popup.untitled"))
        : popup.strings.t("popup.offlineTitle")
      color: popup.ink
      font.family: popup.fontFamily
      font.pixelSize: 34
      font.weight: Font.Bold
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    Text {
      id: artist
      x: 372
      y: 176
      width: 496
      textFormat: Text.PlainText
      text: popup.online ? popup.state.artist : popup.strings.t("popup.offlineHint")
      color: popup.inkMuted
      font.family: popup.fontFamily
      font.pixelSize: 22
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    // ------------------------------------------------------------ timeline
    Item {
      id: timeline
      x: 372
      y: 255
      width: 496
      height: 14

      readonly property real fraction: popup.progress
      readonly property bool interactive: popup.online && popup.state.canSeek && popup.hasTimeline
      property bool dragging: false
      property real previewFraction: popup.progress

      Rectangle {
        y: 6
        width: parent.width
        height: 2
        color: popup.withAlpha(popup.ink, 0.32)
      }

      Rectangle {
        y: 6
        width: Math.round(parent.width * timeline.previewFraction)
        height: 2
        color: popup.withAlpha(popup.ink, timeline.interactive ? 1 : 0.5)
      }

      Rectangle {
        x: Math.round(parent.width * timeline.previewFraction) - 7.5
        y: 0
        width: 15
        height: 15
        radius: 7.5
        color: popup.ink
        opacity: timeline.interactive ? 1 : 0.5
      }

      HoverHandler {
        id: timelineHover
        enabled: timeline.interactive
        cursorShape: Qt.PointingHandCursor
      }

      DragHandler {
        id: scrub
        target: null
        enabled: timeline.interactive
        onActiveChanged: {
          if (scrub.active) {
            timeline.dragging = true
            timeline.previewFraction = timeline.fraction
            popup.seekTrackId = popup.state.uniqueId
          } else if (timeline.dragging) {
            timeline.dragging = false
            popup.state.seekTo(timeline.previewFraction * popup.state.length, popup.seekTrackId)
            timeline.previewFraction = popup.progress
          }
        }
        onCentroidChanged: {
          if (!scrub.active || !timeline.interactive) return
          var point = timeline.mapFromItem(null, scrub.centroid.scenePosition.x, scrub.centroid.scenePosition.y)
          timeline.previewFraction = Math.max(0, Math.min(1, point.x / timeline.width))
        }
      }

      TapHandler {
        enabled: timeline.interactive
        onTapped: function (point) {
          var fraction = Math.max(0, Math.min(1, point.position.x / timeline.width))
          popup.state.seekTo(fraction * popup.state.length, popup.state.uniqueId)
        }
      }

      // Elapsed / total appear only while the pointer is on the timeline (or
      // mid-drag): the reference composition has no standing time labels.
      Item {
        x: 0
        y: -30
        width: timeline.width
        height: 18
        opacity: (timelineHover.hovered || timeline.dragging) && timeline.interactive ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }

        Text {
          anchors.left: parent.left
          textFormat: Text.PlainText
          text: popup.formatTime(timeline.previewFraction * popup.state.length)
          color: popup.ink
          font.family: popup.fontFamily
          font.pixelSize: 18
        }

        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: popup.formatTime(popup.state.length)
          color: popup.inkMuted
          font.family: popup.fontFamily
          font.pixelSize: 18
        }
      }
    }

    // ------------------------------------------------------------ transport
    //
    // Three-bars utility control first (Repeat + Equalizer), then the transport
    // in the reference's exact positions.

    Item {
      id: menuButton
      x: 388
      y: 304
      width: 24
      height: 14

      readonly property bool hovered: menuHover.hovered

      Column {
        spacing: 4
        Repeater {
          model: 3
          delegate: Rectangle {
            width: 24
            height: 2
            color: popup.withAlpha(popup.ink, menuButton.hovered || popup.menuOpen ? 1 : 0.86)
            Behavior on color { ColorAnimation { duration: Style.duration(120) } }
          }
        }
      }

      HoverHandler {
        id: menuHover
        cursorShape: Qt.PointingHandCursor
      }

      TapHandler {
        // While the menu is open the catcher above this card owns the click and
        // closes it. This handler must be disarmed then, or the same release
        // reaches it after the catcher has hidden and the menu re-opens in the
        // same gesture — which is why it would never retract.
        enabled: !popup.menuOpen
        onTapped: popup.menuOpen = true
      }
    }

    Item {
      id: previousButton
      x: 502
      y: 295
      width: 37
      height: 37

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: popup.withAlpha(popup.ink, popup.state.canPrevious ? 0.94 : 0.35)
      }

      Text {
        anchors.centerIn: parent
        text: "\uF048"
        color: popup.withAlpha(popup.interior, popup.state.canPrevious ? 1 : 0.6)
        font.family: popup.fontFamily
        font.pixelSize: 17
        leftPadding: 1
      }

      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler {
        onTapped: popup.state.previous()
      }
    }

    Item {
      id: playButton
      x: 592
      y: 287
      width: 54
      height: 54

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: popup.withAlpha(popup.ink, popup.state.canToggle ? 1 : 0.4)
      }

      Text {
        anchors.centerIn: parent
        text: popup.state.isPlaying ? "\uF04C" : "\uF04B"
        color: popup.withAlpha(popup.interior, popup.state.canToggle ? 1 : 0.6)
        font.family: popup.fontFamily
        font.pixelSize: 23
        leftPadding: popup.state.isPlaying ? 0 : 3
      }

      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler {
        // Same contract as the pill's control: transport when the player is
        // live, a hidden start when it is not. togglePlaying() alone is a
        // no-op while Omatunes is offline, which left this button dead.
        onTapped: popup.state.toggleOrLaunch()
      }
    }

    Item {
      id: nextButton
      x: 699
      y: 295
      width: 38
      height: 38

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: popup.withAlpha(popup.ink, popup.state.canNext ? 0.94 : 0.35)
      }

      Text {
        anchors.centerIn: parent
        text: "\uF051"
        color: popup.withAlpha(popup.interior, popup.state.canNext ? 1 : 0.6)
        font.family: popup.fontFamily
        font.pixelSize: 17
        leftPadding: 1
      }

      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler {
        onTapped: popup.state.next()
      }
    }

    // Shuffle, in the place the reference gave its stop control. Omatunes owns
    // shuffle — the plugin only asks for the toggle and reports what comes
    // back — and it is a switch, so it reads like one: solid while the app is
    // shuffling, a ring while it is playing in order.
    Item {
      id: shuffleButton
      x: 834
      y: 297
      width: 34
      height: 34

      readonly property bool on: popup.state.shuffle
      readonly property bool supported: popup.state.shuffleSupported
      readonly property real inkAlpha: supported ? (on ? 1 : 0.8) : 0.3

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: shuffleButton.on
          ? popup.withAlpha(popup.ink, shuffleButton.supported ? 1 : 0.3)
          : "transparent"
        border.width: shuffleButton.on ? 0 : 2
        border.color: popup.withAlpha(popup.ink, shuffleButton.inkAlpha)
        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
      }

      Text {
        anchors.centerIn: parent
        text: "\uF074"
        color: shuffleButton.on
          ? popup.withAlpha(popup.interior, 1)
          : popup.withAlpha(popup.ink, shuffleButton.inkAlpha)
        font.family: popup.fontFamily
        font.pixelSize: 15
      }

      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler {
        onTapped: popup.state.toggleShuffle()
      }
    }

    }
  }

  // ------------------------------------------------------------- utilities
  //
  // Behind the three-bars control, and only there. Repeat is Omatunes' own
  // three-state mode; the equalizer is the real DSP inside the app. When the
  // application has not published those values the panel says so instead of
  // offering switches that would do nothing.

  Item {
    id: outsideCatcher
    anchors.fill: parent
    visible: popup.menuProgress > 0.001
    z: 10
    TapHandler {
      onTapped: popup.menuOpen = false
    }
  }

  BorderSurface {
    id: menu
    visible: popup.menuProgress > 0.001
    opacity: popup.menuProgress
    z: 11

    // Sits under the transport row, in the room the card grows for it while it
    // is open. Slides the last few pixels into place as it fades, so the card
    // growing underneath and the menu arriving read as one motion.
    width: Math.round(Math.min(popup.contentWidth - 16, popup.unit * 356))
    height: menuColumn.implicitHeight + menu.padding * 2
    x: Math.round(Math.max(8, Math.min(popup.contentWidth - width - 8, popup.unit * 388)))
    y: Math.round(popup.menuTop - (1 - popup.menuProgress) * popup.unit * 10)
    padding: Math.round(popup.unit * 10)
    radius: Math.max(4, popup.radius)
    color: popup.surface
    borderSpec: Border.flat(popup.withAlpha(popup.ink, 0.18), 1)

    Column {
      id: menuColumn
      // `BorderSurface` exposes `padding` but does not inset its children, so
      // the column places itself inside it: without this the labels sit on the
      // top-left border and the extra height lands entirely below them.
      x: menu.padding
      y: menu.padding
      width: parent.width - menu.padding * 2
      spacing: Math.round(popup.unit * 8)

      Row {
        width: parent.width
        spacing: Math.round(popup.unit * 10)
        // Repeat is settable only when Omatunes publishes its own mode; without
        // that, the MPRIS value is still shown but the control is not offered.
        enabled: popup.state.repeatKnown
        opacity: enabled ? 1 : 0.45

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(popup.unit * 88)
          textFormat: Text.PlainText
          text: popup.strings.t("popup.repeat")
          color: popup.inkMuted
          font.family: popup.fontFamily
          font.pixelSize: Math.round(popup.unit * 16)
        }

        Row {
          spacing: Math.round(popup.unit * 4)

          Repeater {
            model: [
              { value: "off", label: popup.strings.t("popup.repeatOff") },
              { value: "queue", label: popup.strings.t("popup.repeatQueue") },
              { value: "track", label: popup.strings.t("popup.repeatTrack") }
            ]

            delegate: Rectangle {
              id: repeatChoice
              required property var modelData

              readonly property bool selected: popup.state.repeatMode === modelData.value
              readonly property bool hovered: choiceHover.hovered

              width: Math.round(popup.unit * 62)
              height: Math.round(popup.unit * 26)
              radius: Math.max(3, popup.unit * 4)
              color: repeatChoice.selected ? popup.withAlpha(popup.accent, 0.22)
                : repeatChoice.hovered ? popup.withAlpha(popup.ink, 0.10) : "transparent"
              border.width: repeatChoice.selected ? 1 : 0
              border.color: popup.withAlpha(popup.accent, 0.55)
              opacity: popup.online ? 1 : 0.4

              Behavior on color { ColorAnimation { duration: Style.duration(120) } }

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: repeatChoice.modelData.label
                color: repeatChoice.selected ? popup.ink : popup.inkMuted
                font.family: popup.fontFamily
                font.pixelSize: Math.round(popup.unit * 15)
              }

              HoverHandler {
                id: choiceHover
                cursorShape: Qt.PointingHandCursor
              }

              TapHandler {
                onTapped: popup.state.setRepeat(repeatChoice.modelData.value)
              }
            }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Math.round(popup.unit * 10)
        visible: popup.state.eqKnown

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(popup.unit * 88)
          textFormat: Text.PlainText
          text: popup.strings.t("popup.equalizer")
          color: popup.inkMuted
          font.family: popup.fontFamily
          font.pixelSize: Math.round(popup.unit * 16)
        }

        ToggleSwitch {
          anchors.verticalCenter: parent.verticalCenter
          checked: popup.state.eqEnabled
          onToggled: popup.state.setEqualizer(!popup.state.eqEnabled)
        }

        Dropdown {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(popup.unit * 168)
          fontFamily: popup.fontFamily
          foreground: popup.ink
          options: popup.state.eqPresets
          value: popup.state.eqPreset
          enabled: popup.state.eqEnabled
          opacity: enabled ? 1 : 0.5
          onChanged: function (value) { popup.state.setEqualizerPreset(value) }
        }
      }

      Text {
        width: parent.width
        visible: !popup.state.eqKnown
        textFormat: Text.PlainText
        text: popup.strings.t("popup.equalizerUnavailable")
        color: popup.inkFaint
        font.family: popup.fontFamily
        font.pixelSize: Math.round(popup.unit * 15)
        wrapMode: Text.WordWrap
      }
    }
  }
}
