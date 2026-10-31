//! Per-folder review decisions, persisted next to the photos so a cull can be
//! resumed later (or from another machine).

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub const STORE_FILE: &str = ".bestshot-cull.json";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Decision {
    Keep,
    Reject,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Store {
    #[serde(default = "current_version")]
    pub version: u32,
    /// Relative path -> decision. Unreviewed files have no entry.
    #[serde(default)]
    pub decisions: BTreeMap<String, Decision>,
    /// Relative paths in rank order, best first. Unranked files are absent.
    #[serde(default)]
    pub ranking: Vec<String>,
}

fn current_version() -> u32 {
    1
}

fn store_path(root: &Path) -> PathBuf {
    root.join(STORE_FILE)
}

/// Loads the store for `root`. A missing file is an empty store. An unreadable
/// one is set aside (never silently overwritten) and a warning is returned.
pub fn load(root: &Path) -> (Store, Option<String>) {
    let path = store_path(root);
    let text = match fs::read_to_string(&path) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return (Store { version: 1, ..Default::default() }, None)
        }
        Err(e) => return (Store::default(), Some(format!("Couldn't read saved decisions: {e}"))),
    };
    match serde_json::from_str::<Store>(&text) {
        Ok(store) => (store, None),
        Err(e) => {
            let backup = root.join(format!("{STORE_FILE}.corrupt"));
            let _ = fs::rename(&path, &backup);
            (
                Store { version: 1, ..Default::default() },
                Some(format!(
                    "Saved decisions were unreadable ({e}); moved them to {} and started fresh.",
                    backup.display()
                )),
            )
        }
    }
}

/// Atomically writes the store (temp file + rename).
pub fn save(root: &Path, store: &Store) -> std::io::Result<()> {
    let path = store_path(root);
    let tmp = root.join(format!("{STORE_FILE}.tmp"));
    let json = serde_json::to_vec_pretty(store).map_err(std::io::Error::other)?;
    fs::write(&tmp, json)?;
    fs::rename(&tmp, &path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_and_recovers_from_corruption() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();

        let (mut store, warn) = load(root);
        assert!(warn.is_none() && store.decisions.is_empty());

        store.decisions.insert("a.jpg".into(), Decision::Keep);
        store.decisions.insert("sub/b.jpg".into(), Decision::Reject);
        store.ranking = vec!["sub/b.jpg".into(), "a.jpg".into()];
        save(root, &store).unwrap();

        let (loaded, _) = load(root);
        assert_eq!(loaded.decisions, store.decisions);
        assert_eq!(loaded.ranking, store.ranking);

        // Files written before ranking existed still load.
        fs::write(root.join(STORE_FILE), r#"{"version":1,"decisions":{"a.jpg":"keep"}}"#).unwrap();
        let (old, warn) = load(root);
        assert!(warn.is_none() && old.ranking.is_empty() && old.decisions.len() == 1);

        fs::write(root.join(STORE_FILE), "{ nope").unwrap();
        let (fresh, warn) = load(root);
        assert!(fresh.decisions.is_empty());
        assert!(warn.is_some());
        assert!(root.join(format!("{STORE_FILE}.corrupt")).exists());
    }
}
