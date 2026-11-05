//! A folder's metadata: what the apps review, filter and write.
//!
//! The XMP is the source of truth. `.bestshot-index.json` is only a cache of
//! it, stamped with each source file's size and modification time so a reopen
//! parses just what changed; delete it and it's rebuilt from the files.
//!
//! `.bestshot-cull.json` stays alongside for ranking and earlier decisions. A
//! colour in the XMP beats a decision there; with no label at all, a saved
//! keep or reject reads as an implied green or red without touching the XMP.
//! Marking a photo writes both, so the two only differ if another app edits
//! the XMP.

use crate::cull;
use crate::embedded;
use crate::labels::{Colour, LabelConfig};
use crate::library::{self, natural_cmp, Item, Kind};
use crate::store::{self, Decision, Store};
use crate::xmp::{self, Change, Fields};
use crate::atomic;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

pub const INDEX_FILE: &str = ".bestshot-index.json";
const INDEX_VERSION: u32 = 1;

/// Identifies the file a record was read from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Stamp {
    /// True if this describes the sidecar, false for the image itself.
    pub sidecar: bool,
    pub size: u64,
    /// Nanoseconds: two edits in one second can leave the size unchanged.
    pub mtime: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Record {
    stamp: Stamp,
    #[serde(flatten)]
    fields: Fields,
    /// Why the file couldn't be read; it won't be written while this is set.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    problem: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Index {
    version: u32,
    files: HashMap<String, Record>,
}

fn load_index(root: &Path) -> HashMap<String, Record> {
    fs::read(root.join(INDEX_FILE))
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Index>(&bytes).ok())
        .filter(|index| index.version == INDEX_VERSION)
        .map(|index| index.files)
        .unwrap_or_default()
}

fn stat(path: &Path) -> Option<(u64, i64)> {
    let meta = fs::metadata(path).ok()?;
    let mtime = meta.modified().ok()?.duration_since(UNIX_EPOCH).ok()?.as_nanos() as i64;
    Some((meta.len(), mtime))
}

fn stamp_of(root: &Path, item: &Item) -> Stamp {
    match stat(&root.join(&item.sidecar)) {
        Some((size, mtime)) => Stamp { sidecar: true, size, mtime },
        None => {
            let (size, mtime) = stat(&root.join(&item.rel)).unwrap_or((item.size, 0));
            Stamp { sidecar: false, size, mtime }
        }
    }
}

/// Reads an item's metadata without changing anything. A sidecar is
/// authoritative when it exists; otherwise it's whatever the image embeds.
fn read_item(root: &Path, item: &Item) -> Result<Fields, String> {
    match fs::read(root.join(&item.sidecar)) {
        Ok(bytes) => xmp::parse_bytes(&bytes).map_err(|e| format!("{}: {e}", item.sidecar)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            if item.kind == Kind::Video {
                return Ok(Fields::default());
            }
            let found = embedded::read_fields(&root.join(&item.rel)).map_err(|e| format!("{}: {e}", item.rel))?;
            Ok(found.unwrap_or_default())
        }
        Err(e) => Err(format!("{}: {e}", item.sidecar)),
    }
}

fn read_record(root: &Path, item: &Item) -> Record {
    let stamp = stamp_of(root, item);
    match read_item(root, item) {
        Ok(fields) => Record { stamp, fields, problem: None },
        Err(problem) => Record { stamp, fields: Fields::default(), problem: Some(problem) },
    }
}

/// One item as the apps show it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Row {
    pub rel: String,
    /// 0 for unrated, 1-5 stars, or -1 for Bridge's "Reject" rating.
    pub rating: i8,
    pub colour: Option<Colour>,
    /// The label text in the file. Set with no `colour` means it isn't mapped.
    pub label: Option<String>,
    /// The colour comes from a saved decision, not from the XMP.
    pub implied: bool,
    pub keywords: Vec<String>,
    pub decision: Option<Decision>,
    pub problem: Option<String>,
}

impl Row {
    /// Has anything been decided about this photo?
    pub fn reviewed(&self) -> bool {
        self.decision.is_some() || self.colour.is_some()
    }
}

/// Everything needed to put an item back, for undo.
#[derive(Debug, Clone, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub fields: Fields,
    pub decision: Option<Decision>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Counts {
    pub keep: u32,
    pub reject: u32,
    /// Labelled, but neither green nor red: maybes and the like.
    pub other: u32,
    pub left: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    #[default]
    All,
    Unreviewed,
    Keep,
    Reject,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Stars {
    #[default]
    Any,
    AtLeast(u8),
    Exactly(u8),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LabelPick {
    Colour(Colour),
    /// No label of any kind.
    Unlabelled,
    /// Label text that isn't mapped to a colour.
    Other,
}

/// Every part must match; within `labels`, any one will do.
#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Filter {
    pub status: Status,
    pub stars: Stars,
    pub labels: Vec<LabelPick>,
    pub keywords: Vec<String>,
    /// Match any of `keywords` rather than all of them.
    pub any_keyword: bool,
}

impl Filter {
    pub fn matches(&self, row: &Row) -> bool {
        let status = match self.status {
            Status::All => true,
            Status::Unreviewed => !row.reviewed(),
            Status::Keep => row.decision == Some(Decision::Keep),
            Status::Reject => row.decision == Some(Decision::Reject),
        };
        let stars = match self.stars {
            Stars::Any => true,
            Stars::AtLeast(n) => row.rating >= n as i8,
            Stars::Exactly(n) => row.rating.max(0) == n as i8,
        };
        let label = self.labels.is_empty()
            || self.labels.iter().any(|pick| match pick {
                LabelPick::Colour(c) => row.colour == Some(*c),
                LabelPick::Unlabelled => row.colour.is_none() && row.label.is_none(),
                LabelPick::Other => row.colour.is_none() && row.label.is_some(),
            });
        let has = |k: &String| row.keywords.iter().any(|w| same_keyword(w, k));
        let keywords = self.keywords.is_empty()
            || if self.any_keyword { self.keywords.iter().any(has) } else { self.keywords.iter().all(has) };
        status && stars && label && keywords
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Sort {
    #[default]
    Name,
    Newest,
    Oldest,
    /// Most stars first.
    Stars,
    /// Colour order, unlabelled last.
    Label,
}

fn same_keyword(a: &str, b: &str) -> bool {
    a.trim().to_lowercase() == b.trim().to_lowercase()
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KeywordCount {
    pub keyword: String,
    pub count: u32,
}

/// A marked item, and anything to tell the user even though it succeeded.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Marked {
    pub row: Row,
    pub warning: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct OpenStats {
    pub parsed: u32,
    pub reused: u32,
}

#[derive(Debug, Clone, Default)]
pub struct Options {
    pub labels: LabelConfig,
    /// Also write into JPEGs, for Adobe apps. Sidecars are always written.
    pub write_jpeg: bool,
}

pub struct Catalog {
    root: PathBuf,
    recursive: bool,
    include_videos: bool,
    items: Vec<Item>,
    by_rel: HashMap<String, usize>,
    store: Store,
    records: HashMap<String, Record>,
    options: Options,
    index_dirty: bool,
    stats: OpenStats,
    warning: Option<String>,
}

impl Catalog {
    /// Scans `root`, loads saved decisions and reads metadata, parsing only
    /// files that have changed since the index was written.
    pub fn open(root: &Path, recursive: bool, include_videos: bool, options: Options) -> std::io::Result<Catalog> {
        let items = library::scan(root, recursive, include_videos)?;
        let (mut store, warning) = store::load(root);
        // Forget decisions for files that have since been moved or deleted.
        let before = (store.decisions.len(), store.ranking.len());
        store.decisions.retain(|rel, _| root.join(rel).exists());
        store.ranking.retain(|rel| root.join(rel).exists());
        if (store.decisions.len(), store.ranking.len()) != before {
            let _ = store::save(root, &store);
        }

        let mut catalog = Catalog {
            root: root.to_path_buf(),
            recursive,
            include_videos,
            items: Vec::new(),
            by_rel: HashMap::new(),
            store,
            records: load_index(root),
            options,
            index_dirty: false,
            stats: OpenStats::default(),
            warning,
        };
        catalog.adopt(items);
        catalog.flush();
        Ok(catalog)
    }

    /// Takes a fresh scan: reuses records whose stamp still matches and reads
    /// the rest, in parallel because a first open reads the whole folder.
    fn adopt(&mut self, items: Vec<Item>) {
        let root = self.root.clone();
        let records = std::mem::take(&mut self.records);
        let known = records.len();
        let mut kept = HashMap::with_capacity(items.len());
        let mut stale = Vec::new();
        let mut reused = 0;
        let mut records = records;
        for item in &items {
            let stamp = stamp_of(&root, item);
            match records.remove(&item.rel) {
                Some(r) if r.stamp == stamp => {
                    kept.insert(item.rel.clone(), r);
                    reused += 1;
                }
                _ => stale.push(item),
            }
        }

        let threads = std::thread::available_parallelism().map_or(2, |n| n.get()).min(4);
        let chunk = stale.len().div_ceil(threads).max(1);
        let parsed: Vec<(String, Record)> = std::thread::scope(|scope| {
            let workers: Vec<_> = stale
                .chunks(chunk)
                .map(|items| {
                    let root = &root;
                    scope.spawn(move || items.iter().map(|i| (i.rel.clone(), read_record(root, i))).collect::<Vec<_>>())
                })
                .collect();
            workers.into_iter().flat_map(|w| w.join().unwrap_or_default()).collect()
        });

        self.stats = OpenStats { parsed: parsed.len() as u32, reused };
        self.index_dirty |= !parsed.is_empty() || known != reused as usize;
        kept.extend(parsed);
        self.records = kept;
        self.by_rel = items.iter().enumerate().map(|(i, item)| (item.rel.clone(), i)).collect();
        self.items = items;
    }

    /// Saves the index if it changed. It's only a cache, so a failure (a
    /// locked card, say) costs a re-parse next time and nothing else.
    pub fn flush(&mut self) {
        if !self.index_dirty {
            return;
        }
        let index = Index { version: INDEX_VERSION, files: self.records.clone() };
        if let Ok(json) = serde_json::to_vec(&index) {
            if atomic::replace(&self.root.join(INDEX_FILE), &json).is_ok() {
                self.index_dirty = false;
            }
        }
    }

    /// Applies new settings. Colours are worked out when read, so nothing
    /// needs re-parsing.
    pub fn set_options(&mut self, options: Options) {
        self.options = options;
    }

    pub fn items(&self) -> &[Item] {
        &self.items
    }

    pub fn ranking(&self) -> &[String] {
        &self.store.ranking
    }

    pub fn stats(&self) -> OpenStats {
        self.stats
    }

    pub fn take_warning(&mut self) -> Option<String> {
        self.warning.take()
    }

    /// Files whose metadata couldn't be read: `(relative path, why)`.
    pub fn problems(&self) -> Vec<(String, String)> {
        let mut out: Vec<_> = self
            .records
            .iter()
            .filter_map(|(rel, r)| r.problem.clone().map(|p| (rel.clone(), p)))
            .collect();
        out.sort();
        out
    }

    fn fields(&self, rel: &str) -> Fields {
        self.records.get(rel).map(|r| r.fields.clone()).unwrap_or_default()
    }

    pub fn row(&self, rel: &str) -> Row {
        let record = self.records.get(rel);
        let empty = Fields::default();
        let fields = record.map_or(&empty, |r| &r.fields);
        let saved = self.store.decisions.get(rel).copied();
        let label = fields.label.clone().or_else(|| fields.label_color.clone());
        let in_xmp = self.options.labels.colour_for(fields);
        let implied = in_xmp.is_none() && label.is_none() && saved.is_some();
        Row {
            rel: rel.to_string(),
            rating: fields.rating.unwrap_or(0),
            colour: in_xmp.or(if implied { saved.map(Colour::for_decision) } else { None }),
            label,
            implied,
            keywords: fields.keywords.clone(),
            decision: match in_xmp {
                Some(colour) => colour.decision(),
                None => saved,
            },
            problem: record.and_then(|r| r.problem.clone()),
        }
    }

    pub fn rows(&self) -> Vec<Row> {
        self.items.iter().map(|i| self.row(&i.rel)).collect()
    }

    pub fn counts(&self) -> Counts {
        let mut c = Counts::default();
        for item in &self.items {
            let row = self.row(&item.rel);
            match (row.decision, row.colour) {
                (Some(Decision::Keep), _) => c.keep += 1,
                (Some(Decision::Reject), _) => c.reject += 1,
                (None, Some(_)) => c.other += 1,
                (None, None) => c.left += 1,
            }
        }
        c
    }

    /// Item positions that pass `filter`, in `sort` order.
    pub fn query(&self, filter: &Filter, sort: Sort) -> Vec<u32> {
        let mut rows: Vec<(usize, Row)> = self
            .items
            .iter()
            .enumerate()
            .map(|(i, item)| (i, self.row(&item.rel)))
            .filter(|(_, row)| filter.matches(row))
            .collect();
        // Stable, so ties stay in name order.
        match sort {
            Sort::Name => {}
            Sort::Newest => rows.sort_by_key(|(i, _)| std::cmp::Reverse(self.items[*i].mtime)),
            Sort::Oldest => rows.sort_by_key(|(i, _)| self.items[*i].mtime),
            Sort::Stars => rows.sort_by_key(|(_, r)| std::cmp::Reverse(r.rating)),
            Sort::Label => rows.sort_by_key(|(_, r)| (r.colour.is_none(), r.colour, r.label.is_none())),
        }
        rows.into_iter().map(|(i, _)| i as u32).collect()
    }

    /// Every keyword in the folder, most used first.
    pub fn keywords(&self) -> Vec<KeywordCount> {
        let mut counts: BTreeMap<String, (String, u32)> = BTreeMap::new();
        for rel in self.by_rel.keys() {
            for word in self.records.get(rel).map_or(&[][..], |r| &r.fields.keywords) {
                counts.entry(word.trim().to_lowercase()).or_insert_with(|| (word.clone(), 0)).1 += 1;
            }
        }
        let mut out: Vec<KeywordCount> =
            counts.into_values().map(|(keyword, count)| KeywordCount { keyword, count }).collect();
        out.sort_by(|a, b| b.count.cmp(&a.count).then_with(|| natural_cmp(&a.keyword, &b.keyword)));
        out
    }

    // MARK: Marking

    fn item(&self, rel: &str) -> Result<&Item, String> {
        self.by_rel.get(rel).map(|i| &self.items[*i]).ok_or_else(|| format!("{rel} isn't in this folder any more"))
    }

    /// Writes `change` to the item's sidecar, always from what's on disk now,
    /// never from the index. Creating a sidecar copies across any embedded
    /// metadata, or the sidecar would hide it.
    fn write(&mut self, rel: &str, change: &Change) -> Result<Option<String>, String> {
        let item = self.item(rel)?.clone();
        let image = self.root.join(&item.rel);
        let sidecar = self.root.join(&item.sidecar);
        if !image.exists() {
            return Err(format!("{rel} isn't in this folder any more"));
        }
        let refused = |e: String| format!("{}: {e}. Nothing was written.", item.sidecar);

        let (before, packet) = match fs::read(&sidecar) {
            Ok(bytes) => {
                let text = String::from_utf8(bytes).map_err(|_| refused("not UTF-8 text".into()))?;
                (xmp::parse(&text).map_err(refused)?, Some(text))
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (read_item(&self.root, &item).map_err(refused)?, None),
            Err(e) => return Err(refused(e.to_string())),
        };
        let after = change.applied_to(&before);
        let unchanged = after == before;
        if !(unchanged && packet.is_none()) {
            let new = match &packet {
                Some(text) => xmp::apply(text, change).map_err(refused)?,
                None => xmp::new_packet(&after).map_err(refused)?,
            };
            if packet.as_deref() != Some(new.as_str()) {
                atomic::replace(&sidecar, new.as_bytes()).map_err(|e| refused(e.to_string()))?;
            }
        }

        let mut warning = None;
        if self.options.write_jpeg && embedded::is_jpeg(&item.ext) && !unchanged {
            if let Err(e) = embedded::write_jpeg(&image, change, &before) {
                warning = Some(format!("{rel}: saved to the sidecar, but not into the JPEG: {e}"));
            }
        }

        let stamp = stamp_of(&self.root, &item);
        self.records.insert(item.rel.clone(), Record { stamp, fields: after, problem: None });
        self.index_dirty = true;
        if stamp.sidecar {
            let i = self.by_rel[rel];
            if !self.items[i].companions.contains(&item.sidecar) {
                self.items[i].companions.push(item.sidecar.clone());
            }
        }
        Ok(warning)
    }

    /// Records a decision in `.bestshot-cull.json`. The XMP has already been
    /// written by now, so a failure here is a warning.
    fn set_saved_decision(&mut self, rel: &str, decision: Option<Decision>) -> Option<String> {
        if self.store.decisions.get(rel).copied() == decision {
            return None;
        }
        match decision {
            Some(d) => self.store.decisions.insert(rel.to_string(), d),
            None => self.store.decisions.remove(rel),
        };
        store::save(&self.root, &self.store).err().map(|e| format!("Couldn't save decisions: {e}"))
    }

    fn marked(&self, rel: &str, warning: Option<String>) -> Marked {
        Marked { row: self.row(rel), warning }
    }

    /// 1-5 sets the stars, 0 clears them.
    pub fn set_rating(&mut self, rel: &str, stars: u8) -> Result<Marked, String> {
        if stars > 5 {
            return Err("Ratings go up to 5 stars.".into());
        }
        let rating = (stars > 0).then_some(stars as i8);
        let warning = self.write(rel, &Change { rating: Some(rating), ..Default::default() })?;
        Ok(self.marked(rel, warning))
    }

    /// Sets a colour, or clears it with `None`. Green and red double as the
    /// decision. Replacing a label also drops `photoshop:LabelColor`, which
    /// would otherwise bring the old colour back when the label is cleared.
    pub fn set_colour(&mut self, rel: &str, colour: Option<Colour>) -> Result<Marked, String> {
        self.item(rel)?;
        let row = self.row(rel);
        if colour == row.colour && !row.implied && colour.is_some() {
            return Ok(self.marked(rel, None));
        }
        let mut warning = None;
        // An implied colour is only a saved decision: nothing to do in the XMP
        // to clear it, or to confirm it.
        let needs_xmp = match colour {
            Some(c) => !(row.implied && row.colour == Some(c)),
            None => row.label.is_some(),
        };
        if needs_xmp {
            let fields = self.fields(rel);
            let label = colour.map(|c| self.options.labels.name(c).to_string());
            let label_color = fields.label_color.is_some().then_some(None);
            warning = self.write(rel, &Change { label: Some(label), label_color, ..Default::default() })?;
        }
        let saved = self.set_saved_decision(rel, colour.and_then(Colour::decision));
        Ok(self.marked(rel, warning.or(saved)))
    }

    /// What 6-9 do: set the colour, or clear it if it's already that colour.
    pub fn toggle_colour(&mut self, rel: &str, colour: Colour) -> Result<Marked, String> {
        let current = self.row(rel).colour;
        self.set_colour(rel, if current == Some(colour) { None } else { Some(colour) })
    }

    /// Keep and reject are green and red by another name.
    pub fn set_decision(&mut self, rel: &str, decision: Option<Decision>) -> Result<Marked, String> {
        let row = self.row(rel);
        match decision {
            Some(d) => self.set_colour(rel, Some(Colour::for_decision(d))),
            None if row.colour.and_then(Colour::decision).is_some() => self.set_colour(rel, None),
            // A maybe or an unmapped label isn't a decision: only the store's entry goes.
            None => {
                let warning = self.set_saved_decision(rel, None);
                Ok(self.marked(rel, warning))
            }
        }
    }

    pub fn set_keywords(&mut self, rel: &str, keywords: Vec<String>) -> Result<Marked, String> {
        let mut clean: Vec<String> = Vec::with_capacity(keywords.len());
        for word in keywords {
            let word: String = word.trim().chars().filter(|c| !c.is_control()).collect();
            if !word.is_empty() && !clean.iter().any(|k| same_keyword(k, &word)) {
                clean.push(word);
            }
        }
        let warning = self.write(rel, &Change { keywords: Some(clean), ..Default::default() })?;
        Ok(self.marked(rel, warning))
    }

    pub fn add_keyword(&mut self, rel: &str, keyword: &str) -> Result<Marked, String> {
        let mut words = self.fields(rel).keywords;
        words.push(keyword.to_string());
        self.set_keywords(rel, words)
    }

    pub fn remove_keyword(&mut self, rel: &str, keyword: &str) -> Result<Marked, String> {
        let mut words = self.fields(rel).keywords;
        words.retain(|k| !same_keyword(k, keyword));
        self.set_keywords(rel, words)
    }

    pub fn snapshot(&self, rel: &str) -> Snapshot {
        Snapshot { fields: self.fields(rel), decision: self.store.decisions.get(rel).copied() }
    }

    /// Puts an item back as it was, for undo.
    pub fn restore(&mut self, rel: &str, snapshot: &Snapshot) -> Result<Marked, String> {
        let warning = if self.fields(rel) == snapshot.fields {
            None
        } else {
            self.write(rel, &Change::all(&snapshot.fields))?
        };
        let saved = self.set_saved_decision(rel, snapshot.decision);
        Ok(self.marked(rel, warning.or(saved)))
    }

    pub fn set_ranking(&mut self, ranking: Vec<String>) -> std::io::Result<()> {
        self.store.ranking = ranking;
        store::save(&self.root, &self.store)
    }

    /// Everything counting as a reject, red or a saved decision alike.
    pub fn rejects(&self) -> Vec<&Item> {
        self.items.iter().filter(|i| self.row(&i.rel).decision == Some(Decision::Reject)).collect()
    }

    /// Moves every reject and its companions to the Trash or `_Rejected/`,
    /// then rescans.
    pub fn apply_cull(&mut self, mode: cull::Mode, trash: &dyn Fn(&Path) -> Result<(), String>) -> cull::Outcome {
        let outcome = cull::apply(&self.root, &self.rejects(), mode, trash);
        for rel in &outcome.culled {
            self.store.decisions.remove(rel);
            self.records.remove(rel);
        }
        self.store.ranking.retain(|rel| !outcome.culled.contains(rel));
        if let Err(e) = store::save(&self.root, &self.store) {
            self.warning = Some(format!("Couldn't save decisions: {e}"));
        }
        if let Ok(items) = library::scan(&self.root, self.recursive, self.include_videos) {
            self.adopt(items);
        }
        self.flush();
        outcome
    }
}

/// One distinct label value in a folder.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LabelValue {
    pub text: String,
    /// `xmp:Label` or `photoshop:LabelColor`.
    pub field: String,
    pub count: u32,
    pub example: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LabelScan {
    pub files: u32,
    pub values: Vec<LabelValue>,
    /// Files that couldn't be read: `(relative path, why)`.
    pub problems: Vec<(String, String)>,
}

/// Lists the label values in a folder, for Import from Bridge. Strictly
/// read-only: no index, no store, nothing in the folder changes.
pub fn scan_labels(root: &Path, recursive: bool) -> std::io::Result<LabelScan> {
    let items = library::scan(root, recursive, true)?;
    let mut out = LabelScan { files: items.len() as u32, ..Default::default() };
    let mut found: BTreeMap<(&'static str, String), LabelValue> = BTreeMap::new();
    for item in &items {
        let fields = match read_item(root, item) {
            Ok(f) => f,
            Err(e) => {
                out.problems.push((item.rel.clone(), e));
                continue;
            }
        };
        for (field, value) in [("xmp:Label", fields.label), ("photoshop:LabelColor", fields.label_color)] {
            let Some(text) = value else { continue };
            found
                .entry((field, text.to_lowercase()))
                .or_insert_with(|| LabelValue { text, field: field.into(), count: 0, example: item.rel.clone() })
                .count += 1;
        }
    }
    out.values = found.into_values().collect();
    out.values.sort_by(|a, b| b.count.cmp(&a.count).then_with(|| a.text.cmp(&b.text)));
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::embedded::tests::jpeg;
    use crate::store::STORE_FILE;

    const CRS: &str = r#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:Exposure2012="+0.35"/></rdf:RDF></x:xmpmeta>"#;

    fn sidecar(attrs: &str) -> String {
        format!(
            r#"<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/" {attrs}/></rdf:RDF>"#
        )
    }

    fn folder(files: &[(&str, &str)]) -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        for (rel, content) in files {
            let path = dir.path().join(rel);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, content).unwrap();
        }
        dir
    }

    fn open(dir: &tempfile::TempDir) -> Catalog {
        Catalog::open(dir.path(), true, true, Options::default()).unwrap()
    }

    fn read(dir: &tempfile::TempDir, rel: &str) -> String {
        fs::read_to_string(dir.path().join(rel)).unwrap()
    }

    fn exists(dir: &tempfile::TempDir, rel: &str) -> bool {
        dir.path().join(rel).exists()
    }

    fn saved(dir: &tempfile::TempDir, json: &str) {
        fs::write(dir.path().join(STORE_FILE), json).unwrap();
    }

    fn make_read_only(path: &Path) {
        let mut perms = fs::metadata(path).unwrap().permissions();
        perms.set_readonly(true);
        fs::set_permissions(path, perms).unwrap();
    }

    #[test]
    fn writes_a_sidecar_keeping_everything_else_and_never_the_image() {
        let dir = folder(&[("a.jpg", "image"), ("a.xmp", CRS)]);
        let mut c = open(&dir);
        c.set_rating("a.jpg", 4).unwrap();
        c.toggle_colour("a.jpg", Colour::Yellow).unwrap();
        c.add_keyword("a.jpg", "東京").unwrap();

        let text = read(&dir, "a.xmp");
        assert!(text.contains("crs:Exposure2012=\"+0.35\""));
        assert_eq!(read(&dir, "a.jpg"), "image");
        let f = xmp::parse(&text).unwrap();
        assert_eq!((f.rating, f.label.as_deref()), (Some(4), Some("Yellow")));
        assert_eq!(f.keywords, ["東京"]);
    }

    #[test]
    fn colour_keys_toggle_and_stand_for_keep_and_reject() {
        let dir = folder(&[("a.jpg", "x"), ("b.jpg", "x")]);
        let mut c = open(&dir);

        let row = c.toggle_colour("a.jpg", Colour::Red).unwrap().row;
        assert_eq!((row.colour, row.decision), (Some(Colour::Red), Some(Decision::Reject)));
        assert_eq!(c.rejects().len(), 1);
        assert!(read(&dir, STORE_FILE).contains("reject"), "the store agrees, for older builds");

        let row = c.toggle_colour("a.jpg", Colour::Green).unwrap().row;
        assert_eq!((row.colour, row.decision), (Some(Colour::Green), Some(Decision::Keep)));

        let row = c.toggle_colour("a.jpg", Colour::Green).unwrap().row;
        assert_eq!((row.colour, row.decision, row.label), (None, None, None));
        assert!(!read(&dir, "a.xmp").contains("xmp:Label"));
        assert!(!read(&dir, STORE_FILE).contains("a.jpg"));

        // Yellow is reviewed but decides nothing.
        c.toggle_colour("b.jpg", Colour::Yellow).unwrap();
        assert_eq!(c.counts(), Counts { keep: 0, reject: 0, other: 1, left: 1 });
        assert!(c.rejects().is_empty());
    }

    #[test]
    fn existing_decisions_read_as_colours_without_writing_xmp() {
        let dir = folder(&[("a.jpg", "x"), ("b.jpg", "x"), ("c.jpg", "x"), ("c.xmp", &sidecar(r#"xmp:Label="Yellow""#))]);
        saved(&dir, r#"{"version":1,"decisions":{"a.jpg":"keep","b.jpg":"reject","c.jpg":"reject"},"ranking":["a.jpg"]}"#);
        let mut c = open(&dir);

        let a = c.row("a.jpg");
        assert_eq!((a.colour, a.implied, a.decision), (Some(Colour::Green), true, Some(Decision::Keep)));
        let b = c.row("b.jpg");
        assert_eq!((b.colour, b.implied, b.decision), (Some(Colour::Red), true, Some(Decision::Reject)));
        // A label in the XMP beats the saved decision.
        let y = c.row("c.jpg");
        assert_eq!((y.colour, y.implied, y.decision), (Some(Colour::Yellow), false, None));
        assert_eq!(c.rejects().iter().map(|i| i.rel.as_str()).collect::<Vec<_>>(), ["b.jpg"]);
        assert!(!exists(&dir, "a.xmp") && !exists(&dir, "b.xmp"), "opening writes no XMP");

        // Confirming or clearing an implied colour doesn't need any XMP either.
        c.set_decision("a.jpg", Some(Decision::Keep)).unwrap();
        c.toggle_colour("b.jpg", Colour::Red).unwrap();
        assert!(!exists(&dir, "a.xmp") && !exists(&dir, "b.xmp"));
        assert_eq!(c.row("b.jpg").decision, None);
        assert_eq!(c.ranking(), ["a.jpg"]);

        // Changing one is a touch: now it's written.
        c.toggle_colour("a.jpg", Colour::Blue).unwrap();
        assert!(exists(&dir, "a.xmp"));
        assert_eq!(c.row("a.jpg").decision, None);
    }

    #[test]
    fn unmapped_labels_are_shown_kept_and_never_count_as_red() {
        let dir = folder(&[("a.jpg", "x"), ("a.xmp", &sidecar(r#"xmp:Label="Select" xmp:Rating="2""#))]);
        let mut c = open(&dir);
        let row = c.row("a.jpg");
        assert_eq!((row.colour, row.label.as_deref(), row.decision), (None, Some("Select"), None));
        assert!(c.rejects().is_empty());

        // Rating it leaves the label text alone.
        c.set_rating("a.jpg", 5).unwrap();
        assert!(read(&dir, "a.xmp").contains("xmp:Label=\"Select\""));

        // Saving a mapping recolours it with no re-read.
        let mut labels = LabelConfig::default();
        labels.map("select", Some(Colour::Red));
        c.set_options(Options { labels, write_jpeg: false });
        assert_eq!(c.row("a.jpg").decision, Some(Decision::Reject));
    }

    #[test]
    fn clearing_a_decision_leaves_labels_that_are_not_decisions() {
        let dir = folder(&[("a.jpg", "x"), ("a.xmp", &sidecar(r#"xmp:Label="Portfolio""#)), ("b.jpg", "x"), ("b.xmp", &sidecar(r#"xmp:Label="Yellow""#))]);
        saved(&dir, r#"{"version":1,"decisions":{"a.jpg":"reject"},"ranking":[]}"#);
        let mut c = open(&dir);
        assert_eq!(c.row("a.jpg").decision, Some(Decision::Reject));

        c.set_decision("a.jpg", None).unwrap();
        c.set_decision("b.jpg", None).unwrap();
        assert_eq!(c.row("a.jpg").decision, None);
        assert_eq!(c.row("a.jpg").label.as_deref(), Some("Portfolio"));
        assert_eq!(c.row("b.jpg").colour, Some(Colour::Yellow));
    }

    #[test]
    fn writes_use_the_configured_name() {
        let dir = folder(&[("a.jpg", "x")]);
        let mut labels = LabelConfig::default();
        labels.rename(Colour::Green, "Approved").unwrap();
        let mut c = Catalog::open(dir.path(), true, true, Options { labels, write_jpeg: false }).unwrap();
        c.toggle_colour("a.jpg", Colour::Green).unwrap();
        assert!(read(&dir, "a.xmp").contains("xmp:Label=\"Approved\""));
        assert_eq!(c.row("a.jpg").colour, Some(Colour::Green));
    }

    #[test]
    fn clearing_a_label_also_clears_label_color_so_it_stays_cleared() {
        let dir = folder(&[("a.jpg", "x"), ("a.xmp", &sidecar(r#"xmp:Label="Green" photoshop:LabelColor="Green""#))]);
        let mut c = open(&dir);
        c.toggle_colour("a.jpg", Colour::Green).unwrap();
        assert_eq!(c.row("a.jpg").colour, None);
        drop(c);
        assert_eq!(open(&dir).row("a.jpg").colour, None);
    }

    #[test]
    fn bridge_reject_rating_survives_and_is_not_a_delete() {
        let dir = folder(&[("a.jpg", "x"), ("a.xmp", &sidecar(r#"xmp:Rating="-1""#))]);
        let mut c = open(&dir);
        assert_eq!(c.row("a.jpg").rating, -1);
        assert!(c.rejects().is_empty());
        c.toggle_colour("a.jpg", Colour::Green).unwrap();
        assert!(read(&dir, "a.xmp").contains("xmp:Rating=\"-1\""));
    }

    #[test]
    fn a_malformed_sidecar_is_reported_and_left_alone() {
        let bad = "<rdf:RDF><half a sidecar";
        let dir = folder(&[("a.jpg", "x"), ("a.xmp", bad), ("b.jpg", "x")]);
        let mut c = open(&dir);
        assert_eq!(c.problems().len(), 1);
        assert!(c.row("a.jpg").problem.is_some());

        assert!(c.set_rating("a.jpg", 3).is_err());
        assert!(c.toggle_colour("a.jpg", Colour::Red).is_err());
        assert!(c.add_keyword("a.jpg", "x").is_err());
        assert_eq!(read(&dir, "a.xmp"), bad);
        assert_eq!(c.row("a.jpg").decision, None, "a failed red must not bin it");
        assert!(c.rejects().is_empty());
        // Others carry on.
        c.set_rating("b.jpg", 3).unwrap();

        // Fixed outside BestShot: picked up on the next open.
        fs::write(dir.path().join("a.xmp"), CRS).unwrap();
        drop(c);
        let c = open(&dir);
        assert!(c.problems().is_empty());
    }

    #[test]
    fn a_read_only_sidecar_is_reported_and_left_alone() {
        let dir = folder(&[("a.jpg", "x"), ("a.xmp", CRS)]);
        make_read_only(&dir.path().join("a.xmp"));
        let mut c = open(&dir);

        let err = c.set_rating("a.jpg", 3).unwrap_err();
        assert!(err.contains("read-only"), "{err}");
        assert_eq!(read(&dir, "a.xmp"), CRS);
        assert_eq!(c.row("a.jpg").rating, 0, "memory matches the disk");
        assert!(c.toggle_colour("a.jpg", Colour::Red).is_err());
        assert!(c.rejects().is_empty());
    }

    #[test]
    fn embedded_metadata_is_read_and_seeds_a_new_sidecar() {
        let packet = sidecar(r#"xmp:Rating="4" xmp:Label="Green""#);
        let dir = tempfile::tempdir().unwrap();
        let original = jpeg(Some(&packet));
        fs::write(dir.path().join("a.jpg"), &original).unwrap();
        let mut c = Catalog::open(dir.path(), true, true, Options::default()).unwrap();
        assert_eq!(c.row("a.jpg").rating, 4);
        assert_eq!(c.row("a.jpg").colour, Some(Colour::Green));
        assert!(!dir.path().join("a.xmp").exists());

        c.add_keyword("a.jpg", "new").unwrap();
        let f = xmp::parse(&fs::read_to_string(dir.path().join("a.xmp")).unwrap()).unwrap();
        assert_eq!((f.rating, f.label.as_deref(), f.keywords.len()), (Some(4), Some("Green"), 1));
        assert_eq!(fs::read(dir.path().join("a.jpg")).unwrap(), original, "the image is not rewritten by default");

        // Clearing stays cleared, though the JPEG still holds the old rating.
        c.set_rating("a.jpg", 0).unwrap();
        drop(c);
        let c = Catalog::open(dir.path(), true, true, Options::default()).unwrap();
        assert_eq!(c.row("a.jpg").rating, 0);
    }

    #[test]
    fn the_jpeg_option_writes_both() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("a.jpg"), jpeg(None)).unwrap();
        let options = Options { labels: LabelConfig::default(), write_jpeg: true };
        let mut c = Catalog::open(dir.path(), true, true, options).unwrap();
        let marked = c.set_rating("a.jpg", 2).unwrap();
        assert_eq!(marked.warning, None);
        assert!(dir.path().join("a.xmp").exists());
        assert_eq!(embedded::read_fields(&dir.path().join("a.jpg")).unwrap().unwrap().rating, Some(2));

        // A file that isn't really a JPEG: the sidecar still lands, with a warning.
        fs::write(dir.path().join("b.jpg"), b"not a jpeg").unwrap();
        drop(c);
        let options = Options { labels: LabelConfig::default(), write_jpeg: true };
        let mut c = Catalog::open(dir.path(), true, true, options).unwrap();
        let marked = c.set_rating("b.jpg", 2).unwrap();
        assert!(marked.warning.unwrap().contains("not into the JPEG"));
        assert_eq!(fs::read(dir.path().join("b.jpg")).unwrap(), b"not a jpeg");
    }

    #[test]
    fn the_index_means_only_changed_files_are_parsed() {
        let dir = folder(&[("a.jpg", "x"), ("a.xmp", &sidecar(r#"xmp:Rating="1""#)), ("b.jpg", "x"), ("b.xmp", &sidecar(r#"xmp:Rating="2""#))]);
        let c = open(&dir);
        assert_eq!(c.stats(), OpenStats { parsed: 2, reused: 0 });
        drop(c);

        let c = open(&dir);
        assert_eq!(c.stats(), OpenStats { parsed: 0, reused: 2 });
        assert_eq!(c.row("b.jpg").rating, 2);
        drop(c);

        // Edited elsewhere, same length: the file wins over the index.
        std::thread::sleep(std::time::Duration::from_millis(20));
        fs::write(dir.path().join("a.xmp"), sidecar(r#"xmp:Rating="5""#)).unwrap();
        let c = open(&dir);
        assert_eq!(c.stats(), OpenStats { parsed: 1, reused: 1 });
        assert_eq!(c.row("a.jpg").rating, 5);
        drop(c);

        // Deleting it loses nothing.
        fs::remove_file(dir.path().join(INDEX_FILE)).unwrap();
        let c = open(&dir);
        assert_eq!(c.stats(), OpenStats { parsed: 2, reused: 0 });
        assert_eq!((c.row("a.jpg").rating, c.row("b.jpg").rating), (5, 2));
        drop(c);

        // Nor does corrupting it, or an index from a future version.
        for junk in ["{ nope", r#"{"version":99,"files":{}}"#] {
            fs::write(dir.path().join(INDEX_FILE), junk).unwrap();
            let c = open(&dir);
            assert_eq!((c.stats().parsed, c.row("a.jpg").rating), (2, 5), "{junk}");
        }
    }

    #[test]
    fn own_writes_keep_the_index_current() {
        let dir = folder(&[("a.jpg", "x")]);
        let mut c = open(&dir);
        c.set_rating("a.jpg", 3).unwrap();
        c.flush();
        drop(c);
        let c = open(&dir);
        assert_eq!(c.stats(), OpenStats { parsed: 0, reused: 1 });
        assert_eq!(c.row("a.jpg").rating, 3);
    }

    #[test]
    fn a_problem_is_remembered_by_the_index() {
        let dir = folder(&[("a.jpg", "x"), ("a.xmp", "garbage")]);
        drop(open(&dir));
        let c = open(&dir);
        assert_eq!(c.stats().parsed, 0);
        assert_eq!(c.problems().len(), 1);
    }

    #[test]
    fn undo_restores_the_exact_previous_state() {
        let dir = folder(&[("a.jpg", "x"), ("a.xmp", &sidecar(r#"xmp:Label="Select" photoshop:LabelColor="Red" xmp:Rating="2""#))]);
        saved(&dir, r#"{"version":1,"decisions":{"a.jpg":"keep"},"ranking":[]}"#);
        let mut c = open(&dir);
        let before = c.snapshot("a.jpg");

        c.toggle_colour("a.jpg", Colour::Red).unwrap();
        c.set_rating("a.jpg", 5).unwrap();
        assert_ne!(c.snapshot("a.jpg"), before);
        c.restore("a.jpg", &before).unwrap();

        assert_eq!(c.snapshot("a.jpg"), before);
        let f = xmp::parse(&read(&dir, "a.xmp")).unwrap();
        assert_eq!((f.label.as_deref(), f.label_color.as_deref(), f.rating), (Some("Select"), Some("Red"), Some(2)));
    }

    #[test]
    fn keywords_are_tidied_and_counted() {
        let dir = folder(&[("a.jpg", "x"), ("b.jpg", "x")]);
        let mut c = open(&dir);
        c.set_keywords("a.jpg", vec![" Beach ".into(), "beach".into(), "".into(), "Zoë".into()]).unwrap();
        c.add_keyword("b.jpg", "BEACH").unwrap();
        assert_eq!(c.row("a.jpg").keywords, ["Beach", "Zoë"]);
        assert_eq!(c.keywords()[0].count, 2);
        c.remove_keyword("a.jpg", "beach").unwrap();
        assert_eq!(c.row("a.jpg").keywords, ["Zoë"]);
    }

    fn rels(c: &Catalog, filter: &Filter, sort: Sort) -> Vec<String> {
        c.query(filter, sort).iter().map(|i| c.items()[*i as usize].rel.clone()).collect()
    }

    #[test]
    fn filters_combine_and_sort() {
        let dir = folder(&[
            ("a.jpg", "x"),
            ("a.xmp", &sidecar(r#"xmp:Rating="5" xmp:Label="Green""#)),
            ("b.jpg", "x"),
            ("b.xmp", &sidecar(r#"xmp:Rating="3" xmp:Label="Red""#)),
            ("c.jpg", "x"),
            ("c.xmp", &sidecar(r#"xmp:Rating="3" xmp:Label="Portfolio""#)),
            ("d.jpg", "x"),
        ]);
        let mut c = open(&dir);
        c.add_keyword("a.jpg", "sea").unwrap();
        c.add_keyword("b.jpg", "sea").unwrap();
        c.add_keyword("b.jpg", "sky").unwrap();

        let all = Filter::default();
        assert_eq!(rels(&c, &all, Sort::Name).len(), 4);
        let at_least = Filter { stars: Stars::AtLeast(4), ..all.clone() };
        assert_eq!(rels(&c, &at_least, Sort::Name), ["a.jpg"]);
        let exactly = Filter { stars: Stars::Exactly(3), ..all.clone() };
        assert_eq!(rels(&c, &exactly, Sort::Name), ["b.jpg", "c.jpg"]);
        let unrated = Filter { stars: Stars::Exactly(0), ..all.clone() };
        assert_eq!(rels(&c, &unrated, Sort::Name), ["d.jpg"]);
        let colours = Filter { labels: vec![LabelPick::Colour(Colour::Red), LabelPick::Colour(Colour::Green)], ..all.clone() };
        assert_eq!(rels(&c, &colours, Sort::Name), ["a.jpg", "b.jpg"]);
        let unlabelled = Filter { labels: vec![LabelPick::Unlabelled], ..all.clone() };
        assert_eq!(rels(&c, &unlabelled, Sort::Name), ["d.jpg"]);
        let other = Filter { labels: vec![LabelPick::Other], ..all.clone() };
        assert_eq!(rels(&c, &other, Sort::Name), ["c.jpg"]);
        let words = Filter { keywords: vec!["SEA".into(), "sky".into()], ..all.clone() };
        assert_eq!(rels(&c, &words, Sort::Name), ["b.jpg"]);
        let either = Filter { any_keyword: true, ..words.clone() };
        assert_eq!(rels(&c, &either, Sort::Name), ["a.jpg", "b.jpg"]);
        let combined = Filter {
            status: Status::Reject,
            stars: Stars::AtLeast(3),
            labels: vec![LabelPick::Colour(Colour::Red)],
            keywords: vec!["sea".into()],
            any_keyword: false,
        };
        assert_eq!(rels(&c, &combined, Sort::Name), ["b.jpg"]);
        let unreviewed = Filter { status: Status::Unreviewed, ..all.clone() };
        assert_eq!(rels(&c, &unreviewed, Sort::Name), ["c.jpg", "d.jpg"]);

        assert_eq!(rels(&c, &all, Sort::Stars), ["a.jpg", "b.jpg", "c.jpg", "d.jpg"]);
        assert_eq!(rels(&c, &all, Sort::Label), ["b.jpg", "a.jpg", "c.jpg", "d.jpg"]);
    }

    #[test]
    fn culling_reds_takes_their_new_sidecars_with_them() {
        let dir = folder(&[("a.jpg", "x"), ("b.jpg", "x"), ("c.jpg", "x")]);
        saved(&dir, r#"{"version":1,"decisions":{"c.jpg":"reject"},"ranking":["a.jpg","b.jpg"]}"#);
        let mut c = open(&dir);
        c.toggle_colour("a.jpg", Colour::Red).unwrap();
        assert_eq!(c.rejects().len(), 2);

        let trashed = std::sync::Mutex::new(Vec::new());
        let out = c.apply_cull(cull::Mode::Trash, &|p| {
            trashed.lock().unwrap().push(p.file_name().unwrap().to_string_lossy().into_owned());
            fs::remove_file(p).map_err(|e| e.to_string())
        });

        assert_eq!((out.items, out.files), (2, 3));
        assert_eq!(trashed.into_inner().unwrap(), ["a.jpg", "a.xmp", "c.jpg"]);
        assert_eq!(c.items().len(), 1);
        assert_eq!(c.ranking(), ["b.jpg"]);
        assert_eq!(c.counts().reject, 0);
        assert!(c.keywords().is_empty());
    }

    #[test]
    fn a_failed_trash_leaves_the_red_marked() {
        let dir = folder(&[("a.jpg", "x")]);
        let mut c = open(&dir);
        c.toggle_colour("a.jpg", Colour::Red).unwrap();
        let out = c.apply_cull(cull::Mode::Trash, &|_| Err("no Trash here".into()));
        assert_eq!((out.items, out.failed.len()), (0, 1));
        assert_eq!(c.row("a.jpg").colour, Some(Colour::Red));
        assert!(exists(&dir, "a.jpg"));
    }

    /// Every file's path, bytes and modification time.
    fn fingerprint(root: &Path) -> Vec<(String, Vec<u8>, std::time::SystemTime)> {
        let mut out: Vec<_> = walkdir::WalkDir::new(root)
            .into_iter()
            .filter_map(Result::ok)
            .filter(|e| e.file_type().is_file())
            .map(|e| {
                let modified = e.metadata().unwrap().modified().unwrap();
                (e.path().display().to_string(), fs::read(e.path()).unwrap(), modified)
            })
            .collect();
        out.sort();
        out
    }

    #[test]
    fn scanning_labels_changes_nothing_and_counts_every_value() {
        let dir = folder(&[
            ("a.jpg", "x"),
            ("a.xmp", &sidecar(r#"xmp:Label="Select" photoshop:LabelColor="Red""#)),
            ("b.jpg", "x"),
            ("b.xmp", &sidecar(r#"xmp:Label="select""#)),
            ("sub/c.jpg", "x"),
            ("sub/c.xmp", &sidecar(r#"xmp:Label="My Keepers""#)),
            ("d.jpg", "x"),
            ("e.jpg", "x"),
            ("e.xmp", "garbage"),
        ]);
        fs::write(dir.path().join("f.jpg"), jpeg(Some(&sidecar(r#"xmp:Label="To Do""#)))).unwrap();
        let before = fingerprint(dir.path());

        let scan = scan_labels(dir.path(), true).unwrap();

        assert_eq!(fingerprint(dir.path()), before, "reading must never change files");
        assert!(!exists(&dir, INDEX_FILE));
        assert_eq!(scan.files, 6);
        assert_eq!(scan.problems.len(), 1);
        let got: Vec<(&str, &str, u32)> =
            scan.values.iter().map(|v| (v.text.as_str(), v.field.as_str(), v.count)).collect();
        assert_eq!(
            got,
            [
                ("Select", "xmp:Label", 2),
                ("My Keepers", "xmp:Label", 1),
                ("Red", "photoshop:LabelColor", 1),
                ("To Do", "xmp:Label", 1),
            ]
        );
    }
}
