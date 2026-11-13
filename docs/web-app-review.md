# Web app review

13 November 2026. The web app (`app/main.py`, `templates/index.html`,
`static/app.js`, `static/styles.css` + `static/theme.css`) compared with the
iPhone/iPad app as it is today. It's a review, not a plan: the web app is the
original "projects + Compare" tool, and `docs/suggestions.md` already says not
to grow it. What's below is where the two have drifted apart, what to bring in
line if the web app stays, and the small things fixed now.

## What's the same

- **The look.** `theme.css` uses the same tokens as `apple/BestShot/Utilities/Theme.swift`
  (table `#efebe1`, paper, tile, ink, grease-pencil red `#c8261d`), the same fonts
  (Archivo for headings, IBM Plex Mono for everything else, both bundled) and the
  same grease-pencil circle and underline paths. The viewer and Compare are the
  black viewfinder, as on iOS.
- **Projects and Compare.** Upload, rank by Compare or drag, tags, comments,
  bulk tag / download / delete, export JSON / CSV / ZIP, EXIF, slideshow and
  All Media all exist on both sides. The iOS Projects screens are a port of this.

## Where it has diverged

| Area | iPhone / iPad | Web | Bring in line? |
|---|---|---|---|
| **What it's for** | Triage, Organise and Rank work on the Photos library; Projects are a side section | Projects are the whole app | No. The web app can't reach a Photos library. Say so on its first screen instead of implying parity. |
| **Name for a project** | "Project" (menu, New Project, Delete Project) | "Album" everywhere (New Album, All Albums, Rename Album) | **Yes.** "Album" on iOS means a Photos album (Organise files into them). Rename the web's labels to Project; the API already says `projects`. |
| **Deleting a project** | Moves its photos to Files (BestShot › Removed Projects), with a confirmation | Was `shutil.rmtree`, "cannot be undone" | **Fixed now**: moves the folder to `.removed/<name> <time>` in the projects folder, hidden from the lists. |
| **Deleting a photo** | Bulk delete in a project removes BestShot's copy | `DELETE …/files/<name>` and `batch-delete` unlink files, "cannot be undone" | Yes: move to `.removed` like projects. Also suggestion 25 (batch-delete can unlink the metadata files). |
| **Rename / description** | Rename from the menu (swipe, long-press) or the project's ⋯ menu; no description editing | Rename and Edit description | Small: add Edit description to the iOS rename sheet if descriptions matter; otherwise drop it from the web. |
| **Move a photo between projects** | No | Drag to another album (`move-file`) | Leave. Low value on iOS; the web's version has dead code (suggestion 26). |
| **Compare** | Skip, Undo; Esc saves and shows the Proposed Ranking | Skip (tie), Continue Later, Apply / Discard | Match the words: the web's "Ranking Complete!" and "Continue Later" vs iOS "Proposed Ranking" and Esc. Both should use the Rust ranker eventually (the iOS one is `ComparisonEngine.swift`, the web's is JS). |
| **Tags** | Project tags; library photos get tags in Triage (tags for the run) and on the monitor | Project tags only | Fine as is. |
| **Light / dark** | Settings → Appearance: System, Light, Dark | A toggle in the gear menu, saved in the browser, with emoji icons | Yes: offer System as well, and use words, not 🌙 / ☀️. |
| **Icons** | SF Symbols, quiet | Emoji and text glyphs (⚙ ⋮ ▼ ↺ ×) | Yes, gradually: one icon set (inline SVG of the same shapes) would read like the app. |
| **Keys** | Esc always leads back to the menu; ⌘. too; Monitor keys | Its own shortcut sheet | Check the shared ones match: Compare's ← → Space ⌫, Esc closes what's on top. |
| **Logo** | App icon (a print in viewfinder corners) and, now, the same mark in the main menu | Manifest pointed at icons that didn't exist; the name was "BestShot Darkroom" | **Fixed now**: icons made from the app icon, name and description corrected, favicon and touch icon linked. |
| **Tools** (Join Videos, Anti-Crop) | iPhone and iPad | None | No. The spec (`media-tools-spec.md`) defers web. |
| **Safety** | Local, sandboxed | Localhost web server, no login | Keep it localhost-only (suggestion 7 is done; 21, 22, 24 are open). |

## Fixed now

- `DELETE /api/projects/<name>` moves the project to `.removed/` instead of
  deleting it; `.removed` (and any dot folder) is left out of the project list
  and All Media. The confirmation says where the files go. Test:
  `tests/test_web_safety.py::test_deleting_a_project_moves_its_files_aside_and_hides_them`.
- `static/icon-192.png`, `icon-512.png` and `apple-touch-icon.png` from the app
  icon, linked from the page; the manifest's name is BestShot and its
  description no longer says "dockerized studio".
- Emoji taken out of the duplicate-files heading and the mobile project button.
- Service worker cache bumped to `bestshot-v1.2.1` so the new page and icons load.

## Not done (bigger than "small and safe")

1. Rename "Album" to "Project" across `index.html` and `app.js` (about 40 strings).
2. Single and bulk photo delete to `.removed`, with the batch-delete name check.
3. Light / dark / System, and words instead of emoji in the gear menu.
4. One icon set for the web.
5. Compare's wording, and in time one ranker (Rust) for both.
