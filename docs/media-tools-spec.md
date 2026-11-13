# BestShot — Media Tools Expansion

**Status:** Proposal, partly built. What shipped (iPhone and iPad only, no saved-settings files, Tools in the main menu plus entry points from a project's selection bar and the viewer) is described in [media-tools-implementation.md](media-tools-implementation.md); where the two differ, that document is right.<br>
**Version:** 1.0 · 11 November 2026<br>
**Feature IDs:** BS-MT-001 (Video Join), BS-MT-002 (Anti-Crop)<br>
**Primary targets:** Apple (iOS, iPadOS, macOS), Linux (Tauri); web as a subsequent target<br>
**Design principle:** Local-first, non-destructive, full-resolution output, shared Rust logic where practical.

## 1. Executive summary

Add a **Tools** area to BestShot containing two standalone utilities:

1. **Join Videos** — combine multiple videos in a chosen order, preserve source resolution when clips match, optionally apply configurable transitions (including crossfades) and audio fades, preview and export.
2. **Anti-Crop** — remove a horizontal or vertical strip from the middle of an image, then join the remaining top/bottom or left/right portions without scaling. Offer an exact hard join first, with optional seam blending and later intelligent seam treatment.

The tools complement BestShot's existing culling/organisation workflows without changing their meaning. They should also be usable independently of a BestShot project.

### 1.1 Goals and success criteria

| Goal | Acceptance measure |
|---|---|
| Predictable output | Exported dimensions and timeline match preview and settings. |
| No unintended data loss | Originals never modified; failed or cancelled exports do not replace originals. |
| Full resolution | Anti-Crop uses source pixels, not a downsampled preview; video output dimensions are explicitly controlled. |
| Reliable large-file handling | No whole-video `Data` loading; bounded-memory image processing where feasible. |
| Consistent multi-platform behaviour | Rust owns portable editing configurations, validation, and image operations. |
| Simple initial workflow | Each tool can be used without creating a project. |

### 1.2 Scope boundaries

**In scope:** clip ordering, hard cuts, configurable fades/crossfades, basic audio handling, source inspection, preview, export, horizontal/vertical Anti-Crop, optional seam blending, non-destructive edit settings, cancellation and error reporting.

**Out of scope for first release:** full multitrack editor, arbitrary video effects, titles/subtitles, keyframed animation, generative image filling, video Anti-Crop, cloud rendering, and promises of universally lossless video joining.

## 2. Existing architecture and integration

BestShot has Apple SwiftUI, Linux Tauri and web implementations, plus a shared Rust core (`core/bestshot-core`) and a UniFFI integration path. Apple-side relevant areas include:

- `apple/BestShot/Views/RootView.swift`: navigation/sidebar and detail routing.
- `apple/BestShot/Services/PhotoLibraryService.swift`: PhotoKit integration, currently oriented toward still images.
- `apple/BestShot/Services/ImportService.swift` and `MediaStore.swift`: existing import paths can hold whole files as `Data`; **do not use that approach for large video sources**.
- `apple/BestShot/Services/ExportService.swift`: existing export conventions.
- `apple/BestShot/Views/ShareSheet.swift`: platform sharing conventions.

### 2.1 Recommended division of responsibility

| Layer | Responsibility | Technology |
|---|---|---|
| UI | Source picking, ordering, handles, playback, settings, progress | SwiftUI / Tauri / web |
| Shared edit model | Validation, clip timing, transitions, serialization, output planning | Rust |
| Anti-Crop engine | Pixel-accurate extraction, stitching, optional blending | Rust |
| Apple video renderer | Decode, compose, audio mix, hardware-assisted encode, export | AVFoundation in Swift |
| Linux video renderer | Render timeline and audio transitions | FFmpeg backend |
| Platform I/O | Photos, file permissions, save/share, temp files | Native platform services |

**Decision:** Rust is the shared media engine, not a requirement to replace mature platform video APIs. Avoid introducing FFmpeg into the Apple build merely for architectural uniformity.

### 2.2 Rust crate layout

Suggested structure (adjust to the existing workspace):

```text
core/
├── bestshot-core/                 # Existing core
└── bestshot-media/                # New reusable media crate
    ├── src/
    │   ├── lib.rs
    │   ├── image/
    │   │   ├── anti_crop.rs
    │   │   ├── seam_blend.rs
    │   │   └── geometry.rs
    │   ├── video/
    │   │   ├── timeline.rs
    │   │   ├── transitions.rs
    │   │   └── validation.rs
    │   └── errors.rs
    └── tests/
```

Bridge only small configuration/results across UniFFI. For large image inputs, use paths, platform buffers, or an explicit low-copy interface; avoid repeatedly transferring full-resolution image arrays between Swift and Rust.

## 3. BS-MT-001 — Join Videos

**Priority:** P1<br>
**Purpose:** Combine two or more video clips into a single export, with optional transitions and predictable output dimensions.

### 3.1 User stories

- As a user, I can select two or more videos from Photos, Files or an existing BestShot project.
- I can drag clips into the intended order and remove or replace a clip before export.
- I can see each clip's thumbnail, duration, pixel dimensions, orientation, frame rate (where known), audio presence and file compatibility.
- I can join with hard cuts or choose configurable transitions.
- I can set one transition for all joins, then override individual joins.
- I can preview joins with audio before committing to a potentially lengthy export.
- I can export to Files, Photos (where supported) or the platform share sheet.
- I can cancel a job and retain all original media.

### 3.2 Primary workflow

1. Open **Tools → Join Videos**.
2. Add at least two clips from supported sources.
3. Inspect and reorder clips; resolve any incompatible source warnings.
4. Select output resolution/orientation, codec/preset and frame-rate behaviour as appropriate.
5. Select **Hard cut** (default), **Crossfade**, or **Fade through black**; set duration and audio behaviour.
6. Preview the timeline or selected boundaries.
7. Export, monitor progress, and save/share the result.

### 3.3 Clip list and editing controls

Each clip row shows a thumbnail, filename/title, duration, resolution and warning indicators. Drag-and-drop changes ordering. Each join has a compact transition control. Provide undo for reorder/removal when practical.

**First release:** whole-clip joining; optional start/end trimming is a subsequent enhancement unless straightforward in the existing implementation.

### 3.4 Resolution, orientation and frame rate

- **All sources share the same dimensions and orientation:** default output to those exact pixel dimensions (e.g. 1920 × 1080 remains 1920 × 1080).
- **Mixed dimensions:** require a visible target resolution choice; default to the first clip's dimensions only with an explicit notice. Offer common presets and a custom size where supported.
- **Mixed aspect ratios:** default to **Fit with padding** rather than silently cropping; optionally offer Fill/Crop with an accurate preview.
- **Rotation metadata:** display upright and normalise transforms correctly during rendering.
- **Mixed frame rates:** select a supported output frame rate, with a sensible automatic default; explain possible frame duplication/dropping or cadence changes.
- **Codec/HDR/colour differences:** inspect and warn where transcoding or tone mapping is required. Preserve colour characteristics where supported; never silently claim HDR preservation.
- **Resolution preservation ≠ lossless export:** retaining pixel dimensions does not imply original bitrate, codec, image quality or file size.

### 3.5 Transition system

Transitions are optional. A **hard cut** is the default and requires no transition duration.

| Transition | Behaviour | Initial status |
|---|---|---|
| Hard cut | Clip B starts when A ends | Required |
| Crossfade | Last frames of A overlap first frames of B, opacity ramps A→0 and B→1 | Required |
| Fade through black | A fades to black, then B fades in; transition semantics must be clearly defined | Required |
| Fade in/out of whole export | Optional fades at beginning/end | Follow-up |

**Configuration:**

- Duration range: **0.1–5.0 seconds**, default **0.5 seconds** for fades; duration is zero for hard cuts.
- Scope: **Apply to all joins** plus **per-join override**.
- Audio: **Crossfade**, **Hard cut**, or **Mute during transition**; default audio follows the visual transition where applicable.
- Preview: play a short segment around each join, including audio.
- Duration editing: clamp or reject impossible transitions with a clear explanation rather than silently changing user settings.

**Fade through black definition:** First-release default is a sequential fade-out/fade-in with total configured duration split evenly between the two sides. It need not overlap the clips; therefore it need not shorten the output. This must be distinct from a crossfade in the timeline model and UI.

**Crossfade timeline arithmetic:**

For clip durations `d[i]` and crossfade overlaps `o[j]`:

```text
output_duration = sum(d[i]) - sum(o[j])
```

For three 10-second clips with two 1-second crossfades: `30 - 2 = 28 seconds`.

**Validation:** Each overlap must fit the footage on both sides. For a clip with incoming and outgoing crossfades, the combined overlaps must not exceed its available duration (unless a more sophisticated overlap model is deliberately implemented). Handle clips shorter than the requested fade with a warning and explicit correction.

### 3.6 Audio handling

- Retain audio from each source where present and maintain A/V sync.
- Silent clips are valid and must not cause failures or unexpected noise.
- For crossfades, ramp outgoing audio down and incoming audio up over the overlap; avoid abrupt gain jumps.
- Provide an option for hard audio cuts even when video crossfades.
- Handle sample-rate/channel-layout mismatches via supported conversion.
- **Not first release:** automatic loudness normalisation, ducking, music beds, multitrack mixing.

### 3.7 Export strategy

**Apple:** AVFoundation composition/export with appropriate video instructions and audio mix. Use hardware-accelerated codecs when available. Attempt a compatible passthrough for straightforward hard-cut jobs **only if the platform confirms support**; transitions, resizing, rotation normalisation and incompatible codecs generally require rendering/re-encoding.

**Linux:** Render from the same shared timeline configuration using FFmpeg, with equivalent transition semantics and codec/preset choices.

**Web:** Future scope. Choose between WASM processing for feasible jobs and a server-backed route only if a separate privacy/product decision authorises it. Do not assume browser memory can support large videos.

Exports must write to a temporary destination and publish the finished file only after success. Report meaningful progress, cancellation and errors. Clean up incomplete temporary outputs.

### 3.8 Proposed shared configuration

Illustrative schema; not a committed API:

```json
{
  "schema_version": 1,
  "clips": [
    { "id": "a", "source_ref": "local-ref-a", "in_ms": 0, "out_ms": 10000 },
    { "id": "b", "source_ref": "local-ref-b", "in_ms": 0, "out_ms": 10000 }
  ],
  "output": {
    "width": 1920,
    "height": 1080,
    "fit_mode": "contain",
    "frame_rate": "auto",
    "codec": "auto"
  },
  "default_transition": {
    "type": "crossfade",
    "duration_ms": 500,
    "audio": "crossfade"
  },
  "join_overrides": []
}
```

`source_ref` is a session-scoped or platform-resolved identifier, not an assumption that PhotoKit asset IDs are portable file paths. The platform layer resolves and securely accesses each source.

### 3.9 Acceptance criteria

1. Two matching 1080p clips export as one 1080p video in the selected order.
2. A hard-cut join produces no unintended transition or black frame.
3. Two 1-second crossfades reduce a three-clip timeline by exactly 2 seconds.
4. Per-join overrides take precedence over the global default.
5. Fade-through-black has the documented duration behaviour.
6. Audio stays in sync, including silent clips and mixed audio formats.
7. Portrait and rotated sources export upright with correct dimensions.
8. Mixed resolutions require a visible, deterministic scaling/padding choice.
9. Cancellation leaves source files unchanged and cleans temporary output.
10. Export handles large files without loading full video files into memory.

## 4. BS-MT-002 — Anti-Crop

**Priority:** P1<br>
**Purpose:** Remove a middle strip from a still image and join the remaining regions directly, reducing the image's width or height without resizing the retained pixels.

### 4.1 User stories

- As a user, I can open an image from Photos, Files or BestShot.
- I can choose to remove a **horizontal band** (joining top to bottom) or a **vertical band** (joining left to right).
- I can drag two boundary handles to define exactly what is removed.
- I can zoom and pan for precise selection, with a live before/after view.
- I can choose an exact hard join or an optional blended seam.
- I can export at full retained-pixel resolution without changing the original.
- I can reopen an edit configuration and adjust the cut before final export.

### 4.2 Geometry and exact behaviour

**Horizontal removal:** Remove image rows in `[y1, y2)` and concatenate rows above `y1` with rows at/after `y2`.

```text
Original: width W, height H
Removed band: y1..y2
Output: width W, height H - (y2 - y1)
```

**Vertical removal:** Remove columns in `[x1, x2)` and concatenate the left and right regions.

```text
Original: width W, height H
Removed band: x1..x2
Output: width W - (x2 - x1), height H
```

Example: A 4000 × 3000 image with a 600-pixel horizontal strip removed produces **4000 × 2400** pixels. No scaling is involved.

Coordinates are integer pixels in an **orientation-normalised** image coordinate system. Boundary convention is inclusive start / exclusive end. Reject zero-width removals if they have no meaningful effect, and reject removal of the entire dimension or cuts that leave an empty side where a join is required.

### 4.3 Editing UI

- Original image with a shaded removable region and two draggable boundary guides.
- Toggle **Horizontal** / **Vertical**.
- Numerical controls for start/end pixel coordinates, alongside touch-friendly handles.
- Zoom/pan and a magnified seam preview for precision.
- Side-by-side or toggle **Before / After**.
- Undo/reset and **Export**.
- On small screens, use a downsampled preview; never derive the final export from that preview.

### 4.4 Join modes

| Mode | Behaviour | Priority |
|---|---|---|
| **Hard Join** | Concatenate retained pixels exactly, no blending or resampling | MVP, required |
| **Feathered Seam** | Blend a configurable band around the new boundary | Phase 2 |
| **Smart Seam** | Search for a less conspicuous joining boundary, potentially with local alignment | Research / Phase 3 |

**Hard Join:** Retained decoded pixel values should remain unchanged in a lossless processing pipeline. Re-encoding to JPEG/HEIC can introduce compression differences; do not describe those outputs as pixel-identical. Offer a lossless format (e.g. PNG/TIFF where supported) for exact preservation.

**Feathered Seam:** Configurable blend width (e.g. 0–100 pixels, bounded by available retained content). Explain that blending can create ghosting or soften detail; it does not invent missing content.

**Smart Seam:** A separate, explicitly experimental feature. Avoid implying that arbitrary missing central content can be removed invisibly. Evaluate seam energy, edge continuity and texture before committing to an algorithm.

### 4.5 Colour, orientation and metadata

- Correctly interpret EXIF orientation before cut coordinates are applied.
- Preserve embedded colour profiles and alpha when supported by output format.
- Define a deterministic policy for HDR/wide-gamut sources and warn when conversion is necessary.
- Retain safe metadata where supported, but update pixel dimensions and orientation metadata appropriately.
- Do not blindly copy stale thumbnails, dimensions or location-sensitive metadata.

### 4.6 Performance

Use the Rust engine for geometry, pixel extraction and joining. Decode/export through a compatible image I/O path. Avoid unnecessary full-frame copies, and consider row-wise/tiled output for very large files. A fully decoded image may still require substantial memory depending on the decoder; benchmark peak memory rather than claiming constant memory prematurely.

### 4.7 Proposed configuration

```json
{
  "schema_version": 1,
  "source_ref": "local-image-ref",
  "axis": "horizontal",
  "remove_start_px": 800,
  "remove_end_px": 1400,
  "join_mode": "hard",
  "blend_width_px": 0,
  "output_format": "png"
}
```

### 4.8 Acceptance criteria

1. Horizontal removal produces exactly the calculated height, with unchanged width.
2. Vertical removal produces exactly the calculated width, with unchanged height.
3. Hard Join retains correct pixel order and decoded pixel values in lossless output.
4. Export uses the original-resolution source, not the UI preview.
5. Portrait/rotated images use intuitive, correct coordinate mapping.
6. Alpha and colour profiles are handled correctly for supported formats.
7. Invalid boundaries are rejected with actionable feedback.
8. Large images complete within a measured memory budget or fail gracefully.
9. The original image is never overwritten.
10. Preview and export use the same geometry and mode settings.

## 5. UI and navigation integration

Add a **Tools** section to BestShot's main navigation:

```text
BestShot
├── Triage
├── Organise
├── Rank
├── Projects / Folders
└── Tools
    ├── Join Videos
    └── Anti-Crop
```

On Apple, extend `SidebarSelection`, `MenuSection`, `MenuRow` and `detailView` routing in `RootView.swift`. Match the app's existing theme, navigation, accessibility and keyboard conventions. The tools should be available without requiring a project.

### 5.1 Proposed Apple files

```text
apple/BestShot/
├── Views/Tools/
│   ├── ToolsHomeView.swift
│   ├── VideoJoinView.swift
│   ├── VideoClipRow.swift
│   ├── VideoTransitionEditor.swift
│   ├── AntiCropView.swift
│   └── AntiCropCanvas.swift
├── ViewModels/
│   ├── VideoJoinSession.swift
│   └── AntiCropSession.swift
├── Services/
│   ├── VideoJoinService.swift
│   ├── AntiCropBridge.swift
│   └── MediaOutputService.swift
└── Models/
    ├── VideoJoinConfiguration.swift
    └── AntiCropConfiguration.swift
```

These names were suggestions. As built there is no `ToolsHomeView` (the menu lists the two tools directly), the row and transition editor live in `VideoJoinView.swift`, the canvas in `AntiCropView.swift`, shared parts in `ToolParts.swift`, and both configurations in `Models/MediaToolConfiguration.swift`. Avoid duplicating Rust configuration structures by generating bindings where practical.

## 6. Non-functional requirements

### 6.1 Privacy and safety

- All processing happens on-device by default.
- No automatic uploads or remote transcoding.
- Source media is read-only; edits are represented as configurations until export.
- Use temporary output files and atomic publish/rename where supported.
- Clean up on cancellation, error and abandoned sessions.
- Respect Photos permissions and sandbox/security-scoped file access.

### 6.2 Reliability and resource use

- Show export progress and allow cancellation.
- Validate available storage before expensive jobs where possible.
- Avoid unbounded memory growth with large source files.
- Prevent concurrent jobs from exhausting device resources; start with one active render per session.
- Preserve application responsiveness during processing.
- Emit actionable errors for unsupported codec, permission failure, corrupt media, insufficient storage and invalid geometry.

### 6.3 Accessibility

- Keyboard-accessible clip ordering and numeric Anti-Crop controls.
- VoiceOver labels for boundary handles and transition controls.
- Adequate contrast for cut regions, focus indicators and progress.
- Do not rely on colour alone to indicate warnings.

### 6.4 Project/session persistence

The MVP may use an ephemeral editing session, but configurations should be serializable and versioned from day one. Later, optionally save editing sessions within BestShot projects. Persist source references carefully: platform asset identifiers and temporary URLs may expire or become inaccessible.

## 7. Implementation plan

| Phase | Deliverables | Exit criteria |
|---|---|---|
| **0 — Foundation** | Tools navigation, shared Rust crate, config schema, error model, import/export interfaces | Tool screens launch and configurations validate |
| **1 — Anti-Crop MVP** | Hard Join, horizontal/vertical controls, preview, full-resolution export, Rust tests | Pixel/dimension acceptance tests pass |
| **2 — Video Join MVP** | Clip import/reorder, hard cuts, output sizing, audio retention, Apple export | Multi-clip exports correct and stable |
| **3 — Video transitions** | Crossfade, fade through black, per-join settings, audio ramps, preview | Timeline and audio/video tests pass |
| **4 — Refinement** | Seam feathering, trim controls, batch actions, Linux renderer, performance tuning | Cross-platform parity for prioritised functions |
| **5 — Research** | Smart seam, advanced codec/HDR options, web feasibility | Evidence-based decision on scope |

If configurable fades are essential to the first public Video Join release, treat **Phases 2 and 3 as a single release milestone**. Internal implementation can remain incremental.

## 8. Test strategy

### 8.1 Rust unit/property tests

- Anti-Crop geometry for edge cases and random valid ranges.
- Pixel placement and preservation in lossless buffers.
- Invalid coordinate and dimension rejection.
- Video timeline calculations for hard cuts, crossfades and sequential fade-through-black.
- Per-join overrides, short clips, and overlap validation.
- Configuration serialization/version migration.

### 8.2 Platform integration tests

- iPhone/iPad/macOS Photos and Files import permissions.
- Video files with/without audio, variable frame rates, rotation metadata, mixed resolutions and mixed codecs.
- Correct transitions and audio ramps at each join.
- Save to Photos / Files / share sheet.
- Backgrounding, cancellation, storage exhaustion and recovery.
- Full-resolution still images with EXIF rotation, alpha, wide gamut and large dimensions.

### 8.3 Benchmarks

Track peak memory, processing duration, output dimensions, export bitrate/size and preview responsiveness. Use representative small, medium and large assets. Record device model, OS and input codec to make results reproducible.

## 9. Risks and decisions

| Risk | Impact | Mitigation |
|---|---|---|
| AVFoundation export limitations | Some sources/transitions require full re-encode | Capability checks, supported presets, explicit warnings |
| FFmpeg build/licensing complexity | Larger distribution and compliance burden | Keep Apple native; introduce Linux backend only when needed; review licence choices |
| HDR/colour conversion | Unexpected appearance changes | Explicit compatibility matrix and tests |
| Large-file memory pressure | Crashes or OS termination | URL-based video access, bounded buffers, benchmarks |
| Preview/export mismatch | User distrust and incorrect results | Shared timeline/geometry model and parity tests |
| Seam blending artefacts | Ghosting or visible discontinuity | Hard Join default; clear optional mode labels |
| Cross-platform parity | Divergent export behaviour | Shared Rust validation, golden tests, platform-specific capability flags |

## 10. Open decisions

1. **First release platform:** Apple-first is recommended; confirm whether Linux parity is required at launch.
2. **Transition scope:** This specification includes crossfade and fade-through-black in the first public Video Join release, with implementation phased internally.
3. **Export format defaults:** Choose Apple-appropriate H.264/HEVC presets and Linux equivalents after testing representative inputs.
4. **Source policy:** Decide whether BestShot project media is available directly in both tools at launch or after Files/Photos support.
5. **Anti-Crop blending:** Hard Join is required at launch; feathered and smart seams are later features.

## 11. Definition of done

A feature is complete only when its workflow, validation, export, cancellation, error handling, accessibility basics, automated tests and documentation are implemented. Successful export alone is insufficient.

**Recommended next action:** Commit this specification as `docs/media-tools-spec.md`, then create implementation issues grouped by phases 0–3. This document is a proposal; no GitHub repository changes are implied by generating it.
