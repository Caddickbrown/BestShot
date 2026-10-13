mod cull;
mod library;
mod media;
mod store;
mod video;

use library::{Item, Kind};
use serde::Serialize;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use store::{Decision, Store};
use tauri::http::StatusCode;
use tauri::{Manager, State};

const CACHE_LIMIT_BYTES: u64 = 2 * 1024 * 1024 * 1024;

/// The folder currently being reviewed. `gen` changes on every (re)open so the
/// webview never shows a cached image for a different file at the same index.
struct Session {
    gen: u64,
    root: PathBuf,
    items: Vec<Item>,
    store: Store,
}

struct AppState {
    session: Mutex<Option<Session>>,
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
    warning: Option<String>,
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
    let (items, store, warning) = blocking(move || -> Result<_, String> {
        let items = library::scan(&root, recursive, include_videos).map_err(|e| e.to_string())?;
        let (mut store, warning) = store::load(&root);
        // Forget decisions for files that have since been moved or deleted.
        let before = store.decisions.len();
        store.decisions.retain(|rel, _| root.join(rel).exists());
        if store.decisions.len() != before {
            let _ = store::save(&root, &store);
        }
        Ok((items, store, warning))
    })
    .await??;

    let root = session_root;
    let gen = NEXT_GEN.fetch_add(1, Ordering::Relaxed);
    let info = SessionInfo {
        gen,
        root: root.to_string_lossy().into_owned(),
        name: root.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
        items: items.clone(),
        decisions: store.decisions.clone(),
        warning,
    };
    *state.session.lock().unwrap() = Some(Session { gen, root, items, store });
    Ok(info)
}

#[tauri::command]
async fn set_decision(
    state: State<'_, AppState>,
    gen: u64,
    rel: String,
    decision: Option<Decision>,
) -> Result<(), String> {
    let mut guard = state.session.lock().unwrap();
    let session = guard.as_mut().filter(|s| s.gen == gen).ok_or("That folder is no longer open")?;
    match decision {
        Some(d) => session.store.decisions.insert(rel, d),
        None => session.store.decisions.remove(&rel),
    };
    store::save(&session.root, &session.store).map_err(|e| format!("Couldn't save decisions: {e}"))
}

#[tauri::command]
async fn photo_info(state: State<'_, AppState>, gen: u64, index: usize) -> Result<media::Info, String> {
    let (root, item) = lookup(&state, gen, index)?;
    blocking(move || media::info(&root, &item)).await
}

#[tauri::command]
async fn apply_cull(state: State<'_, AppState>, gen: u64, mode: cull::Mode) -> Result<cull::Outcome, String> {
    let (root, rejects) = {
        let guard = state.session.lock().unwrap();
        let session = guard.as_ref().filter(|s| s.gen == gen).ok_or("That folder is no longer open")?;
        let rejects: Vec<Item> = session
            .items
            .iter()
            .filter(|i| session.store.decisions.get(&i.rel) == Some(&Decision::Reject))
            .cloned()
            .collect();
        (session.root.clone(), rejects)
    };

    let outcome = {
        let root = root.clone();
        blocking(move || cull::apply(&root, &rejects.iter().collect::<Vec<_>>(), mode)).await?
    };

    let mut guard = state.session.lock().unwrap();
    if let Some(session) = guard.as_mut().filter(|s| s.gen == gen) {
        for rel in &outcome.culled {
            session.store.decisions.remove(rel);
        }
        store::save(&session.root, &session.store).map_err(|e| format!("Couldn't save decisions: {e}"))?;
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
            app.manage(AppState {
                session: Mutex::new(None),
                cache_dir,
                thumb_pool: media::LifoPool::new(threads.saturating_sub(1).max(2)),
                video_base,
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            open_folder,
            set_decision,
            photo_info,
            apply_cull,
            reveal,
            open_external,
            video_base
        ])
        .run(tauri::generate_context!())
        .expect("error while running BestShot");
}
