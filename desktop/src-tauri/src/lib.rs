mod media;
mod video;

use bestshot_core::{catalog, cull, labels, library, store};

use catalog::{Catalog, Row, Snapshot};
use labels::Colour;
use library::{Item, Kind};
use serde::Serialize;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use store::Decision;
use tauri::http::StatusCode;
use tauri::{Manager, State};

const CACHE_LIMIT_BYTES: u64 = 2 * 1024 * 1024 * 1024;

/// The folder currently being reviewed. `gen` changes on every (re)open so the
/// webview never shows a cached image for a different file at the same index.
///
/// The catalog is the Mac's: stars, colour labels and keywords in standard XMP,
/// with keep and reject as green and red, so a folder reads the same on both.
/// It's `None` only while Finish is moving files.
struct Session {
    gen: u64,
    root: PathBuf,
    items: Vec<Item>,
    catalog: Option<Catalog>,
}

struct AppState {
    session: Mutex<Option<Session>>,
    /// The label names, in the same `labels.json` shape the Mac app writes.
    labels_path: PathBuf,
    cache_dir: PathBuf,
    thumb_pool: media::LifoPool,
    /// Base URL of the loopback video server, if it started.
    video_base: Option<String>,
}

static NEXT_GEN: AtomicU64 = AtomicU64::new(1);

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SessionInfo {
    gen: u64,
    root: String,
    name: String,
    items: Vec<Item>,
    decisions: BTreeMap<String, Decision>,
    /// Stars and colour, for photos that have either.
    marks: BTreeMap<String, Mark>,
    ranking: Vec<String>,
    warning: Option<String>,
}

/// What the loupe shows besides the decision.
#[derive(Serialize, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
struct Mark {
    rating: i8,
    colour: Option<Colour>,
    /// The label text, when it isn't a colour BestShot knows.
    label: Option<String>,
}

/// One photo after a change, and how it was before, for undo.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Changed {
    rel: String,
    decision: Option<Decision>,
    mark: Mark,
    before: Snapshot,
    warning: Option<String>,
}

fn mark_of(row: &Row) -> Mark {
    Mark { rating: row.rating, colour: row.colour, label: row.label.clone().filter(|_| row.colour.is_none()) }
}

/// Decisions and marks for the frontend. A red or green label in the XMP is a
/// decision here, exactly as on the Mac.
fn summarise(catalog: &Catalog) -> (BTreeMap<String, Decision>, BTreeMap<String, Mark>) {
    let mut decisions = BTreeMap::new();
    let mut marks = BTreeMap::new();
    for row in catalog.rows() {
        if let Some(d) = row.decision {
            decisions.insert(row.rel.clone(), d);
        }
        let mark = mark_of(&row);
        if mark.rating != 0 || mark.colour.is_some() || mark.label.is_some() {
            marks.insert(row.rel.clone(), mark);
        }
    }
    (decisions, marks)
}

/// Runs one change on the open catalog and reports the photo afterwards.
fn change(
    state: &AppState,
    gen: u64,
    rel: &str,
    f: impl FnOnce(&mut Catalog) -> Result<catalog::Marked, String>,
) -> Result<Changed, String> {
    let mut guard = state.session.lock().unwrap();
    let session = guard.as_mut().filter(|s| s.gen == gen).ok_or("That folder is no longer open")?;
    let catalog = session.catalog.as_mut().ok_or("Still moving files")?;
    let before = catalog.snapshot(rel);
    let marked = f(catalog)?;
    catalog.flush();
    Ok(Changed {
        rel: rel.to_string(),
        decision: marked.row.decision,
        mark: mark_of(&marked.row),
        before,
        warning: marked.warning,
    })
}

fn blocking<T: Send + 'static>(f: impl FnOnce() -> T + Send + 'static) -> impl std::future::Future<Output = Result<T, String>> {
    let task = tauri::async_runtime::spawn_blocking(f);
    async move { task.await.map_err(|e| e.to_string()) }
}

/// Resolves `(gen, index)` from the frontend to the session root and item.
fn lookup(state: &AppState, gen: u64, index: usize) -> Result<(PathBuf, Item), String> {
    let guard = state.session.lock().unwrap();
    let session = guard.as_ref().filter(|s| s.gen == gen).ok_or("That folder is no longer open")?;
    let item = session.items.get(index).ok_or("No such photo")?;
    Ok((session.root.clone(), item.clone()))
}

#[tauri::command]
async fn open_folder(
    state: State<'_, AppState>,
    path: String,
    recursive: bool,
    include_videos: bool,
) -> Result<SessionInfo, String> {
    // A dropped file means "the folder it's in".
    let mut root = PathBuf::from(&path);
    if root.is_file() {
        root.pop();
    }
    let session_root = root.clone();
    let (labels, label_warning) = labels::load(&state.labels_path);
    let options = catalog::Options { labels, write_jpeg: false };
    let mut catalog = blocking(move || {
        Catalog::open(&root, recursive, include_videos, options).map_err(|e| e.to_string())
    })
    .await??;

    let root = session_root;
    let gen = NEXT_GEN.fetch_add(1, Ordering::Relaxed);
    let (decisions, marks) = summarise(&catalog);
    let problems = catalog.problems();
    let warning = [
        catalog.take_warning(),
        label_warning,
        (!problems.is_empty()).then(|| {
            format!("{} couldn't be read, and won't be written: {}", problems.len(), problems[0].0)
        }),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>();
    let items = catalog.items().to_vec();
    let info = SessionInfo {
        gen,
        root: root.to_string_lossy().into_owned(),
        name: root.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
        items: items.clone(),
        decisions,
        marks,
        ranking: catalog.ranking().to_vec(),
        warning: (!warning.is_empty()).then(|| warning.join(" ")),
    };
    *state.session.lock().unwrap() = Some(Session { gen, root, items, catalog: Some(catalog) });
    Ok(info)
}

/// Keep is green and reject red, in the XMP and `.bestshot-cull.json`, as on the Mac.
#[tauri::command]
async fn set_decision(
    state: State<'_, AppState>,
    gen: u64,
    rel: String,
    decision: Option<Decision>,
) -> Result<Changed, String> {
    change(&state, gen, &rel, |c| c.set_decision(&rel, decision))
}

/// 1-5 stars, 0 to clear.
#[tauri::command]
async fn set_rating(state: State<'_, AppState>, gen: u64, rel: String, stars: u8) -> Result<Changed, String> {
    change(&state, gen, &rel, |c| c.set_rating(&rel, stars))
}

/// What 6-9 do: that colour, or none if it's already that colour.
#[tauri::command]
async fn toggle_colour(state: State<'_, AppState>, gen: u64, rel: String, colour: Colour) -> Result<Changed, String> {
    change(&state, gen, &rel, |c| c.toggle_colour(&rel, colour))
}

/// Undo: puts the photo back as `snapshot` says.
#[tauri::command]
async fn restore(state: State<'_, AppState>, gen: u64, rel: String, snapshot: Snapshot) -> Result<Changed, String> {
    change(&state, gen, &rel, |c| c.restore(&rel, &snapshot))
}

/// Replaces the saved rank order (best first).
#[tauri::command]
async fn set_ranking(state: State<'_, AppState>, gen: u64, ranking: Vec<String>) -> Result<(), String> {
    let mut guard = state.session.lock().unwrap();
    let session = guard.as_mut().filter(|s| s.gen == gen).ok_or("That folder is no longer open")?;
    let catalog = session.catalog.as_mut().ok_or("Still moving files")?;
    catalog.set_ranking(ranking).map_err(|e| format!("Couldn't save ranking: {e}"))
}

#[tauri::command]
async fn photo_info(state: State<'_, AppState>, gen: u64, index: usize) -> Result<media::Info, String> {
    let (root, item) = lookup(&state, gen, index)?;
    blocking(move || media::info(&root, &item)).await
}

/// Moves every reject, red label or saved decision alike, as the Mac does.
#[tauri::command]
async fn apply_cull(state: State<'_, AppState>, gen: u64, mode: cull::Mode) -> Result<cull::Outcome, String> {
    let mut catalog = {
        let mut guard = state.session.lock().unwrap();
        let session = guard.as_mut().filter(|s| s.gen == gen).ok_or("That folder is no longer open")?;
        session.catalog.take().ok_or("Already moving files")?
    };
    let (catalog, outcome) = blocking(move || {
        let trash = |p: &std::path::Path| trash::delete(p).map_err(|e| e.to_string());
        let outcome = catalog.apply_cull(mode, &trash);
        (catalog, outcome)
    })
    .await?;
    // The frontend reopens the folder next, so the old session only needs its catalog back.
    if let Some(session) = state.session.lock().unwrap().as_mut().filter(|s| s.gen == gen) {
        session.catalog = Some(catalog);
    }
    Ok(outcome)
}

#[tauri::command]
fn video_base(state: State<'_, AppState>) -> Option<String> {
    state.video_base.clone()
}

#[tauri::command]
async fn reveal(state: State<'_, AppState>, gen: u64, index: usize) -> Result<(), String> {
    let (root, item) = lookup(&state, gen, index)?;
    tauri_plugin_opener::reveal_item_in_dir(root.join(item.rel)).map_err(|e| e.to_string())
}

#[tauri::command]
async fn open_external(state: State<'_, AppState>, gen: u64, index: usize) -> Result<(), String> {
    let (root, item) = lookup(&state, gen, index)?;
    tauri_plugin_opener::open_path(root.join(item.rel), None::<&str>).map_err(|e| e.to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        // bestshot://localhost/{thumb|full}/{gen}/{index}
        .register_asynchronous_uri_scheme_protocol("bestshot", |ctx, request, responder| {
            let app = ctx.app_handle().clone();
            let state = app.state::<AppState>();
            let parts: Vec<&str> = request.uri().path().trim_matches('/').split('/').collect();
            let parsed = match parts.as_slice() {
                [variant, gen, index] => {
                    let variant = match *variant {
                        "thumb" => Some(media::Variant::Thumb),
                        "full" => Some(media::Variant::Full),
                        _ => None,
                    };
                    variant.zip(gen.parse().ok()).zip(index.parse().ok())
                }
                _ => None,
            };
            let Some(((variant, gen), index)) = parsed else {
                return responder.respond(media::error_response(StatusCode::BAD_REQUEST, "Bad media URL"));
            };
            let (root, item) = match lookup(&state, gen, index) {
                Ok(found) => found,
                Err(e) => return responder.respond(media::error_response(StatusCode::NOT_FOUND, &e)),
            };
            let cache = state.cache_dir.clone();
            let job = move || responder.respond(media::respond(&cache, &root, &item, variant));
            match variant {
                // Thumbnails can queue up by the thousand; full-size requests
                // are what the user is looking at right now, so never wait.
                media::Variant::Thumb => state.thumb_pool.spawn(job),
                media::Variant::Full => {
                    std::thread::spawn(job);
                }
            }
        })
        .setup(|app| {
            let cache_dir = app.path().app_cache_dir()?;
            std::fs::create_dir_all(&cache_dir)?;
            {
                let cache_dir = cache_dir.clone();
                std::thread::spawn(move || media::prune_cache(&cache_dir, CACHE_LIMIT_BYTES));
            }
            let handle = app.handle().clone();
            let video_base = video::start(Arc::new(move |gen, index| {
                let (root, item) = lookup(&handle.state::<AppState>(), gen, index).ok()?;
                (item.kind == Kind::Video).then(|| (root.join(&item.rel), item.ext))
            }))
            .map(|s| format!("http://127.0.0.1:{}/{}", s.port, s.token))
            .map_err(|e| eprintln!("bestshot: couldn't start video server: {e}"))
            .ok();
            let threads = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
            let labels_path = app.path().app_config_dir()?.join("labels.json");
            app.manage(AppState {
                session: Mutex::new(None),
                labels_path,
                cache_dir,
                thumb_pool: media::LifoPool::new(threads.saturating_sub(1).max(2)),
                video_base,
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            open_folder,
            set_decision,
            set_rating,
            toggle_colour,
            restore,
            set_ranking,
            photo_info,
            apply_cull,
            reveal,
            open_external,
            video_base
        ])
        .run(tauri::generate_context!())
        .expect("error while running BestShot");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folder() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            std::fs::write(dir.path().join(name), b"not really a jpeg").unwrap();
        }
        dir
    }

    /// A folder labelled in Bridge or on the Mac reads the same on Linux:
    /// Red is a reject and Green a keep, from the XMP alone.
    #[test]
    fn labels_in_the_xmp_are_decisions_here() {
        let dir = folder();
        let xmp = |label: &str, rating: u8| {
            format!(
                r#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Label="{label}" xmp:Rating="{rating}"/></rdf:RDF></x:xmpmeta>"#
            )
        };
        std::fs::write(dir.path().join("a.xmp"), xmp("Red", 0)).unwrap();
        std::fs::write(dir.path().join("b.xmp"), xmp("Green", 4)).unwrap();
        let catalog = Catalog::open(dir.path(), false, false, catalog::Options::default()).unwrap();
        let (decisions, marks) = summarise(&catalog);
        assert_eq!(decisions.get("a.jpg"), Some(&Decision::Reject));
        assert_eq!(decisions.get("b.jpg"), Some(&Decision::Keep));
        assert_eq!(decisions.get("c.jpg"), None);
        assert_eq!(marks.get("b.jpg"), Some(&Mark { rating: 4, colour: Some(Colour::Green), label: None }));
        assert!(!marks.contains_key("c.jpg"));
    }

    /// Keeping on Linux writes a green label the Mac (and Bridge) can see, and
    /// the snapshot taken first puts it back.
    #[test]
    fn a_keep_writes_xmp_and_undo_restores_it() {
        let dir = folder();
        let mut catalog = Catalog::open(dir.path(), false, false, catalog::Options::default()).unwrap();
        let before = catalog.snapshot("c.jpg");
        catalog.set_decision("c.jpg", Some(Decision::Keep)).unwrap();
        catalog.set_rating("c.jpg", 3).unwrap();
        let sidecar = std::fs::read_to_string(dir.path().join("c.xmp")).unwrap();
        assert!(sidecar.contains("Green"), "{sidecar}");
        let reopened = Catalog::open(dir.path(), false, false, catalog::Options::default()).unwrap();
        let (decisions, marks) = summarise(&reopened);
        assert_eq!(decisions.get("c.jpg"), Some(&Decision::Keep));
        assert_eq!(marks.get("c.jpg").map(|m| m.rating), Some(3));
        catalog.restore("c.jpg", &before).unwrap();
        let (decisions, marks) = summarise(&catalog);
        assert_eq!(decisions.get("c.jpg"), None);
        assert!(!marks.contains_key("c.jpg"));
    }
}
