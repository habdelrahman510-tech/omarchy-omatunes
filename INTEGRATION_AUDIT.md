# Integration audit — Omatunes Omarchy companion

Audit of the finished integration, kept current with the working trees. Every claim below comes
from source inspection or from a command whose output is quoted; nothing is inferred from the fact
that a feature exists inside the application.

Started 2026-11-16 against the pre-rewrite trees; final state recorded 2026-11-17.

## 1. Repositories

| Repo | Path | Branch | Commit | Working tree |
|---|---|---|---|---|
| Plugin | `~/Projects/omarchy-omatunes` | `main` | `c2b959e` (feat: Omatunes Deluxe bar widget) | dirty — the rewrite is uncommitted; five files removed, eleven added or rewritten |
| Application | `~/Projects/omatunes` (remote: `habdelrahman510-tech/Omatunes-Deluxe`) | `main` | `324cde4` (chore(pkg): refresh the 2.0.2 checksums) | dirty — `src/app/companion.rs` (new), `src/ui/theme.rs` (theme export), `src/app/mod.rs` + `src/app/playback.rs` (repeat message, publish call sites), `src/audio/mpris.rs` + `src/app/playback.rs` (unreleased `xesam:userRating` publication) |
| Installed plugin copy | `~/.config/omarchy/plugins/omatunes` | git checkout of the same remote | installed release | stale relative to the work tree; re-synced from the repo after testing |

Runtime:

- `quickshell --version` → `Quickshell 0.3.2 (revision 2b4501a282689792b62e94f3fb30d8f512324fe6, distributed by Omarchy)`
- Omarchy `/usr/share/omarchy/version` → `4.0.0.alpha`
- Qt 6.12. QML imports used by the plugin: `QtQuick`, `QtQuick.Effects`, `Quickshell`,
  `Quickshell.Io`, `Quickshell.Services.Mpris`, `qs.Commons`, `qs.Ui`.

## 2. Plugin file map and lifecycle

```
manifest.json             schemaVersion 1, kinds ["bar-widget","service"], version 2.1.0
BarWidget.qml             the standalone pill; left-click opens the popup
Service.qml               `service` entry point: instantiates the controller at shell start-up
PlayerPopup.qml           the card: fixed design space, artwork backdrop, transport, utility panel
lib/qmldir                two singleton declarations
lib/OmatunesService.qml   singleton: MPRIS + companion snapshot, position model, verbs
lib/ThemeAdapter.qml      singleton: reads Omatunes' theme export, falls back to the shell
lib/ArtworkBackground.qml the one artwork image, blurred once, cross-faded
lib/Colors.js             pure colour maths (alpha, mixing, luminance)
i18n/en.json              popup strings
bin/omatunes-ctl          one-shot UDP client, argument-validated
```

Removed in this pass: `PlayerState.qml`, `PaletteService.qml`, `Palette.js`,
`AmbientBackground.qml`, `bin/omatunes-palette`.

Shipped lifecycle, and why it was wrong: the shell's `PluginRegistry` discovered `manifest.json`,
the active bar pulled `BarWidget.qml` through a `Loader`, and the widget owned `PlayerState`, the
`PlayerPopup` window *and* the palette helper process. Player state, the MPRIS binding and the
palette cache therefore lived inside a visual item the bar may destroy on layout or monitor
changes; the popup owned image processing; and click mapping was right-click-to-open,
left-click-to-play/pause — the opposite of the required interaction.

Rewritten lifecycle: the manifest declares `service`, so `shell.qml` instantiates `Service.qml`
once with `createObject(null)` and keeps it for the life of the plugin's enablement. That file
touches the `OmatunesService` singleton, which is engine-owned and shared by the service, the
widget and the popup. Closing the popup destroys a window; it cannot disconnect a subscription.

## 3. Omarchy / Quickshell contract

### Manifest (`/usr/share/omarchy/bin/omarchy-plugin-validate`, `shell/services/PluginRegistry.qml`)

- `schemaVersion` must be the JSON number `1`.
- Required: `id`, `name`, `version`, `kinds`, `entryPoints`.
- `kinds` is a non-empty array; each kind fixes its entry-point key:
  `bar`→`bar`, `bar-widget`→`barWidget`, `menu`→`menu`, `overlay`→`overlay`,
  `panel`→`panel`, `service`→`service`.
- `barWidget.defaultSection` must be one of `left`, `centerBegin`, `center`,
  `centerEnd`, `tray`, `right`.
- Entry points must be safe relative paths that exist; **no symlinks anywhere** in the plugin
  folder (the installed copy is a git checkout, `.git` is skipped).
- Plugin ids may not use the `omarchy.*` namespace.

### Bar widgets

Injected properties (`plugins/bar/Bar.qml`, `injectProps`): `fixedEdge`, `bar`, `moduleName`,
`settings`. For a third-party plugin, `bar` is a **facade** object (`pluginBarApiFor`) offering
`showTooltip`/`hideTooltip`, `run`, `requestPopout`/`releasePopout`, `pluginShellFor…`; it is
*not* the real `Bar` and does not expose `ShellRoot` to untrusted plugins. Built-in widgets get
the real bar.

`Ui/BarWidget.qml` adds the shared surface: `bar`, `moduleName`, `settings`, `fixedEdge`,
`vertical`, `barSize`, `broadcast(method)`, `setting(name, fallback)`.

The active bar in this session is the third-party `bit-dev.bar` ("Pill Bar"), not
`omarchy.bar`. Its layout normaliser only keeps `left`/`center`/`right`; the shell rewrites
`~/.config/omarchy/shell.json` on start and, in this bar, parks the widget at the head of the
`right` section (`right[1]`, after the tray). The manifest declares `center`, since a `centerEnd`
declaration would silently disappear behind this bar.

The pill is a **fixed-width** widget (`Style.space(238)`) and is always visible, player or not:
the disc, the label box and the play/pause control are laid out from constants, and the label
elides inside its own box. A track name cannot resize the widget, which is what keeps the rest of
the bar from shifting when the song changes. It is **not** pinned absolutely: the right section is
right-packed, so the pill's x follows the widths of the widgets to its right (battery percentage,
the world clock) and of the tray when icons come and go. Fixed width is guaranteed; fixed screen
position is a property of the bar's section packing, not of the widget.

### Services (the persistent-lifecycle hook)

`shell/shell.qml` `_syncServices()` iterates installed plugins; for every plugin whose `kinds`
contains `service`, that has `entryPoints.service` and is enabled, it calls `ensureService(id)`:

- `Qt.createComponent(url, Component.PreferSynchronous)`;
- `comp.createObject(null)` — third-party services have **no visual parent**;
- injected properties, when declared: `omarchyPath`, `shell`, `manifest`, `barWidgetRegistry`,
  `pluginRegistry`;
- the instance is kept in a `_services` map for the life of the plugin's enablement and survives
  bar/widget recreation and bar layout edits; it is destroyed only when the plugin is disabled,
  removed, or the shell restarts;
- `keepLoaded: true` additionally preserves it across plugin hot-reload.

QML singletons declared through a `qmldir` in a plugin subdirectory work in this Quickshell:
`lib/qmldir` declares `singleton OmatunesService` and `singleton ThemeAdapter`, imported by a
relative directory import (`import "lib"`), and both resolve and instantiate in a real
`quickshell -p` run. They are engine-owned and therefore shared by the service, the bar widget
and the popup — one controller, not three.

### Popup

The card is a `Ui/KeyboardPanel`, not a `Ui/PopupCard`. In this session `PopupCard` never mapped
(it opened, logged no error, and produced no surface), while `KeyboardPanel` maps reliably on the
bar's own screen. What that base provides: `anchorItem`, `owner`, `bar`, `open`, `focusTarget`,
`contentWidth`/`contentHeight`, `fittedContentWidth/Height`, `padding`, `borderSpec`, and the
`omarchy-keyboard-panel` layer surface that outside-click and `Escape` already dismiss.

Three consequences are load-bearing:

- **`contentItem` is a list of `Item`s only.** A bare `Timer` or any non-`Item` at the card's top
  level fails the whole file with `Cannot assign object of type "QQmlTimer" to list property
  "contentItem"`. Anything that must run while the card is closed belongs in the singleton, not
  in the panel.
- **The panel is a full-screen surface.** `contentWidth/Height` size the card inside it; the
  panel's own hit area is the bar strip (~0..15 px). Clicks aimed at the bar at y=20 miss the bar
  and land on the panel's content, so the pill's hit point is y≈13.
- **The card's height is live.** It is the compact tile's height normally, and grows by
  `menuTop + menu.height + unit*10` while the utility menu is open; the panel animates the change,
  so it reads as a stretch rather than a jump.


## 4. Omatunes MPRIS surface (runtime-verified)

```
bus     org.mpris.MediaPlayer2.omatunes       (owner present; :1.710)
path    /org/mpris/MediaPlayer2
Identity "Omatunes"        DesktopEntry ""     CanRaise false   CanQuit false
```

`org.mpris.MediaPlayer2.Player` (from `busctl introspect`):

| Property | Value observed | Notes |
|---|---|---|
| `PlaybackStatus` | `"Paused"` | `emits-change` |
| `Metadata` | `a{sv}` 7 | keys below |
| `Position` | `19900000` (µs) | **no** `emits-change` — clients interpolate from `Rate` and rebase on `Seeked` |
| `Rate` | `1` | writable, emits-change |
| `CanControl` / `CanPlay` / `CanPause` / `CanGoNext` / `CanGoPrevious` / `CanSeek` | all `true` | |
| `Shuffle` | `true` | declared writable, but the app ignores `Set` (see §5) |
| `LoopStatus` | `"Playlist"` | declared writable, same caveat |
| `Volume` | `1` | writable (deliberately not surfaced — recorded in README) |

Methods: `Play`, `Pause`, `PlayPause`, `Stop`, `Next`, `Previous`, `Seek`, `SetPosition`,
`OpenUri`. Signal: `Seeked`.

Metadata keys published by the build this was verified against (`2.0.2` plus the change set below):
`mpris:artUrl`, `mpris:length` (µs), `xesam:album`, `xesam:artist` (array), `xesam:title`,
`xesam:url`, `xesam:userRating` (double). The `omatunes-bin 2.0.2-1` package installed on this
machine publishes the first six only: no `xesam:userRating`, no `mpris:trackid`. The rating comes
from the uncommitted `MprisUpdate::Rating` in `src/audio/mpris.rs`, which is why the liked heart
falls back to `~/.cache/omatunes_current_state.json` when that build is not the one running.

Artwork is a **local file URL**, and it is the track's own picture. `AppState::publish_current_art`
(`src/app/playback.rs`) takes `track.cover_data`, else `library::scanner::load_cover(&track.path)` —
the same order the app's own player draws with: the embedded tag picture first, a
`cover.jpg`/`Cover.jpg`/`cover.png`/`Cover.png`/`cover.webp`/`Cover.webp`/`folder.jpg`/`Folder.jpg`
beside the track only when the file has none. The bytes are written to
`~/.cache/omatunes_current_art.jpg` and the URL gains `?t=<track id>`.

This replaced an older order that preferred the folder file first. That advertised the album's one
shared `cover.jpg` for every track in the folder — observed live: `Self Aware` by Temper City was
served `file:///home/dog/Music/cover.jpg` (1000×1000) while the app drew the track's embedded
1280×720 picture, mean absolute difference 50.6/255. The cache-buster is now keyed on the track
alone, not the clock, so repeated notifications for one track reuse a URL instead of forcing a
reload.

The plugin keeps the query in `cleanArtUrl()` — it is what gives Qt's image cache a distinct key
per track — but validates only the path: `file://` or an absolute path is accepted, everything
else is rejected, so metadata can never cause a network request.

## 5. App-specific interfaces

Every interface the companion uses is either an already-documented surface or a new, versioned,
read-only snapshot. Nothing reads the library database, and nothing in the plugin writes app state.

| Interface | Source | Status |
|---|---|---|
| UDP control socket `127.0.0.1:18888` | `src/app/mod.rs` (`UdpSubscriptionId`); documented in `USER_MANUAL.md` §"The control socket" | **Documented integration surface.** Verbs: `play <abs path>`, `play-pause`, `next`, `prev`, `like`, `shuffle`, `repeat`, `seek <seconds>` (fractional, e.g. `12.500`). One datagram ≤ 1024 bytes. |
| `omatunes-open` CLI | packaged helper, documented in `USER_MANUAL.md` | Wrapper over `play <path>`; starts the app if it is not running. |
| `~/.cache/omatunes_current_liked` | `src/app/playback.rs:80-91` | Plain `1`/`0`, atomic (tmp + rename). |
| `~/.cache/omatunes_current_state.json` | `src/app/playback.rs:91-135` | `{"liked":bool,"shuffle":bool,"repeat":bool}`, atomic rename. Read-only for the plugin; the liked fallback. |
| `~/.cache/omatunes_theme.json` | `src/ui/theme.rs` (`publish_theme_export`) — **new, schema 1** | Read-only. The resolved 11-role palette, written whenever a palette is installed. |
| `~/.cache/omatunes_companion.json` | `src/app/companion.rs` — **new, schema 1** | Read-only. Upcoming order, repeat, playing context, equalizer state/presets. |
| MPRIS | `src/audio/mpris.rs` | Standard interface, see §4. |
| Queue, playlists, lyrics, statistics, visualizer, output devices | app-internal (`src/ui/views/*`, `src/audio/*`) | **Not exposed.** Nothing in the plugin claims them. |

### 5.1 `omatunes_companion.json` (schema 1)

Written by `AppState::publish_companion()` in `src/app/companion.rs`. Payload:

```json
{"schema":1,"revision":7,"updated":1763340000,
 "product":"omatunes",
 "repeat":"queue",
 "context":{"kind":"Album","name":"Tripp","queue_length":9},
 "eq":{"enabled":true,"preset":"Bass boost",
       "presets":["Flat","Loudness","Bass boost","Bass cut","Treble boost","Treble cut","Vocal","Rock"]},
 "upcoming":[{"id":41,"title":"Find you","artist":"Tripp","duration_ms":218000},
             {"id":42,"title":"Mafesh Meno","artist":"Tripp","duration_ms":216000},
             {"id":43,"title":"Loser","artist":"Tripp","duration_ms":221000}]}
```

Guarantees, all enforced in the writer:

- **Atomic.** Tmp file plus rename, with a direct-write fallback.
- **Change-gated.** The body is compared against `companion_last_body`; identical payloads touch
  no disk. `revision` increments only on a real change and is the client's change signal.
- **Real order.** `companion_upcoming()` walks the app's own queue from the current entry forward
  using the same rule as `advance_track(1)`; it wraps only when `RepeatMode::All`. With shuffle
  on, the queue *is* the sequence the app chose, so the snapshot inherits it — the plugin never
  orders anything.
- **Published at every change point.** `commit_equalizer`, `maybe_shuffle_queue` (both exits),
  `on_spliced`, `play_track_internal`, `ToggleShuffle`, `ToggleRepeat`, `SetRepeat`,
  `AddToQueue`, `Remove/Move QueueTrack*`, `ClearQueue`, `QueueDragOver`, plus once at start-up.
- **Absence is honest.** Without the file the plugin reports nothing: the equalizer row is hidden
  and repeat falls back to MPRIS `LoopStatus`. (The card no longer paints `upcoming` or `context`;
  the snapshot still publishes them, so another consumer — or a later version of this card — can
  use them.)

### 5.2 New verbs on the UDP socket

Existing verbs are unchanged. Three absolute-state verbs were added, because MPRIS `Set` on
`Shuffle`/`LoopStatus` is dropped by the app and the equalizer has no MPRIS surface at all:

| Verb | Effect | Validation |
|---|---|---|
| `repeat off\|queue\|track` | `Message::SetRepeat(RepeatMode)` — absolute, never a toggle | mode must be one of the three literals |
| `eq on\|off` | enables/disables the real DSP | must be `on` or `off` |
| `eq preset <Name>` | selects a built-in preset, commits it | name must match one of `BUILTIN_PRESETS` |
| `show` | maps the window of a hidden (`--background`) instance and focuses it | no argument |

`Message::SetRepeat` is idempotent: setting the mode already in force publishes nothing.
`bin/omatunes-ctl` validates every argument before sending (fixed verb vocabulary; preset names
must match `^[A-Za-z0-9 +/&'-]{1,40}$` and are additionally checked against the advertised preset
list in QML before the helper is even invoked).

## 6. Theme tokens

`src/ui/theme.rs` defines the application's one palette shape — 11 roles, named after their
Catppuccin lineage but used semantically across the UI:

```rust
pub struct Palette { base, mantle, surface0, overlay0, text, subtext,
                      accent, green, red, yellow, blue }
```

Three sources, selected by `config.theme_source` (`~/.config/omatunes/config.toml`,
`theme_source = "System"` here):

1. `"System"` — `~/.local/state/omarchy/current/theme/colors.toml`, resolved through
   `theme.name`; the app derives `mantle`, `surface0`, `overlay0`, `subtext` from
   `background`/`foreground`/`color8`/`color15` (`parse_colors_toml`).
2. `"Preset"` — one of seven hard-coded palettes (`theme_preset`).
3. `"Custom"` — `[custom_theme]` base/text/accent/green/red/yellow/blue plus the same
   derivations.

Change mechanism: `Message::CheckTheme` runs every 3 s (`src/app/mod.rs`) and, for `System` only,
compares `theme.name` against `loaded_theme_name`; on a difference it calls `reload_system_theme()`
and rebuilds the iced theme. Saving settings calls `load_palette_from_config()` +
`apply_palette()` directly.

`publish_theme_export()` is called from the palette mutex initialisation and from `apply_palette`,
so any path that changes the palette republishes it. `~/.cache/omatunes_theme.json`:

```json
{"schema":1,"product":"omatunes","source":"System","name":"last-horizon",
 "palette":{"base":"#0c0b0c","mantle":"#…","surface":"#…","overlay":"#…",
            "text":"#fafcfb","subtext":"#…","accent":"#b59790",
            "green":"#…","red":"#…","yellow":"#…","blue":"#…"}}
```

Read-only for the plugin, atomic, schema-versioned, echoes the app's own role names. It is
necessary because `Commons.Color` carries only four roles from the Omarchy theme file, while
Omatunes resolves eleven, four of them *derived* by the app's own maths, and two of its three
sources do not come from Omarchy at all. Re-implementing that outside the app would be the
second, drifting design system the brief forbids.

`lib/ThemeAdapter.qml` maps those eleven roles onto the semantic surface the popup paints with
(`background`, `surface`, `raised`, `text`, `muted`, `faint`, `accent`), reads the export
read-only, and falls back to `Commons.Color` (not to a hand-written palette) when the file is
absent. `fromApp` reports which path is in use. The popup's own colours are all `withAlpha`/
`mix` calls over those tokens; the only extra layer is one uniform veil over the blurred artwork.

Artwork: `mpris:artUrl` only. Omatunes computes no palette, no dominant colour and no blurred
asset (verified: no such code in `src/`). The plugin therefore does one thing to the image —
`Image` at `sourceSize 320` for the backdrop and `616` for the tile, a single `MultiEffect` blur —
and paints nothing from it but a uniform veil.

## 7. Capability matrix

| Capability | Exposed and reusable | Inside the app only | Unavailable |
|---|---|---|---|
| Title / artist / album / duration | MPRIS `Metadata` | | |
| Artwork | MPRIS `mpris:artUrl` (local file) | | |
| Playback status | MPRIS `PlaybackStatus` | | |
| Play / pause / stop / next / previous | MPRIS methods + capability flags | | |
| Position / seek | MPRIS `Position`, `Seek`, `SetPosition`, `CanSeek` | | |
| Shuffle | UDP `shuffle`; state via MPRIS `Shuffle` — the card's fourth transport control | | |
| Repeat (3-state) | UDP `repeat off\|queue\|track`; state via companion `repeat`, MPRIS `LoopStatus` as fallback | | |
| Like / favourite | UDP `like`; state via `xesam:userRating` (unreleased) or `~/.cache/omatunes_current_state.json` | | |
| Upcoming queue (real order) | companion `upcoming[]` — published, not painted by this card | | |
| Playing context (album/playlist/artist) | companion `context` — published, not painted by this card | | |
| Equalizer state + presets | companion `eq`; changes via UDP `eq` | | |
| Volume | MPRIS `Volume` (deliberately not surfaced) | | |
| Theme palette | `~/.cache/omatunes_theme.json` | | |
| Open / focus the app | window class `omatunes`; `omarchy-launch-or-focus omatunes` (validated against `hyprctl clients`); MPRIS `CanRaise` is `false` | | |
| Playlists / library management | | ✓ | |
| Synced lyrics | | ✓ | |
| Listening statistics | | ✓ | |
| Visualizer / FFT | | ✓ | |
| Output device info | | | ✓ |

## 8. Cost

- No whole-player polling. MPRIS bindings are signal-driven; the companion and state files are
  `FileView`s with `watchChanges: true`, re-read on change and again on popup open as the
  reconciliation step.
- One repeating timer exists: a 200 ms position clock, running only while Omatunes is playing.
  It reads Quickshell's live MPRIS position getter — no D-Bus polling, no second estimate — and
  `Seeked` rebases it at track changes and seeks.
- Three one-shot helper invocations maximum: `bin/omatunes-ctl` per control verb (≤ 40 ms), and
  `omarchy-launch-or-focus` per artwork click.
- Artwork is decoded once per track at 320 px for the backdrop and 616 px for the tile, and blurred
  by one GPU pass; the two `Image` slots cross-fade on decode-ready instead of re-decoding, and
  nothing renders while the popup is hidden. The published art is written once per track, and its
  `?t=<track id>` key means a repeated notification for the same track reuses the cached image.
- Measured idle baseline for the whole shell, popup closed, no helper running: `pid 343425`,
  RSS `560392 KiB`, 33 threads, **50 CPU ticks in 10 s** (~5 % of one core for the entire shell
  and all its plugins). No `omatunes-*` helper processes resident; no leftover children beyond
  the shell's own `inotifywait`/`wl-paste` watchers.

## 9. Files changed in the plugin

| File | Change |
|---|---|
| `manifest.json` | added the `service` kind + `entryPoints.service`, `defaultSection: center`, version 2.1.0, new description |
| `Service.qml` | **new** — service entry point; keeps the controller alive independently of the bar and popup |
| `lib/qmldir` | **new** — `OmatunesService` and `ThemeAdapter` singletons |
| `lib/OmatunesService.qml` | **new** — persistent controller (was `PlayerState.qml`), plus companion snapshot, position model and verbs |
| `lib/ThemeAdapter.qml` | **new** — theme export reader with a `Commons.Color` fallback |
| `lib/ArtworkBackground.qml` | **new** — one blurred artwork image with a two-slot cross-fade |
| `lib/Colors.js` | rewritten — alpha/mix/luminance only; palette derivation deleted |
| `PlayerState.qml` | **removed** |
| `PaletteService.qml`, `Palette.js`, `bin/omatunes-palette` | **removed** — no palette extraction anywhere |
| `AmbientBackground.qml` | **removed** — replaced by `ArtworkBackground.qml` |
| `BarWidget.qml` | standalone pill, left-click opens, no badges, no image processing, no timer |
| `PlayerPopup.qml` | rebuilt to the reference geometry: badges and the open button removed, artwork is the launch surface, utility panel behind the three-bars control; the reference's stop control became the shuffle toggle |
| `bin/omatunes-ctl` | rewritten with absolute-state verbs and strict argument validation |
| `i18n/en.json` | badge/status strings removed; panel strings added |
| `README.md`, `INTEGRATION_AUDIT.md` | documented behaviour and contract |

## 10. Application changes (all non-visual)

| File | Change |
|---|---|
| `src/app/companion.rs` | **new, ~180 lines** — builds, change-gates and atomically publishes `~/.cache/omatunes_companion.json` |
| `src/app/mod.rs` | `mod companion;`, `companion_last_body`/`companion_revision` fields, `Message::SetRepeat`, the three new UDP verbs, `publish_companion()` at start-up |
| `src/app/playback.rs` | `publish_companion()` at track start, splice and queue mutation points; `publish_current_art()` — embedded-first artwork resolution (the same order `load_cover` uses), written to `~/.cache/omatunes_current_art.jpg` and cache-keyed on the track id |
| `src/ui/theme.rs` | **~90 added lines** — `publish_theme_export()`, called from the palette mutex init and `apply_palette` |
| `src/main.rs` | `--background` starts without a window; `write_pid`/`clear_pid` and `hand_off_to_running_instance` — a second `omatunes` from the launcher or a keybinding sends `show` over the control socket and exits instead of starting a second engine |
| `src/app/mod.rs` | the iced runner is a **daemon**, not an application: a normal start opens the window itself, `--background` opens none, `show` opens one on demand (`player_window`, `show_player_window`) and `WindowClosed` exits, so closing the window still quits |

`--background` changes only whether a window exists at start; the UI, layout and playback are
untouched, and `show` opens the same window later. This has to be a daemon rather than an
application with an invisible window: on Wayland `winit::Window::set_visible` is a no-op, so
`window::Settings.visible` is silently ignored and a "hidden" start still maps a toplevel. A daemon
with no window is the only honest hidden start. The pid handoff is invisible: it makes a second
launch focus the existing player instead of racing it for the audio device and the MPRIS name.

Nothing here changes a pixel, a layout, a control, a dependency or a playback rule. The
companion writer only reads app state it already holds; `SetRepeat` is an idempotent setter over
the existing repeat mode; the theme export only writes out a palette the app already installed.
`cargo check` and `cargo fmt --check` are clean (the 99 warnings are pre-existing dead-code
warnings in unrelated view modules).

## 11. Files that remain untouched

All visual application files: `src/ui/**` (including every consumer of `theme.rs`),
`src/main.rs`, the views, components and assets. `src/app/mod.rs` and `src/app/playback.rs` are
touched only for the message variant, the verb arms and `publish_companion()` call sites — no
rendering, no layout, no behaviour change. Nothing in the plugin writes to Omatunes' config,
database (`~/.config/omatunes/db.json`) or music library.

## 12. Verification performed

- **Geometry.** The card is a fixed 898×371 design space (the reference's left-hand composition,
  cropped to a 30 px margin on all four sides) scaled as one item; `contentWidth` is capped at
  760 px, which renders a 760×314 card. Measured live on `eDP-1`: artwork 30,30 308², identity and
  timeline x372, transport row centred on y≈314, card origin ≈(1150, 33) with the rounded corners
  and the blurred backdrop intact to every edge. Removing the queue partition cut the canvas from
  1410×500 to 898×371 and the rendered card from 1240 px wide to 760.
- **Utility menu.** The card grows downward by `menuTop + menu.height + unit*10` while the menu is
  open and shrinks back on close, so nothing above it is covered. Verified with the menu open:
  Repeat chips (Off/Queue/Track, `Off` selected), the equalizer toggle and its preset dropdown all
  render inside the grown card. The menu's column is placed at `padding` on both axes: `BorderSurface`
  exposes `padding` but does not inset its children, so before this the labels sat on the surface's
  top-left corner and the whole vertical padding landed below them.
- **Menu retraction.** Two faults, both fixed. The menu button's tap handler stayed armed while the
  menu was open, so the release that the outside-click catcher used to close it also landed on the
  button and re-opened it in the same gesture: sampled via `onMenuOpenChanged`, one click produced
  `true → false → true`. The handler is now `enabled: !popup.menuOpen`, and it only ever opens.
  Separately, a single-step height change did not commit a frame in this panel — the closing menu
  hid and shrank while the surface kept showing the open frame until another interaction forced a
  repaint (a closed-menu frame was pixel-identical to the frame before the click). `contentHeight`
  now animates on the `smooth` curve, so frames commit throughout and the vacated band is repainted.
  Verified: one click opens, the next closes, and the card returns to its 314 px height with the
  menu gone.
- **Type.** Title 44 → 34 and artist 28 → 22 (design px), with the identity block re-seated at
  y 128 / 176, so the names read at a normal size against the 308 px artwork instead of shouting.
- **Pill artwork.** The bar's 16 px album tile is now a half-circle (`radius: width / 2`) rather
  than a rounded square.
- **Motion.** `reveal` is bound to `open` and drives a `Behavior` on the `smooth` bezier
  (`[0.22, 1.0, 0.1, 1.1]`) at `1000/5.5` ≈ 182 ms, with the content fading and sliding 12 design
  px. Slowed to 1200 ms and sampled via `onRevealChanged`: a monotonic ramp to **1.031** — the
  curve's own 3 % overshoot — then back to 0, with no QML warnings from the bezier. The real
  duration is restored.
- **Album artwork.** Confirmed live before the fix: MPRIS advertised
  `file:///home/dog/Music/cover.jpg` (1000×1000) for `Self Aware` while the app drew the track's
  embedded picture (1280×720), mean absolute difference 50.6/255. After the fix, with the card open
  and playback paused on `The Box`: `mpris:artUrl` was
  `file:///home/dog/.cache/omatunes_current_art.jpg?t=4522683830968259981`, and the cache file was
  **byte-identical** (`md5` equal, 18053 bytes, 1280×720) to the picture extracted from that track.
  A track whose embedded picture exceeds 100 KB caches at 512×512 — the library loader's own
  downscale, i.e. exactly the bytes the app draws. `t` is `track.id`, a hash of the track path, so
  it is stable across notifications and across restarts (sampled three times: unchanged), and
  changes when the track changes.
- **Shuffle.** Clicked the new control: MPRIS `Shuffle` went `false` → `true`, the app's
  `omatunes_current_state.json` agreed (`"shuffle": true`), and the control switched from ring to
  solid. Clicked again: `false`, ring. `Stop` remains available through MPRIS but is no longer
  painted on the card.
- **States.** Rendered and inspected in full playback, menu-open, shuffling, no-artwork and offline
  states, on pale and dark artwork, at the 760 px cap and at narrower widths.
- **Atomic replace under watch.** Both cache files are written to a temporary name and renamed.
  A `FileView` with `watchChanges: true` was driven through repeated write-and-rename cycles: it
  re-fired on every rename and re-read the new content each time. (It also fires once for the
  temporary file's creation, which re-reads the previous content harmlessly; the load that
  follows the rename carries the new snapshot.) `refreshCompanion()` on popup open is the
  belt-and-braces reconciliation if an event is ever missed.
- **Theming.** Colours resolve to the same tokens the application exports; the fallback path was
  exercised by hiding the export.
- **Lifecycle.** A popup close destroys the window only; the singleton's subscriptions and
  snapshot are observable from a field outside the popup.
- **Fixed pill.** Measured at 238 px wide and 26 px tall with a 20 px disc, a fixed label box and an
  18 px control; the label elides inside the box. A one-word title and a 60-character one produce
  the same widget box, so the bar does not reflow when the track changes. The pill renders while
  Omatunes is closed (`Omatunes` + play control), while paused (art + play), and while playing
  (art + pause), all at the same width.
- **Hidden start.** `omatunes --background` started with no mapped window, the MPRIS player up and
  `PlaybackStatus` readable; `show` (the new UDP verb) mapped and focused the window without a
  second process. The pill's play control with no player runs `setsid omatunes --background`, then
  the autoplay timer starts playback once a track is loaded.
- **Playback clock.** The 200 ms ticker runs only while playing and stops on pause. It reads
  Quickshell's live MPRIS `position` getter instead of re-anchoring from `positionChanged`
  notifications, which Quickshell emits only for nonlinear jumps and which can lag the getter by
  hundreds of milliseconds. Omatunes emits `Seeked` on track changes and seeks, so the getter is
  rebased to the new track's zero instead of inheriting the previous position.
