//! Scanning a folder into an ordered list of reviewable items.
//!
//! Files sharing a stem in the same directory are grouped: an iPhone Live Photo
//! (`IMG_0001.HEIC` + `IMG_0001.MOV`) or an edit sidecar (`IMG_0001.AAE`) becomes a
//! single item whose companions travel with it when it is culled.

use serde::Serialize;
use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::path::Path;
use std::time::UNIX_EPOCH;
use walkdir::WalkDir;

pub const IMAGE_EXTS: &[&str] = &[
    "jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff", "heic", "heif",
];
pub const VIDEO_EXTS: &[&str] = &["mp4", "mov", "m4v", "webm", "mkv", "avi", "3gp"];
pub const SIDECAR_EXTS: &[&str] = &["aae", "xmp"];

/// Where "move to folder" puts rejects. Never scanned.
pub const REJECT_DIR: &str = "_Rejected";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Image,
    Video,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Item {
    /// Path relative to the session root, always `/`-separated.
    pub rel: String,
    pub kind: Kind,
    pub ext: String,
    pub size: u64,
    /// Seconds since the Unix epoch.
    pub mtime: i64,
    /// Files (relative paths) that are culled together with this one.
    pub companions: Vec<String>,
}

pub fn ext_of(path: &Path) -> String {
    path.extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase()
}

struct Found {
    rel: String,
    ext: String,
    size: u64,
    mtime: i64,
}

pub fn scan(root: &Path, recursive: bool, include_videos: bool) -> std::io::Result<Vec<Item>> {
    if !root.is_dir() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            format!("{} is not a folder", root.display()),
        ));
    }

    // (directory, lowercase stem) -> files in that group
    let mut groups: BTreeMap<(String, String), Vec<Found>> = BTreeMap::new();

    let walker = WalkDir::new(root)
        .max_depth(if recursive { usize::MAX } else { 1 })
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| {
            if e.depth() == 0 {
                return true;
            }
            let name = e.file_name().to_string_lossy();
            !(name.starts_with('.') || (e.file_type().is_dir() && name == REJECT_DIR))
        });

    for entry in walker.filter_map(Result::ok) {
        if !entry.file_type().is_file() {
            continue;
        }
        let path = entry.path();
        let ext = ext_of(path);
        let known = IMAGE_EXTS.contains(&ext.as_str())
            || VIDEO_EXTS.contains(&ext.as_str())
            || SIDECAR_EXTS.contains(&ext.as_str());
        if !known {
            continue;
        }
        let Ok(rel) = path.strip_prefix(root) else { continue };
        let rel = rel
            .components()
            .map(|c| c.as_os_str().to_string_lossy())
            .collect::<Vec<_>>()
            .join("/");
        let (dir, stem) = match rel.rfind('/') {
            Some(i) => (&rel[..i], &rel[i + 1..]),
            None => ("", rel.as_str()),
        };
        let stem = match stem.rfind('.') {
            Some(i) => &stem[..i],
            None => stem,
        };
        let key = (dir.to_string(), stem.to_lowercase());
        let meta = entry.metadata().ok();
        let size = meta.as_ref().map(|m| m.len()).unwrap_or(0);
        let mtime = meta
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        groups.entry(key).or_default().push(Found { rel, ext, size, mtime });
    }

    let mut items = Vec::new();
    for (_, mut files) in groups {
        files.sort_by(|a, b| natural_cmp(&a.rel, &b.rel));
        let is = |f: &Found, exts: &[&str]| exts.contains(&f.ext.as_str());
        let images: Vec<&Found> = files.iter().filter(|f| is(f, IMAGE_EXTS)).collect();
        let videos: Vec<&Found> = files.iter().filter(|f| is(f, VIDEO_EXTS)).collect();
        let sidecars: Vec<String> = files
            .iter()
            .filter(|f| is(f, SIDECAR_EXTS))
            .map(|f| f.rel.clone())
            .collect();

        let to_item = |f: &Found, kind: Kind| Item {
            rel: f.rel.clone(),
            kind,
            ext: f.ext.clone(),
            size: f.size,
            mtime: f.mtime,
            companions: Vec::new(),
        };

        if !images.is_empty() {
            // Live Photo videos and sidecars belong to the first image of the group.
            for (i, img) in images.iter().enumerate() {
                let mut item = to_item(img, Kind::Image);
                if i == 0 {
                    item.companions.extend(videos.iter().map(|v| v.rel.clone()));
                    item.companions.extend(sidecars.iter().cloned());
                }
                items.push(item);
            }
        } else if include_videos && !videos.is_empty() {
            for (i, vid) in videos.iter().enumerate() {
                let mut item = to_item(vid, Kind::Video);
                if i == 0 {
                    item.companions.extend(sidecars.iter().cloned());
                }
                items.push(item);
            }
        }
    }

    items.sort_by(|a, b| natural_cmp(&a.rel, &b.rel));
    Ok(items)
}

/// Case-insensitive ordering that compares digit runs numerically, so
/// `IMG_9.jpg` sorts before `IMG_10.jpg`.
pub fn natural_cmp(a: &str, b: &str) -> Ordering {
    let (ab, bb) = (a.as_bytes(), b.as_bytes());
    let (mut i, mut j) = (0, 0);
    while i < ab.len() && j < bb.len() {
        if ab[i].is_ascii_digit() && bb[j].is_ascii_digit() {
            let si = i;
            while i < ab.len() && ab[i].is_ascii_digit() {
                i += 1;
            }
            let sj = j;
            while j < bb.len() && bb[j].is_ascii_digit() {
                j += 1;
            }
            let na = a[si..i].trim_start_matches('0');
            let nb = b[sj..j].trim_start_matches('0');
            let ord = na.len().cmp(&nb.len()).then_with(|| na.cmp(nb));
            if ord != Ordering::Equal {
                return ord;
            }
        } else {
            let ord = ab[i].to_ascii_lowercase().cmp(&bb[j].to_ascii_lowercase());
            if ord != Ordering::Equal {
                return ord;
            }
            i += 1;
            j += 1;
        }
    }
    (ab.len() - i).cmp(&(bb.len() - j)).then_with(|| a.cmp(b))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn touch(root: &Path, rel: &str) {
        let p = root.join(rel);
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, b"x").unwrap();
    }

    fn rels(items: &[Item]) -> Vec<&str> {
        items.iter().map(|i| i.rel.as_str()).collect()
    }

    #[test]
    fn natural_order() {
        let mut v = vec!["IMG_10.jpg", "img_9.jpg", "IMG_0011.jpg", "a/IMG_1.jpg"];
        v.sort_by(|a, b| natural_cmp(a, b));
        assert_eq!(v, vec!["a/IMG_1.jpg", "img_9.jpg", "IMG_10.jpg", "IMG_0011.jpg"]);
    }

    #[test]
    fn groups_live_photos_and_sidecars() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        touch(root, "IMG_0001.HEIC");
        touch(root, "IMG_0001.MOV");
        touch(root, "IMG_0001.AAE");
        touch(root, "IMG_0002.MOV");
        touch(root, "notes.txt");

        let items = scan(root, true, true).unwrap();
        assert_eq!(rels(&items), vec!["IMG_0001.HEIC", "IMG_0002.MOV"]);
        assert_eq!(items[0].kind, Kind::Image);
        assert_eq!(items[0].companions, vec!["IMG_0001.MOV", "IMG_0001.AAE"]);
        assert_eq!(items[1].kind, Kind::Video);

        // Standalone videos can be excluded, but Live Photo halves stay attached.
        let items = scan(root, true, false).unwrap();
        assert_eq!(rels(&items), vec!["IMG_0001.HEIC"]);
        assert_eq!(items[0].companions.len(), 2);
    }

    #[test]
    fn skips_hidden_and_reject_dirs_and_respects_recursion() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        touch(root, "a.jpg");
        touch(root, "trip/b.jpg");
        touch(root, ".hidden/c.jpg");
        touch(root, "_Rejected/d.jpg");

        assert_eq!(rels(&scan(root, true, true).unwrap()), vec!["a.jpg", "trip/b.jpg"]);
        assert_eq!(rels(&scan(root, false, true).unwrap()), vec!["a.jpg"]);
    }
}
