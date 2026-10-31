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
  be culled on either machine.
- **Organise**: file photos into Photos albums.
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
| Shared logic (Rust) | `../core/bestshot-core`: folder scanning with Live Photo grouping, `.bestshot-cull.json`, culling, the ranking engine |
| Swift bindings | `../core/bestshot-ffi` (UniFFI) → `BestShot/Generated/BestShotCore.swift` + `Frameworks/BestShotCore.xcframework` (both generated, not committed) |
| Swift glue | `BestShot/Core/CoreBridge.swift`: the Trash for the sandbox (`FileManager.trashItem`), conveniences |
| Rank | `ViewModels/RankBoard.swift` (pools, saved order, Compare runs), `Views/Rank/*` |
| Folders (Mac) | `ViewModels/FolderCullSession.swift`, `Views/Folder/*` (ImageIO thumbnails, HEIC native) |
| Look | `Utilities/Theme.swift` (tokens shared with `desktop/src/styles.css`), `Views/Design/*` (grease-pencil marks, buttons, contact sheet), `Resources/Fonts` (Archivo, IBM Plex Mono; OFL) |
| Photos library | `Services/PhotoLibraryService.swift`, Triage / Organise |
| Projects | SwiftData models + `Services/*`, the original port of the web app |

### Keys (Mac and iPad keyboards)

Folders: `→`/`P` keep · `←`/`X` reject · `↓`/`Space` next · `↑` previous ·
`⌫`/`⌘Z` undo · `U` clear · `N` next unreviewed · `Z` zoom · `G` grid ·
`I` info · `R` rank.

Compare: `←`/`1` left · `→`/`2` right · `Space` skip · `⌫` undo · `Esc` save
and exit.
