# BestShot: suggestion guide

A read-through of the whole repo (web app, Linux Tauri app, Rust core, Apple app), November 2026. Nothing was built or run, so every finding comes from reading the code. Where I'm inferring runtime behaviour I say "likely". I checked before calling anything missing, but a few Adobe-side claims need confirming on a real Bridge install; those are marked "confirm in Bridge".

The aim I reviewed against: **replace Adobe Bridge**, on the Mac first. The stars, labels and XMP work is new and untested, so it got the most attention.

## The short version

The foundation is better than most Bridge alternatives. XMP edits are splices, never re-serialisations. Writes are atomic. A JPEG rewrite proves the image bytes are unchanged before it replaces the file. That is the hard, unglamorous part, and it's done well.

What stops it replacing Bridge today falls into three groups:

1. **Label meaning.** A Bridge "Select" can arrive as a reject without any mapping (bug 1). Keep and reject overwrite existing labels. Linux and Mac can disagree about what's rejected.
2. **Round-tripping with Adobe.** For JPEGs and DNGs, Adobe and BestShot read different places, and BestShot's sidecar then hides anything Adobe writes.
3. **Everyday Bridge tasks that don't exist yet.** No multi-select, capture-date sort, folder tree, search, side-by-side compare, Open With or metadata fields beyond stars, labels and keywords.

Loupe speed is the other big one: all decoding goes through one serial queue, and marks block the main thread.

## What's great and should be protected

- **Splice editing** (`core/bestshot-core/src/xmp.rs:4-8`, `:86-113`). Unknown fields, Camera Raw settings and padding survive byte for byte, and each result is re-parsed and compared before it can reach disk. Never swap this for a serialiser.
- **Top-level-only reads** (`xmp.rs:6-8`). Ignoring nested `crs:Look` and `xmpMM:Pantry` descriptions is a subtle correctness win that many tools get wrong.
- **The proof on JPEG writes** (`embedded.rs:228-233`), and the fact the option is off by default.
- **`atomic::replace`** (`atomic.rs:24-51`): refuses read-only files, follows symlinks, keeps mode and xattrs, flushes the folder too.
- **Failure handling as a feature.** A malformed sidecar is reported and never written, and `FolderProblemsView` tells you so. "Nothing was written" is exactly the right promise.
- **XMP as the source of truth with a disposable index** (`catalog.rs:3-5`). No lock-in, no database to corrupt. This is the strongest argument against Bridge's cache and Lightroom's catalog, so keep it.
- **`FolderKeymap` as a pure function** resolving to `FolderCommand`, with tests. It's the right shape for menus, remote control and Monitor Mode later.
- **Sidecar ownership rules** (`library.rs:86-103`): the raw owns `A.xmp` and the JPEG beside it gets `A.JPG.xmp`, so one photo's rating can't land on another.
- **The design language.** Light table to sort, black viewfinder to judge, grease-pencil marks. It's distinctive and it has an idea behind it. Don't let "more panels" dilute it.
- **Bridge's reject rating is preserved and never treated as a delete** (test at `catalog.rs:889`). Good instinct, and the same instinct should apply to bug 1.
- **Copy.** "Keep reviewing", "for the bin", and the line under Clear out saying it covers every red, not only what's filtered.

## Bugs and risks

Ordered by how much they'd hurt. All file references are from `core/bestshot-core/src/` unless the path says otherwise.

### Serious

**1. A Bridge "Select" can become a reject with no mapping, and go in Trash all red.** `labels.rs:104-107`: `colour_for` tries `xmp:Label`, then falls back to `photoshop:LabelColor`. With default settings "Select" is unmapped (deliberately: "never guess a delete", `labels.rs:184`), so the fallback runs, finds `Red`, and `catalog.rs:413-414` turns that into `Decision::Reject`. The repo's own fixtures use this exact shape (`xmp:Label="Select" photoshop:LabelColor="Red"`, `catalog.rs:1038`, `:1170`), but the test that promises safety, `unmapped_labels_are_shown_kept_and_never_count_as_red` (`catalog.rs:835`), has no `LabelColor`, so it passes. Choosing "Not a colour" for Select in Import from Bridge doesn't help either: the explicit `null` makes `of(label)` return `None`, and the `.or_else` still falls through. Result: a folder of Bridge favourites opens with its best photos in the reject count, and `⌘⌫` then one click puts them in the Trash. The sheet's confirmation and the Trash limit the damage, but this is the exact failure the design set out to prevent. Fix: an unmapped or explicitly `null` label must stop the fallback, and `LabelColor` must never produce a decision on its own. Add the missing test.

**2. Mapping Bridge's defaults turns picks into rejects by design.** `labels.rs:137` suggests Select to Red, which is correct as a colour, and the import screen pre-selects it (`BridgeImportView.swift:119`). But red also means bin. For a Bridge user "Select" is usually a top pick. The warning line is honest, but a pre-selected default shouldn't need one. See "The label model" below for the fix.

**3. Linux and Mac can silently disagree about what's rejected.** The Linux app uses only the store, with no catalog or XMP (`desktop/src-tauri/src/lib.rs:76-83`, `:117`). The Mac lets a label beat the store (`catalog.rs:7-11`, `:413`). So a photo marked red on the Mac and changed to Keep on Linux is still a reject on the Mac, and goes in Trash all red. A green photo rejected on Linux is quietly kept on the Mac, because Linux can't change the XMP. The README promises the folder "can be culled on Linux or Mac interchangeably", which is no longer true. Fix: move Linux to `Catalog`. It's the same crate, so this is mostly plumbing.

**4. A sidecar on a JPEG hides anything Adobe writes later.** `catalog.rs:83-95`: a sidecar is authoritative if it exists. Adobe ignores sidecars for JPEGs and writes into the file (the app's own Settings text says so). Sequence: rate in BestShot (sidecar created), rate the same JPEG in Bridge (embedded). BestShot still shows its old value, for good, because `stamp_of` (`catalog.rs:71-79`) only watches the sidecar, so the index never notices the image changed. An undo that restores an empty state also leaves an empty sidecar hiding the file. Fix: for JPEG, TIFF, PNG and DNG, compare both, and take the newer by `xmp:MetadataDate` or mtime, or surface a conflict. Stamp both files.

**5. The JPEG option leaves earlier work behind.** `catalog.rs:512-516` writes only the current `change` into the JPEG. Turn the option on after rating 500 photos and those ratings are never pushed. When a packet already exists, `seed` isn't used either, so the JPEG and sidecar drift field by field. Needs a one-off "Write all metadata into these JPEGs" action with progress, and a dry-run count.

**6. Keyword edits can wipe a keyword added elsewhere.** `write()` promises it works "always from what's on disk now, never from the index" (`catalog.rs:479-481`), but `add_keyword` and `remove_keyword` build the full list from the cached fields (`:615-625`) and send it as a replacement. Add a keyword in Bridge while the folder is open, add one in BestShot, and Bridge's is gone. Fix: express these as add and remove operations resolved inside `write()` against the fresh `before`. `set_colour` reads `label_color` from the cache in the same way (`:574-576`).

**7. Web: `python app/main.py` starts a debugger on every interface.** `app/main.py:1118` binds to all interfaces with `debug=True`, and that's the README's Quick Start. The Werkzeug debugger allows code execution behind a PIN, and the pinned Werkzeug 3.0.1 predates a published debugger fix. Bind to localhost and remove `debug=True`.

**8. Web: any website can delete your projects.** `app/main.py:106-111` sends `Access-Control-Allow-Origin: *` with DELETE allowed on every route, and there's no authentication. While the server runs, a page in your browser can call `DELETE /api/projects/<name>`, which is a `shutil.rmtree` (`:948`). Project names are listable from the same API. Drop the CORS block (the frontend is same-origin), and add a token if it's ever reachable beyond localhost.

### Medium

**9. Renaming can reassign old files to red.** `labels.rs:111-126`. Rename Green to "Keep": an alias `green -> Green` is stored. Rename Red to "Green": the alias is removed (`:123`). Every file written as "Green" is now red, a reject. Refuse a rename onto a name that has an alias for a different colour, or ask.

**10. A same-named video disappears and gets binned.** `library.rs:171-207`: with any image in the group, videos are never items. They become companions. `trip.jpg` and `trip.mov` that aren't a Live Photo means the video is invisible and is trashed with the photo. Counter rollovers and hand-named files do this. The Finish sheet's "Live Photo / sidecar file" count doesn't say which. Fix: treat as Live Photo only if it looks like one (short, or matching content identifier), and show a size warning when a companion is much larger than the photo.

**11. Reject folder pairs can split.** `cull.rs:85-112`: `unique_path` runs per file, so on a name clash `IMG_1.HEIC` becomes `IMG_1 (1).HEIC` and `IMG_1.MOV` keeps its name. The test at `cull.rs:139` bakes this in. The sidecar then no longer pairs with its photo. Pick one suffix per item.

**12. A failed Trash leaves half an item.** `cull.rs:66`: `try_for_each` stops at the first failure, so the image can be gone with its sidecar left behind, reported as "couldn't be moved". Trash the companions first and the main file last, or report what moved.

**13. The store doesn't use the atomic writer.** `store.rs:65-72` has a fixed temp name and no flush, while `atomic::replace` sits next to it. Two machines or two windows collide on `.bestshot-cull.json.tmp`. It's also last-writer-wins: the whole store is held in memory and written back, so a second machine's decisions are overwritten. Use `atomic::replace`, and re-read and merge before saving.

**14. Triage: quitting before the commit strands photos.** `TriageSession.swift:82-89` persists `.deleted` straight away, and `TriageHomeView.swift:127-128` excludes `.deleted` from later sessions. Close the app before the summary and those photos are never deleted and never shown again. Add a "N photos waiting to be deleted" banner on Triage home, and exclude only committed deletes.

**15. Triage: an existing favourite can't be unfavourited.** `TriageSession.swift:74-80`: `newValue` is worked out from the session's set, not `asset.isFavorite`. On an already-favourite photo the heart is on, and tapping it sets it to true again.

**16. Dropping a file on the Mac can't work under the sandbox (likely).** `FolderHomeView.swift:155`: `url.deletingLastPathComponent()` opens the parent folder, but dragging a file only grants that file. Show "Drop the folder instead", or use `NSOpenPanel` with the parent preselected.

**17. Holding an arrow doesn't move.** `FolderCullView.swift:29` uses `.onKeyPress(phases: .down)`, which excludes repeats, so ↑ and ↓ won't flick through photos. Linux has this right: it blocks repeats only for decision keys (`desktop/src/app.js`, "machine-gun" comment). Handle `.repeat` for navigation only.

**18. Video restarts on any state change (likely).** `FolderCullView.swift:195`: `VideoPlayer(player: AVPlayer(url: url))` creates a player in `body`, so pressing a star key during playback probably re-creates it. Hold the player in state, keyed by URL.

**19. Leaving Folders loses the session (likely).** Session state lives in `@State` in `FolderHomeView`, inside the split view's detail. Selecting Triage and coming back probably drops the session and undo stack, and `onDisappear` doesn't stop the security scope. Lift the session into the app's state.

**20. Scope handling.** `FolderHomeView.swift:163` starts a security scope, and the `catch` branches never stop it. The `stale` flag at `:41-42` is ignored, so a stale bookmark isn't renewed until close.

**21. Web: a corrupt or half-written JSON file wipes metadata.** `app/main.py:195-205`: on `JSONDecodeError` it returns `{}`, and the next save writes that back. `write_text` isn't atomic and Gunicorn runs four workers, so concurrent uploads can both lose updates and read a partial file. Tags, comments and hashes go. Use temp-and-rename plus a lock, or SQLite.

**22. Web: thumbnails collide by stem.** `app/main.py:282`: `IMG.jpg` and `IMG.png` share `IMG_thumb.webp`, so one shows the wrong picture and deleting one removes the other's thumbnail (`:869`, `:968`).

**23. Web: project names with `#` or `%` break.** The sanitiser allows them (`:90`) and `url` is built without quoting (`:401`, `:411`), then used directly (`static/app.js:836`, `:864`). Quote in Python.

**24. Web: uploads and ZIPs are unbounded.** No `MAX_CONTENT_LENGTH`. `upload_images` reads each file into memory (`:548`), and ZIPs are built in a `BytesIO` (`:718`, `:745`) with deflate, which costs CPU and saves almost nothing on JPEGs. A large project can exhaust memory or hit the 120-second worker timeout. Stream, use `ZIP_STORED`.

**25. Web: `batch-delete` isn't limited to media.** `:860-866` will unlink `.ranking.json` or `.project.json` if asked. Check the name against `_list_media_files`.

**26. Web: `move-file` has dead code.** `:1032-1034` aborts if the name exists, so `_next_available_name` at `:1037` never renames. Remove the abort.

### Small

- `xmp.rs:540`: a self-closed `<xmp:Label/>` gets its value spliced after the tag, then fails read-back. Safe, but the file can't be labelled. Handle it.
- `embedded.rs:207`: the offset assumes no fill bytes before the marker. It fails safe.
- `embedded.rs` reads tag 700 only from IFD0 and classic TIFF. Fine for most raws, but `.orf` and `.rw2` use different magic numbers, so they're skipped silently, as are CR3, RAF and HEIC. In-camera ratings in those formats won't appear. Worth a line in the docs.
- `xmp.rs:312`: a trailing NUL after the packet counts as "text outside the root element", turning a harmless quirk into a blocked file. Some writers do this. Trim NULs before parsing.
- `xmp.rs:436`: a qualified keyword (`rdf:li` holding an `rdf:Description`) is decoded as raw XML text and shows as a keyword.
- `catalog.rs:462`: `by_rel.keys()` has no fixed order, so a keyword's displayed capitalisation can change between launches.
- `catalog.rs:198`: `Stars::Exactly(0)` includes Bridge-rejected photos.
- `BridgeImportView.swift:65`: `ForEach(scan.values, id: \.text)` has duplicate ids when "Red" appears in both fields, and `choices` is keyed by text too.
- `BridgeImportView.swift:136`: `try?` swallows a rename failure, so a clash is silent.
- `atomic.rs:12-15`: a crash leaves a hidden temp file the size of the JPEG. Nothing cleans these up. Sweep `.*.bestshot-*.tmp` on open.
- `app/main.py:518`: renaming a project through the API wipes the description if it isn't sent. The frontend sends it, so this only bites API users.
- `app/__pycache__/*.pyc` is tracked, and there's no root `.gitignore`.
- The README ends "see LICENSE file", and there's no LICENSE file. The repo is public, so as it stands nobody has a licence.
- `requirements.txt` pins old versions with published advisories (Werkzeug, Pillow, Gunicorn). Bump them. The Dockerfile also runs as root.
- The Mac Help menu is an empty placeholder (`BestShotApp.swift:30-32`).
- `CODE_REVIEW_FINDINGS.md` predates everything else. Delete it or move it into `docs/`.

## The label model: a decision to make

Right now Green is Keep and Red is Reject, everywhere, unconditionally. That's neat for a fresh folder and wrong for a folder Bridge has touched:

- Pressing → on a photo labelled Blue ("Review") overwrites Blue with Green (`catalog.rs:590-594`). Culling destroys label data with one key. Undo only lasts for the session.
- Red already means something in the user's system, often the opposite of bin.
- Lightroom's default label text is literally "Red". Open a Lightroom-labelled folder and every red photo counts as a reject on first open.

**My recommendation:** separate the decision from the label.

- Keep and reject stay in `.bestshot-cull.json`, and optionally write `xmp:Rating="-1"` for reject, which is Bridge's own Reject and hides by default there. Confirm in Bridge how it treats that alongside a star rating, as rejecting would replace the stars.
- Labels stay labels. Add a setting, "Treat this label as reject", defaulting to none once a folder has foreign labels.
- A fresh folder can keep today's behaviour if you like the speed of one concept. But never derive a Trash candidate from a label BestShot didn't write, without showing a dedicated review step first.

If you keep the coupling, at minimum: rejects that came from a label BestShot didn't write should be listed separately in the Clear out sheet with thumbnails, unticked by default.

## UX and flows

- **Mac default landing is wrong for the aim.** `RootView.swift` opens on Triage. If Bridge is the target, open on Folders, resuming the last folder.
- **Too many doors.** Triage, Organise, Rank, Folders, All Media and Projects are six entry points with overlapping meanings. "Rank" is both a Photos screen and a mode inside Folders. See "What to cut".
- **Clear out vs Trash all red** are two names for nearly one action. Keep Clear out, with Trash and `_Rejected` as its options, and let `⌘⌫` open it.
- **A review sheet before Trash.** The count is good, but show thumbnails of what's going, at least a strip. It's the last chance, and it turns bug 1 into something you'd notice.
- **Undo across Clear out.** The stack is cleared after a cull (`FolderCullSession.swift`, `applyCull`). Keep a "Put back" for `_Rejected` moves, and use `resultingItemURL` to offer it for the Trash too.
- **Grid thumbnail size is fixed** (`minimum: 150`). Add a slider and `⌘+`/`⌘-`, and Bridge's habit of remembering it.
- **Grid hint text** is good. Consider the same in the loupe, fading after a few uses.
- **Filter bar always on.** Lovely in the grid, noisy in the loupe. Collapse it there to a single "Filters: 3" control.
- **Empty and first-run.** Folders home explains XMP well, but say the three keys that matter in big type the first time the loupe opens.
- **Recents cap at 8 and only store a count.** Show a thumbnail and when it was last opened. Add Favourites, which are what Bridge users actually rely on.
- **Web and Linux parity notes:** Linux has a real 100% zoom with mouse pan and an on-screen `?` sheet. The Mac's `Z` fits the image in a `ScrollView` at up to 8000px with no zoom-to-click. Port Linux's behaviour. Focus checking is the point of a culling tool.

## Visual design

- Stars in the tile badge are white on 60% black, which works. In the loupe they're fine too, but rejected-in-Bridge is text only and easy to miss. Give it a mark in the grid as well: `TileMetaBadge` shows nothing for `rating < 0`.
- The 2px progress bar (`FolderCullView.swift:114-123`) is elegant but hard to read. Keep it, with a hover tooltip.
- 10 to 11pt mono is everywhere. It's on-brand, but at arm's length on a big monitor it's tiring. Step everything up one size in the viewfinder.
- `.preferredColorScheme(.light)` is forced, which suits the concept. Worth keeping, but make sure system dialogs don't flash.
- Loupe margins of 84px for the edge labels cost real image area on a laptop. Let them fade out after the first few actions, or shrink to an edge glow on hover.
- A true neutral-grey surround option for the viewfinder would matter to anyone judging colour. Black exaggerates contrast.

## Accessibility

- **Folders has no accessibility labels at all**: zero `accessibilityLabel` calls in `Views/Folder/` (Rank has some). The filter-bar colour dots are unlabelled to VoiceOver, since `.help` isn't a label. Star and label state on tiles is invisible to it, as `Image(decorative:)` plus `.allowsHitTesting(false)` overlays offer nothing. Add a combined label per tile: "IMG_0123, 4 stars, green, kept".
- **Colour-only state.** Label bands rely on colour. Red and green is the classic failure, and it's the app's main distinction. The circle and cross marks help for decisions, but the filter dots and bands don't. Add a letter or shape option.
- **Contrast.** `Theme.viewfinder.dim` is `#E8E6E1` at 42% on black (about 3.3:1 by my estimate) and it's used at 10pt for the keyword field's hint. `Theme.table.dim` `#8A857A` on `#EFEBE1` is about 3:1. Reserve `dim` for decoration.
- **Dynamic Type.** `Font.custom` scales on iPhone and iPad, but the 10 to 12pt mono layouts haven't been built with that in mind. Test Triage at the largest sizes.
- **Reduce Motion.** Nothing reads `accessibilityReduceMotion`. The filmstrip scroll and any drawn marks should respect it.
- **Keyboard reach.** Filter bar controls and Clear out can't be reached without the mouse. See below.

## Keyboard and Monitor Mode

The keymap is close to Lightroom's, which is a good choice: 1-5, 6-9, P, X, U. Notes for Bridge users:

- Bridge uses `⌘1`-`⌘5` and `⌘6`-`⌘9`. Accept both forms, as it costs nothing and removes a retraining step. Also add `⌘,` and `⌘.` (Bridge's lower and raise rating) or `[` and `]` (Lightroom's).
- **Purple has no key** (`CoreBridge.swift`). Use `Shift+9` or `⌘⌥9`.
- **`⌫` means undo here** and reject on Linux's `Delete`. Muscle memory from Finder and Bridge says "delete". I'd make `⌫` reject-and-advance, and leave `⌘Z` as undo.
- **Missing keys:** filter by stars and label (Bridge's `⌘⌥1`-`5`), clear filters, sort, next and previous folder, zoom to 100% at the cursor, Reveal in Finder, Open With, Quick Look, thumbnail size, full screen.
- **No Mac menus.** Everything lives in key handlers and buttons. A proper menu bar (File: Open Folder, Reveal; Edit: Undo; Photo: Rate, Label, Keep, Reject; View: Grid, Loupe, Info) makes every key discoverable and gives Mac users what they expect. `FolderCommand` makes this nearly free. It also fixes Undo in the Edit menu.
- **`?` in the Folder view:** Linux has it, and the Mac sheet is reached from a menu in the sidebar. Bind `?` in `FolderKeymap`.

**Monitor Mode.** The only reference in the repo is the comment in `FolderKeymap.swift:6`, so it isn't built. My reading of what it should be, given that comment: a second-display surface driven by the same commands.

- The Mac window stays as the control surface (grid, filters), and an external display shows the full-bleed viewfinder with nothing else: no chrome, true colour, grey surround option, optional 100% crop.
- Same commands drive both, so nothing new in the session. A second `WindowGroup` observing the same `FolderCullSession`, positioned by `NSScreen`.
- A further step: client review. Show ratings to nobody, pick on an iPad as a remote over the local network. That's a real differentiator for working photographers.

## Performance

**The loupe decode path is the main problem** (`FolderImage.swift`):

- `FolderImageCache` is an `actor`, and `image(at:maxPixel:)` decodes synchronously inside it. So **every decode in the app runs one at a time**. The photo you've just landed on queues behind filmstrip thumbnails, grid tiles and preloads. Move decoding out to a bounded concurrent pool (2-4), with the loupe at top priority, and keep only the dictionary in the actor.
- Cancelled requests still decode: nothing checks cancellation, so fast scrolling builds a backlog. Linux already has a LIFO pool for this (`thumb_pool: media::LifoPool`).
- `kCGImageSourceCreateThumbnailFromImageAlways: true` forces a full decode for every thumbnail, even a 56px filmstrip tile from a 45MP raw. Use `FromImageIfAbsent` for grid and filmstrip sizes, so the embedded preview is used. The difference on raw is likely an order of magnitude.
- Thumbnails aren't cached on disk, so each open decodes everything again. Add a per-machine thumbnail cache in Caches, keyed on path, size and mtime. Keep it out of the photo folder.
- `maxPixel: 2400` is soft on a 5K or 6K display. Size it from the view's pixel size.
- Preload is forward-only, 3 images (`FolderCullView.swift:312-318`). Include one back, and start the raw preview first, then swap in the full decode.

**Marks block the main thread.** `FolderCullSession.mark` calls the catalog synchronously on `@MainActor`. Each mark reads the sidecar, writes temp, fsyncs the file and the folder, and renames. Rust's `sync_all` on macOS is `F_FULLFSYNC`, which is slow, more so on a USB drive or SD card. With JPEG writing on, it also reads and copies the whole JPEG. Then `counts()`, `query()` and `rebuildRankBoard()` run over all items, cloning rows. At culling speed this is the app's heartbeat. Update the UI optimistically and send writes to a single background queue, flushing on leave. Failures can still surface, because the banner exists. Keep counts incrementally. Drop the folder fsync for sidecars, or do it once per batch.

**Ranking at scale.** `rank.rs` builds every pair up front, and `history.push(self.engine.clone())` (`:151`) clones those pairs and both relation maps on every answer, 30 deep. At 1,000 keepers that's about 500,000 string pairs per copy. Keep undo as a list of inverse operations, and generate pairs lazily. Binary insertion would ask fewer questions than random pairs too, and suits "add this new photo to the ranking" particularly well.

**Scanning.** `adopt` stats every item, then reads metadata on up to 4 threads. Good. For large trees, show the folder as soon as `scan` finishes and stream metadata in, rather than blocking on the whole read.

## Reliability and data safety

- **No file watching.** Nothing in `apple/` watches the folder, so files added, removed or edited elsewhere don't appear until reopening, and marking a since-moved file gives an error. An `FSEvents` watcher reusing `adopt` gives you this cheaply. Bridge does it, and it's half of what makes a browser feel live.
- **A changed-on-disk check** before marking would make it clear when Bridge and BestShot are both open.
- **`store.decisions.retain` on open** (`catalog.rs:281`) permanently drops decisions for anything not present at that moment. A subfolder moved temporarily or a partly synced NAS loses them. Keep them for a while, and only drop on explicit cleanup.
- **`xmp:MetadataDate` isn't updated.** Other apps use it to detect newer metadata, and it's the natural tie-break for bug 4. Set it on each write.
- **`mtime` changes on JPEG write.** This matters because of the sort below, and because backup tools will re-copy. Consider preserving the original mtime (with a stamp written from the new one) as an option.
- **Write-into-originals audit.** Before the JPEG option is trusted with real work, offer a one-file-at-a-time mode with a log of what changed.
- **MPF offsets.** `jpeg_with` proves that bytes outside the segment are unchanged, but not that offsets still hold. If an XMP segment sits after an APP2 MPF block and grows, the multi-picture offsets (gain maps, MPO) that point past it become wrong while the byte proof still passes. XMP before MPF is safe, and new segments go there. Refuse the write, or preserve size using packet padding, when MPF comes first. Using padding in general is good practice: most Adobe packets have 2-4KB spare, and an in-place edit changes no offsets at all.

## Interoperability (the Bridge replacement's real test)

- **Keywords are `dc:subject` only.** `lr:hierarchicalSubject` isn't touched, so a keyword removed in BestShot can come back in Lightroom or Bridge if it's held there too. Hierarchical keywords show flattened. At minimum, remove matching leaves from it. Confirm in Bridge.
- **IPTC-IIM in JPEGs isn't updated.** Keywords are often mirrored in APP13. Readers that prefer IIM will show the old list. If `photoshop:LegacyIPTCDigest` is present, behaviour varies by reader, so test it.
- **Adobe ignores sidecars for more than JPEG.** DNG, TIFF, PNG and PSD also keep their XMP inside, as far as I know. So on those, BestShot's ratings are invisible to Bridge, and there's no write path (JPEG only). DNG matters, as ProRAW and many converted libraries use it. Either add embedded writes for TIFF-based files, which is harder, or say so clearly in Settings.
- **Default names mismatch.** BestShot writes "Green"; Bridge's default set is "Approved" and so on. Before the import is run, Bridge shows these as a white "unknown" label, as far as I recall. Prompt to run Import from Bridge the first time a folder contains Bridge's defaults.
- **`darktable:colorlabels`** and Capture One's own conventions aren't read. Fine to skip, but the README shouldn't say "readable by ... darktable" for labels until it's tested.
- **A darktable `IMG.NEF.xmp` beats an Adobe `IMG.xmp`** (`library.rs:93`). When both exist, the Adobe one is ignored and left orphaned. Show a warning.

### A Bridge round-trip test plan

As this work is untested, here's the checklist I'd run once, with real files, before trusting it:

| Step | Check |
|---|---|
| Rate, label and keyword a raw in Bridge; open in BestShot | All show; rejects unchanged at 0 |
| Same in BestShot; open in Bridge | Stars, label colour, keywords all correct; not a white label |
| Edit a raw with Camera Raw, then rate in BestShot | Develop settings still applied afterwards |
| JPEG, option off: rate in BestShot, then in Bridge | Reveals bug 4 |
| JPEG, option on: rate in BestShot; open in Bridge and Photoshop | Rating shows, file opens, ICC profile intact |
| iPhone HDR JPEG with gain map, Ultra HDR, MPO | Still HDR or multi-picture after a write |
| Bridge Reject (rating -1) | Shown, stays out of Trash all red |
| Hierarchical keyword removed in BestShot | Doesn't return in Lightroom |
| Folder with `Select` plus `LabelColor` | Doesn't count as reject (bug 1) |
| Cull with `_Rejected`, then open that folder in Bridge | Sidecars still paired |
| Same folder alternating Mac and Linux | Same answer on both (bug 3) |
| SMB share, exFAT card, read-only card | Temp files, xattrs, index and errors all behave |

Keep the resulting files as fixtures. Nearly every XMP test today uses hand-written packets.

## Privacy and security

- Apple and Linux apps: on-device, no network. That's a selling point, so state it on the store page.
- The Tauri CSP is tight, capabilities are minimal, and the loopback video server carries a random token. Well done. `video.rs` spawns one thread per connection with no cap, which is fine for loopback.
- Web: see bugs 7, 8, 21, 24. It should be treated as localhost-only unless authentication is added. The README's "share the URL" implies network use, so say explicitly that there's no login.
- `README.md`'s "Cross-device sync" oversells a shared server with no authentication.
- EXIF location: exports and ZIPs keep GPS. Add a "strip location" option on share paths.
- `FolderInfoPanel` shows no location at all. If you add a map, keep it offline by default.

## Testing

- **Good:** the Rust core has real behavioural tests including malformed input, read-only files, undo and index reuse. The keymap has tests. CI runs Rust and macOS builds.
- **Gaps:**
  - No real-world fixtures (see the round-trip plan).
  - No fuzzing. `xmp::apply`, `embedded::read` and `jpeg_layout` parse hostile bytes and are ideal for `cargo fuzz`. "Never panics" is currently asserted for nine inputs.
  - A property test: for any packet and change, everything outside the touched properties is identical.
  - No test covers label plus `LabelColor` with default settings (bug 1), or rename chains (bug 9).
  - No Python tests at all, despite 1,100 lines of destructive routes. `pytest` plus Flask's test client for path traversal, delete and upload would take an hour.
  - No tests for `FolderCullSession` navigation (held positions, wrap-around), which is subtle. It's `@MainActor` but testable with a catalog on a temp folder.
  - CI doesn't cover `desktop/` at all (the workflow's path filter is `apple/**` and `core/**`), so a core change can break Linux unnoticed.
  - Linux and Mac sharing `.bestshot-cull.json` is covered by one test. Add a golden file.

## Code health

- **`catalog.rs` is 1,200 lines but well organised.** No action.
- **`static/app.js` at 3,277 lines and `styles.css` at 3,246** are the unmaintained end of the project.
- **Duplicate design tokens** in `Theme.swift`, `desktop/src/styles.css` and `static/theme.css`. Generate them from one JSON file, or accept the drift.
- **Generated bindings are uncommitted**, which is right, but a fresh clone needs Rust, XcodeGen and a script. A one-line `make` target would help.
- **`store::load` returns default on read errors**, and a later save then overwrites. `Err(e) => return (Store::default(), Some(..))` at `store.rs:47`: if the file is temporarily unreadable, the next decision replaces it. Refuse to save in that state.
- **`Swift 5.9` setting.** Move to Swift 6 language mode for the actor and sendable checks, since `@unchecked Sendable` appears in a few places.
- **The README top section** still reads as a Flask project. Rewrite it around the apps people should use.

## New feature ideas

### Needed to replace Bridge (in rough priority)

1. **Multi-select in grid and batch marks.** `FolderCullSession` has one `index`, and nothing selects. Shift and `⌘`-click, `⌘A`, and all marks applying to the selection. Biggest single gap. The core needs batch versions, with one undo entry per batch.
2. **Sort by capture date.** `Newest` uses file mtime (`catalog.rs:451`), which is wrong after a copy from a card, and changes when writing into JPEGs. Read `DateTimeOriginal` during `adopt`, and store it in the index. Add sort by filename, file type and size.
3. **Folder tree and Favourites** in a sidebar, instead of open-a-folder-then-leave. Bridge's core navigation.
4. **Filename search** and filtering by camera, lens, ISO, date, and file type. Bridge's Filter panel is a big reason people stay.
5. **N-up compare with synced zoom.** Rank's Compare is two photos, for ordering. Culling a burst wants 2-4 up with locked pan and zoom.
6. **Open With and drag out.** There's only Show in Finder, with no `NSWorkspace.open` anywhere in Folders. Open in Photoshop or Lightroom, and dragging files to other apps. Also Quick Look.
7. **Stacks.** RAW+JPEG as one item (cull both together, an option) and bursts grouped by capture time. Today a RAW+JPEG pair is two items you have to mark twice.
8. **Metadata panel.** Title, caption, creator, copyright, location, and templates applied to a batch. The splice editor generalises easily.
9. **Batch rename** with tokens and a preview. Sidecars and companions should follow, which BestShot already models well.
10. **Copy and move between folders**, new folder, and import from a card with renaming and a backup destination (Bridge's Photo Downloader).
11. **Non-destructive rotate.** There's no rotate at all. Write `tiff:Orientation` in XMP.
12. **Collections.** Saved filters as smart collections (`.bestshot` files in the folder or per-machine). Filter state is already a clean struct, so saving it is cheap.
13. **Export presets:** resize, format, watermark, strip metadata, contact-sheet PDF.
14. **Histogram and clipping warnings** in the Info panel.

### What would make it better than Bridge

- **"Best of burst"**, which is literally the name. Group near-duplicates with Vision's `VNGenerateImageFeaturePrintRequest` and capture time, then rank by sharpness (Laplacian variance through Accelerate), eyes open (face landmarks) and `VNCalculateImageAestheticsScoresRequest` on macOS 15+. Suggest, never decide: "We'd keep this one". Fully on-device.
- **Focus peaking and a face-zoom key:** `F` jumps the 100% loupe to the detected face. Saves the most time when culling portraits.
- **Blur and closed-eye filters** as extra filter chips.
- **"Cull with me" stats:** keep rate, time per photo, and "you've kept 34% of this shoot". Small delight, useful for pacing.
- **Rating by comparison.** Turn a finished Rank into stars: top 10% get 5 stars. Links the two halves of the app, and no other tool has it.
- **Undo history panel** so a bad batch can be reviewed.
- **Grease-pencil notes:** draw on a photo to mark a crop or retouch. Stored in XMP or a sidecar. Very on-brand.
- **Share a selection** as a local review page, reusing the web app for what it's good at: a client picks favourites in a browser, and the picks flow back as XMP.
- **Small delights:** the circle drawn on a keeper could animate like a real pencil; a soft tick on Keep with haptics on trackpads; "All reviewed" could show the three highest-rated photos.

### Bigger bets

- **Sell it.** There's a real gap for a fast, native, sidecar-honest, non-subscription culler for Mac. Photo Mechanic is pricey and dated, and Bridge is slow.
- **iPad culling from an SD card or external drive** via Files and the Rust core. The Folder code is `#if os(macOS)` only, and most of it wouldn't need to be. Travel photographers would pay for this.
- **Sync decisions via iCloud Drive** using the existing per-folder files.

## Platform features worth using

- **Mac:** menu bar, Services and Share menu, Quick Look, `NSFilePresenter` or FSEvents, multiple windows (one per folder), full-screen with the toolbar hidden, trackpad pinch to zoom, Stage Manager-friendly sizes, display P3 and EDR for HDR photos.
- **App Intents and Shortcuts:** "Open last folder", "Count unreviewed", and an automation for rating. Also Finder Quick Actions: "Cull this folder".
- **Vision** (see above). Core Spotlight for keywords, later.
- **Finder tags:** optionally mirror colours to Finder tags. Five lines of `URLResourceValues`, and they're visible everywhere on a Mac.
- **iOS:** a share extension to add a photo to a Rank board could be fun. `PHPhotoLibraryChangeObserver` isn't used, so Triage won't notice library changes mid-session.

## App Store readiness and marketing

- **Sandbox, hardened runtime and app icon are done.** Security-scoped bookmarks are done.
- **To add:** `PrivacyInfo.xcprivacy` (there's none in the repo, and UserDefaults is a required-reason API) and `ITSAppUsesNonExemptEncryption`. There are no string catalogues yet, which is fine until you go beyond English.
- **Purpose strings:** the `NSPhotoLibraryUsageDescription` says "imports photos and videos you choose so you can rank them", but Triage reads the whole library and deletes. Rewrite it to say so, or review may push back.
- **Deleting from the Photos library** is user-confirmed by the system, so it's safe to describe plainly.
- **`assets.pictures.read-write`** is an entitlement you may not need, as user-selected folders cover it. Unused entitlements invite review questions.
- **Positioning:** "Your photos stay your files." Sidecars, no catalog, no subscription, no cloud. Lead with speed and "works with what you already use".
- **Comparison page** vs Bridge, Photo Mechanic and Lightroom, with an honest feature table.
- **Screenshots:** the viewfinder and grease-pencil look will stand out. Show the marks.
- **Pricing:** one-off purchase. It's the anti-subscription tool. Add a free cap (say 200 photos a folder) if you want a trial.
- **Trust page:** explain the byte-for-byte proof and atomic writes. Photographers care, and nobody else says it.

## What to cut

Honest opinions, all for discussion.

- **Apple Projects and Compare (the SwiftData port of the web app).** It imports copies, which is the opposite of what the rest of the app stands for, and `ComparisonEngine.swift` duplicates the Rust ranker. Remove it, or at least hide it on the Mac. It also takes the sidebar's largest section.
- **The web app, as a product.** It's 3,000+ lines of JS, its own storage, and most of this document's security bugs. Either freeze it behind localhost, or shrink it to the "client review page" idea above. Don't let it get new features.
- **Organise** probably belongs in Photos itself. It's the least distinctive screen. Keep it only if you use it.
- **Linux as a second first-class app, unless it moves to `Catalog`.** Two apps with different meanings of reject (bug 3) is worse than one. Moving it is cheap, so do that rather than cutting.
- **"Trash all red" as a separate command.** Merge it with Clear out.

## Top 10

| # | What | Effort | Impact |
|---|---|---|---|
| 1 | Fix label fallback so an unmapped or `null` label can never become a reject, and add the test (bug 1) | Small | High |
| 2 | Lock the web server down: no `debug`, localhost only, remove CORS (bugs 7, 8) | Small | High |
| 3 | Decide the label model: separate decisions from labels, stop overwriting them, and show foreign rejects separately before Trash (bug 2) | Medium | High |
| 4 | Fix sidecar vs embedded precedence, and add a "write all into JPEGs" action (bugs 4, 5) | Medium | High |
| 5 | Make decoding concurrent, use embedded previews, add a disk thumbnail cache | Medium | High |
| 6 | Move writes off the main thread with optimistic UI | Medium | High |
| 7 | Run the Bridge round-trip plan and keep the files as fixtures; add fuzzing | Medium | High |
| 8 | Multi-select and batch marks in the grid | Medium | High |
| 9 | Move Linux onto `Catalog` so both apps agree (bug 3) | Medium | Medium |
| 10 | Capture-date sort, 100% zoom at the cursor, Mac menu bar, and key repeat for navigation | Medium | High |

After those, the next tier is folder tree, Open With, RAW+JPEG stacks and N-up compare, then "best of burst", which is where BestShot stops being a Bridge replacement and becomes the reason to switch.
