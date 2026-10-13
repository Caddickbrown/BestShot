# BestShot for Linux (Tauri)

A desktop app for culling a folder of photos quickly: flick through every shot,
mark it **Keep** or **Reject**, then send the rejects to the Trash in one go.
Then **Rank** the keepers best-first, with the same side-by-side Compare as the
BestShot web app.

Built with [Tauri 2](https://tauri.app): a Rust backend and a plain
HTML/CSS/JS frontend (no npm or bundler needed).

## Using it

1. **Open folder…** (or drop a folder onto the window). Subfolders and videos
   are included by default; untick them on the home screen if you don't want them.
2. Review. Each decision auto-advances to the next photo:

   | Key | Action |
   |-----|--------|
   | `→` / `P` | Keep |
   | `←` / `X` | Reject |
   | `↓` / `Space` | Next without deciding |
   | `↑` | Previous |
   | `Backspace` / `Ctrl+Z` | Undo |
   | `U` | Clear the decision on this photo |
   | `N` | Jump to the next unreviewed photo |
   | `Z` or click | Zoom to 100% (move the mouse to pan) to check focus |
   | `G` | Grid of everything, filterable by Kept / Rejected / Unreviewed |
   | `I` | Details: date, camera, exposure, dimensions |
   | `?` | Shortcut cheat sheet |

   On a touchscreen, swipe right to keep and left to reject.
3. **Finish…** moves the rejects either to the **Trash** (recoverable from your
   file manager) or into a **`_Rejected`** folder inside the one you're reviewing.
   Kept and unreviewed photos are never touched.
4. **Rank** (`R`): your keepers in order, best first. Drag photos to reorder,
   or press **Compare all** / **Compare new** to pick the better of two photos
   at a time:

   | Key | Action |
   |-----|--------|
   | `←` / `1` | Left is better |
   | `→` / `2` | Right is better |
   | `Space` / `S` | Skip (tie) |
   | `Backspace` | Undo |
   | `Esc` | Save progress and exit |

   Answers are applied transitively (if A beat B and B beat C, A vs C is never
   asked), so a full ranking needs far fewer than every pair. **Compare new**
   only asks about photos that aren't ranked yet and slots them into your
   existing order. Switch to **Not rejected** to rank everything you didn't reject.

Decisions and the ranking are saved as you go in a hidden `.bestshot-cull.json` file in the
folder, so you can close the app and pick up where you left off.

### iPhone photos

- **Live Photos**: `IMG_1234.HEIC` + `IMG_1234.MOV` are treated as one photo.
  Rejecting it moves both, along with any `.AAE` / `.xmp` sidecars.
- **HEIC** needs `heif-convert`: `sudo apt install libheif-examples`
- **Video thumbnails** need `ffmpeg`: `sudo apt install ffmpeg`. Playing HEVC
  video inside the app needs the GStreamer codecs
  (`sudo apt install gstreamer1.0-libav gstreamer1.0-plugins-bad`).

Thumbnails and HEIC conversions are cached in `~/.cache/io.github.caddickbrown.bestshot`
(trimmed automatically above 2 GB).

## Building

Prerequisites (Ubuntu / Zorin / Debian):

```bash
sudo apt install libwebkit2gtk-4.1-dev build-essential libssl-dev \
  libayatana-appindicator3-dev librsvg2-dev
cargo install tauri-cli --version "^2"
```

Then from `desktop/src-tauri`:

```bash
cargo tauri dev                    # run it
cargo test                         # backend unit tests
cargo tauri build --bundles deb    # -> target/release/bundle/deb/BestShot_*.deb
cargo tauri build --bundles appimage
```

Install the `.deb` with `sudo apt install ./target/release/bundle/deb/BestShot_0.2.0_amd64.deb`
and BestShot will show up in your app launcher.

## Layout

```
desktop/
├── src/                 # Frontend (served as-is)
│   ├── index.html
│   ├── styles.css
│   ├── app.js       # Cull: loupe, grid, finish
│   ├── rank.js      # Rank: ranked sheet, drag-reorder, Compare engine
│   └── rank.css
└── src-tauri/
    ├── tauri.conf.json
    └── src/
        ├── lib.rs       # Commands, app state, bestshot:// protocol
        ├── library.rs   # Folder scanning, Live Photo / sidecar grouping
        ├── store.rs     # .bestshot-cull.json persistence (decisions + ranking)
        ├── media.rs     # Thumbnails, HEIC/TIFF previews, EXIF
        ├── video.rs     # Loopback HTTP server for video (WebKitGTK can't stream custom schemes)
        └── cull.rs      # Moving rejects to Trash / _Rejected
```

Images reach the webview through a custom `bestshot://` protocol rather than
raw file access: `bestshot://localhost/{thumb|full}/{session}/{index}`.
Thumbnails are generated on demand by a small worker pool that serves the
newest request first, so the tiles you're looking at load before the ones you
scrolled past.

## Mac and iPhone later

Tauri 2 also targets macOS and iOS, so this code could become the Mac app with
few changes (macOS WebKit displays HEIC natively). The SwiftUI app in
[`../apple`](../apple) already has a Photos-library triage mode for iPhone,
which is likely the better fit there because it works on the Photos library
directly rather than on folders.
