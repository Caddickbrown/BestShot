//! UniFFI bindings over `bestshot-core` for the iOS/macOS app.
//!
//! Generate the Swift side with `apple/scripts/build-core.sh`, which also
//! builds the XCFramework the app links against.

use bestshot_core::{catalog, cull, labels, library, rank, store, xmp};
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
    /// This item's `.xmp` sidecar: the existing file, or where a new one goes.
    pub sidecar: String,
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
            sidecar: i.sidecar,
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
            sidecar: i.sidecar,
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

// ---------------------------------------------------------------------------
// Labels

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum LabelColour {
    Red,
    Yellow,
    Green,
    Blue,
    Purple,
}

impl From<labels::Colour> for LabelColour {
    fn from(c: labels::Colour) -> Self {
        match c {
            labels::Colour::Red => Self::Red,
            labels::Colour::Yellow => Self::Yellow,
            labels::Colour::Green => Self::Green,
            labels::Colour::Blue => Self::Blue,
            labels::Colour::Purple => Self::Purple,
        }
    }
}

impl From<LabelColour> for labels::Colour {
    fn from(c: LabelColour) -> Self {
        match c {
            LabelColour::Red => Self::Red,
            LabelColour::Yellow => Self::Yellow,
            LabelColour::Green => Self::Green,
            LabelColour::Blue => Self::Blue,
            LabelColour::Purple => Self::Purple,
        }
    }
}

/// The text written for each colour, and how label text found in files maps
/// to colours. A `None` colour means "not a colour".
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct LabelSettings {
    pub names: HashMap<LabelColour, String>,
    pub aliases: HashMap<String, Option<LabelColour>>,
    /// How a label looks on screen, `#RRGGBB`. A colour not here keeps its own look.
    pub tints: HashMap<LabelColour, String>,
}

impl From<labels::LabelConfig> for LabelSettings {
    fn from(c: labels::LabelConfig) -> Self {
        Self {
            names: c.names.into_iter().map(|(k, v)| (k.into(), v)).collect(),
            aliases: c.aliases.into_iter().map(|(k, v)| (k, v.map(Into::into))).collect(),
            tints: c.tints.into_iter().map(|(k, v)| (k.into(), v)).collect(),
        }
    }
}

impl From<LabelSettings> for labels::LabelConfig {
    fn from(s: LabelSettings) -> Self {
        Self {
            names: s.names.into_iter().map(|(k, v)| (k.into(), v)).collect(),
            aliases: s.aliases.into_iter().map(|(k, v)| (k, v.map(Into::into))).collect(),
            tints: s.tints.into_iter().map(|(k, v)| (k.into(), v)).collect(),
            ..Default::default()
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct LabelSettingsLoad {
    pub settings: LabelSettings,
    /// Set when the saved file was unreadable and has been set aside.
    pub warning: Option<String>,
}

/// Loads the label settings, or the defaults if there are none yet.
#[uniffi::export]
pub fn load_label_settings(path: String) -> LabelSettingsLoad {
    let (config, warning) = labels::load(Path::new(&path));
    LabelSettingsLoad { settings: config.into(), warning }
}

#[uniffi::export]
pub fn save_label_settings(path: String, settings: LabelSettings) -> Result<(), CoreError> {
    labels::save(Path::new(&path), &settings.into()).map_err(|e| CoreError::Io { message: e.to_string() })
}

/// Renames a colour; files written under the old name keep their colour.
#[uniffi::export]
pub fn rename_label(settings: LabelSettings, colour: LabelColour, name: String) -> Result<LabelSettings, CoreError> {
    let mut config: labels::LabelConfig = settings.into();
    config.rename(colour.into(), &name).map_err(|message| CoreError::Io { message })?;
    Ok(config.into())
}

/// Sets how a label looks, or puts its own look back with `None`.
#[uniffi::export]
pub fn tint_label(settings: LabelSettings, colour: LabelColour, hex: Option<String>) -> Result<LabelSettings, CoreError> {
    let mut config: labels::LabelConfig = settings.into();
    config.set_tint(colour.into(), hex.as_deref()).map_err(|message| CoreError::Io { message })?;
    Ok(config.into())
}

/// Maps label text found in files to a colour, or to "not a colour".
#[uniffi::export]
pub fn map_label(settings: LabelSettings, text: String, colour: Option<LabelColour>) -> LabelSettings {
    let mut config: labels::LabelConfig = settings.into();
    config.map(&text, colour.map(Into::into));
    config.into()
}

/// What `text` maps to under `settings`.
#[uniffi::export]
pub fn label_colour_of(settings: LabelSettings, text: String) -> Option<LabelColour> {
    labels::LabelConfig::from(settings).colour_of(&text).map(Into::into)
}

/// What Bridge's default names suggest for `text`. Only a suggestion: nothing
/// is mapped until it's saved.
#[uniffi::export]
pub fn label_suggestion(text: String) -> Option<LabelColour> {
    labels::suggestion(&text).map(Into::into)
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct MetaProblem {
    pub rel: String,
    pub message: String,
}

/// One distinct label value found in a folder.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct LabelValue {
    pub text: String,
    /// `xmp:Label` or `photoshop:LabelColor`.
    pub field: String,
    pub count: u32,
    pub example: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct LabelScan {
    pub files: u32,
    pub values: Vec<LabelValue>,
    pub problems: Vec<MetaProblem>,
}

/// Lists the label values in a folder. Strictly read-only.
#[uniffi::export]
pub fn scan_labels(root: String, recursive: bool) -> Result<LabelScan, CoreError> {
    let scan = catalog::scan_labels(Path::new(&root), recursive).map_err(|e| CoreError::Io { message: e.to_string() })?;
    Ok(LabelScan {
        files: scan.files,
        values: scan
            .values
            .into_iter()
            .map(|v| LabelValue { text: v.text, field: v.field, count: v.count, example: v.example })
            .collect(),
        problems: scan.problems.into_iter().map(|(rel, message)| MetaProblem { rel, message }).collect(),
    })
}

// ---------------------------------------------------------------------------
// A folder's metadata

/// One item as the app shows it.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct MetaRow {
    pub rel: String,
    /// 0 for unrated, 1-5 stars, or -1 for Bridge's "Reject" rating.
    pub rating: i8,
    pub colour: Option<LabelColour>,
    /// The label text in the file. Set with no `colour` means it isn't mapped.
    pub label: Option<String>,
    /// The colour comes from a saved decision, not from the XMP.
    pub implied: bool,
    pub keywords: Vec<String>,
    pub decision: Option<Decision>,
    /// Why this file's metadata can't be read or written.
    pub problem: Option<String>,
}

fn decision_of(d: store::Decision) -> Decision {
    match d {
        store::Decision::Keep => Decision::Keep,
        store::Decision::Reject => Decision::Reject,
    }
}

fn core_decision(d: Decision) -> store::Decision {
    match d {
        Decision::Keep => store::Decision::Keep,
        Decision::Reject => store::Decision::Reject,
    }
}

impl From<catalog::Row> for MetaRow {
    fn from(r: catalog::Row) -> Self {
        Self {
            rel: r.rel,
            rating: r.rating,
            colour: r.colour.map(Into::into),
            label: r.label,
            implied: r.implied,
            keywords: r.keywords,
            decision: r.decision.map(decision_of),
            problem: r.problem,
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct MarkResult {
    pub row: MetaRow,
    /// Something to tell the user, though the mark itself succeeded.
    pub warning: Option<String>,
}

impl From<catalog::Marked> for MarkResult {
    fn from(m: catalog::Marked) -> Self {
        Self { row: m.row.into(), warning: m.warning }
    }
}

/// An item's exact state, for undo.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct MetaSnapshot {
    pub rating: Option<i8>,
    pub label: Option<String>,
    pub label_color: Option<String>,
    pub keywords: Vec<String>,
    pub decision: Option<Decision>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct FolderCounts {
    pub keep: u32,
    pub reject: u32,
    /// Labelled, but neither green nor red.
    pub other: u32,
    pub left: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ReviewStatus {
    All,
    Unreviewed,
    Keep,
    Reject,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum StarFilter {
    Any,
    AtLeast { stars: u8 },
    Exactly { stars: u8 },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum LabelPick {
    Colour { colour: LabelColour },
    /// No label of any kind.
    Unlabelled,
    /// Label text that isn't mapped to a colour.
    Other,
}

/// Every part must match; within `labels`, any one will do.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FolderFilter {
    pub status: ReviewStatus,
    pub stars: StarFilter,
    pub labels: Vec<LabelPick>,
    pub keywords: Vec<String>,
    /// Match any of `keywords` rather than all of them.
    pub any_keyword: bool,
}

impl From<FolderFilter> for catalog::Filter {
    fn from(f: FolderFilter) -> Self {
        Self {
            status: match f.status {
                ReviewStatus::All => catalog::Status::All,
                ReviewStatus::Unreviewed => catalog::Status::Unreviewed,
                ReviewStatus::Keep => catalog::Status::Keep,
                ReviewStatus::Reject => catalog::Status::Reject,
            },
            stars: match f.stars {
                StarFilter::Any => catalog::Stars::Any,
                StarFilter::AtLeast { stars } => catalog::Stars::AtLeast(stars),
                StarFilter::Exactly { stars } => catalog::Stars::Exactly(stars),
            },
            labels: f
                .labels
                .into_iter()
                .map(|p| match p {
                    LabelPick::Colour { colour } => catalog::LabelPick::Colour(colour.into()),
                    LabelPick::Unlabelled => catalog::LabelPick::Unlabelled,
                    LabelPick::Other => catalog::LabelPick::Other,
                })
                .collect(),
            keywords: f.keywords,
            any_keyword: f.any_keyword,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FolderSort {
    Name,
    Newest,
    Oldest,
    /// Most stars first.
    Stars,
    /// Colour order, unlabelled last.
    Label,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct KeywordCount {
    pub keyword: String,
    pub count: u32,
}

fn io_error(message: String) -> CoreError {
    CoreError::Io { message }
}

/// A folder's items, decisions and XMP metadata. See `bestshot_core::catalog`.
#[derive(uniffi::Object)]
pub struct FolderCatalog {
    inner: Mutex<catalog::Catalog>,
}

#[uniffi::export]
impl FolderCatalog {
    /// Scans `root` and reads its metadata, parsing only what has changed
    /// since the index in the folder was written.
    #[uniffi::constructor]
    pub fn open(
        root: String,
        recursive: bool,
        include_videos: bool,
        settings: LabelSettings,
        write_jpeg: bool,
    ) -> Result<Arc<Self>, CoreError> {
        let options = catalog::Options { labels: settings.into(), write_jpeg };
        let inner = catalog::Catalog::open(Path::new(&root), recursive, include_videos, options)
            .map_err(|e| io_error(e.to_string()))?;
        Ok(Arc::new(Self { inner: Mutex::new(inner) }))
    }

    /// Applies new settings; nothing is re-read.
    pub fn configure(&self, settings: LabelSettings, write_jpeg: bool) {
        self.inner.lock().unwrap().set_options(catalog::Options { labels: settings.into(), write_jpeg });
    }

    pub fn items(&self) -> Vec<FolderItem> {
        self.inner.lock().unwrap().items().iter().cloned().map(Into::into).collect()
    }

    pub fn rows(&self) -> Vec<MetaRow> {
        self.inner.lock().unwrap().rows().into_iter().map(Into::into).collect()
    }

    pub fn counts(&self) -> FolderCounts {
        let c = self.inner.lock().unwrap().counts();
        FolderCounts { keep: c.keep, reject: c.reject, other: c.other, left: c.left }
    }

    /// Item positions that pass `filter`, in `sort` order.
    pub fn query(&self, filter: FolderFilter, sort: FolderSort) -> Vec<u32> {
        let sort = match sort {
            FolderSort::Name => catalog::Sort::Name,
            FolderSort::Newest => catalog::Sort::Newest,
            FolderSort::Oldest => catalog::Sort::Oldest,
            FolderSort::Stars => catalog::Sort::Stars,
            FolderSort::Label => catalog::Sort::Label,
        };
        self.inner.lock().unwrap().query(&filter.into(), sort)
    }

    /// Every keyword in the folder, most used first.
    pub fn keywords(&self) -> Vec<KeywordCount> {
        self.inner
            .lock()
            .unwrap()
            .keywords()
            .into_iter()
            .map(|k| KeywordCount { keyword: k.keyword, count: k.count })
            .collect()
    }

    /// Files whose metadata couldn't be read.
    pub fn problems(&self) -> Vec<MetaProblem> {
        self.inner.lock().unwrap().problems().into_iter().map(|(rel, message)| MetaProblem { rel, message }).collect()
    }

    pub fn take_warning(&self) -> Option<String> {
        self.inner.lock().unwrap().take_warning()
    }

    /// Files that move with `rel`, including a sidecar written since the scan.
    pub fn companions(&self, rel: String) -> Vec<String> {
        let inner = self.inner.lock().unwrap();
        inner.items().iter().find(|i| i.rel == rel).map(|i| i.companions.clone()).unwrap_or_default()
    }

    /// 1-5 sets the stars, 0 clears them.
    pub fn set_rating(&self, rel: String, stars: u8) -> Result<MarkResult, CoreError> {
        self.inner.lock().unwrap().set_rating(&rel, stars).map(Into::into).map_err(io_error)
    }

    /// Sets a colour, or clears it if the photo already has that colour.
    pub fn toggle_colour(&self, rel: String, colour: LabelColour) -> Result<MarkResult, CoreError> {
        self.inner.lock().unwrap().toggle_colour(&rel, colour.into()).map(Into::into).map_err(io_error)
    }

    /// Keep is green and reject is red; `None` clears either.
    pub fn set_decision(&self, rel: String, decision: Option<Decision>) -> Result<MarkResult, CoreError> {
        self.inner.lock().unwrap().set_decision(&rel, decision.map(core_decision)).map(Into::into).map_err(io_error)
    }

    pub fn add_keyword(&self, rel: String, keyword: String) -> Result<MarkResult, CoreError> {
        self.inner.lock().unwrap().add_keyword(&rel, &keyword).map(Into::into).map_err(io_error)
    }

    pub fn remove_keyword(&self, rel: String, keyword: String) -> Result<MarkResult, CoreError> {
        self.inner.lock().unwrap().remove_keyword(&rel, &keyword).map(Into::into).map_err(io_error)
    }

    pub fn snapshot(&self, rel: String) -> MetaSnapshot {
        let s = self.inner.lock().unwrap().snapshot(&rel);
        MetaSnapshot {
            rating: s.fields.rating,
            label: s.fields.label,
            label_color: s.fields.label_color,
            keywords: s.fields.keywords,
            decision: s.decision.map(decision_of),
        }
    }

    pub fn restore(&self, rel: String, snapshot: MetaSnapshot) -> Result<MarkResult, CoreError> {
        let snapshot = catalog::Snapshot {
            fields: xmp::Fields {
                rating: snapshot.rating,
                label: snapshot.label,
                label_color: snapshot.label_color,
                keywords: snapshot.keywords,
            },
            decision: snapshot.decision.map(core_decision),
        };
        self.inner.lock().unwrap().restore(&rel, &snapshot).map(Into::into).map_err(io_error)
    }

    pub fn ranking(&self) -> Vec<String> {
        self.inner.lock().unwrap().ranking().to_vec()
    }

    pub fn set_ranking(&self, ranking: Vec<String>) -> Result<(), CoreError> {
        self.inner.lock().unwrap().set_ranking(ranking).map_err(|e| io_error(e.to_string()))
    }

    /// Everything counting as a reject, red or a saved decision alike.
    pub fn rejects(&self) -> Vec<FolderItem> {
        self.inner.lock().unwrap().rejects().into_iter().cloned().map(Into::into).collect()
    }

    /// Moves every reject and its companions to the Trash or `_Rejected/`,
    /// then rescans.
    pub fn apply_cull(&self, mode: CullMode, trasher: Arc<dyn Trasher>) -> CullOutcome {
        let mode = match mode {
            CullMode::Trash => cull::Mode::Trash,
            CullMode::Folder => cull::Mode::Folder,
        };
        let trash = |p: &Path| match trasher.trash(p.to_string_lossy().into_owned()) {
            None => Ok(()),
            Some(err) => Err(err),
        };
        let out = self.inner.lock().unwrap().apply_cull(mode, &trash);
        CullOutcome {
            items: out.items as u32,
            files: out.files as u32,
            bytes: out.bytes,
            culled: out.culled,
            failed: out.failed.into_iter().map(|f| CullFailure { rel: f.rel, error: f.error }).collect(),
        }
    }

    /// Saves the index. It's only a cache, so call this when leaving a folder
    /// rather than after every mark.
    pub fn flush(&self) {
        self.inner.lock().unwrap().flush();
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
    fn marking_and_filtering_through_the_ffi() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().to_string_lossy().into_owned();
        for f in ["a.jpg", "b.jpg", "c.jpg"] {
            std::fs::write(dir.path().join(f), b"data").unwrap();
        }
        let path = dir.path().join("labels.json").to_string_lossy().into_owned();
        let settings = load_label_settings(path.clone()).settings;
        let settings = rename_label(settings, LabelColour::Green, "Approved".into()).unwrap();
        let settings = map_label(settings, "Binned".into(), Some(LabelColour::Red));
        save_label_settings(path.clone(), settings.clone()).unwrap();
        assert_eq!(load_label_settings(path).settings, settings);
        assert_eq!(label_colour_of(settings.clone(), "binned".into()), Some(LabelColour::Red));
        assert_eq!(label_suggestion("To Do".into()), Some(LabelColour::Purple));

        let c = FolderCatalog::open(root.clone(), true, true, settings, false).unwrap();
        let before = c.snapshot("a.jpg".into());
        let row = c.toggle_colour("a.jpg".into(), LabelColour::Green).unwrap().row;
        assert_eq!((row.colour, row.decision), (Some(LabelColour::Green), Some(Decision::Keep)));
        assert!(std::fs::read_to_string(dir.path().join("a.xmp")).unwrap().contains("Approved"));
        c.set_rating("b.jpg".into(), 4).unwrap();
        c.add_keyword("b.jpg".into(), "東京".into()).unwrap();
        c.set_decision("c.jpg".into(), Some(Decision::Reject)).unwrap();

        let filter = FolderFilter {
            status: ReviewStatus::All,
            stars: StarFilter::AtLeast { stars: 3 },
            labels: vec![LabelPick::Unlabelled],
            keywords: vec!["東京".into()],
            any_keyword: false,
        };
        assert_eq!(c.query(filter, FolderSort::Name), [1]);
        assert_eq!(c.counts(), FolderCounts { keep: 1, reject: 1, other: 0, left: 1 });
        assert_eq!(c.keywords()[0].count, 1);
        assert_eq!(c.companions("a.jpg".into()), ["a.xmp"]);

        c.restore("a.jpg".into(), before).unwrap();
        assert_eq!(c.rows()[0].colour, None);

        let out = c.apply_cull(CullMode::Folder, Arc::new(NoTrash));
        assert_eq!((out.items, out.files), (1, 2));
        assert!(dir.path().join("_Rejected/c.xmp").exists());
        assert_eq!(c.items().len(), 2);

        let scan = scan_labels(root, true).unwrap();
        assert_eq!(scan.files, 2);
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
