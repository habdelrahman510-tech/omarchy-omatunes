# Omatunes Plugin

An [Omatunes](https://github.com/habdelrahman510-tech/Omatunes-Deluxe) companion for the Omarchy bar.
It is a companion, not a second player: Omatunes keeps the library, the queue, the lyrics, the audio
engine and the truth about what is playing. This plugin presents that state and offers the fast
controls.

## Install

```bash
omarchy plugin add https://github.com/habdelrahman510-tech/omarchy-omatunes --enable --yes
```

Or, if it is already installed and you just want to update:

```bash
omarchy plugin update omatunes --yes
```

The plugin installs as `omatunes`, requires nothing besides Omatunes 2.1 or newer for the full
feature set, and lands in `center` unless your `shell.json` says otherwise.

### Keeping a local checkout permanent

`omarchy plugin update` replaces the installed plugin, and `pacman -Syu` can replace the patched
player with an older packaged build. From this checkout, one command restores the whole setup —
plugin sync, `Super + Alt + O` binding, patched player in `/usr/local/bin`, reload and verification:

```bash
./scripts/make-permanent.sh
```

It is idempotent, safe to re-run after any update, and asks for privileges through `pkexec` only
when rebuilding the player. Set `OMATUNES_APP_REPO` if the player checkout is not at
`~/Projects/omatunes`.

## What you get

**In the bar** — a standalone pill of a fixed width: a 20px round artwork tile, `Artist — Title`
elided inside its own box, a play/pause control, and a two-pixel hairline of elapsed time. A title
never resizes it, so the bar around it never shifts. The disc wears a thin accent ring and the
hairline only while something is playing; a liked track gets a small heart on the disc rather than a
glyph in the row.

The pill is always there, playing or not. With Omatunes closed the disc goes quiet, the label says
`Omatunes`, and the control becomes a play button that starts the app **hidden** — a process with
no window at all, not an invisible one, because Wayland offers no way to unmap a toplevel — and
begins playback without a window interrupting the desktop. The album art is the door to the window:
it asks a running instance to show itself (or launches one when there is nothing to ask). The pill
does no image processing and owns no timer; the one timer in the companion runs only while
something is playing, for the hairline and the card's timeline.

**In the popup** (left-click the pill) — a compact now-playing card, not a second window:

- the current artwork as the only background, cropped to cover and blurred once — no gradients, no
  palette extraction, no stacked glass panels;
- a soft, neutral light that follows the pointer across the card and the artwork disc alike: it
  lifts luminance only, so the sleeve keeps its own colours instead of being washed out;
- the artwork itself as Omatunes' launch surface: click it to focus a running Omatunes or start it;
- title and artist, with a seekable timeline that shows elapsed/total while you point at it;
- previous, play/pause, next and shuffle, plus the three-bars control in the reference position.
  Shuffle is Omatunes' own switch, drawn solid while shuffling and as a ring while playing in order;
- a compact utility panel behind the three-bars control: Omatunes' real repeat mode and its real
  equalizer (on/off and preset). The card grows downward to hold that panel while it is open, so it
  never covers the track it belongs to, and shrinks back when it closes.

There is no queue column and no context heading: the card shows what is playing and the controls
for it, and nothing else. It arrives and leaves on the same curve the desktop uses to switch
workspaces — see [Motion](#motion).

## Motion

The card fades and slides in, and dissolves out, on the desktop's own switching transition rather
than a curve of its own: the `smooth` bezier defined in `~/.config/hypr/looknfeel.lua`
(`cubic-bezier(0.22, 1, 0.1, 1.1)`), with the overshoot preserved so the arrival has the same
small settle as a workspace change. The panel contributes its own envelope (180 ms in, 120 ms out,
3% scale from the bar edge); the card adds a 24-design-pixel slide and a fade over 240 ms, long
enough to be read instead of merely sensed.

The card's height moves on that same curve too, so opening the utility menu stretches it down and
closing it pulls it back instead of jumping between two sizes.

The transition follows the bar's animation setting: with bar animations disabled the card simply
appears and disappears, with no travel and no fade.

## Controls

| Where | Action |
|---|---|
| Pill, left click | Open or close the companion |
| Pill, middle click | Like / unlike the current track |
| Pill, artwork | Show the Omatunes window, or start one |
| Pill, play/pause | Play or pause; with no player, start Omatunes hidden and play |
| Popup, artwork | Show the Omatunes window, or start one |
| Popup, timeline | Click or drag to seek |
| Popup, transport | Previous / play-pause / next / shuffle |
| Popup, three bars | Repeat mode and equalizer |
| `Escape` / click outside | Close the panel, then the popup |
| `Super + Alt + O` | Open the companion from anywhere, with the bar shown or hidden |

Volume is deliberately not in the popup. Omatunes owns its own volume; use the application, or your
desktop's mixer, rather than a second control surface that can disagree with it.

## How it talks to Omatunes

| Capability | Interface | Notes |
|---|---|---|
| Track, artist, album, cover, duration | MPRIS `Metadata` | `mpris:artUrl` only, always a local file — the same art the app itself draws |
| Playback state | MPRIS `PlaybackStatus` | Event-driven; no polling |
| Play/pause/stop, previous, next | MPRIS methods | Guarded by the player's capability flags |
| Shuffle | UDP `shuffle`; state from MPRIS `Shuffle` | Toggle only, app-owned; the card mirrors the state it reports |
| Seek | MPRIS `SetPosition` / `Position`, rebased by `Seeked` | Only when `CanSeek` is true |
| Liked | `xesam:userRating`, else `~/.cache/omatunes_current_state.json` | Read-only |
| Next queue entries, repeat mode, playing context | `~/.cache/omatunes_companion.json` | Schema 1, read-only, written by the app |
| Equalizer state and presets | `~/.cache/omatunes_companion.json` | The real DSP, not a plugin effect |
| Repeat / equalizer changes, like | UDP `127.0.0.1:18888` via `bin/omatunes-ctl` | Argument-validated, one-shot |
| Hidden start / show the window | `omatunes --background`, UDP `show` | `--background` is a process with no window; `show` opens and focuses one; a second launch hands `show` to the running instance instead of starting a second engine |
| Theme tokens | `~/.cache/omatunes_theme.json` | Schema 1, read-only, written by the app |

Both cache files are replaced atomically by Omatunes and are optional: if they are absent the
companion falls back to the shell theme, hides the equalizer controls, and shows no queue at all
(the card is a now-playing tile, so there is nothing to fill in when the app is silent). Nothing in
the plugin writes to Omatunes' state or database.

### Artwork

`mpris:artUrl` is the track's *own* picture, not the album's: Omatunes resolves it the way its own
player does — the embedded tag picture first, a `cover.jpg`/`folder.jpg` beside the track only when
the file has none — writes the bytes to `~/.cache/omatunes_current_art.jpg`, and appends the track
id as a query (`file://…jpg?t=41`). The query is the image cache key: a new track is a new key, so
Qt's `Image` cache cannot show the previous sleeve.

The plugin keeps that query and checks only the path: `file://` (or an absolute path) is accepted,
anything else — `http:`, `data:`, a bare remote reference — is rejected, so metadata can never turn
into a network request.

## Architecture

```
BarWidget.qml          standalone pill; left-click opens the popup
Service.qml            `service` entry point, loaded once per shell session
PlayerPopup.qml        the card: fixed design space, blurred backdrop, transport, utility panel
lib/OmatunesService.qml  singleton: MPRIS + companion snapshot, position model, verbs
lib/ThemeAdapter.qml     singleton: Omatunes theme tokens with a shell fallback
lib/ArtworkBackground.qml one artwork image, blurred once, cross-faded on track change
lib/Colors.js            colour maths (alpha, mixing, luminance)
bin/omatunes-ctl         the one-shot UDP helper
```

The service is a QML singleton owned by the shell's engine, and the plugin declares the `service`
kind so Omarchy instantiates it at start-up. Closing the popup destroys a window, not a
subscription: playback state, the queue snapshot and the current artwork identity stay live, which
is why reopening the popup is instant and always current.

## Cost

One MPRIS subscription set, two watched files, and a 200 ms clock while Omatunes is playing (the
bar hairline needs it too). The clock reads Quickshell's live MPRIS position getter; track changes
and seeks rebase it through the player's `Seeked` signal, so there is no second estimate to drift.
Artwork is decoded once per track at 320px for the backdrop and 616px for the tile, blurred
by a single GPU pass; the popup cross-fades rather than re-decoding, and nothing is rendered while
it is hidden.
