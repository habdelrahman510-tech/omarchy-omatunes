import QtQuick

// A pre-rendered radial light.
//
// One 256px texture, one quad: following the pointer only changes x and y, so
// there is no blur pass, shader or regenerated texture per frame. The PNG's
// alpha reaches zero at its edge, so the falloff is smooth with no hard rim,
// and it is white — it lifts luminance only, never adds hue.
Item {
  id: root

  property point center: Qt.point(-10000, -10000)
  property real diameter: 240
  property real strength: 0.09

  Image {
    id: light
    source: Qt.resolvedUrl("../assets/cursor-glow.png")
    width: root.diameter
    height: root.diameter
    x: root.center.x - width / 2
    y: root.center.y - height / 2
    smooth: true
    opacity: root.strength
    visible: root.strength > 0.001
  }
}
