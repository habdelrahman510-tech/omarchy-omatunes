#!/usr/bin/env python3
"""Build the vinyl texture used by PlayerPopup.qml.

Rendered once at twice the shipped size and downsampled, so the grooves stay
smooth and the disc edge is antialiased. No runtime effect or blur is involved:
the QML side only moves and rotates this one image.
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

# Two soft angular lobes make the light lie on the record rather than sit on
# top of it. They are deliberately dim so the grooves remain the detail you
# notice.
def lobe(theta, width):
    d = np.angle(np.exp(1j * (a - theta)))
    return np.exp(-(d * d) / (2.0 * width * width))

grooves = np.sin(r * 220 * np.pi) * 2.1 + np.sin(r * 520 * np.pi) * 0.9
base = 9.0 + 13.0 * (1.0 - r) + grooves
sheen = 30.0 * lobe(-0.95, 0.42) * np.clip((r - 0.30) / 0.70, 0, 1)
sheen += 10.0 * lobe(2.20, 0.55) * np.clip((r - 0.32) / 0.68, 0, 1)
v = np.clip(base + sheen + np.where(r > 0.97, 10.0, 0.0), 0, 70)

disc = np.stack([v, v, v], axis=-1)

# Warm paper label, with a pressed inner ring and a small spindle hole.
label = r < 0.30
lr = r / 0.30
label_rgb = np.stack([
    196.0 - 14.0 * lr,
    122.0 + 6.0 * lr,
    62.0 + 10.0 * lr,
], axis=-1)
ring = (lr > 0.88) & (lr < 0.94)
label_rgb[ring] *= 0.82
disc[label] = np.clip(label_rgb[label], 0, 255)

hole = r < 0.034
rim = (r >= 0.034) & (r < 0.050)
disc[hole] = (7, 7, 7)
disc[rim] = (48, 33, 22)

alpha = np.clip((1.0 - r) * c, 0, 1) * 255.0
rgba = np.dstack([disc, alpha]).astype(np.uint8)

img = Image.fromarray(rgba, "RGBA").resize((OUT, OUT), Image.Resampling.LANCZOS)
img.save("assets/vinyl.png", optimize=True)
print("wrote assets/vinyl.png", img.size)
