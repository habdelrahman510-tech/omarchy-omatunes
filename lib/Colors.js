.pragma library

// Colour maths for the companion. Pure functions only.
//
// Nothing here decides a colour scheme: the palette itself comes from
// Omatunes through ThemeAdapter. These helpers only translate and composite
// those values (alpha, mixing, luminance) so contrast can be reasoned about
// instead of hoped for.

function parse(value) {
  var text = String(value || "").trim()
  if (text.charAt(0) === "#") text = text.substring(1)
  if (text.length === 3) {
    text = text.charAt(0) + text.charAt(0) + text.charAt(1) + text.charAt(1) + text.charAt(2) + text.charAt(2)
  }
  if (text.length === 8) text = text.substring(2) // #aarrggbb -> rgb
  if (text.length !== 6 || !/^[0-9a-fA-F]{6}$/.test(text)) return null
  return {
    r: parseInt(text.substring(0, 2), 16),
    g: parseInt(text.substring(2, 4), 16),
    b: parseInt(text.substring(4, 6), 16)
  }
}

function hex(rgb) {
  function part(value) {
    var n = Math.max(0, Math.min(255, Math.round(value)))
    var text = n.toString(16)
    return text.length === 1 ? "0" + text : text
  }
  return "#" + part(rgb.r) + part(rgb.g) + part(rgb.b)
}

function valid(value) {
  return !!parse(value)
}

function withAlpha(value, alpha) {
  var rgb = parse(value)
  if (!rgb) return "transparent"
  var a = Math.max(0, Math.min(1, Number(alpha) || 0))
  var text = Math.round(a * 255).toString(16)
  if (text.length === 1) text = "0" + text
  return "#" + text + hex(rgb).substring(1)
}

function mix(a, b, amount) {
  var one = parse(a)
  var two = parse(b)
  if (!one) return two ? hex(two) : "transparent"
  if (!two) return hex(one)
  var t = Math.max(0, Math.min(1, Number(amount) || 0))
  return hex({
    r: one.r + (two.r - one.r) * t,
    g: one.g + (two.g - one.g) * t,
    b: one.b + (two.b - one.b) * t
  })
}

function channel(value) {
  var c = value / 255
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
}

// WCAG relative luminance, 0 (black) to 1 (white).
function luminance(value) {
  var rgb = parse(value)
  if (!rgb) return 0
  return 0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b)
}
