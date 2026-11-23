#!/usr/bin/env python3
"""Build the vinyl texture used by PlayerPopup.qml.

Rendered once at twice the shipped size and downsampled, so the grooves stay
smooth and the disc edge is antialiased. No runtime effect or blur is involved:
the QML side only moves and rotates this one image.

Concentric grooves alone look the same at every angle, so the spin is invisible.
The directional glints below are baked into the texture: they rotate with the
record, which is what makes the motion legible at a glance.
"""

import numpy as np
from PIL import Image

S = 1024
OUT = 512
c = (S - 1) / 2.0

y, x = np.mgrid[0:S, 0:S]
dx = (x - c) / c
dy = (y - c) / c
r = np.sqrt(dx * dx + dy * dy)
a = np.arctan2(dy, dx)


def lobe(theta, width):
    d = np.angle(np.exp(1j * (a - theta)))
    return np.exp(-(d * d) / (2.0 * width * width))


radial = np.clip((r - 0.26) / 0.72, 0, 1)

# Deeper radial shading and a mid-band lift give the disc some body.
base = 6.0 + 17.0 * (1.0 - r) + 5.0 * np.exp(-((r - 0.70) / 0.16) ** 2)

# Pressed grooves. They carry detail, not motion; the glints below do that.
grooves = np.sin(r * 220 * np.pi) * 3.2 + np.sin(r * 520 * np.pi) * 1.4

# A broad reflection and a tighter specular streak on the same bearing, plus a
# second weaker one opposite. A small off-axis patch catches the light too.
glint = 56.0 * lobe(-0.95, 0.26) * radial
glint += 20.0 * lobe(-0.95, 0.075) * radial
glint += 17.0 * lobe(2.20, 0.42) * radial
dr = (r - 0.63) / 0.10
dt = np.angle(np.exp(1j * (a - 0.55))) / 0.30
patch = 26.0 * np.exp(-(dr * dr + dt * dt))

# A lit rim and a dark step just inside it read as a pressed edge.
edge = np.where(r > 0.965, 16.0, 0.0) + np.where(r > 0.992, 10.0, 0.0)

v = np.clip(base + grooves + glint + patch + edge, 0, 110)
disc = np.stack([v, v, v], axis=-1)

# Warm paper label with an angular shade and one printed mark, so the label
# turns with the record instead of looking like a flat static disc.
label = r < 0.30
lr = r / 0.30
label_rgb = np.stack([
    190.0 - 18.0 * lr,
    116.0 + 8.0 * lr,
    58.0 + 12.0 * lr,
], axis=-1)
label_rgb = label_rgb + (6.0 * lobe(-0.95, 0.60))[:, :, None]
label_rgb[(lr > 0.88) & (lr < 0.94)] *= 0.80
mark = (lr > 0.50) & (lr < 0.78) & (np.abs(np.angle(np.exp(1j * (a - 1.15)))) < 0.11)
label_rgb[mark] *= 0.76
disc[label] = np.clip(label_rgb[label], 0, 255)

hole = r < 0.034
rim = (r >= 0.034) & (r < 0.050)
disc[hole] = (6, 6, 6)
disc[rim] = (48, 33, 22)

alpha = np.clip((1.0 - r) * c, 0, 1) * 255.0
rgba = np.dstack([disc, alpha]).astype(np.uint8)

img = Image.fromarray(rgba, "RGBA").resize((OUT, OUT), Image.Resampling.LANCZOS)
img.save("assets/vinyl.png", optimize=True)
print("wrote assets/vinyl.png", img.size)
