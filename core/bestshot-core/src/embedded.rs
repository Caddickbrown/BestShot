//! XMP stored inside image files.
//!
//! Reads JPEG (APP1), TIFF and TIFF-based raw files including DNG (tag 700) and
//! PNG (`iTXt`), seeking past the image data rather than loading it. Writing
//! is JPEG only, and off by default: Adobe apps ignore sidecars for JPEGs, but
//! it means rewriting an original, so everything outside the XMP segment is
//! checked byte for byte before the file is replaced.

use crate::atomic;
use crate::xmp::{self, Change, Fields};
use std::fs::{self, File};
use std::io::{self, BufReader, Read, Seek, SeekFrom};
use std::path::Path;

const JPEG_XMP_HEADER: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";
/// A JPEG segment holds 65535 bytes, including its length and the header.
const JPEG_XMP_MAX: usize = 65533 - JPEG_XMP_HEADER.len();
/// Larger than any packet worth reading: a bad offset shouldn't allocate gigabytes.
const PACKET_LIMIT: u64 = 32 * 1024 * 1024;

/// The XMP packet inside an image, if it has one and the format is supported.
pub fn read(path: &Path) -> io::Result<Option<Vec<u8>>> {
    let mut file = BufReader::new(File::open(path)?);
    let mut magic = [0u8; 8];
    if file.read_exact(&mut magic).is_err() {
        return Ok(None);
    }
    file.seek(SeekFrom::Start(0))?;
    // A truncated file just has no readable packet.
    let eof_is_none = |r: io::Result<Option<Vec<u8>>>| match r {
        Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => Ok(None),
        other => other,
    };
    match magic {
        [0xFF, 0xD8, ..] => eof_is_none(read_jpeg(&mut file)),
        [0x89, b'P', b'N', b'G', ..] => eof_is_none(read_png(&mut file)),
        [b'I', b'I', 42, 0, ..] => eof_is_none(read_tiff(&mut file, false)),
        [b'M', b'M', 0, 42, ..] => eof_is_none(read_tiff(&mut file, true)),
        _ => Ok(None),
    }
}

/// The fields in a file's embedded packet. `Err` means a packet exists but
/// can't be parsed.
pub fn read_fields(path: &Path) -> Result<Option<Fields>, String> {
    match read(path).map_err(|e| e.to_string())? {
        Some(packet) => xmp::parse_bytes(&packet).map(Some),
        None => Ok(None),
    }
}

fn read_jpeg<R: Read + Seek>(file: &mut R) -> io::Result<Option<Vec<u8>>> {
    file.seek(SeekFrom::Start(2))?;
    loop {
        let mut marker = [0u8; 2];
        file.read_exact(&mut marker)?;
        if marker[0] != 0xFF {
            return Ok(None);
        }
        // Fill bytes before a marker are legal.
        while marker[1] == 0xFF {
            let mut b = [0u8; 1];
            file.read_exact(&mut b)?;
            marker[1] = b[0];
        }
        match marker[1] {
            0xD9 | 0xDA => return Ok(None), // metadata comes before the scan
            0x01 | 0xD0..=0xD7 => continue, // no length
            _ => {}
        }
        let mut len = [0u8; 2];
        file.read_exact(&mut len)?;
        let body = u16::from_be_bytes(len).saturating_sub(2) as usize;
        if marker[1] == 0xE1 && body >= JPEG_XMP_HEADER.len() {
            let mut data = vec![0u8; body];
            file.read_exact(&mut data)?;
            if let Some(packet) = data.strip_prefix(JPEG_XMP_HEADER) {
                return Ok(Some(packet.to_vec()));
            }
        } else {
            file.seek(SeekFrom::Current(body as i64))?;
        }
    }
}

fn read_png<R: Read + Seek>(file: &mut R) -> io::Result<Option<Vec<u8>>> {
    const KEYWORD: &[u8] = b"XML:com.adobe.xmp\0";
    file.seek(SeekFrom::Start(8))?;
    loop {
        let mut head = [0u8; 8];
        file.read_exact(&mut head)?;
        let len = u32::from_be_bytes([head[0], head[1], head[2], head[3]]) as u64;
        let kind = &head[4..8];
        if kind == b"IEND" {
            return Ok(None);
        }
        if kind == b"iTXt" && len >= KEYWORD.len() as u64 && len <= PACKET_LIMIT {
            let mut data = vec![0u8; len as usize];
            file.read_exact(&mut data)?;
            file.seek(SeekFrom::Current(4))?; // CRC
            if let Some(rest) = data.strip_prefix(KEYWORD) {
                // Compression flag and method, then language and translated keyword.
                if rest.len() < 2 || rest[0] != 0 {
                    return Ok(None); // compressed: not worth a zlib dependency
                }
                let mut text = &rest[2..];
                for _ in 0..2 {
                    let Some(nul) = text.iter().position(|b| *b == 0) else { return Ok(None) };
                    text = &text[nul + 1..];
                }
                return Ok(Some(text.to_vec()));
            }
        } else {
            file.seek(SeekFrom::Current(len as i64 + 4))?;
        }
    }
}

fn read_tiff<R: Read + Seek>(file: &mut R, big_endian: bool) -> io::Result<Option<Vec<u8>>> {
    const TAG_XMP: u16 = 700;
    let u16_of = |b: [u8; 2]| if big_endian { u16::from_be_bytes(b) } else { u16::from_le_bytes(b) };
    let u32_of = |b: [u8; 4]| if big_endian { u32::from_be_bytes(b) } else { u32::from_le_bytes(b) };

    file.seek(SeekFrom::Start(4))?;
    let mut offset = [0u8; 4];
    file.read_exact(&mut offset)?;
    file.seek(SeekFrom::Start(u32_of(offset) as u64))?;
    let mut count = [0u8; 2];
    file.read_exact(&mut count)?;
    for _ in 0..u16_of(count) {
        let mut entry = [0u8; 12];
        file.read_exact(&mut entry)?;
        if u16_of([entry[0], entry[1]]) != TAG_XMP {
            continue;
        }
        let len = u32_of([entry[4], entry[5], entry[6], entry[7]]) as u64;
        if len <= 4 || len > PACKET_LIMIT {
            return Ok(None);
        }
        file.seek(SeekFrom::Start(u32_of([entry[8], entry[9], entry[10], entry[11]]) as u64))?;
        let mut packet = vec![0u8; len as usize];
        file.read_exact(&mut packet)?;
        return Ok(Some(packet));
    }
    Ok(None)
}

/// Byte ranges of a JPEG's metadata segments: `(segment start, segment end)`
/// for the XMP APP1 if there is one, and where a new one should go.
struct JpegLayout {
    xmp: Option<(usize, usize)>,
    insert_at: usize,
}

fn jpeg_layout(bytes: &[u8]) -> Result<JpegLayout, String> {
    if !bytes.starts_with(&[0xFF, 0xD8]) {
        return Err("not a JPEG".into());
    }
    let mut i = 2;
    let mut xmp = None;
    let mut insert_at = 2;
    let mut leading = true;
    loop {
        if *bytes.get(i).ok_or("JPEG ended before its image data")? != 0xFF {
            return Err("JPEG structure not understood".into());
        }
        let start = i;
        while bytes.get(i + 1) == Some(&0xFF) {
            i += 1;
        }
        let marker = *bytes.get(i + 1).ok_or("JPEG ended before its image data")?;
        i += 2;
        match marker {
            0xDA => break,
            0xD9 => return Err("JPEG has no image data".into()),
            0x01 | 0xD0..=0xD7 => continue,
            _ => {}
        }
        let len = match bytes.get(i..i + 2) {
            Some(l) => u16::from_be_bytes([l[0], l[1]]) as usize,
            None => return Err("JPEG ended inside a segment".into()),
        };
        if len < 2 || i + len > bytes.len() {
            return Err("JPEG segment length is wrong".into());
        }
        let body = &bytes[i + 2..i + len];
        let is_xmp = marker == 0xE1 && body.starts_with(JPEG_XMP_HEADER);
        if is_xmp && xmp.is_none() {
            xmp = Some((start, i + len));
        }
        // New XMP goes after the JFIF and Exif headers, which readers expect first.
        leading = leading && (marker == 0xE0 || (marker == 0xE1 && !is_xmp));
        i += len;
        if leading {
            insert_at = i;
        }
    }
    Ok(JpegLayout { xmp, insert_at })
}

/// Builds the JPEG with `change` applied, leaving every other byte alone.
fn jpeg_with(bytes: &[u8], change: &Change, seed: &Fields) -> Result<Vec<u8>, String> {
    let layout = jpeg_layout(bytes)?;
    let packet = match layout.xmp {
        Some((start, end)) => {
            // Segment marker (2), length (2), then the header.
            let existing = std::str::from_utf8(&bytes[start + 4 + JPEG_XMP_HEADER.len()..end])
                .map_err(|_| "embedded XMP isn't UTF-8".to_string())?;
            xmp::apply(existing, change)?
        }
        None => xmp::new_packet(&change.applied_to(seed))?,
    };
    if packet.len() > JPEG_XMP_MAX {
        return Err("metadata is too large for a JPEG's XMP segment".into());
    }

    let mut segment = vec![0xFF, 0xE1];
    segment.extend(((2 + JPEG_XMP_HEADER.len() + packet.len()) as u16).to_be_bytes());
    segment.extend(JPEG_XMP_HEADER);
    segment.extend(packet.as_bytes());

    let (start, end) = layout.xmp.unwrap_or((layout.insert_at, layout.insert_at));
    let mut out = Vec::with_capacity(bytes.len() + segment.len());
    out.extend(&bytes[..start]);
    out.extend(&segment);
    out.extend(&bytes[end..]);

    // Prove it: remove the XMP segment from both and they must be identical.
    let after = jpeg_layout(&out)?;
    let (new_start, new_end) = after.xmp.ok_or("XMP segment went missing")?;
    if new_start != start || out[..new_start] != bytes[..start] || out[new_end..] != bytes[end..] {
        return Err("rewrite would have changed image data".into());
    }
    Ok(out)
}

/// Writes `change` into a JPEG's embedded XMP, atomically. `seed` fills a new
/// packet when the file has none.
pub fn write_jpeg(path: &Path, change: &Change, seed: &Fields) -> Result<(), String> {
    let bytes = fs::read(path).map_err(|e| e.to_string())?;
    let out = jpeg_with(&bytes, change, seed)?;
    if out == bytes {
        return Ok(());
    }
    atomic::replace(path, &out).map_err(|e| e.to_string())
}

pub fn is_jpeg(ext: &str) -> bool {
    ext == "jpg" || ext == "jpeg"
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    const PACKET: &str = r#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4" xmp:Label="Select"/></rdf:RDF></x:xmpmeta>"#;

    fn segment(marker: u8, body: &[u8]) -> Vec<u8> {
        let mut s = vec![0xFF, marker];
        s.extend(((body.len() + 2) as u16).to_be_bytes());
        s.extend(body);
        s
    }

    /// SOI, JFIF, Exif, optional XMP, then a stand-in for the image data.
    pub(crate) fn jpeg(xmp: Option<&str>) -> Vec<u8> {
        let mut j = vec![0xFF, 0xD8];
        j.extend(segment(0xE0, b"JFIF\0\x01\x01\0\0\x01\0\x01\0\0"));
        j.extend(segment(0xE1, b"Exif\0\0MM\0*\0\0\0\x08\0\0"));
        if let Some(x) = xmp {
            let mut body = JPEG_XMP_HEADER.to_vec();
            body.extend(x.as_bytes());
            j.extend(segment(0xE1, &body));
        }
        j.extend(segment(0xDB, &[7u8; 65]));
        j.extend([0xFF, 0xDA, 0x00, 0x02]);
        j.extend((0..=255u8).cycle().take(5000).map(|b| if b == 0xFF { 0xFE } else { b }));
        j.extend([0xFF, 0xD9]);
        j
    }

    fn tiff(xmp: &str, big_endian: bool) -> Vec<u8> {
        let (u16b, u32b): (fn(u16) -> [u8; 2], fn(u32) -> [u8; 4]) = if big_endian {
            (u16::to_be_bytes, u32::to_be_bytes)
        } else {
            (u16::to_le_bytes, u32::to_le_bytes)
        };
        let mut t = if big_endian { b"MM\0*".to_vec() } else { b"II*\0".to_vec() };
        t.extend(u32b(8));
        t.extend(u16b(2));
        // Width, then the XMP tag pointing past the IFD.
        t.extend(u16b(256));
        t.extend(u16b(3));
        t.extend(u32b(1));
        t.extend(u32b(100));
        t.extend(u16b(700));
        t.extend(u16b(1));
        t.extend(u32b(xmp.len() as u32));
        t.extend(u32b(8 + 2 + 24 + 4));
        t.extend(u32b(0));
        t.extend(xmp.as_bytes());
        t
    }

    fn png(xmp: &str) -> Vec<u8> {
        let mut p = b"\x89PNG\r\n\x1a\n".to_vec();
        let chunk = |kind: &[u8], data: &[u8]| {
            let mut c = (data.len() as u32).to_be_bytes().to_vec();
            c.extend(kind);
            c.extend(data);
            c.extend([0, 0, 0, 0]);
            c
        };
        p.extend(chunk(b"IHDR", &[0; 13]));
        let mut text = b"XML:com.adobe.xmp\0\0\0\0\0".to_vec();
        text.extend(xmp.as_bytes());
        p.extend(chunk(b"iTXt", &text));
        p.extend(chunk(b"IDAT", &[1; 40]));
        p.extend(chunk(b"IEND", &[]));
        p
    }

    fn read_bytes(name: &str, bytes: &[u8]) -> Result<Option<Fields>, String> {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(name);
        fs::write(&path, bytes).unwrap();
        read_fields(&path)
    }

    #[test]
    fn reads_jpeg_tiff_dng_and_png() {
        let want = (Some(4), Some("Select".to_string()));
        for (name, bytes) in [
            ("a.jpg", jpeg(Some(PACKET))),
            ("a.tif", tiff(PACKET, false)),
            ("a.dng", tiff(PACKET, true)),
            ("a.png", png(PACKET)),
        ] {
            let f = read_bytes(name, &bytes).unwrap().unwrap_or_else(|| panic!("{name}: no XMP"));
            assert_eq!((f.rating, f.label), want, "{name}");
        }
    }

    #[test]
    fn files_without_xmp_or_with_damage_are_handled() {
        assert_eq!(read_bytes("a.jpg", &jpeg(None)).unwrap(), None);
        assert_eq!(read_bytes("a.heic", b"\0\0\0\x18ftypheic").unwrap(), None);
        assert_eq!(read_bytes("a.jpg", b"").unwrap(), None);
        let whole = jpeg(Some(PACKET));
        assert_eq!(read_bytes("a.jpg", &whole[..60]).unwrap(), None, "cut off inside a segment");
        assert_eq!(read_bytes("a.tif", b"II*\0\xFF\xFF\xFF\xFF").unwrap(), None);
        // A packet that's there but broken is an error, not "no metadata".
        assert!(read_bytes("a.jpg", &jpeg(Some("<rdf:RDF"))).is_err());
    }

    /// Everything but the XMP segment.
    fn without_xmp(bytes: &[u8]) -> Vec<u8> {
        let l = jpeg_layout(bytes).unwrap();
        let (s, e) = l.xmp.unwrap_or((0, 0));
        [&bytes[..s], &bytes[e..]].concat()
    }

    #[test]
    fn writing_a_jpeg_keeps_everything_else_byte_identical() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("a.jpg");
        let original = jpeg(Some(PACKET));
        fs::write(&path, &original).unwrap();

        let change = Change { rating: Some(Some(2)), keywords: Some(vec!["Zoë".into()]), ..Default::default() };
        write_jpeg(&path, &change, &Fields::default()).unwrap();

        let written = fs::read(&path).unwrap();
        assert_eq!(without_xmp(&written), without_xmp(&original));
        let f = read_fields(&path).unwrap().unwrap();
        assert_eq!((f.rating, f.label.as_deref(), f.keywords.len()), (Some(2), Some("Select"), 1));
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1, "no temp file left");
    }

    #[test]
    fn a_new_segment_goes_after_exif_and_seeds_from_the_sidecar() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("a.jpg");
        let original = jpeg(None);
        fs::write(&path, &original).unwrap();
        let seed = Fields { keywords: vec!["kept".into()], ..Default::default() };

        write_jpeg(&path, &Change { rating: Some(Some(3)), ..Default::default() }, &seed).unwrap();

        let written = fs::read(&path).unwrap();
        let layout = jpeg_layout(&written).unwrap();
        let (start, end) = layout.xmp.unwrap();
        assert_eq!(start, 2 + 18 + 20, "after JFIF and Exif");
        assert_eq!([&written[..start], &written[end..]].concat(), original);
        let f = read_fields(&path).unwrap().unwrap();
        assert_eq!((f.rating, f.keywords), (Some(3), vec!["kept".to_string()]));
    }

    #[test]
    fn refuses_what_it_cant_write_safely() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("a.jpg");
        let change = Change { rating: Some(Some(3)), ..Default::default() };

        // Broken packet, truncated file, oversized metadata, read-only file.
        let broken = jpeg(Some("<rdf:RDF"));
        fs::write(&path, &broken).unwrap();
        assert!(write_jpeg(&path, &change, &Fields::default()).is_err());
        assert_eq!(fs::read(&path).unwrap(), broken);

        let short = &jpeg(None)[..30];
        fs::write(&path, short).unwrap();
        assert!(write_jpeg(&path, &change, &Fields::default()).is_err());
        assert_eq!(fs::read(&path).unwrap(), short);

        let original = jpeg(Some(PACKET));
        fs::write(&path, &original).unwrap();
        let huge = Change { keywords: Some(vec!["x".repeat(70_000)]), ..Default::default() };
        assert!(write_jpeg(&path, &huge, &Fields::default()).is_err());
        assert_eq!(fs::read(&path).unwrap(), original);

        let mut perms = fs::metadata(&path).unwrap().permissions();
        perms.set_readonly(true);
        fs::set_permissions(&path, perms).unwrap();
        assert!(write_jpeg(&path, &change, &Fields::default()).is_err());
        assert_eq!(fs::read(&path).unwrap(), original);
    }
}
