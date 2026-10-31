//! UniFFI bindings over `bestshot-core` for the iOS/macOS app.
//!
//! Generate the Swift side with `apple/scripts/build-core.sh`, which also
//! builds the XCFramework the app links against.

use bestshot_core::{cull, library, rank, store};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

uniffi::setup_scaffolding!();

// ---------------------------------------------------------------------------
// Folders

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum MediaKind {
    Image,
    Video,
}

/// One reviewable item in a folder.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FolderItem {
    /// Path relative to the folder, always `/`-separated.
    pub rel: String,
    pub kind: MediaKind,
    pub ext: String,
    pub size: u64,
    /// Seconds since the Unix epoch.
    pub mtime: i64,
    /// Files culled together with this one (Live Photo video, sidecars).
    pub companions: Vec<String>,
}

impl From<library::Item> for FolderItem {
    fn from(i: library::Item) -> Self {
        Self {
            rel: i.rel,
            kind: match i.kind {
                library::Kind::Image => MediaKind::Image,
                library::Kind::Video => MediaKind::Video,
            },
            ext: i.ext,
            size: i.size,
            mtime: i.mtime,
            companions: i.companions,
        }
    }
}

impl From<FolderItem> for library::Item {
    fn from(i: FolderItem) -> Self {
        Self {
            rel: i.rel,
            kind: match i.kind {
                MediaKind::Image => library::Kind::Image,
                MediaKind::Video => library::Kind::Video,
            },
            ext: i.ext,
            size: i.size,
            mtime: i.mtime,
            companions: i.companions,
        }
    }
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("{message}")]
    Io { message: String },
}

/// Scans a folder into reviewable items, in natural filename order.
#[uniffi::export]
pub fn scan_folder(root: String, recursive: bool, include_videos: bool) -> Result<Vec<FolderItem>, CoreError> {
    library::scan(Path::new(&root), recursive, include_videos)
        .map(|items| items.into_iter().map(Into::into).collect())
        .map_err(|e| CoreError::Io { message: e.to_string() })
}

// ---------------------------------------------------------------------------
// .bestshot-cull.json

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum Decision {
    Keep,
    Reject,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CullStore {
    pub version: u32,
    /// Relative path -> decision. Unreviewed files have no entry.
    pub decisions: HashMap<String, Decision>,
    /// Relative paths, best first.
    pub ranking: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StoreLoad {
    pub store: CullStore,
    /// Set when the saved file was unreadable and has been set aside.
    pub warning: Option<String>,
}

impl From<store::Store> for CullStore {
    fn from(s: store::Store) -> Self {
        Self {
            version: s.version,
            decisions: s
                .decisions
                .into_iter()
                .map(|(k, d)| {
                    let d = match d {
                        store::Decision::Keep => Decision::Keep,
                        store::Decision::Reject => Decision::Reject,
                    };
                    (k, d)
                })
                .collect(),
            ranking: s.ranking,
        }
    }
}

impl From<CullStore> for store::Store {
    fn from(s: CullStore) -> Self {
        Self {
            version: s.version,
            decisions: s
                .decisions
                .into_iter()
                .map(|(k, d)| {
                    let d = match d {
                        Decision::Keep => store::Decision::Keep,
                        Decision::Reject => store::Decision::Reject,
                    };
                    (k, d)
                })
                .collect(),
            ranking: s.ranking,
        }
    }
}

/// Loads a folder's decisions and ranking, forgetting entries for files that
/// no longer exist (and saving that cleanup).
#[uniffi::export]
pub fn load_store(root: String) -> StoreLoad {
    let root = PathBuf::from(root);
    let (mut s, warning) = store::load(&root);
    let before = (s.decisions.len(), s.ranking.len());
    s.decisions.retain(|rel, _| root.join(rel).exists());
    s.ranking.retain(|rel| root.join(rel).exists());
    if (s.decisions.len(), s.ranking.len()) != before {
        let _ = store::save(&root, &s);
    }
    StoreLoad { store: s.into(), warning }
}

/// Atomically saves a folder's decisions and ranking.
#[uniffi::export]
pub fn save_store(root: String, store: CullStore) -> Result<(), CoreError> {
    store::save(Path::new(&root), &store.into()).map_err(|e| CoreError::Io { message: e.to_string() })
}

// ---------------------------------------------------------------------------
// Culling

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum CullMode {
    Trash,
    Folder,
}

/// Sends one file to the platform's Trash. Implemented in Swift with
/// `FileManager.trashItem`. Returns an error message, or `None` on success.
#[uniffi::export(with_foreign)]
pub trait Trasher: Send + Sync {
    fn trash(&self, path: String) -> Option<String>;
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CullFailure {
    pub rel: String,
    pub error: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CullOutcome {
    pub items: u32,
    pub files: u32,
    pub bytes: u64,
    pub culled: Vec<String>,
    pub failed: Vec<CullFailure>,
}

/// Moves each reject and its companions to the Trash or `_Rejected/`.
#[uniffi::export]
pub fn apply_cull(root: String, rejects: Vec<FolderItem>, mode: CullMode, trasher: Arc<dyn Trasher>) -> CullOutcome {
    let items: Vec<library::Item> = rejects.into_iter().map(Into::into).collect();
    let refs: Vec<&library::Item> = items.iter().collect();
    let mode = match mode {
        CullMode::Trash => cull::Mode::Trash,
        CullMode::Folder => cull::Mode::Folder,
    };
    let trash = |p: &Path| match trasher.trash(p.to_string_lossy().into_owned()) {
        None => Ok(()),
        Some(err) => Err(err),
    };
    let out = cull::apply(Path::new(&root), &refs, mode, &trash);
    CullOutcome {
        items: out.items as u32,
        files: out.files as u32,
        bytes: out.bytes,
        culled: out.culled,
        failed: out.failed.into_iter().map(|f| CullFailure { rel: f.rel, error: f.error }).collect(),
    }
}

// ---------------------------------------------------------------------------
// Ranking

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum RankScope {
    All,
    Unranked,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum RankChoice {
    Left,
    Right,
    Skip,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RankPair {
    pub left: String,
    pub right: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RankProgress {
    pub asked: u32,
    pub inferred: u32,
    pub total_pairs: u32,
    pub percent: u32,
    pub finished: bool,
    pub can_undo: bool,
}

/// A Compare session over ids (Photos local identifiers or folder paths).
#[derive(uniffi::Object)]
pub struct RankSession {
    inner: Mutex<rank::RankSession>,
}

#[uniffi::export]
impl RankSession {
    /// `ranking` is the saved order (best first); entries not in `ids` are ignored.
    #[uniffi::constructor]
    pub fn new(ids: Vec<String>, ranking: Vec<String>, scope: RankScope) -> Arc<Self> {
        let scope = match scope {
            RankScope::All => rank::Scope::All,
            RankScope::Unranked => rank::Scope::Unranked,
        };
        Arc::new(Self { inner: Mutex::new(rank::RankSession::new(ids, &ranking, scope)) })
    }

    pub fn current_pair(&self) -> Option<RankPair> {
        self.inner.lock().unwrap().current_pair().map(|(left, right)| RankPair { left, right })
    }

    pub fn choose(&self, choice: RankChoice) {
        self.inner.lock().unwrap().choose(match choice {
            RankChoice::Left => rank::Choice::Left,
            RankChoice::Right => rank::Choice::Right,
            RankChoice::Skip => rank::Choice::Skip,
        });
    }

    pub fn undo(&self) -> bool {
        self.inner.lock().unwrap().undo()
    }

    pub fn progress(&self) -> RankProgress {
        let s = self.inner.lock().unwrap();
        RankProgress {
            asked: s.asked(),
            inferred: s.inferred(),
            total_pairs: s.total_pairs(),
            percent: s.percent(),
            finished: s.is_finished(),
            can_undo: s.can_undo(),
        }
    }

    /// Best first; photos with no result yet stay unranked.
    pub fn order(&self) -> Vec<String> {
        self.inner.lock().unwrap().order()
    }

    /// This session's order, then anything in `saved` outside the pool.
    pub fn merged_ranking(&self, saved: Vec<String>) -> Vec<String> {
        self.inner.lock().unwrap().merged_ranking(&saved)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct NoTrash;
    impl Trasher for NoTrash {
        fn trash(&self, path: String) -> Option<String> {
            Some(format!("refused {path}"))
        }
    }

    #[test]
    fn folder_round_trip_through_the_ffi_types() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().to_string_lossy().into_owned();
        for f in ["IMG_1.HEIC", "IMG_1.MOV", "IMG_2.JPG"] {
            std::fs::write(dir.path().join(f), b"data").unwrap();
        }

        let items = scan_folder(root.clone(), true, true).unwrap();
        assert_eq!(items.iter().map(|i| i.rel.as_str()).collect::<Vec<_>>(), ["IMG_1.HEIC", "IMG_2.JPG"]);
        assert_eq!(items[0].companions, ["IMG_1.MOV"]);

        let mut s = load_store(root.clone()).store;
        s.decisions.insert("IMG_1.HEIC".into(), Decision::Reject);
        s.ranking = vec!["IMG_2.JPG".into()];
        save_store(root.clone(), s.clone()).unwrap();
        assert_eq!(load_store(root.clone()).store, s);

        // Trash failures are reported per item, and nothing moves.
        let out = apply_cull(root.clone(), vec![items[0].clone()], CullMode::Trash, Arc::new(NoTrash));
        assert_eq!(out.items, 0);
        assert_eq!(out.failed.len(), 1);

        let out = apply_cull(root.clone(), vec![items[0].clone()], CullMode::Folder, Arc::new(NoTrash));
        assert_eq!((out.items, out.files), (1, 2));
        assert!(dir.path().join("_Rejected/IMG_1.MOV").exists());

        // The ranking entry for a moved file is forgotten on the next load.
        s.ranking.push("IMG_1.HEIC".into());
        save_store(root.clone(), s).unwrap();
        assert_eq!(load_store(root).store.ranking, ["IMG_2.JPG"]);
    }

    #[test]
    fn rank_session_through_the_ffi() {
        let s = RankSession::new(vec!["a".into(), "b".into(), "c".into()], vec![], RankScope::All);
        while let Some(pair) = s.current_pair() {
            s.choose(if pair.left < pair.right { RankChoice::Left } else { RankChoice::Right });
        }
        let p = s.progress();
        assert!(p.finished && p.can_undo && p.percent == 100);
        assert_eq!(s.order(), ["a", "b", "c"]);
    }
}
