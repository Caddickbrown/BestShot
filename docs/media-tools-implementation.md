# iOS media tools

Implementation scope: iPhone and iPad, per the 11 November 2026 product decision.
The proposal is preserved in [media-tools-spec.md](media-tools-spec.md).
Linux, web, feathered/smart seams, trim controls and advanced HDR preservation are deferred.

## Where to find them

- **Main menu → Tools → Join Videos / Anti-Crop.** The Tools section sits between
  Review and Library, on iPhone and iPad only. Neither tool needs a project.
- **In a project:** select two or more videos and tap **Join Videos** in the
  selection bar; they open in Join Videos in the grid's order.
- **In the viewer** (a project or All Media): the Anti-Crop button on a photo
  opens it in Anti-Crop.

Opened from a project or the viewer, a tool comes up as a sheet with **Done**,
and Esc closes it. Both screens use the shared parts of the light table: the
`ScreenHeader` (eyebrow "Tools", the size or clip count on the right), forms of
`TableSection`s, the `BottomBar` with one red pill, and `EmptyState` with the
sources. The shared tool parts are in `Views/Tools/ToolParts.swift`: the project
picker, `PixelField`, the sources, `ToolBottomBar` (progress, Cancel, then
Save to Photos and Share) and `ToolSheet`.

## Workflows

Sources come from Photos (the pill), Files or a project. Files and Photos videos
are copied directly between URLs; video bytes never pass through `Data`,
`ImportService` or `MediaStore.storeMedia`.

Clip rows are reordered by holding and dragging (VoiceOver has Move earlier /
Move later actions) and removed by swiping left; Undo puts them back. The output defaults to the first source's upright dimensions and a nearby
supported frame rate. Mixed dimensions require explicit confirmation of the
chosen target with padding. All exports are re-encoded MP4 with H.264 or HEVC,
SDR Rec.709; HDR conversion and frame-rate changes are disclosed. Preview and
export consume the same AVFoundation composition, video instructions and audio
mix, built from a Rust-validated millisecond timeline. Whole clips are used.

Crossfades overlap by their configured duration. Sequential black fades divide
the duration between the end of the outgoing clip and beginning of the incoming
clip, without shortening the timeline. Per-join settings override the default.
Audio supports ramps, hard cuts at the midpoint of a crossfade, or silence over
the transition. Clips without audio remain silent. Frame output is quantised to
the selected frame rate, so decoded duration may differ from the millisecond
plan by up to one output frame.

Anti-Crop's coordinates are inclusive start / exclusive end in the upright
original's pixels. Two handles, pixel fields, pinch or double-tap zoom, Before/After,
Undo (one drag of a handle is one step) and Reset are available. PNG exports decode the original, convert to premultiplied
8-bit sRGB RGBA, then stream those pixel rows through Rust. There is no resizing.
Alpha is retained; wide gamut/HDR are converted, and source metadata (including
location and stale thumbnails) is omitted. PNG contains the output sRGB profile.
Exact retained bytes are guaranteed in the Rust RGBA pipeline; source decoding,
colour conversion and alpha premultiplication may change encoded-source values.

There is no saved-settings file. An earlier version exported a JSON document of
the edit; it was taken out because it could only be reopened against the same
originals in the same order. The configurations stay serialisable (`version: 1`)
for when sessions are kept in projects.

## Resource and file safety

Each session owns a private temporary directory. Sources are copied under
security-scoped, coordinated access and remain untouched. Exports render to a
partial file and are renamed only on success; cancellation and errors remove
partials. Completed files stay available for Share (which includes Save to Files)
and Save to Photos until the session closes. Save to Photos asks only for add
access. Only one import/preview/export operation runs
per session. Leaving a tool cancels its current operation.

Before imports and renders, available storage is checked where the platform
reports it. Anti-Crop refuses photos over 256 MiB of decoded RGBA (about 67 MP)
as soon as they are opened, before the band is set. This is an allocation limit, **not** a peak-memory guarantee:
ImageIO/CoreImage and PNG encoding require additional memory. The decoded buffer
and CoreImage cache are released before stitching/encoding. Rust uses one row,
bounded to 64 MiB, with a cancellation check per row. Very large images still
need on-device peak-memory profiling before raising the limit. AVFoundation
streams video decoding/encoding from files.

## Verification

Run `cargo test --manifest-path core/Cargo.toml` for shared geometry, exhaustive
small-image pixel placement, cancellation, serialization and timeline validation.
Rebuild bindings with `PATH="$HOME/.cargo/bin:$PATH" bash apple/scripts/build-core.sh`
(the rustup toolchain supplies cross-target standard libraries), then
`xcodegen generate --spec apple/project.yml`.

`MediaToolsTests` exercises the actual Rust bridge, original-resolution image
export, EXIF orientation, alpha, cancellation and native video transitions.
Platform permission dialogs, Photos cloud downloads, device backgrounding,
codec-specific HDR conversion and large-file peak memory require device testing.

### Verified on 11 November 2026

- Shared Rust workspace: **76 tests passed** (67 core, 3 FFI, 6 media).
- Xcode 26.5, iPhone 17 Pro simulator, iOS 26.5: **116 tests passed**,
  including 8 media integration tests. The media tests took 3.94 seconds.
- Native fixtures cover 8×6 stills (including transparency), EXIF-rotated TIFF,
  portrait H.264 video, all three visual transitions, mixed 48 kHz mono /
  44.1 kHz stereo audio with a silent middle clip, and active video-export
  cancellation. (The saved-settings test went with the feature; a test that one
  drag of a handle is one step of Undo replaced it.) Tiny synthetic fixtures verify correctness, not
  throughput or peak memory for production-sized media.
- The XCFramework and Swift bindings were regenerated for all existing Apple
  architectures. `git diff --check` passed.
- The macOS target also built successfully. Scene-based external-display
  detection and per-window Escape environments remove the reported deprecation
  and actor-isolation warnings; the additional test checks environment isolation.

The simulator UI automation service timed out, so interactive layout and
accessibility review remain manual checks. Physical-device Photos permissions,
HDR appearance, interruption handling and large-media memory/storage profiling
remain pre-release checks. No Linux or web renderer was added.
