import QtQuick
import QtQuick.Effects

// One blurred, cropped copy of the current artwork.
//
// This is the popup's only background: no gradients, no palette extraction and
// no second surface. The artwork is decoded small, once, and blown up — which
// is both the cheapest and the calmest way to get a soft backdrop — then given
// a single GPU blur pass.
//
// Track changes cross-fade rather than cutting: the incoming artwork loads into
// the idle slot and is only promoted once it is actually decoded, so the old
// image stays visible until the new one is ready and there is never a blank
// frame between tracks. Nothing here runs while `url` is unchanged, and the
// popup only passes a URL while it is open.
Item {
  id: root

  property string url: ""
  property bool animate: true
  // The theme's surface, used to build the veil above the blur.
  property color tint: "#000000"

  readonly property bool hasImage: slotA.status === Image.Ready || slotB.status === Image.Ready

  // Which slot is currently on top. Promotion happens only on a decoded image.
  property int front: 0
  readonly property var slots: [slotA, slotB]

  // Resolve the visible slot for the current URL. This has to look at *both*
  // slots, not just the idle one: a URL can flip back to one the idle slot is
  // already holding (A -> B -> A), and in that case assigning no new source
  // means no status change fires, so nothing would ever promote it and the
  // previous track's art would stay on screen. Checking first also avoids a
  // needless reload when the front already shows the right image.
  function sync() {
    if (!root.url) return

    var current = root.slots[root.front]
    if (current.status === Image.Ready && String(current.source) === root.url)
      return

    var backIndex = 1 - root.front
    var back = root.slots[backIndex]
    if (back.status === Image.Ready && String(back.source) === root.url) {
      root.front = backIndex
      return
    }
    if (String(back.source) !== root.url)
      back.source = root.url
  }

  onUrlChanged: root.sync()
  Component.onCompleted: root.sync()

  Item {
    id: art
    anchors.fill: parent
    // The effect draws the source; drawing it here as well would double-paint.
    visible: false

    Image {
      id: slotA
      anchors.fill: parent
      asynchronous: true
      cache: true
      smooth: true
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: 320
      sourceSize.height: 320
      opacity: root.front === 0 ? 1 : 0
      onStatusChanged: root.sync()

      Behavior on opacity {
        enabled: root.animate
        NumberAnimation { duration: 320; easing.type: Easing.InOutQuad }
      }
    }

    Image {
      id: slotB
      anchors.fill: parent
      asynchronous: true
      cache: true
      smooth: true
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: 320
      sourceSize.height: 320
      opacity: root.front === 1 ? 1 : 0
      onStatusChanged: root.sync()

      Behavior on opacity {
        enabled: root.animate
        NumberAnimation { duration: 320; easing.type: Easing.InOutQuad }
      }
    }
  }

  MultiEffect {
    anchors.fill: parent
    source: art
    visible: root.hasImage
    blurEnabled: true
    blurMax: 64
    blur: 0.85
    saturation: -0.15
  }
}
