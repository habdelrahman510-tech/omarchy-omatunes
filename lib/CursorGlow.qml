import QtQuick
import QtQuick.Effects

// A soft light that follows the pointer.
//
// One small, low-alpha disc is blurred into a texture the size of this item,
// so the falloff is radial without a shader and without stretching the source.
// The light is neutral by design: it lifts luminance instead of adding hue,
// which means the artwork and type underneath keep their own colours. A mask
// can be supplied when the glow has to stay inside a circular surface.
Item {
  id: root

  property point center: Qt.point(-1000, -1000)
  property real diameter: 240
  property color light: "#ffffff"
  property real strength: 0.09
  property real blurMultiplier: 1
  property Item maskItem: null

  Item {
    id: field
    anchors.fill: parent
    visible: false

    Rectangle {
      x: root.center.x - root.diameter / 2
      y: root.center.y - root.diameter / 2
      width: root.diameter
      height: root.diameter
      radius: width / 2
      color: root.light
      opacity: root.strength
    }
  }

  MultiEffect {
    anchors.fill: parent
    source: field
    blurEnabled: true
    blurMax: 64
    blur: 1.0
    blurMultiplier: root.blurMultiplier
    maskEnabled: root.maskItem !== null
    maskSource: root.maskItem
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1.0
    visible: root.strength > 0.001
  }
}
