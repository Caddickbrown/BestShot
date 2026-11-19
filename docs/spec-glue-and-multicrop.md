# BestShot — Glue and Multi Crop

**Status:** Agreed with Dan on 19 November (see [Decisions, 19 Nov](#decisions-19-nov), which wins wherever the text below still differs). Being built: Multi Crop first, then Glue.<br>
**Date:** 19 November 2026<br>
**Feature IDs:** BS-MT-003 (Glue), BS-MT-004 (Multi Crop)<br>
**Builds on:** [media-tools-spec.md](media-tools-spec.md) and what shipped in [media-tools-implementation.md](media-tools-implementation.md) (Anti-Crop's RGBA row pipeline, `MediaWorkspace`, `ToolParts.swift`, `bestshot-media`).<br>
**Targets:** Mac (Folders) and iPhone/iPad (Tools, projects, viewer). Linux is left for later (see open questions).

Dan's asks, in his words:

1. **Glue**: "just glue two pictures directly together, maybe with a manual fade".
2. **Multi Crop**: "pull multiple images out of a single image": a scanned page of several prints, a contact sheet, a screenshot with several pictures in it.

Both make **new files**. Neither ever writes to an original, its sidecar or its embedded XMP. That rule comes first, and every section below follows from it.

---

## 0. What they share

The two tools have the same frame. Each is an editor that opens on one or more sources, shows a live preview, and on ↵ writes one or more new photos beside the sources. The parts below are built once and used by both. Section 4 has the estimate for them.

### 0.1 The pipeline (same split as Anti-Crop)

```
 source file(s)                     Swift (platform)                    Rust (bestshot-media)
 ───────────────                    ────────────────                    ─────────────────────
 JPEG/HEIC/PNG/TIFF/RAW ──decode──▶ upright RGBA8 in one working space ─▶ plan: geometry, names, order
                                    (ImageIO, CIRAWFilter, EXIF           compose / warp, row by row
                                     orientation applied)                 (exact copy where unscaled)
                                                                              │
 new file + sidecar ◀──encode + metadata── RGBA8 result (mmapped) ◀───────────┘
 (atomic publish)     (ImageIO, catalog writes the XMP)
```

- **Rust** owns everything that has to come out the same on every platform: the edit model and its validation, the layout and auto-layout rules, output sizes, blend ramps, crop-box geometry, reading order and numbering, output names and collision handling, and the pixel work itself (composite rows, blend, warp a quad). These are plain functions over JSON configurations and RGBA staging files, the same shape as `crop_rgba`. They come with shared test vectors.
- **Swift** owns the screen and the platform: the editors, handles, focus and keys, decoding and colour management (ImageIO, Core Image, `CIRAWFilter`), Vision detection, encoding, Photos and Files, and security-scoped access.
- One call crosses the bridge per operation (`plan`, `compose`, `extract`), never a value per drag (guide: "cross the bridge with whole operations").
- **Preview matches export.** The preview runs the same Rust plan and compose on downscaled staging (longest side 2048 px, so about 1–4 MP, around 10 ms per frame in Rust), redrawn when a drag ends and throttled to about 30 fps while dragging. While a drag is moving, the Glue preview may draw with Core Image transforms from the same plan. When the drag ends it is always redrawn by Rust.

### 0.2 Output files

- **Where:** beside the source in Folders (Mac), meaning the same directory as the first source (Glue) or as the source (Multi Crop). On iPhone and iPad the tools work as they do today: Save to Photos, Share (which includes Save to Files), or into the open project.
- **Written safely:** render to `MediaWorkspace`, encode to `name.partial.<ext>` in the destination directory under file coordination, then rename with `create_new` semantics. A failure or cancel removes the partial. Nothing existing is ever replaced. A name that is taken gets `-2`, `-3`, and so on (rule in Rust, tested).
- **Format:** **JPEG by default, whatever the source** (quality 0.92), including HEIC, PNG and RAW sources (Dan, 19 Nov). The editor's ⋯ options menu offers JPEG, HEIC, PNG and TIFF. The choice is kept per tool between launches.
- **Pixels:** 8-bit RGBA in one working space (see 0.4). Alpha is kept for PNG and TIFF and flattened onto the background colour for JPEG and HEIC.

### 0.3 Metadata on the new files

| What | Glue | Multi Crop | Why |
|---|---|---|---|
| EXIF capture date, camera, lens, exposure | From the **first** source | From the source | So the new photo sorts beside its originals by date, in Folders and in Photos |
| GPS | **Kept**, from the first source (Dan, 19 Nov) | Same | Matches the sources |
| Orientation | Reset to 1 (pixels are already upright) | Same | Otherwise a viewer would rotate it twice |
| Pixel size, DPI | New size; DPI from first source | New size; **scanner DPI kept** | DPI lets a scan's crops print at their real size |
| Embedded thumbnail, maker notes, `crs:*` (Camera Raw / Lightroom develop settings) | **Dropped** | **Dropped** | A stale thumbnail shows the wrong picture. A copied `crs:` crop or develop would re-apply to the new image in Lightroom or ACR |
| Keywords (`dc:subject`) | **Union** of all sources, in first-seen order | Copied from the source | Cheap, and nearly always what's wanted |
| Stars (`xmp:Rating`) | **Not carried** (new photo is unrated) | **Not carried** | It's a new file and hasn't been culled. No "copy stars" option (Dan, 19 Nov) |
| Colour label (`xmp:Label`) | **Not carried** | **Not carried** | In BestShot, red means reject and green means keep. A carried red would put the new photo in the next "Trash the reds" |
| Provenance | `xmpMM:DerivedFrom` (first source) plus `xmpMM:Ingredients` listing every source by relative path | `xmpMM:DerivedFrom` (source) and `bestshot:CropIndex` | Shows what a file was made from. Adobe apps keep these fields |

**How it's written (v1, 19 Nov).** The new file is ours, so its keywords and provenance go into the new file's own embedded XMP as it is encoded (ImageIO `CGImageMetadata`), with no sidecar; a Folders session rescans to pick it up. `Catalog::adopt_new` and sidecar writing, described next, are deferred until a reason appears (a RAW-only output, which can't happen while outputs are JPEG/HEIC/PNG/TIFF).

**Original design.** The new file joins the folder's catalog through one new core call, `Catalog::adopt_new(rel, fields)`. It writes the XMP the way any mark is written: the sidecar always, and into the JPEG too when **Also write into JPEGs** is on, through the existing `write` path. That keeps the sidecar/embedded rules in one place. `xmp.rs` today knows rating, label, label colour and keywords; it needs `DerivedFrom` and `Ingredients` added to `new_packet` (a small extension with its own tests). EXIF and TIFF tags (date, camera, GPS, DPI) are copied by ImageIO when encoding, from a whitelist and never as a blind copy of the source dictionary.

**Bridge.** A new file shows up in Bridge on its next refresh, like any file dropped into the folder. For a JPEG, Bridge reads the embedded XMP and not the sidecar. With "Also write into JPEGs" off, Bridge shows no keywords on a new JPEG, which is how BestShot's JPEG marks already behave today; the spec doesn't change that. For HEIC, PNG and TIFF, Bridge reads the sidecar. Provenance appears in Bridge under File Info ▸ Raw Data only. Nothing a Bridge user relies on (labels, ratings, the Reject rating) is set on the new file, so nothing surprises them.

### 0.4 Colour, RAW, HEIC and orientation

- **Upright first.** Every coordinate in both tools is in the upright (EXIF-orientation-applied) image, the same convention as Anti-Crop. Sources with orientation 5–8 swap width and height before anything else.
- **Working space.** sRGB, unless any source is wide-gamut (Display P3 from an iPhone HEIC, Adobe RGB from a camera), in which case Display P3 is used. The output carries that profile. Everything is converted into it before compositing, so a P3 photo glued to an sRGB photo doesn't shift colour on one side. 16-bit and HDR (gain-map HEIC, HDR AVIF) are converted to 8-bit SDR, and the editor says so in a single line, as Anti-Crop does. Keeping the HDR gain map is out of scope.
- **RAW.** Rendered with `CIRAWFilter` at the camera's default rendering. **It doesn't apply the person's Lightroom or ACR edits**, because BestShot can't read `crs:` develop settings. When a RAW has a JPEG beside it (a RAW+JPEG pair, which `library.rs` already groups), the tool uses **the JPEG by default**, since it's the camera's own rendering and decodes fast, with a toggle "Use the raw". A RAW without a JPEG shows a line: "Raw files use the camera's default look, not your edits."
- **HEIC.** Decoded by ImageIO. The primary image only: auxiliary depth maps, Portrait mattes and Live Photo video don't come along. A Live Photo's still glues as a still.
- **Huge images.** The same rule as Anti-Crop, extended. Each **source** must be at most 67 MP decoded (256 MiB of RGBA) on iPhone and iPad, and 256 MP on the Mac. The **output** must be at most 100 MP on iPhone and iPad and 400 MP on the Mac, and each side at most 65,500 px (JPEG's limit; HEIC's encoder limit is checked at runtime and falls back to JPEG with a notice). The check happens when the tool opens, or the moment a setting would exceed it ("Too big to glue at this size: 142 MP, 100 MP at most here. Turn on Match smaller."), never after export starts. Free storage is checked first, as `MediaWorkspace.requireSpace` does. These limits are allocation guards, not peak-memory promises. They get raised only after profiling on a device.

### 0.5 Undo

- **In the editor:** a local undo stack. One drag, one added or removed box, or one setting change is one step. ⌘Z and ⇧⌘Z (on touch, the Undo and Redo icons). Reset puts it back how it opened.
- **After making files:** a kit notice, "Glued · IMG_0012-glued.jpg" or "Made 4 photos from Scan_004", with **Undo** and ⌘Z. Undo moves the new files and their sidecars **to the Trash** (Mac), removes them from the project (iPhone and iPad), or, for a Photos save, asks Photos to delete the asset (Photos shows its own confirmation; that's the system's rule and can't be avoided). Undo also removes the catalog's entries. Originals are untouched either way, so there's nothing of theirs to restore.

### 0.6 Where they live

| Surface | Glue | Multi Crop |
|---|---|---|
| **Mac, Folders grid** | Select 2–6 photos (multi-select is new, see 0.7) → **Glue** icon in the selection bar, the Photo menu **Glue…** `⌥⌘G`, or ⌘K "Glue" | One photo current → **Multi Crop** icon, the Photo menu **Multi Crop…** `⌥⌘C`, or ⌘K "Multi crop" |
| **Mac, Folders loupe** | Not offered (one photo) unless a selection exists | Same entries, on the current photo |
| **iPhone/iPad, Tools menu** (beside Join Videos and Anti-Crop) | **Glue**: pick 2–6 from Photos, Files or a project | **Multi Crop**: pick 1 |
| **iPhone/iPad, project selection bar** (`BulkActionBar`) | Select 2–6 photos → Glue icon | Select 1 → Multi Crop icon |
| **iPhone/iPad, viewer** | — | Multi Crop icon beside Anti-Crop |
| **Monitor Mode** | ⌘K "Glue" on the current selection. The editor draws on the monitor and works from the keyboard | ⌘K "Multi crop". Detection, Tab between boxes and arrow-key nudging work without a pointer; drawing a fresh box wants a pointer or the phone |
| **Triage** (Photos) | Not in v1: Triage is one-photo-at-a-time. Reach it from Tools | Same |

The Mac gains a **Tools** entry too (Tools is iPhone and iPad only today). It's wanted for Glue and Multi Crop on files outside a Folders session, but it isn't needed for v1 (Q9).

Icons, following the guide's icons over text (minimal stroke, 44 pt, tooltip and accessible label): Glue uses `rectangle.split.2x1` with a join mark, or the closest set glyph; Multi Crop uses `crop` over `square.on.square`. The editor's only text button is its primary action, **Glue** or **Make 4**. Everything else is an icon.

### 0.7 Multi-select in Folders (new, Mac)

Folders has one "current" photo today and no selection. Glue needs one. The selection model belongs in `FolderCullSession` and `FolderCommand`. **This spec doesn't touch `FolderCullView.swift`; it's being edited for a CI fix.**

- ⌘-click toggles a photo. ⇧-click selects a range. ⇧← and ⇧→ (⇧↑ and ⇧↓ in the grid) extend from the current photo. ⌘A selects everything visible (respecting filters). Esc clears the selection first, then does what Esc does now.
- When anything is selected, a bottom selection bar shows the count ("3 selected") and icon actions: Glue, plus stars and label for all, which is a natural follow-on but outside this spec.
- The selection order is the **grid order**, not the click order, so Glue's left-to-right matches what's on screen. The order can be changed in the editor.

---

## 1. Glue

### 1.1 What it is

Glue puts 2–10 photos edge to edge in a row, a column or a grid, or lets them be placed freely ("jagged") on a background. They can butt straight up against each other, sit apart with a gap, or overlap with a hand-placed seam and an optional fade across it. The output is one new photo. The intent is quick and manual. It's not a panorama stitcher (see 1.9).

### 1.2 Flow

1. Select two or more photos (Folders grid, a project, or the Tools picker) and choose **Glue** (`⌥⌘G` on the Mac).
2. The editor opens with a preview already laid out:
   - **Layout** is picked automatically: whichever of side by side or stacked gives an output closest to square (smallest `|ln(aspect)|`), ties going side by side. In practice two portraits sit side by side, two landscapes stack, and a mixed pair sits side by side. `o` flips it (Q1 on whether two landscapes should default to side by side instead).
   - **Size:** *Match smaller* by default. Side by side, every photo is scaled to the shortest height; stacked, to the narrowest width. Nothing is scaled up, so nothing gets blurry.
   - **Join:** butted, with no gap and no overlap.
3. Adjust if wanted:
   - Reorder (drag a photo; `⌘←`/`⌘→` moves the focused photo earlier or later).
   - **Size:** Match smaller · Match larger (scales up, with a warning icon on any photo scaled past 150%) · Keep pixels (no scaling; shorter photos are aligned to start, centre or end and the rest filled with the background colour).
   - **Join slider:** one control running from **Gap** (left, 0–200 px of background colour between photos) through **0** to **Overlap** (right, 0 up to half the narrower photo). A gap and an overlap can't both be set.
   - **Overlap only:** a **seam** line inside the overlap, dragged directly, which sets where the change happens (default: the middle). A **fade width**, 0 up to the whole overlap: 0 is a straight edge (a hard cut at the seam), anything above 0 is a feathered blend centred on the seam. The ramp is smoothstep, not linear, which hides the start and end of the blend.
   - **Offset:** slide a photo across the join (up or down when side by side, left or right when stacked) to line up a horizon. The output is then cropped to the band every photo covers (default) or padded with the background colour (toggle).
   - **Border:** an optional outer border, 0–200 px, in the background colour.
   - **Background colour:** white, black, or picked. It's used for the gap, the border and Keep-pixels fill.
   - **Before/after:** `\` shows the photos butted with no settings (just the order and the layout) for comparison.
4. **Glue** (↵) writes `IMG_0012-glued.jpg` beside the first photo. On the Mac the editor closes, the new photo appears in the grid (after the first source in natural order) and becomes current, and a notice says "Glued · Undo". On iPhone and iPad it stays open with Save to Photos and Share, as the current tools do.

For three or more photos, every join shares one Join value and one fade width. Each seam can be dragged on its own, and each photo can be offset on its own. A per-join override, as Join Videos has, is left for later unless asked for.

### 1.3 Sketches

**Mac (Folders, a sheet over the grid, or a full window on a small screen):**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ‹  Glue · 2 photos                                    7,412 × 4,000 · JPEG ▾  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────────────────────┬┬──────────────────────────────┐          │
│   │                              ││                              │          │
│   │                              ││  ◀ seam (drag)               │          │
│   │        IMG_0012              ││         IMG_0013             │          │
│   │                              ││                              │          │
│   │                              ││                              │          │
│   └──────────────────────────────┴┴──────────────────────────────┘          │
│              overlap 400 px ├────┼────┤ fade 240 px                         │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ [⇆ ⇅]  Size [Smaller ▾]  Gap ◀──────●──────────▶ Overlap   Fade ◀──●───▶     │
│ Offset ↕ −12 px   Border 0   Background ○●◐   ↶ ↷ ⟲          [  Glue  ↵ ]   │
├─────────────────────────────────────────────────────────────────────────────┤
│ o layout  ←→ seam  ⇧←→ ×10  ↑↓ offset  -/= overlap  [ ] fade  \ before  ↵   │
└─────────────────────────────────────────────────────────────────────────────┘
```

**iPhone (portrait; the preview on top, controls in a sheet that can be pulled up):**

```
┌─────────────────────────┐
│ ‹  Glue          ⇆  ⋯   │  ← solid bar into the safe area
├─────────────────────────┤
│  ┌──────────┬┬────────┐ │
│  │  0012    ││  0013  │ │
│  │          ││        │ │
│  └──────────┴┴────────┘ │
│   pinch to zoom the seam│
├─────────────────────────┤
│ ━━━━  (grabber)         │
│ Size      Smaller    ›  │
│ Gap ◀────●────▶ Overlap │
│ Fade ◀──●──────▶        │
│ Offset  ↕  −12 px   ± │
│ Background  ○ ● ◐       │
├─────────────────────────┤
│ ↶  ↷        [  Glue  ]  │  ← bottom bar, clear of the home indicator
└─────────────────────────┘
```

iPad shows the Mac layout, with the controls in a trailing column in landscape.

### 1.4 Keys (in the Glue editor)

Kit keys keep their meaning (↵ go, Esc back, ⌘Z undo, ? keys). The single letters apply only in the editor and only when no field has focus.

| Key | Action |
|---|---|
| `o` | Flip layout (side by side ⇄ stacked) |
| Tab / ⇧Tab | Focus the next or previous photo (and the join after it) |
| ← → (↑ ↓ when stacked) | Move the focused seam 1 px; with ⇧, 10 px |
| ↑ ↓ (← → when stacked) | Offset the focused photo across the join 1 px; with ⇧, 10 px |
| ⌘← / ⌘→ | Move the focused photo earlier or later |
| `-` / `=` | Join: less or more overlap (negative = gap), 10 px a step |
| `[` / `]` | Fade width narrower or wider (no groups here, so the kit's group keys are free) |
| `m` | Cycle Size: Smaller → Larger → Keep pixels |
| `\` | Hold for before (butted, no settings) |
| ↵ | Glue |
| Esc | Leave. The settings are kept for this selection until the app quits, so reopening resumes |
| ⌘Z / ⇧⌘Z | Undo / Redo in the editor |

### 1.5 Data model (Rust)

```json
{
  "schema_version": 1,
  "sources": [
    { "ref": "IMG_0012.JPG", "width": 4000, "height": 6000 },
    { "ref": "IMG_0013.JPG", "width": 4000, "height": 6000 }
  ],
  "layout": "auto",
  "size": "match_smaller",
  "align": "centre",
  "join_px": -400,
  "fade_px": 240,
  "seams": [ { "position": 0.5 } ],
  "offsets_px": [0, -12],
  "offset_fill": "crop",
  "border_px": 0,
  "background": "#FFFFFF",
  "output": { "format": "same", "quality": 0.92 }
}
```

- `plan(config) → Plan` returns the resolved layout, each source's scaled size and placement, the canvas size, each overlap's range, and each blend ramp's start and end in output pixels. That's everything Swift needs to stage the inputs and draw the handles. It's pure and fully tested.
- `compose_rgba(plan, staged_inputs[], destination, cancelled)` streams output rows. Each row takes the right span from each staged input, blends the overlap with the ramp, and fills the gap, border and padding. Memory is about one row per input. Pixels outside any blend or fill are **copied exactly** (tested, as Anti-Crop is).
- **Scaling:** Rust resamples each source to its planned size (Lanczos-3, separable, two passes over the staging file) so preview and export agree and a later Linux shell gets it for free. The plain alternative is vImage in Swift, which is faster. Measure first, and if Rust meets the budget in 1.7, keep it in Rust (guide: one answer, in the core).

### 1.6 Edge cases

- **Mixed portrait and landscape:** handled by auto-layout and Match. Keep pixels shows the fill clearly.
- **Very different sizes** (a 12 MP phone photo and a 45 MP camera photo): Match smaller scales the 45 MP down, which is fine. Match larger would scale the phone photo up about 2×, so it gets the warning icon.
- **EXIF-rotated sources:** made upright before planning. Tested with orientation 6 and 8 fixtures.
- **Alpha** (PNG screenshots): kept for PNG and TIFF output, flattened onto the background for JPEG and HEIC.
- **Same photo twice:** allowed (a mirror-style join is a real use), so no error.
- **A video in the selection:** the Glue action is disabled with a tooltip, "Glue is for photos. Join Videos joins videos." On iPhone and iPad the selection bar already offers Join Videos for videos.
- **Offset crops too much:** an offset that would leave under 10% of the height shared is refused, and the handle stops there.
- **Overlap of more than half the narrower photo:** the slider stops there. Past that point a seam can't sit inside both photos.
- **Six photos at full size past the output limit:** Glue says so as the setting is reached (0.4) and suggests Match smaller.
- **A source changed on disk while the editor is open** (Bridge relabelling it, say): the pixels were staged when the editor opened, so the output uses what was opened. Labels don't matter because they're not carried.

### 1.7 Performance budgets (to measure, not assume)

| Action | Mac (M-series) | iPhone (A17-class) |
|---|---|---|
| Open editor with 2 × 24 MP JPEG (decode to previews, first preview) | < 0.5 s | < 1 s |
| Preview update after a drag ends | < 30 ms | < 60 ms |
| Export 2 × 24 MP → ~45 MP JPEG | < 3 s | < 6 s |
| Peak memory during export, 2 × 24 MP | < 600 MB | < 450 MB |

Full-resolution decode happens only on **Glue**. The editor works on ≤ 2048 px previews from `CGImageSourceCreateThumbnailAtIndex`, the same as Anti-Crop.

### 1.8 Tests

- **Rust:** auto-layout vectors (portrait pairs, landscape pairs, mixed, square, three or more); canvas size for every Size, Join and offset combination; exact copy outside blends (exhaustive on small images); ramp values at known pixels (0, ½ and 1 at the ends and seam; straight edge when fade = 0); gap, border and fill colour; offset-crop band; refusal of an overlap past half, an over-limit canvas and a zero-pixel source; cancellation removes the partial; schema round-trip; name collisions (`-glued`, `-glued-2`). Vectors go in `core/bestshot-media/tests/vectors/glue.json` so any shell can replay them.
- **Swift integration** (`MediaToolsTests`, plus a new `GlueTests`): EXIF-rotated inputs; a P3 HEIC plus an sRGB JPEG giving a P3 output with no shift on the sRGB side (sample a flat patch); HEIC and PNG outputs; RAW+JPEG pair uses the JPEG; metadata (date and GPS from the first source, keyword union, **no rating or label**, `DerivedFrom` and `Ingredients` present, no `crs:`); the catalog sees the new file with a sidecar, and the JPEG has embedded XMP only with the setting on; Undo moves the output and sidecar to the Trash; **the originals' bytes and their sidecars' bytes are identical before and after** (hash check, every test).
- **Keymap:** pure tests of the editor key → command mapping, like `FolderKeymapTests`.
- **Device:** a 24 MP pair on a real iPhone and iPad (peak memory, time), and a screen check scrolled and at rest in light and dark, per the guide.

### 1.9 Not included, and the cheap option

- **No automatic panorama stitching.** No feature matching, homography warps, cylindrical projection or exposure matching. Glue never moves pixels except to scale them uniformly and slide them along the join.
- ~~No grids in v1.~~ **Grids and free layouts are in v1** (Dan, 19 Nov): see Decisions.
- **Option, cheap with Vision: "Line up".** An icon that runs `VNTranslationalImageRegistrationRequest` on the two neighbouring previews and sets **overlap and offset** from the translation it finds. It's a pure translation (no rotation or warp), on 2048 px previews, in well under a second. It fits Glue's model exactly, since it only fills in the numbers the person could set by hand, and the person can still drag afterwards. If the result is implausible (overlap outside the allowed range), it says "Couldn't line these up" and changes nothing. About +1 day. **In v1** (Dan, 19 Nov). Anything beyond this (`VNHomographicImageRegistrationRequest` with warping and blending) is panorama territory and out of scope.

---

## 2. Multi Crop

### 2.1 What it is

Multi Crop takes one image and makes several photos from it. On a scanned page of prints, a contact sheet or a screenshot of a grid of pictures, the person places several crop boxes (or lets the app find them), straightens each, and on ↵ gets one new photo per box. The source is untouched.

### 2.2 Flow

1. With a photo current (Folders loupe or grid, the viewer, a project, or Tools → pick one), choose **Multi Crop** (`⌥⌘C`).
2. The editor opens on a preview and **runs Find straight away** (Q10 on whether it should run on open). Found photos show as numbered boxes. If nothing is found, the editor opens empty with the hint "Drag to draw a box, or press F to find photos." Find never runs on its own after that.
3. Adjust:
   - **Draw:** drag on empty space. **Add:** `n` adds a box in the centre, the same size as the last one. **Duplicate:** ⌘D, offset to the next free spot in the row (good for contact sheets).
   - **Move or resize:** drag the box or its eight handles; arrow keys nudge.
   - **Rotate:** drag the rotation handle above the box, or press `[` and `]` (0.1°; with ⇧, 1°). ⌘[ and ⌘] turn the box's **output** 90° (for a print scanned on its side). Snaps at 0° and to the found angle.
   - **Perspective:** `p` switches a box between a rotated rectangle and a **four-corner** box, each corner dragged on its own. The output is made rectangular (for a photo shot on a table at an angle, or a page in a screenshot drawn in perspective).
   - **Trim:** one value for all boxes, 0–30 px (default 0; 4 px after Find), shaving the inside edge to lose the sliver of scanner bed or white border a box often catches.
   - **Snapping:** edges snap to found edges, image edges and other boxes' edges and sizes (so a contact sheet's boxes come out the same size), within 6 screen pt. Hold ⌥ (Mac) to place freely. On touch it always snaps, with a light haptic.
   - **Order:** boxes are numbered in reading order (rows top to bottom, left to right within a row, with a row tolerance of half the median box height), done in Rust. Press `#` and then the boxes in turn to renumber them, or drag a box's number chip onto another to swap them.
   - **Remove:** ⌫ removes the focused box (one undo step). Never red: it isn't a delete of anything that exists.
4. **Make 4** (↵; the button says the count) writes `Scan_004-1.jpg` … `Scan_004-4.jpg` beside the source. On the Mac, the outputs appear in the grid after the source, the **source stays current**, and a notice says "Made 4 photos from Scan_004 · Show · Undo" (Show selects them). On iPhone and iPad, Save to Photos saves all of them, and Share shares all of them.

### 2.3 Sketches

**Mac:**

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ‹  Multi Crop · Scan_004.tif                       4 photos · TIFF ▾ · 600 dpi │
├──────────────────────────────────────────────────────────────────────────────┤
│   ┌────────────────────────────────────────────────────────────────────┐     │
│   │ ┌─①──────────────┐        ┌─②──────────────┐                        │     │
│   │ │               │        │  ↻             │                         │     │
│   │ │   (photo)     │        │   (photo, 2°)  │                         │     │
│   │ └───────────────┘        └────────────────┘                         │     │
│   │                                                                     │     │
│   │ ┌─③──────────────┐        ◇─④─────────────◇   ← four-corner box     │     │
│   │ │               │        ╱   (photo)       ╲                         │     │
│   │ │   (photo)     │       ◇───────────────────◇                        │     │
│   │ └───────────────┘                                                   │     │
│   └────────────────────────────────────────────────────────────────────┘     │
├──────────────────────────────────────────────────────────────────────────────┤
│ ⌕ Find   ＋  ⧉  ⌫   ↻ 90°   ◇ Perspective   Trim 4 px   1·2·3 Order          │
│ Output beside the source · Scan_004-1 … -4                ↶ ↷ ⟲ [ Make 4 ↵ ]  │
├──────────────────────────────────────────────────────────────────────────────┤
│ f find  n new  ⌘D dup  ⇥ next box  ←→↑↓ move  ⌥ resize  [ ] rotate  p corners  │
└──────────────────────────────────────────────────────────────────────────────┘
```

A strip of the outputs at their real proportions, as they'll be written (after straightening), can be shown under the canvas with `v`. It's worth having, because it's where a box that's upside down or catching the scanner lid shows up.

**iPhone:**

```
┌─────────────────────────┐
│ ‹  Multi Crop    ⌕   ⋯  │
├─────────────────────────┤
│ ┌─①────┐  ┌─②────┐      │
│ │      │  │      │      │
│ └──────┘  └──────┘      │
│ ┌─③────┐  ◇─④───◇       │
│ │      │  ╲      ╱       │
│ └──────┘   ◇────◇        │
│  two fingers: pan/zoom   │
├─────────────────────────┤
│  ＋  ⧉  ⌫  ↻  ◇   1·2·3 │
│ ↶ ↷        [ Make 4 ]   │
└─────────────────────────┘
```

On touch, one finger on empty space draws a box and two fingers pan and zoom. Tapping a box focuses it. A focused box's handles are 44 pt hit targets even when they look smaller. A loupe magnifier appears while a corner is being dragged.

### 2.4 Keys (in the Multi Crop editor)

| Key | Action |
|---|---|
| `f` | Find photos (Vision). Replaces boxes only if none have been edited, otherwise adds the ones not already covered |
| `n` | New box (kit `n` = New) |
| ⌘D | Duplicate the focused box |
| Tab / ⇧Tab | Next / previous box, in reading order |
| ← → ↑ ↓ | Move the focused box 1 px; with ⇧, 10 px |
| ⌥ + arrows | Resize from the bottom-right edge; with ⇧⌥, 10 px |
| `[` / `]` | Rotate −0.1° / +0.1°; with ⇧, 1° |
| ⌘[ / ⌘] | Turn the output 90° left / right |
| `p` | Rectangle ⇄ four corners |
| `#` | Renumber: then press or click boxes in their new order; Esc ends |
| `v` | Show or hide the output strip |
| ⌫ | Remove the focused box |
| ↵ | Make |
| Esc | Unfocus the box, then leave. The boxes are kept for this source until the app quits, so reopening resumes |
| ⌘Z / ⇧⌘Z | Undo / Redo in the editor |

### 2.5 Detection (Swift, Vision)

- **`VNDetectRectanglesRequest`** on the 2048 px preview with `maximumObservations = 20`, `minimumSize = 0.08` (of the shorter side), `minimumAspectRatio = 0.2`, `quadratureTolerance = 20°`, and `minimumConfidence = 0.6`. It returns quads in normalised coordinates, which Swift maps to upright source pixels and hands to Rust.
- **Rust then tidies them:** it drops quads mostly inside another (nested frames, a photo's own border), merges near-duplicates (IoU > 0.85), turns quads whose corners are within 3° of right angles into **rotated rectangles** (the common case for a flatbed scan), keeps the rest as four-corner boxes, sorts by reading order and applies the default trim. That's one call: `tidy_boxes(quads, image_size) → boxes`.
- **`VNDetectDocumentSegmentationRequest`** finds one document, so it isn't the main detector. It's a fallback when the rectangle request finds nothing in a photo of a single print on a table.
- **Screenshots:** rectangle detection also finds buttons and panels in UI screenshots. `minimumSize = 0.08` filters most of them. Anything left is a box to delete with ⌫. Detection is a starting point, not a promise.
- **Which way up:** Vision doesn't know whether a print is upside down. An option, which is cheap: run `VNDetectFaceRectanglesRequest` on each box's preview at 0°, 90°, 180° and 270°, and pre-set the 90° turn where faces are only found at one orientation. About +0.5 day, worth it for old family scans (Q11).
- **Linux:** Vision is Apple-only. A Rust detector (estimate the background colour from the border, threshold, connected components, min-area rectangle) would suit flatbed scans and work everywhere, but it would find different boxes from Vision's. Not in v1 (Q12).

### 2.6 Data model (Rust)

```json
{
  "schema_version": 1,
  "source": { "ref": "Scan_004.tif", "width": 7016, "height": 4960 },
  "boxes": [
    { "id": "b1", "kind": "rect", "cx": 1210.5, "cy": 980.0, "w": 1800, "h": 1200, "angle_deg": 0.0,  "turn": 0 },
    { "id": "b2", "kind": "rect", "cx": 3410.0, "cy": 1002.0, "w": 1790, "h": 1205, "angle_deg": 2.1, "turn": 0 },
    { "id": "b4", "kind": "quad", "corners": [[3000,3000],[4900,3050],[4950,4300],[2950,4250]], "turn": 90 }
  ],
  "order": ["b1", "b2", "b3", "b4"],
  "trim_px": 4,
  "naming": { "pattern": "{stem}-{n}", "start": 1 },
  "output": { "format": "same", "quality": 0.92, "folder": "beside" }
}
```

- `plan(config) → Plan` gives each box's output size (a rotated rect's own w × h after trim; a quad's size from the average of its opposite edges, rounded), its name, and whether it's an **exact copy** (axis-aligned, 0°, integer edges, no turn other than 90° steps) or **resampled**. It validates that every box has at least 16 px a side, that the output is within the limits and that names don't collide.
- `extract_rgba(plan, box_id, staged_source, destination, cancelled)`:
  - **Exact copy:** row slices straight from the staging file, the same code path as Anti-Crop, so it's lossless. 90° turns are a row/column transpose and stay exact.
  - **Resampled** (any angle or quad): an inverse perspective map from output pixel to source point, bicubic sampling, from the staging file **memory-mapped** (random access is needed; the source is read-only). Rust owns this so the preview strip and the export are the same pixels, and a later Linux shell gets it for free. Core Image's `CIPerspectiveCorrection` is the plain alternative if the Rust warp misses the budget in 2.8.
- **Naming:** `{stem}-{n}`, zero-padded to the width of the count (`-01` … `-12` when there are 10 or more), with collisions moving the whole set on (`Scan_004-1` taken → that box becomes `Scan_004-1-2`, with no renumbering of the others). `Scan_004-1.jpg` sorts straight after `Scan_004.tif` in `natural_cmp`, so the crops sit beside their source in Folders.

### 2.7 Edge cases

- **Big scans.** An A4 scan at 600 dpi is about 35 MP, which is fine everywhere. At 1200 dpi it's about 140 MP: over the iPhone and iPad limit (the editor says so on open: "This scan is 140 MP, 67 MP at most on iPhone and iPad. Open it on the Mac, or scan at 600 dpi.") and fine on the Mac. Staging needs about 4 bytes × the source's pixels of free disk, checked first.
- **TIFF scans with 16 bits per channel:** converted to 8-bit, with a one-line notice. Keeping 16-bit TIFF output is a later option, since Rust's row code is 8-bit today (Q8).
- **Scanner DPI** is copied into every output, so a 6×4" print scanned at 600 dpi comes out as a 3600 × 2400 file that knows it's 6×4".
- **Capture date:** a scan's EXIF date is the scan date, not when the print was taken. The outputs copy what the source has. Setting a different date is out of scope (Q13 notes it).
- **EXIF-rotated source** (a phone photo of prints on a table): made upright first, as everywhere.
- **Boxes past the edge:** clamped to the image while dragging. A quad may not self-intersect: the corner stops before it would cross.
- **Overlapping boxes:** allowed, since two crops of one region is legitimate. Find's tidy step is what drops near-duplicates.
- **One box:** allowed. It's a single straightened crop, a handy side effect.
- **A RAW source:** uses the JPEG sibling by default (0.4); output is JPEG.
- **Alpha PNG screenshot:** kept for PNG output.
- **The source is a video:** not offered.

### 2.8 Performance budgets

| Action | Mac | iPhone |
|---|---|---|
| Open and Find on a 35 MP TIFF scan | < 0.8 s | < 1.5 s |
| Drag a box (preview redraw) | 60 fps (draws on the preview, no Rust in the loop) | 60 fps |
| Output strip refresh after a drag ends | < 50 ms | < 100 ms |
| Make 6 crops from a 35 MP scan (all rotated, bicubic) | < 3 s | < 6 s |
| Peak memory, 35 MP scan | < 500 MB | < 400 MB |

Crops are made one after another, so cancelling stops before the next. A cancelled run removes every file it made, and nothing half-made stays behind.

### 2.9 Tests

- **Rust:** `tidy_boxes` vectors (nested quads dropped, duplicates merged, near-rectangles become rects, the reading order of grids with uneven rows); output size for rects, rotated rects and quads; exact copy is byte-identical (exhaustive on small images, including 90°, 180° and 270° turns); warp of a synthetic checkerboard drawn in a known perspective recovers the squares within 1 px; trim; clamping; the 16 px minimum; naming with padding and collisions; cancellation leaves no outputs; schema round-trip. Vectors go in `core/bestshot-media/tests/vectors/multicrop.json`.
- **Swift integration:** Find on a fixture scan of four prints on white (a checked-in 1600 px fixture made from public-domain or synthetic images; guide: public repos hold no licensed assets) finds exactly four boxes in reading order; DPI kept; TIFF, JPEG and HEIC outputs; metadata rules as in Glue (keywords carried, no stars or label, `DerivedFrom` and `CropIndex`, no `crs:`); catalog adoption and sidecars; Undo moves all outputs to the Trash; **source and sidecar hashes unchanged**.
- **Keymap:** pure tests of the editor key → command mapping.
- **Device:** a real 600 dpi scan on the Mac; a phone photo of prints on a table on an iPhone; touch handles at 44 pt; VoiceOver labels ("Box 2 of 4, rotated 2 degrees, adjustable"), with the VoiceOver adjust actions moving the box.

### 2.10 Not included

- Content-aware fill of the corners a rotation leaves. A rotated rect is always cut **inside** the source, so there's nothing to fill.
- Automatic colour restoration or fade correction of old prints.
- Splitting video frames, or PDFs with several pages (a PDF's first page could be decoded later if asked).
- Batch Multi Crop over many scans at once. One source per editor in v1, but **"Use last crop" is in v1** (Dan, 19 Nov): it puts the previous image's boxes on this one.

---

## 3. What goes in Rust vs Swift (summary)

| | Rust core (`bestshot-media`, `bestshot-core`) | Swift (Apple shell) |
|---|---|---|
| Edit models | Glue and Multi Crop configs, validation, schema versions | Building them from the UI state |
| Layout and geometry | Auto-layout, scaling plan, overlap/seam/ramp, offsets; box geometry, quads ↔ rects, reading order | Drawing handles from the plan |
| Pixels | Resample, composite, blend, exact copy, perspective warp on RGBA8 staging files | Decode (ImageIO, `CIRAWFilter`), colour conversion to the working space, encode |
| Detection | `tidy_boxes` (dedupe, rectify, order, trim) | Vision rectangle, document and face requests |
| Files | Output names, collision rule; `Catalog::adopt_new`, new XMP fields (`DerivedFrom`, `Ingredients`) | Coordinated, security-scoped write and atomic publish; Photos and Files; EXIF whitelist copy |
| UI | — | Editors, keys and `FolderCommand` cases, selection in Folders, Monitor Mode drawing, notices, Undo |

Bridge calls per operation: `glue_plan`, `glue_compose`, `multicrop_tidy`, `multicrop_plan`, `multicrop_extract`, `catalog_adopt_new`, all over JSON and paths, each with a `MediaRenderJob` for cancellation, as `cropRgba` has now. **Rebuild the XCFramework whenever the FFI changes** (guide, "Builds and devices").

---

## 4. Effort (working days)

Estimates are for one developer at the pace of the existing media tools, including tests and a device run.

| Piece | Days |
|---|---|
| **Shared:** output naming and safe publish, `Catalog::adopt_new`, XMP `DerivedFrom`/`Ingredients`, metadata whitelist, working-space conversion, "made files" Undo, size limits | 2.5 |
| **Shared:** Folders multi-select (session and commands, selection bar) | 1.5 |
| **Glue:** Rust plan, resample, compose and tests | 2.5 |
| **Glue:** Swift staging and export, metadata | 1.5 |
| **Glue:** editor on Mac, iPhone and iPad, keys, Monitor Mode, entry points | 3 |
| **Glue:** integration tests, device checks | 1 |
| **Glue total** (with shared) | **12** |
| Glue option: Line up (Vision translation) | +1 |
| Glue option: grids | +1.5 |
| **Multi Crop:** Rust box model, tidy, order, naming, exact copy, warp and tests | 3.5 |
| **Multi Crop:** Vision detection | 1 |
| **Multi Crop:** editor (draw, handles, rotate, corners, snap, renumber, output strip) on Mac, iPhone and iPad, keys, Monitor Mode | 5 |
| **Multi Crop:** export and metadata, entry points | 1 |
| **Multi Crop:** integration tests, fixture, device checks | 1.5 |
| **Multi Crop total** (shared already counted in Glue) | **12** |
| Multi Crop option: face-based "which way up" | +0.5 |
| Multi Crop option: same boxes on the next scan | +1.5 |
| **Both, v1** | **~24** |

Suggested order: shared parts → **Multi Crop first**, as the more useful on its own and the one that proves the warp and naming → Glue → options. Each ships with a `CHANGELOG.md` entry and a "What's new" line, per the guide. BestShot has no `CHANGELOG.md` yet, so the first of these starts it.

---

## 5. Open questions for Dan (each with a recommended default)

All answered on 19 November: see [Decisions, 19 Nov](#decisions-19-nov). Where Dan didn't say otherwise, the recommended default below stands.

1. **Two landscapes: stacked or side by side by default?** The "closest to square" rule stacks them, which suits two separate photos; side by side suits halves of a wide view. **Recommend: closest to square, with `o` to flip.** It's predictable, one key fixes it, and Glue remembers the last flip for the session.
2. **More than two photos, and grids?** **Recommend: 2–6 in a row or column for v1, no grids.** A grid is +1.5 days when wanted.
3. **Add "Line up" (Vision translation) to Glue?** **Recommend: yes, as v1.1** (+1 day). It only fills in overlap and offset; no warping, no stitching.
4. **Glue's file name?** **Recommend `IMG_0012-glued.jpg`** (first source's stem). The alternative, `IMG_0012+IMG_0013.jpg`, gets long with three or more.
5. **Multi Crop's file names and folder?** **Recommend `Scan_004-1.jpg` … beside the source**, not a subfolder: a subfolder would vanish from a Folders session that isn't recursive.
6. **Carry stars and colour labels to the new files?** **Recommend: no; keywords only.** A carried red would mark the new photo as a reject. Offer "Copy stars and label too" in the editor's ⋯ menu if wanted.
7. **Keep location (GPS) on the new files?** Anti-Crop drops all metadata. **Recommend: keep it (setting, on by default)**, since the originals in the same folder carry it anyway and dropping it breaks Photos' map and date sorting. Anti-Crop's rule could be made to match later.
8. **Output format default?** **Recommend "same as the source"** (RAW → JPEG, JPEG at 0.92), with the picker remembered per tool. Should 16-bit TIFF in give 16-bit TIFF out? **Recommend: not in v1** (8-bit with a notice).
9. **Tools on the Mac?** Today Tools is iPhone and iPad only. **Recommend: Folders entry points only in v1.** Add a Mac Tools section when there's a reason to glue files outside a Folders session.
10. **Run Find when Multi Crop opens?** **Recommend: yes.** It's under a second and is nearly always the first thing wanted. It never runs again on its own.
11. **Guess which way up from faces?** **Recommend: yes** (+0.5 day). It only pre-sets the 90° turn, which can be seen and changed in the output strip.
12. **Linux (the Tauri desktop app) for either tool?** **Recommend: not in v1.** The Rust core already holds the geometry and pixel work, so a Linux editor is UI plus a Rust detector for scans when that shell really goes there.
13. **Change the date on scan crops** (scan date ≠ when the print was taken)? **Recommend: out of scope for these tools.** A general "Set date" action in Folders would serve scans and more.
14. **"Same boxes on the next scan"** for a batch of same-layout pages? **Recommend: v1.1** (+1.5 days), if Dan scans in batches.
15. **After Multi Crop, do anything to the source** (a label, a keyword "cropped")? **Recommend: nothing.** Never change an original. The `DerivedFrom` on each crop already says where it came from.

---

## Decisions, 19 Nov

Dan's answers. These win wherever the sections above still say otherwise.

**Both tools**
- **New files are new files.** No stars and no colour label are carried, and there's no "copy stars" option. Keywords are carried as the metadata table says (Glue: the union; Multi Crop: the source's). Location (GPS) is kept.
- **Output is JPEG by default** for every source, HEIC, PNG and RAW included, at quality 0.92. The ⋯ options menu offers HEIC, PNG and TIFF; the choice is remembered per tool.
- **Quick rotate before saving matters more than guessing.** Every photo (Glue) and every box (Multi Crop) has a rotate icon, and `r` / `⇧R` turn the focused one 90° right / left. Face-based "which way up" (Q11) is fine but not important, so it's left out of v1.
- **Keywords and provenance are embedded in the new file's XMP** at encode time (no sidecar, no `Catalog::adopt_new` in v1). Folders rescans after making files.
- Every other open question takes the recommended default in section 5.

**Multi Crop**
- As specced. Plus **Use last crop** (`l`, and an icon): the previous image's boxes, kept in proportion to the image, are put on this one, so a run of same-layout scans takes one key each.
- Q10 Find runs on open, Q5 names `Scan_004-1.jpg` beside the source, Q15 nothing is done to the source.

**Glue**
- **Up to 10 photos** (was 2–6).
- **Layouts:** horizontal or vertical, as a **line** (row or column), a **grid** (rows of N, or columns of N when vertical), or **free**. Free ("jagged") lets each photo be resized on its own (aspect kept) and placed anywhere, so edges needn't line up; whatever isn't covered is background. Switching to Free starts from the current line or grid, so the tidy layout is the starting point for the jagged one.
- **Background:** a colour picker (white and black one tap away), plus **Blurred fill**, which fills the background with a soft, extended blur of the photos themselves (a push-pull fill of a small copy, then blurred). It's cheap in the same Rust pass, so it's in. A separate "extend edges" isn't offered: in a free layout there's no single edge to extend, and the blurred fill covers the same need.
- **Zoom the canvas freely:** pinch, ⌘+ / ⌘−, and ⌘0 (or the icon) to fit.
- **Kept from the spec:** the gap ↔ overlap Join control and the seam with a straight or feathered (smoothstep) fade. In a grid the join applies within rows and between rows. In Free, the fade is a feather on the edges of each photo that sits over another.
- **Line up (Vision) is in v1**: on a line layout it sets each join's overlap and offset from `VNTranslationalImageRegistrationRequest`, per neighbouring pair (so joins can differ after Line up). Implausible results change nothing and say "Couldn't line these up".
- Q1 closest-to-square layout with `o` to flip, Q4 `IMG_0012-glued.jpg`.

**How it's split (as built)**
- Rust (`bestshot-media`, `glue.rs` and `multicrop.rs`): edit models and validation, layouts (line, grid, free), placements and blend ramps, output names and collisions, box tidy and reading order, box geometry, the exact-copy and bicubic perspective extract, and the compositor (fade, gap, border, colour or blurred background). Shared vectors in `core/bestshot-media/tests/vectors/`.
- Swift: decode, colour, and **scaling each Glue photo to its planned size while staging** (Core Image Lanczos, the plain alternative section 1.5 allows; Rust then composites 1:1, so unscaled photos are exact copies), Vision, encode with the EXIF whitelist and XMP, the editors, keys, and file placement.
- Originals are never written: tests hash the source bytes before and after.
