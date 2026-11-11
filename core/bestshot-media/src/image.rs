//! Orientation-normalised integer geometry; row-wise RGBA processing is lossless.
use crate::{require, Result};
use serde::{Deserialize, Serialize};
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Axis {
    Horizontal,
    Vertical,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AntiCrop {
    pub schema_version: u32,
    pub source_ref: String,
    pub axis: Axis,
    pub remove_start_px: u32,
    pub remove_end_px: u32,
    pub join_mode: String,
    pub blend_width_px: u32,
    pub output_format: String,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Geometry {
    pub width: u32,
    pub height: u32,
    pub seam_px: u32,
}
impl AntiCrop {
    pub fn plan(&self, width: u32, height: u32) -> Result<Geometry> {
        require(
            self.schema_version == 1,
            "Unsupported Anti-Crop version; use version 1.",
        )?;
        require(!self.source_ref.is_empty(), "Choose an image first.")?;
        require(width > 0 && height > 0, "The image has no pixels.")?;
        require(
            self.join_mode == "hard" && self.blend_width_px == 0,
            "Only Hard Join is currently supported.",
        )?;
        require(
            self.output_format == "png",
            "Choose PNG for lossless output.",
        )?;
        let dimension = match self.axis {
            Axis::Horizontal => height,
            Axis::Vertical => width,
        };
        require(self.remove_start_px > 0 && self.remove_start_px < self.remove_end_px && self.remove_end_px < dimension,
            "Start must be greater than 0, end must follow start, and both retained sides must contain pixels.")?;
        let removed = self.remove_end_px - self.remove_start_px;
        Ok(Geometry {
            width: width
                - if self.axis == Axis::Vertical {
                    removed
                } else {
                    0
                },
            height: height
                - if self.axis == Axis::Horizontal {
                    removed
                } else {
                    0
                },
            seam_px: self.remove_start_px,
        })
    }
}

/// Reads/writes tightly packed RGBA rows without changing retained bytes.
/// Input and output must be distinct files. Creates a new output exclusively;
/// removes partial output on error/cancellation. Memory is at most one input row.
pub fn crop_rgba(
    edit: &AntiCrop,
    width: u32,
    height: u32,
    source: &Path,
    destination: &Path,
    cancelled: &AtomicBool,
) -> Result<Geometry> {
    let plan = edit.plan(width, height)?;
    let row_bytes = u64::from(width) * 4;
    // Bound allocations even for malicious dimensions, independent of the decoder.
    require(
        row_bytes <= 64 * 1024 * 1024,
        "Image rows exceed the 64 MB processing limit.",
    )?;
    let mut input = File::open(source)?;
    require(
        input.metadata()?.len() == row_bytes * u64::from(height),
        "Decoded pixel file has an unexpected size.",
    )?;
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(destination)?;
    let result = (|| {
        let mut row = vec![0; row_bytes as usize];
        for y in 0..height {
            require(!cancelled.load(Ordering::Relaxed), "Export cancelled.")?;
            if edit.axis == Axis::Horizontal
                && (edit.remove_start_px..edit.remove_end_px).contains(&y)
            {
                input.seek(SeekFrom::Current(row_bytes as i64))?;
                continue;
            }
            input.read_exact(&mut row)?;
            if edit.axis == Axis::Vertical {
                output.write_all(&row[..edit.remove_start_px as usize * 4])?;
                output.write_all(&row[edit.remove_end_px as usize * 4..])?;
            } else {
                output.write_all(&row)?;
            }
        }
        output.sync_all()?;
        require(!cancelled.load(Ordering::Relaxed), "Export cancelled.")?;
        Ok(plan)
    })();
    drop(output);
    if result.is_err() {
        let _ = std::fs::remove_file(destination);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    fn edit(axis: Axis, start: u32, end: u32) -> AntiCrop {
        AntiCrop {
            schema_version: 1,
            source_ref: "test".into(),
            axis,
            remove_start_px: start,
            remove_end_px: end,
            join_mode: "hard".into(),
            blend_width_px: 0,
            output_format: "png".into(),
        }
    }
    #[test]
    fn dimensions_and_all_small_pixel_orders() {
        let dir = tempfile::tempdir().unwrap();
        // Exhaust every valid band in both axes, including one-pixel retained sides.
        for width in 3..10 {
            for height in 3..10 {
                for axis in [Axis::Horizontal, Axis::Vertical] {
                    let dimension = if axis == Axis::Horizontal {
                        height
                    } else {
                        width
                    };
                    for start in 1..dimension - 1 {
                        for end in start + 1..dimension {
                            let source = dir.path().join("source");
                            let dest = dir.path().join("output");
                            let pixels: Vec<u8> =
                                (0..width * height * 4).map(|n| n as u8).collect();
                            std::fs::write(&source, &pixels).unwrap();
                            let plan = crop_rgba(
                                &edit(axis, start, end),
                                width,
                                height,
                                &source,
                                &dest,
                                &AtomicBool::new(false),
                            )
                            .unwrap();
                            let mut expected = Vec::new();
                            for y in 0..height {
                                for x in 0..width {
                                    let coordinate = if axis == Axis::Horizontal { y } else { x };
                                    if !(start..end).contains(&coordinate) {
                                        let offset = ((y * width + x) * 4) as usize;
                                        expected.extend_from_slice(&pixels[offset..offset + 4]);
                                    }
                                }
                            }
                            assert_eq!(std::fs::read(&dest).unwrap(), expected);
                            assert_eq!(expected.len(), (plan.width * plan.height * 4) as usize);
                            std::fs::remove_file(dest).unwrap();
                        }
                    }
                }
            }
        }
        assert_eq!(
            edit(Axis::Horizontal, 800, 1400)
                .plan(4000, 3000)
                .unwrap()
                .height,
            2400
        );
    }
    #[test]
    fn reject_invalid_and_future_configs() {
        for (start, end) in [(0, 2), (2, 2), (3, 2), (1, 10), (1, 11)] {
            assert!(edit(Axis::Horizontal, start, end).plan(10, 10).is_err());
        }
        let mut e = edit(Axis::Vertical, 1, 2);
        assert_eq!(
            crate::decode::<AntiCrop>(&crate::encode(&e).unwrap()).unwrap(),
            e
        );
        e.schema_version = 2;
        assert!(e.plan(10, 10).is_err());
    }
    #[test]
    fn cancellation_and_existing_output_are_safe() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source");
        let dest = dir.path().join("output");
        std::fs::write(&source, [1; 36]).unwrap();
        let e = edit(Axis::Vertical, 1, 2);
        assert!(crop_rgba(&e, 3, 3, &source, &dest, &AtomicBool::new(true)).is_err());
        assert!(!dest.exists());
        std::fs::write(&dest, b"existing").unwrap();
        assert!(crop_rgba(&e, 3, 3, &source, &dest, &AtomicBool::new(false)).is_err());
        assert_eq!(std::fs::read(dest).unwrap(), b"existing");
        assert_eq!(std::fs::read(source).unwrap(), [1; 36]);
    }
}
