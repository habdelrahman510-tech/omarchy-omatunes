#!/usr/bin/env python3
"""Build the printed-paper texture laid over the album sleeve.

The PNG is mostly transparent. Each pixel is either white or black with a low
alpha, so it lifts or darkens the cover by a fraction without shifting its hue.
A broad diagonal sheen matches the direction of the light on the vinyl, making
the sleeve and the record read as one object. Rounded corners are cut into the
alpha channel, so the QML side needs no mask for this layer.
"""

import numpy as np
from PIL import Image

S = 512
c = (S - 1) / 2.0
rng = np.random.default_rng(20261123)

y, x = np.mgrid[0:S, 0:S]
px = x - c
py = y - c

# Fine paper grain, clipped so an occasional loud speck cannot punch through.
grain = np.clip(rng.normal(size=(S, S)) * 0.62, -1, 1)

# Fibre direction: a slowly varying x-only noise, stretched across the sleeve.
line = rng.normal(size=(1, S))
kernel = np.ones(9) / 9.0
line = np.convolve(line.ravel(), kernel, mode="same").reshape(1, S)
fibre = np.clip(line / max(1e-6, np.std(line)) * 0.7, -1, 1)

# One soft diagonal band, perpendicular to the vinyl's highlight direction.
theta = -0.95
nx, ny = np.cos(theta + np.pi / 2), np.sin(theta + np.pi / 2)
proj = (px * nx + py * ny) / c
sheen = np.exp(-((proj + 0.28) ** 2) / (2.0 * 0.48 ** 2))

delta = np.clip(grain * 0.055 + fibre * 0.018 + sheen * 0.045, -0.12, 0.12)

# Antialiased rounded-square alpha, matching the sleeve's 8px corner at 224px.
half = S / 2.0
radius = 18.0
q = np.abs(np.stack([px, py], axis=-1)) - (half - radius)
d = np.linalg.norm(np.maximum(q, 0), axis=-1) + np.minimum(np.max(q, axis=-1), 0) - radius
mask = np.clip(0.5 - d, 0, 1)

alpha = np.abs(delta) * mask * 255.0
light = np.where(delta >= 0, 255, 0).astype(np.uint8)
rgba = np.dstack([light, light, light, alpha.astype(np.uint8)])

img = Image.fromarray(rgba, "RGBA")
img.save("assets/sleeve-texture.png", optimize=True)
print("wrote assets/sleeve-texture.png", img.size)
