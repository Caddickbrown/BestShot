//! Scanning a folder into an ordered list of reviewable items.
//!
//! Files sharing a stem in the same directory are grouped: an iPhone Live Photo
//! (`IMG_0001.HEIC` + `IMG_0001.MOV`) or an edit sidecar (`IMG_0001.AAE`) becomes a
//! single item whose companions travel with it when it is culled.
//!
//! An `.xmp` sidecar is either `IMG_0001.xmp` (Adobe) or `IMG_0001.jpg.xmp`
//! (darktable, digiKam). When several images share a stem, a raw file with a
//! JPEG beside it for instance, `IMG_0001.xmp` belongs to the raw and the
//! others use the full-name form, so one photo's rating can't land on another.

use serde::Serialize;
use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::path::Path;
use std::time::UNIX_EPOCH;
use walkdir::WalkDir;

pub const RAW_EXTS: &[&str] = &[
    "dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "rw2", "pef", "srw", "x3f", "3fr",
    "iiq", "erf", "mef", "mos", "mrw", "kdc", "dcr",
];
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
    /// This item's `.xmp` sidecar: the existing file, or where a new one goes.
    pub sidecar: String,
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

fn is_image(ext: &str) -> bool {
    IMAGE_EXTS.contains(&ext) || RAW_EXTS.contains(&ext)
}

fn is_media(ext: &str) -> bool {
    is_image(ext) || VIDEO_EXTS.contains(&ext)
}

/// `dir/name.ext` -> `dir/name`.
fn without_ext(rel: &str) -> &str {
    let name_start = rel.rfind('/').map_or(0, |i| i + 1);
    match rel[name_start..].rfind('.') {
        Some(i) => &rel[..name_start + i],
        None => rel,
    }
}

/// Picks each item's sidecar from the group's `.xmp` files. `primary` is the
/// one item that may claim the plain `stem.xmp`; returns the chosen path and
/// whether that file exists.
fn sidecar_for(rel: &str, primary: bool, group: &[Found]) -> (String, bool) {
    let exact = format!("{rel}.xmp");
    let stem = format!("{}.xmp", without_ext(rel));
    let xmps = || group.iter().filter(|f| f.ext == "xmp");
    if let Some(f) = xmps().find(|f| f.rel.eq_ignore_ascii_case(&exact)) {
        return (f.rel.clone(), true);
    }
    if !primary {
        return (exact, false);
    }
    match xmps().find(|f| f.rel.to_lowercase() == stem.to_lowercase()) {
        Some(f) => (f.rel.clone(), true),
        None => (stem, false),
    }
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
        let known = is_media(&ext) || SIDECAR_EXTS.contains(&ext.as_str());
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
        let mut stem = match stem.rfind('.') {
            Some(i) => &stem[..i],
            None => stem,
        };
        // `IMG_1.jpg.xmp` joins the group of `IMG_1.jpg`.
        if ext == "xmp" && is_media(&ext_of(Path::new(stem))) {
            stem = without_ext(stem);
        }
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
        // A raw file leads its group, whatever the JPEG beside it sorts as.
        let mut images: Vec<&Found> = files.iter().filter(|f| is_image(&f.ext)).collect();
        images.sort_by_key(|f| !RAW_EXTS.contains(&f.ext.as_str()));
        let videos: Vec<&Found> = files.iter().filter(|f| VIDEO_EXTS.contains(&f.ext.as_str())).collect();

        let to_item = |f: &Found, kind: Kind, primary: bool| {
            let (sidecar, exists) = sidecar_for(&f.rel, primary, &files);
            let mut companions = Vec::new();
            if primary {
                if kind == Kind::Image {
                    companions.extend(videos.iter().map(|v| v.rel.clone()));
                }
                companions.extend(files.iter().filter(|s| s.ext == "aae").map(|s| s.rel.clone()));
            }
            if exists {
                companions.push(sidecar.clone());
            }
            Item {
                rel: f.rel.clone(),
                kind,
                ext: f.ext.clone(),
                size: f.size,
                mtime: f.mtime,
                companions,
                sidecar,
            }
        };

        if !images.is_empty() {
            // Live Photo videos and sidecars belong to the first image of the group.
            for (i, img) in images.iter().enumerate() {
                items.push(to_item(img, Kind::Image, i == 0));
            }
        } else if include_videos {
            for (i, vid) in videos.iter().enumerate() {
                items.push(to_item(vid, Kind::Video, i == 0));
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
    fn sidecars_go_with_the_right_file() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        for f in ["A.NEF", "A.JPG", "A.xmp", "B.jpg", "B.jpg.xmp", "c/C.heic", "D.jpg", "D.XMP", "E.jpg", "E.tif", "orphan.xmp"] {
            touch(root, f);
        }
        let items = scan(root, true, true).unwrap();
        let find = |rel: &str| items.iter().find(|i| i.rel == rel).unwrap();

        assert_eq!(items.len(), 7, "sidecars alone never become items");
        // The raw owns `A.xmp`, even though .JPG sorts first.
        assert_eq!(find("A.NEF").sidecar, "A.xmp");
        assert_eq!(find("A.NEF").companions, ["A.xmp"]);
        assert_eq!(find("A.JPG").sidecar, "A.JPG.xmp");
        assert!(find("A.JPG").companions.is_empty());
        // The full-name form is grouped with its image.
        assert_eq!(find("B.jpg").sidecar, "B.jpg.xmp");
        assert_eq!(find("B.jpg").companions, ["B.jpg.xmp"]);
        // Not there yet: where a new one would go.
        assert_eq!(find("c/C.heic").sidecar, "c/C.xmp");
        assert!(find("c/C.heic").companions.is_empty());
        // An uppercase extension keeps its real name.
        assert_eq!(find("D.jpg").sidecar, "D.XMP");
        // Two plain images: only one can have `E.xmp`.
        assert_eq!(find("E.jpg").sidecar, "E.xmp");
        assert_eq!(find("E.tif").sidecar, "E.tif.xmp");
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
