//! Applying a cull: moving rejected items (and their companions) out of the way.

use crate::library::{Item, REJECT_DIR};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    /// Freedesktop Trash, so everything is recoverable from the file manager.
    Trash,
    /// `<root>/_Rejected/<original relative path>`.
    Folder,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Failure {
    pub rel: String,
    pub error: String,
}

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Outcome {
    /// Items culled successfully.
    pub items: usize,
    /// Files moved, including companions.
    pub files: usize,
    pub bytes: u64,
    /// Relative paths of the items that were culled.
    pub culled: Vec<String>,
    pub failed: Vec<Failure>,
}

pub fn apply(root: &Path, rejects: &[&Item], mode: Mode) -> Outcome {
    let mut out = Outcome::default();
    for item in rejects {
        let rels: Vec<&String> = std::iter::once(&item.rel).chain(item.companions.iter()).collect();
        let paths: Vec<PathBuf> = rels
            .iter()
            .map(|r| root.join(r))
            .filter(|p| p.exists())
            .collect();
        let bytes: u64 = paths
            .iter()
            .filter_map(|p| fs::metadata(p).ok())
            .map(|m| m.len())
            .sum();

        let result = match mode {
            Mode::Trash => trash::delete_all(&paths).map_err(|e| e.to_string()),
            Mode::Folder => move_into_reject_dir(root, &rels),
        };
        match result {
            Ok(()) => {
                out.items += 1;
                out.files += paths.len();
                out.bytes += bytes;
                out.culled.push(item.rel.clone());
            }
            Err(error) => out.failed.push(Failure { rel: item.rel.clone(), error }),
        }
    }
    out
}

fn move_into_reject_dir(root: &Path, rels: &[&String]) -> Result<(), String> {
    for rel in rels {
        let src = root.join(rel);
        if !src.exists() {
            continue;
        }
        let dest = unique_path(root.join(REJECT_DIR).join(rel));
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        fs::rename(&src, &dest).map_err(|e| format!("{rel}: {e}"))?;
    }
    Ok(())
}

/// `photo.jpg` -> `photo (1).jpg` -> `photo (2).jpg` ... until unused.
fn unique_path(path: PathBuf) -> PathBuf {
    if !path.exists() {
        return path;
    }
    let stem = path.file_stem().unwrap_or_default().to_string_lossy().into_owned();
    let ext = path
        .extension()
        .map(|e| format!(".{}", e.to_string_lossy()))
        .unwrap_or_default();
    (1..)
        .map(|n| path.with_file_name(format!("{stem} ({n}){ext}")))
        .find(|p| !p.exists())
        .unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::scan;

    #[test]
    fn folder_mode_moves_item_with_companions_preserving_layout() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        fs::create_dir_all(root.join("trip")).unwrap();
        for f in ["trip/IMG_1.HEIC", "trip/IMG_1.MOV", "trip/IMG_2.JPG"] {
            fs::write(root.join(f), b"data").unwrap();
        }
        // A name clash already waiting in the reject folder.
        fs::create_dir_all(root.join("_Rejected/trip")).unwrap();
        fs::write(root.join("_Rejected/trip/IMG_1.HEIC"), b"old").unwrap();

        let items = scan(root, true, true).unwrap();
        let reject: Vec<&Item> = items.iter().filter(|i| i.rel == "trip/IMG_1.HEIC").collect();
        let out = apply(root, &reject, Mode::Folder);

        assert_eq!((out.items, out.files, out.bytes), (1, 2, 8));
        assert!(out.failed.is_empty());
        assert!(!root.join("trip/IMG_1.HEIC").exists());
        assert!(!root.join("trip/IMG_1.MOV").exists());
        assert!(root.join("trip/IMG_2.JPG").exists());
        assert!(root.join("_Rejected/trip/IMG_1 (1).HEIC").exists());
        assert!(root.join("_Rejected/trip/IMG_1.MOV").exists());
        // The reject folder is never rescanned.
        assert_eq!(scan(root, true, true).unwrap().len(), 1);
    }
}
