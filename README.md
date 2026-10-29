# omarchy-omatunes

Bar widget for [Omatunes Deluxe](https://github.com/habdelrahman510-tech/Omatunes-Deluxe) — the
native Wayland music player for Omarchy.

Shows the current track and artist, and gives you play/pause, next, previous, shuffle, repeat and
like controls from the bar, matching whatever system theme you are running.

## Install

```bash
omarchy plugin add https://github.com/habdelrahman510-tech/omarchy-omatunes --enable --yes
```

Or, if you already have it installed and just want to update:

```bash
omarchy plugin update omatunes --yes
```

## Requirements

- Omarchy (Quickshell shell)
- Omatunes Deluxe — the widget looks for a player whose MPRIS identity, bus name or desktop entry
  contains `omatunes`, and deliberately never falls back to any other media player

```bash
git clone https://github.com/habdelrahman510-tech/Omatunes-Deluxe
cd Omatunes-Deluxe/packaging/omatunes-deluxe-bin && makepkg -si
```

## What is in here

| File | Purpose |
|---|---|
| `manifest.json` | Omarchy plugin manifest, id `omatunes`, kind `bar-widget` |
| `BarWidget.qml` | The widget itself — self-contained |
| `LICENSE` | MIT |

The player lives in a separate repository; this one is only the plugin, because `omarchy plugin add`
reads `manifest.json` from the repository root.

## Licence

MIT. See [LICENSE](LICENSE).
