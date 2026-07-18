# BestShot — Native (SwiftUI)

A native, **fully on-device** port of the BestShot media-ranking darkroom for
**iPhone, iPad, and Mac**. No server, no network: media and rankings are stored
locally (SwiftData + the app's Application Support container). This is a
feature-parity rewrite of the Flask + vanilla-JS web app in the repository root.

## Requirements

- **macOS with Xcode 15+** (iOS 17 / macOS 14 SDKs). *This project cannot be
  built on Linux — it requires Apple's toolchain.*
- [XcodeGen](https://github.com/yonatanmn/XcodeGen) to generate the Xcode
  project from `project.yml`:
  ```bash
  brew install xcodegen
  ```

## Build & Run

```bash
cd apple
xcodegen generate          # creates BestShot.xcodeproj from project.yml
open BestShot.xcodeproj
```

Then in Xcode pick the **BestShot_iOS** scheme (iPhone/iPad Simulator) or
**BestShot_macOS** (My Mac) and press ⌘R.

> No XcodeGen? Create a new multiplatform **App** in Xcode (SwiftData enabled),
> then drag the `BestShot/` source folder and `BestShotTests/` into it, set the
> deployment targets to iOS 17 / macOS 14, and add the entitlements file.

## Run the tests

The ranking engine is the one component fully verifiable without a GUI. Run:

```bash
xcodebuild test -scheme BestShot \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

or press ⌘U in Xcode. `ComparisonEngineTests` proves the transitive-inference
port matches the web app's behaviour (A>B, B>C ⇒ A>C inferred; inferred pairs
are never asked; unranked-scope seeding).

## Architecture

| Layer | Files |
|---|---|
| App entry / container | `BestShot/BestShotApp.swift` |
| Models (SwiftData) | `Models/Project.swift`, `Models/MediaItem.swift`, `Models/ExifData.swift`, `Models/Enums.swift` |
| Ranking engine (pure, tested) | `Services/ComparisonEngine.swift` |
| Disk / import / export | `Services/MediaStore.swift`, `ImportService.swift`, `ThumbnailService.swift`, `ExifExtractor.swift`, `ExportService.swift`, `RankingService.swift` |
| Comparison session | `ViewModels/ComparisonSession.swift` |
| UI | `Views/*` (gallery, viewer, comparison, bulk, all-media, settings, help) |
| Utilities | `Utilities/*` (image loading + cache, flow layout, platform shims) |

**Storage model** mirrors the web app's "files + JSON sidecar" split: SwiftData
holds lightweight metadata + relative paths; the actual bytes and generated
thumbnails live under `Application Support/BestShotMedia/<projectUUID>/…` and
`…/BestShotThumbs/…`.

## Feature parity map

Projects & descriptions · import from Photos/Files with SHA-256 duplicate
detection · auto thumbnails (image + video) · gallery with S/M/L grid, media
filter, search, and sort · **drag-to-rank** · **comparison mode with transitive
inference** + results/apply · fullscreen viewer (paging, zoom, EXIF, tags,
notes, slideshow, keyboard) · bulk select → tag / ZIP download / delete ·
export JSON & CSV · download project/selected as ZIP · all-media view ·
light/dark theme · keyboard-shortcut help.

**Intentionally dropped** (was server-specific): URL-based cross-device sync —
replaced by local persistence. All formats the OS can decode preview natively;
exotic web formats (AVI/WMV/FLV/MKV) still import and rank but may show a
placeholder if AVFoundation can't play them.

## Notes / follow-ups

- ZIP uses `NSFileCoordinator(.forUploading)` — no third-party dependency.
- Reorder-by-drag uses a live hover reorder; fine for typical project sizes.
- Video thumbnails grab the first playable frame via `AVAssetImageGenerator`.
