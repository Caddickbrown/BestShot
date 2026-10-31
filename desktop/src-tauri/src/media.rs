//! Serving pixels to the webview: on-demand thumbnails, display-ready
//! previews for formats WebKit can't decode (HEIC, TIFF), and EXIF details.

use bestshot_core::library::{self, Item, Kind};
use image::metadata::Orientation;
use image::{DynamicImage, GrayImage, ImageDecoder, ImageReader, RgbImage};
use serde::Serialize;
use std::fs::{self, File};
use std::io::BufReader;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use tauri::http::{header, Response, StatusCode};

pub const THUMB_SIZE: u32 = 480;

// ---------------------------------------------------------------------------
// Worker pool

type Job = Box<dyn FnOnce() + Send>;

/// A fixed pool that runs the *most recently* queued job first. When the user
/// scrolls through a big grid, the tiles currently on screen are always the
/// newest requests, so they jump ahead of ones that scrolled past.
pub struct LifoPool {
    queue: Arc<(Mutex<Vec<Job>>, Condvar)>,
}

impl LifoPool {
    pub fn new(threads: usize) -> Self {
        let queue: Arc<(Mutex<Vec<Job>>, Condvar)> = Arc::default();
        for _ in 0..threads.max(1) {
            let queue = queue.clone();
            std::thread::spawn(move || loop {
                let job = {
                    let (lock, cvar) = &*queue;
                    let mut jobs = lock.lock().unwrap();
                    loop {
                        if let Some(job) = jobs.pop() {
                            break job;
                        }
                        jobs = cvar.wait(jobs).unwrap();
                    }
                };
                job();
            });
        }
        Self { queue }
    }

    pub fn spawn(&self, job: impl FnOnce() + Send + 'static) {
        let (lock, cvar) = &*self.queue;
        lock.lock().unwrap().push(Box::new(job));
        cvar.notify_one();
    }
}

// ---------------------------------------------------------------------------
// HTTP responses

#[derive(Clone, Copy)]
pub enum Variant {
    Thumb,
    Full,
}

pub fn respond(cache: &Path, root: &Path, item: &Item, variant: Variant) -> Response<Vec<u8>> {
    let abs = root.join(&item.rel);
    let result = match (variant, item.kind) {
        (Variant::Thumb, _) => thumbnail(cache, &abs, item).and_then(|p| file_response(&p, "image/jpeg")),
        // WebKitGTK can't stream media from custom schemes; see video.rs.
        (Variant::Full, Kind::Video) => Err("Videos are served by the local video server".into()),
        (Variant::Full, Kind::Image) => match item.ext.as_str() {
            "heic" | "heif" => heic_to_jpeg(cache, &abs, item).and_then(|p| file_response(&p, "image/jpeg")),
            "tif" | "tiff" => tiff_to_jpeg(cache, &abs, item).and_then(|p| file_response(&p, "image/jpeg")),
            ext => file_response(&abs, mime_for(ext)),
        },
    };
    result.unwrap_or_else(|e| {
        eprintln!("bestshot: {}: {e}", item.rel);
        error_response(StatusCode::INTERNAL_SERVER_ERROR, &e)
    })
}

pub fn error_response(status: StatusCode, msg: &str) -> Response<Vec<u8>> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, "text/plain")
        // Lets the UI fetch() the message to explain a broken image.
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .body(msg.as_bytes().to_vec())
        .unwrap()
}

fn file_response(path: &Path, mime: &str) -> Result<Response<Vec<u8>>, String> {
    let bytes = fs::read(path).map_err(|e| e.to_string())?;
    Ok(Response::builder()
        .header(header::CONTENT_TYPE, mime)
        // URLs carry the session generation, so they're safe to cache.
        .header(header::CACHE_CONTROL, "max-age=86400")
        .body(bytes)
        .unwrap())
}

/// Parses a single `bytes=` range into inclusive offsets.
pub fn parse_range(header: &str, len: u64) -> Option<(u64, u64)> {
    let spec = header.trim().strip_prefix("bytes=")?.split(',').next()?.trim();
    let (a, b) = spec.split_once('-')?;
    let (start, end) = match (a.trim(), b.trim()) {
        ("", suffix) => {
            let n: u64 = suffix.parse().ok()?;
            (len.saturating_sub(n), len - 1)
        }
        (s, "") => (s.parse().ok()?, len - 1),
        (s, e) => (s.parse().ok()?, e.parse::<u64>().ok()?.min(len - 1)),
    };
    (start <= end && start < len).then_some((start, end))
}

pub fn mime_for(ext: &str) -> &'static str {
    match ext {
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "webp" => "image/webp",
        "gif" => "image/gif",
        "bmp" => "image/bmp",
        "mp4" | "m4v" => "video/mp4",
        "mov" => "video/quicktime",
        "webm" => "video/webm",
        "mkv" => "video/x-matroska",
        "avi" => "video/x-msvideo",
        "3gp" => "video/3gpp",
        _ => "application/octet-stream",
    }
}

// ---------------------------------------------------------------------------
// Derived images (cached on disk)

fn cache_file(cache: &Path, kind: &str, abs: &Path, item: &Item) -> PathBuf {
    // FNV-1a over everything that should invalidate the cached copy.
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    let parts = [
        abs.as_os_str().as_encoded_bytes(),
        kind.as_bytes(),
        &item.size.to_le_bytes(),
        &item.mtime.to_le_bytes(),
    ];
    for b in parts.iter().flat_map(|p| p.iter()) {
        h ^= *b as u64;
        h = h.wrapping_mul(0x0100_0000_01b3);
    }
    cache.join(kind).join(format!("{h:016x}.jpg"))
}

/// A private scratch directory; finished files are renamed into place so a
/// half-written image is never served.
fn scratch_dir(cache: &Path) -> Result<PathBuf, String> {
    static N: AtomicU64 = AtomicU64::new(0);
    let dir = cache
        .join("tmp")
        .join(format!("{}-{}", std::process::id(), N.fetch_add(1, Ordering::Relaxed)));
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

fn finish(tmp: &Path, out: &Path) -> Result<(), String> {
    fs::create_dir_all(out.parent().unwrap()).map_err(|e| e.to_string())?;
    fs::rename(tmp, out).map_err(|e| e.to_string())
}

fn thumbnail(cache: &Path, abs: &Path, item: &Item) -> Result<PathBuf, String> {
    let out = cache_file(cache, "thumbs", abs, item);
    if out.exists() {
        return Ok(out);
    }
    if item.kind == Kind::Video {
        video_frame(cache, abs, &out)?;
        return Ok(out);
    }
    let source = match item.ext.as_str() {
        "heic" | "heif" => heic_to_jpeg(cache, abs, item)?,
        _ => abs.to_path_buf(),
    };
    let img = decode_oriented(&source, THUMB_SIZE)?.thumbnail(THUMB_SIZE, THUMB_SIZE);
    write_jpeg(cache, &img, &out, 82)
        .map(|_| out)
}

fn write_jpeg(cache: &Path, img: &DynamicImage, out: &Path, quality: u8) -> Result<(), String> {
    let dir = scratch_dir(cache)?;
    let tmp = dir.join("out.jpg");
    let file = File::create(&tmp).map_err(|e| e.to_string())?;
    let mut writer = std::io::BufWriter::new(file);
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut writer, quality)
        .encode_image(&DynamicImage::ImageRgb8(img.to_rgb8()))
        .map_err(|e| e.to_string())?;
    drop(writer);
    let result = finish(&tmp, out);
    let _ = fs::remove_dir_all(&dir);
    result
}

/// Decodes an image with its EXIF orientation applied. JPEGs are decoded at a
/// reduced DCT scale when only `min_size` pixels are needed, which is several
/// times faster for large camera files.
fn decode_oriented(path: &Path, min_size: u32) -> Result<DynamicImage, String> {
    let ext = library::ext_of(path);
    if ext == "jpg" || ext == "jpeg" {
        if let Some(mut img) = decode_jpeg_scaled(path, min_size) {
            if let Some(o) = exif_orientation(path).and_then(|o| Orientation::from_exif(o as u8)) {
                img.apply_orientation(o);
            }
            return Ok(img);
        }
    }
    let mut decoder = ImageReader::open(path)
        .and_then(|r| r.with_guessed_format())
        .map_err(|e| e.to_string())?
        .into_decoder()
        .map_err(|e| e.to_string())?;
    let orientation = decoder.orientation().unwrap_or(Orientation::NoTransforms);
    let mut img = DynamicImage::from_decoder(decoder).map_err(|e| e.to_string())?;
    img.apply_orientation(orientation);
    Ok(img)
}

fn decode_jpeg_scaled(path: &Path, min_size: u32) -> Option<DynamicImage> {
    let mut dec = jpeg_decoder::Decoder::new(BufReader::new(File::open(path).ok()?));
    dec.read_info().ok()?;
    let info = dec.info()?;
    let (w, h) = (info.width as u32, info.height as u32);
    let longest = w.max(h).max(1);
    let (sw, sh) = dec
        .scale(
            (min_size * w).div_ceil(longest).min(u16::MAX as u32) as u16,
            (min_size * h).div_ceil(longest).min(u16::MAX as u32) as u16,
        )
        .ok()?;
    let pixels = dec.decode().ok()?;
    let (sw, sh) = (sw as u32, sh as u32);
    match dec.info()?.pixel_format {
        jpeg_decoder::PixelFormat::RGB24 => RgbImage::from_raw(sw, sh, pixels).map(DynamicImage::ImageRgb8),
        jpeg_decoder::PixelFormat::L8 => GrayImage::from_raw(sw, sh, pixels).map(DynamicImage::ImageLuma8),
        // CMYK / 16-bit: rare enough to leave to the full decoder.
        _ => None,
    }
}

/// Serialises work on one output file, so the thumbnail and full-size
/// requests for a new HEIC don't both run a (slow) conversion.
fn output_lock(out: &Path) -> Arc<Mutex<()>> {
    static LOCKS: Mutex<Option<std::collections::HashMap<PathBuf, Arc<Mutex<()>>>>> = Mutex::new(None);
    let mut locks = LOCKS.lock().unwrap();
    let map = locks.get_or_insert_with(Default::default);
    map.retain(|_, lock| Arc::strong_count(lock) > 1);
    map.entry(out.to_path_buf()).or_default().clone()
}

fn heic_to_jpeg(cache: &Path, abs: &Path, item: &Item) -> Result<PathBuf, String> {
    let out = cache_file(cache, "full", abs, item);
    let lock = output_lock(&out);
    let _guard = lock.lock().unwrap();
    if out.exists() {
        return Ok(out);
    }
    let dir = scratch_dir(cache)?;
    let tmp = dir.join("out.jpg");
    // libheif applies the HEIF rotation itself and resets the EXIF orientation.
    let result = Command::new("heif-convert")
        .arg("-q")
        .arg("90")
        .arg(abs)
        .arg(&tmp)
        .output();
    let outcome = match result {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Err(
            "HEIC photos need heif-convert — install it with: sudo apt install libheif-examples".into(),
        ),
        Err(e) => Err(e.to_string()),
        Ok(o) if !tmp.exists() => Err(format!(
            "heif-convert failed: {}",
            String::from_utf8_lossy(&o.stderr).trim()
        )),
        Ok(_) => finish(&tmp, &out),
    };
    let _ = fs::remove_dir_all(&dir);
    outcome.map(|_| out)
}

fn tiff_to_jpeg(cache: &Path, abs: &Path, item: &Item) -> Result<PathBuf, String> {
    let out = cache_file(cache, "full", abs, item);
    if !out.exists() {
        let img = decode_oriented(abs, u32::MAX)?;
        write_jpeg(cache, &img, &out, 90)?;
    }
    Ok(out)
}

fn video_frame(cache: &Path, abs: &Path, out: &Path) -> Result<(), String> {
    let dir = scratch_dir(cache)?;
    let tmp = dir.join("out.jpg");
    let scale = format!("scale={THUMB_SIZE}:{THUMB_SIZE}:force_original_aspect_ratio=decrease");
    let mut last_err = String::new();
    // A second in avoids black fade-in frames; retry at 0 for very short clips.
    for seek in ["1", "0"] {
        let result = Command::new("ffmpeg")
            .args(["-v", "error", "-y", "-ss", seek, "-i"])
            .arg(abs)
            .args(["-frames:v", "1", "-vf", &scale, "-q:v", "4"])
            .arg(&tmp)
            .output();
        match result {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                last_err = "Video thumbnails need ffmpeg — install it with: sudo apt install ffmpeg".into();
                break;
            }
            Err(e) => last_err = e.to_string(),
            Ok(o) => {
                if fs::metadata(&tmp).map(|m| m.len() > 0).unwrap_or(false) {
                    let r = finish(&tmp, out);
                    let _ = fs::remove_dir_all(&dir);
                    return r;
                }
                last_err = String::from_utf8_lossy(&o.stderr).trim().to_string();
            }
        }
    }
    let _ = fs::remove_dir_all(&dir);
    Err(last_err)
}

/// Keeps the on-disk cache under `max_bytes` by deleting the oldest files, and
/// clears scratch space left behind by a crash.
pub fn prune_cache(cache: &Path, max_bytes: u64) {
    let _ = fs::remove_dir_all(cache.join("tmp"));
    let mut files: Vec<(PathBuf, u64, std::time::SystemTime)> = ["thumbs", "full"]
        .iter()
        .filter_map(|d| fs::read_dir(cache.join(d)).ok())
        .flatten()
        .filter_map(Result::ok)
        .filter_map(|e| {
            let m = e.metadata().ok()?;
            Some((e.path(), m.len(), m.modified().ok()?))
        })
        .collect();
    let mut total: u64 = files.iter().map(|f| f.1).sum();
    if total <= max_bytes {
        return;
    }
    files.sort_by_key(|f| f.2);
    for (path, len, _) in files {
        if total <= max_bytes / 4 * 3 {
            break;
        }
        if fs::remove_file(&path).is_ok() {
            total -= len;
        }
    }
}

// ---------------------------------------------------------------------------
// Details panel

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Info {
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub taken: Option<String>,
    pub camera: Option<String>,
    pub lens: Option<String>,
    pub exposure: Option<String>,
    pub aperture: Option<String>,
    pub iso: Option<String>,
    pub focal: Option<String>,
}

fn read_exif(path: &Path) -> Option<exif::Exif> {
    let file = File::open(path).ok()?;
    exif::Reader::new().read_from_container(&mut BufReader::new(file)).ok()
}

fn exif_orientation(path: &Path) -> Option<u32> {
    read_exif(path)?
        .get_field(exif::Tag::Orientation, exif::In::PRIMARY)?
        .value
        .get_uint(0)
}

pub fn info(root: &Path, item: &Item) -> Info {
    let abs = root.join(&item.rel);
    let mut info = Info::default();
    if item.kind == Kind::Image && !matches!(item.ext.as_str(), "heic" | "heif") {
        if let Ok((w, h)) = image::image_dimensions(&abs) {
            info.width = Some(w);
            info.height = Some(h);
        }
    }
    let Some(exif) = read_exif(&abs) else { return info };

    let field = |tag| exif.get_field(tag, exif::In::PRIMARY);
    let text = |tag| match &field(tag)?.value {
        exif::Value::Ascii(v) => v
            .first()
            .map(|s| String::from_utf8_lossy(s).trim().trim_end_matches('\0').to_string())
            .filter(|s| !s.is_empty()),
        _ => None,
    };
    let shown = |tag| field(tag).map(|f| f.display_value().with_unit(&exif).to_string());
    let uint = |tag| field(tag).and_then(|f| f.value.get_uint(0));

    if info.width.is_none() {
        info.width = uint(exif::Tag::PixelXDimension);
        info.height = uint(exif::Tag::PixelYDimension);
    }
    // Both sources report stored (unrotated) dimensions.
    if matches!(uint(exif::Tag::Orientation), Some(5..=8)) {
        std::mem::swap(&mut info.width, &mut info.height);
    }
    // EXIF dates look like "2024:05:01 12:34:56".
    info.taken = text(exif::Tag::DateTimeOriginal)
        .or_else(|| text(exif::Tag::DateTime))
        .map(|d| d.replacen(':', "-", 2));
    info.camera = match (text(exif::Tag::Make), text(exif::Tag::Model)) {
        (Some(make), Some(model)) if model.starts_with(&make) => Some(model),
        (Some(make), Some(model)) => Some(format!("{make} {model}")),
        (make, model) => make.or(model),
    };
    info.lens = text(exif::Tag::LensModel);
    info.exposure = shown(exif::Tag::ExposureTime);
    info.aperture = field(exif::Tag::FNumber).map(|f| format!("f/{}", f.display_value()));
    info.iso = uint(exif::Tag::PhotographicSensitivity).map(|n| format!("ISO {n}"));
    info.focal = shown(exif::Tag::FocalLength);
    info
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_ranges() {
        assert_eq!(parse_range("bytes=0-", 100), Some((0, 99)));
        assert_eq!(parse_range("bytes=10-19", 100), Some((10, 19)));
        assert_eq!(parse_range("bytes=90-500", 100), Some((90, 99)));
        assert_eq!(parse_range("bytes=-10", 100), Some((90, 99)));
        assert_eq!(parse_range("bytes=100-", 100), None);
        assert_eq!(parse_range("items=0-1", 100), None);
    }

    #[test]
    fn thumbnails_respect_exif_orientation() {
        let dir = tempfile::tempdir().unwrap();
        let (root, cache) = (dir.path().join("photos"), dir.path().join("cache"));
        fs::create_dir_all(&root).unwrap();

        // A landscape 1600x800 JPEG flagged "rotate 90° CW" should thumb as portrait.
        let mut jpeg = Vec::new();
        image::codecs::jpeg::JpegEncoder::new(&mut jpeg)
            .encode_image(&DynamicImage::ImageRgb8(RgbImage::new(1600, 800)))
            .unwrap();
        fs::write(root.join("p.jpg"), with_orientation(&jpeg, 6)).unwrap();

        let items = library::scan(&root, false, false).unwrap();
        let thumb = thumbnail(&cache, &root.join("p.jpg"), &items[0]).unwrap();
        let (w, h) = image::image_dimensions(&thumb).unwrap();
        assert_eq!((w, h), (THUMB_SIZE / 2, THUMB_SIZE));
        // Second call is a cache hit on the same file.
        assert_eq!(thumbnail(&cache, &root.join("p.jpg"), &items[0]).unwrap(), thumb);
    }

    /// Splices a minimal EXIF APP1 segment carrying `orientation` after SOI.
    fn with_orientation(jpeg: &[u8], orientation: u16) -> Vec<u8> {
        let mut tiff = b"MM\0\x2a\0\0\0\x08".to_vec();
        tiff.extend([0, 1]); // one IFD entry
        tiff.extend([0x01, 0x12, 0, 3, 0, 0, 0, 1]); // Orientation, SHORT, count 1
        tiff.extend(orientation.to_be_bytes());
        tiff.extend([0, 0, 0, 0, 0, 0]); // padding + next IFD = 0
        let mut app1 = b"Exif\0\0".to_vec();
        app1.extend(tiff);
        let mut out = jpeg[..2].to_vec();
        out.extend([0xFF, 0xE1]);
        out.extend(((app1.len() + 2) as u16).to_be_bytes());
        out.extend(app1);
        out.extend(&jpeg[2..]);
        out
    }
}
