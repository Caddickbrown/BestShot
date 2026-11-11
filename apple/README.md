# BestShot for iPhone, iPad and Mac (SwiftUI + Rust core)

A native photo culling and ranking app, fully on-device. It shares its look
(light table to sort, black viewfinder to judge) and its core logic with
[BestShot for Linux](../desktop):

- **Triage**: blast through your **Photos library**. Swipe right to keep, left
  to delete (batched into one system confirmation, then Recently Deleted).
- **Rank**: put your Triage keepers in order, best first. Use **Compare**
  (two photos side by side; pick the better one) or drag photos into place.
  **Save as album** writes the order to a "BestShot · Ranked" album in Photos.
- **Folders** (Mac): cull a folder of files exactly like the Linux app, with
  the same keys, then send rejects to the Trash or a `_Rejected` folder and
  rank the keepers. Decisions and ranking are saved in the folder's
  `.bestshot-cull.json`, **the same file the Linux app uses**, so a folder can
  be culled on either machine. Stars, colour labels and keywords are standard
  XMP (see below), with filters across all of them.
- **Organise**: file photos into Photos albums.
- **Tools** (iPhone/iPad): join videos with cuts, crossfades or sequential black fades; remove a middle image band with Anti-Crop. Sources come from Files, Photos or projects. Exports are local and non-destructive. See [implementation notes](../docs/media-tools-implementation.md) for format, colour and memory limits.
- **Projects / Compare**: the original web-app ranking over imported copies.

## Requirements

- macOS with **Xcode 15+** (iOS 17 / macOS 14 SDKs).
- **Rust** (https://rustup.rs). The build script adds the Apple targets it needs.
- [XcodeGen](https://github.com/yonatanm/XcodeGen): `brew install xcodegen`

## Build & run

```bash
cd apple
./scripts/build-core.sh     # Rust core -> Frameworks/BestShotCore.xcframework + Swift bindings
xcodegen generate           # BestShot.xcodeproj from project.yml
open BestShot.xcodeproj
```

Pick the **BestShot_macOS** scheme (My Mac) or **BestShot_iOS** (an iPhone /
iPad or the Simulator) and press ⌘R. Re-run `build-core.sh` whenever `core/`
changes.

## Tests

```bash
(cd ../core && cargo test)    # the shared logic: scanning, store, culling, ranking
xcodebuild test -project BestShot.xcodeproj -scheme BestShot_macOS -destination 'platform=macOS'
```

`CoreBridgeTests` call the Rust core through the generated bindings
(including reading a `.bestshot-cull.json` exactly as the Linux app writes it);
`ComparisonEngineTests` cover the projects' Compare.

GitHub Actions (`.github/workflows/apple.yml`) runs all of this on a macOS
runner for every push touching `apple/` or `core/`.

## Architecture

| Layer | Where |
|---|---|
| Shared logic (Rust) | `../core/bestshot-core`: folder scanning with Live Photo grouping, `.bestshot-cull.json`, culling, the ranking engine, XMP, the folder catalog and index |
| Swift bindings | `../core/bestshot-ffi` (UniFFI) → `BestShot/Generated/BestShotCore.swift` + `Frameworks/BestShotCore.xcframework` (both generated, not committed) |
| Swift glue | `BestShot/Core/CoreBridge.swift`: the Trash for the sandbox (`FileManager.trashItem`), conveniences |
| Rank | `ViewModels/RankBoard.swift` (pools, saved order, Compare runs), `Views/Rank/*` |
| Folders (Mac) | `ViewModels/FolderCullSession.swift`, `Views/Folder/*` (ImageIO thumbnails, HEIC native) |
| Look | `Utilities/Theme.swift` (tokens shared with `desktop/src/styles.css`), `Views/Design/*` (grease-pencil marks, buttons, contact sheet), `Resources/Fonts` (Archivo, IBM Plex Mono; OFL) |
| Photos library | `Services/PhotoLibraryService.swift`, Triage / Organise |
| Monitor (iOS) | `Monitor/*`: `MonitorDesk` (state), `MonitorKeymap` (keys and hint bar), `MonitorDisplay` (the external-display scene, lock, idle), `PhotoMarks` |
| Projects | SwiftData models + `Services/*`, the original port of the web app |

### Keys (Mac and iPad keyboards)

Folders: `→`/`P` keep · `←`/`X` reject · `↓`/`Space` next · `↑` previous ·
`⌫`/`⌘Z` undo · `U` clear · `N` next unreviewed · `Z` zoom · `G` grid ·
`I` info · `R` rank · `K` keywords · `1`-`5` stars · `0` clear stars ·
`6` red · `7` yellow · `8` green · `9` blue (again to clear) · `⌘⌫` Trash all
red. Marks work in the loupe and the grid; in the grid the arrows move and
`Return` opens the photo. Colour keys stay on the photo, so a second press can
clear it; `→` and `←` set green and red and move on.

Compare: `←`/`1` left · `→`/`2` right · `Space` skip · `⌫` undo · `Esc` save
and exit.

The app opens on its main menu (Triage, Organise, Rank, All Media,
Projects). `Esc` on iPhone and iPad always leads back there: each press lets go
of a field (keeping its text), closes what's on top, then steps back. Nothing is
lost on the way: a Triage session with photos marked for deletion waits behind
Resume Triage, a project's Compare goes to its Proposed Ranking and Esc there
applies it, a tag being typed in the viewer is added, and New Project and
Settings keep what's typed for next time. On an external monitor Esc steps
back the same way, through Triage's start to the monitor's own main menu.

### Metadata

Folders metadata is standard XMP, readable by Bridge, Lightroom, darktable and
exiftool. BestShot reads `xmp:Rating`, `xmp:Label`, `dc:subject` and, as a
fallback, `photoshop:LabelColor`.

- **Sidecars**: `IMG_1.xmp`, or `IMG_1.jpg.xmp` if that's what exists or if a
  raw file already owns `IMG_1.xmp`. Edits are splices, so every other byte
  (Camera Raw settings included) is preserved. If a sidecar exists it wins over
  embedded XMP; a new one starts with a copy of any embedded fields.
- **Embedded XMP** is read from JPEG, TIFF, DNG and PNG. Originals are only
  written if **Settings → Also write into JPEGs** is on.
- **Failures**: a file that can't be parsed, or a read-only sidecar, isn't
  written, and the app says so.
- **Green and red**: green is Keep and red is Reject, written to both the XMP
  and `.bestshot-cull.json`. A label in the XMP beats a saved decision; a saved
  decision with no label shows as an implied colour and writes no XMP.
- **`.bestshot-index.json`** in each folder is a cache of the XMP, keyed on file
  size and modification time, so reopening parses only what changed. Delete it
  freely.
- **Label names**: Settings holds the text written for each colour and the
  mapping from text found in files, in `labels.json` in Application Support.
  **Import from Bridge** lists a folder's label values, read-only, to map them.
  Only the plain colour words are recognised until then, because Bridge's
  names are configurable and red means bin.
