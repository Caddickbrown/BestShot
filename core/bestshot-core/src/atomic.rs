//! Replacing a file atomically: the old version or the new one, never half of
//! either.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_TMP: AtomicU64 = AtomicU64::new(0);

fn tmp_path(path: &Path) -> PathBuf {
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let n = NEXT_TMP.fetch_add(1, Ordering::Relaxed);
    path.with_file_name(format!(".{name}.bestshot-{}-{n}.tmp", std::process::id()))
}

/// Writes `bytes` to `path` through a hidden temp file in the same folder,
/// flushed before the rename.
///
/// A rename would replace a read-only file without complaint, so that's
/// checked first: read-only stays untouched. Writing through a symlink updates
/// its target. For an existing file the temp file starts as a copy, which
/// keeps its mode and (on macOS) extended attributes such as Finder tags.
pub fn replace(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let target = match fs::symlink_metadata(path) {
        Ok(m) if m.file_type().is_symlink() => fs::canonicalize(path)?,
        _ => path.to_path_buf(),
    };
    let existing = match fs::metadata(&target) {
        Ok(m) => Some(m),
        Err(e) if e.kind() == io::ErrorKind::NotFound => None,
        Err(e) => return Err(e),
    };
    if existing.as_ref().is_some_and(|m| m.permissions().readonly()) {
        return Err(io::Error::new(io::ErrorKind::PermissionDenied, "file is read-only"));
    }

    let tmp = tmp_path(&target);
    let result = write_tmp(&tmp, &target, existing.is_some(), bytes).and_then(|()| fs::rename(&tmp, &target));
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result?;
    // The rename itself survives a crash only once the folder is flushed.
    if let Some(parent) = target.parent() {
        if let Ok(dir) = File::open(parent) {
            let _ = dir.sync_all();
        }
    }
    Ok(())
}

fn write_tmp(tmp: &Path, target: &Path, exists: bool, bytes: &[u8]) -> io::Result<()> {
    if exists {
        fs::copy(target, tmp)?;
    }
    let mut file = OpenOptions::new().write(true).create(!exists).truncate(true).open(tmp)?;
    file.write_all(bytes)?;
    file.sync_all()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entries(dir: &Path) -> usize {
        fs::read_dir(dir).unwrap().count()
    }

    #[test]
    fn creates_and_replaces_leaving_no_temp_files() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("a.xmp");
        replace(&path, b"one").unwrap();
        replace(&path, b"two").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"two");
        assert_eq!(entries(dir.path()), 1);
    }

    #[test]
    fn refuses_a_read_only_file() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("a.xmp");
        fs::write(&path, b"keep me").unwrap();
        let mut perms = fs::metadata(&path).unwrap().permissions();
        perms.set_readonly(true);
        fs::set_permissions(&path, perms).unwrap();

        assert!(replace(&path, b"new").is_err());
        assert_eq!(fs::read(&path).unwrap(), b"keep me");
        assert_eq!(entries(dir.path()), 1);
    }

    #[cfg(unix)]
    #[test]
    fn keeps_mode_and_writes_through_symlinks() {
        use std::os::unix::fs::{symlink, PermissionsExt};
        let dir = tempfile::tempdir().unwrap();
        let real = dir.path().join("real.xmp");
        let link = dir.path().join("link.xmp");
        fs::write(&real, b"old").unwrap();
        fs::set_permissions(&real, fs::Permissions::from_mode(0o640)).unwrap();
        symlink(&real, &link).unwrap();

        replace(&link, b"new").unwrap();
        assert!(fs::symlink_metadata(&link).unwrap().file_type().is_symlink());
        assert_eq!(fs::read(&real).unwrap(), b"new");
        assert_eq!(fs::metadata(&real).unwrap().permissions().mode() & 0o777, 0o640);
    }
}
