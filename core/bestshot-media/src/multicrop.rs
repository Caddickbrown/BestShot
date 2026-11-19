//! Multi Crop: several new photos out of one image (a scanned page of prints, a
//! contact sheet, a screenshot). Coordinates are upright source pixels. The
//! source staging file is only ever read.
use crate::{require, MediaError, Result};
use serde::{Deserialize, Serialize};
use std::fs::{File, OpenOptions};
use std::io::{BufWriter, Read, Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

pub const MIN_SIDE: u32 = 16;
pub const MAX_SIDE: u32 = 65_500;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SourceRef {
    #[serde(rename = "ref")]
    pub reference: String,
    pub width: u32,
    pub height: u32,
}

/// A box is a rotated rectangle (the common flatbed case) or four corners
/// (a print photographed at an angle). Corners run top-left, top-right,
/// bottom-right, bottom-left of the photo as it will come out (before `turn`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Shape {
    Rect {
        cx: f64,
        cy: f64,
        w: f64,
        h: f64,
        #[serde(default)]
        angle_deg: f64,
    },
    Quad {
        corners: [[f64; 2]; 4],
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CropBox {
    pub id: String,
    #[serde(flatten)]
    pub shape: Shape,
    /// Turn of the output, clockwise: 0, 90, 180 or 270.
    #[serde(default)]
    pub turn: u32,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct Naming {
    /// The source's file name without extension. Empty: no names planned.
    #[serde(default)]
    pub stem: String,
    #[serde(default)]
    pub ext: String,
    /// File names already in the destination folder.
    #[serde(default)]
    pub existing: Vec<String>,
    #[serde(default = "one")]
    pub start: u32,
}
fn one() -> u32 {
    1
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MultiCrop {
    pub schema_version: u32,
    pub source: SourceRef,
    pub boxes: Vec<CropBox>,
    /// Box ids in output order. Empty: reading order.
    #[serde(default)]
    pub order: Vec<String>,
    #[serde(default)]
    pub trim_px: u32,
    #[serde(default)]
    pub naming: Naming,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlannedBox {
    pub id: String,
    /// 1-based position in the output order.
    pub number: u32,
    pub name: String,
    /// Output size after trim and turn.
    pub width: u32,
    pub height: u32,
    /// Axis-aligned with whole-pixel edges inside the image: copied byte for byte.
    pub exact: bool,
    /// The trimmed source quad (TL, TR, BR, BL before the turn).
    pub corners: [[f64; 2]; 4],
    pub turn: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MultiCropPlan {
    pub boxes: Vec<PlannedBox>,
}

impl Shape {
    pub fn corners(&self) -> [[f64; 2]; 4] {
        match *self {
            Shape::Quad { corners } => corners,
            Shape::Rect { cx, cy, w, h, angle_deg } => {
                let (s, c) = angle_deg.to_radians().sin_cos();
                let pt = |x: f64, y: f64| [cx + x * c - y * s, cy + x * s + y * c];
                [pt(-w / 2.0, -h / 2.0), pt(w / 2.0, -h / 2.0), pt(w / 2.0, h / 2.0), pt(-w / 2.0, h / 2.0)]
            }
        }
    }
    /// Untrimmed output size before the turn.
    pub fn size(&self) -> (f64, f64) {
        match *self {
            Shape::Rect { w, h, .. } => (w.round(), h.round()),
            Shape::Quad { corners: q } => {
                let d = |a: [f64; 2], b: [f64; 2]| ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2)).sqrt();
                (((d(q[0], q[1]) + d(q[3], q[2])) / 2.0).round(), ((d(q[0], q[3]) + d(q[1], q[2])) / 2.0).round())
            }
        }
    }
}

fn is_whole(v: f64) -> bool {
    (v - v.round()).abs() < 1e-6
}

impl MultiCrop {
    pub fn validate(&self) -> Result<()> {
        require(self.schema_version == 1, "Unsupported Multi Crop version; use version 1.")?;
        require(self.source.width > 0 && self.source.height > 0, "The image has no pixels.")?;
        require(!self.boxes.is_empty(), "Draw a box, or press F to find photos.")?;
        require(self.boxes.len() <= 200, "Up to 200 boxes at once.")?;
        let mut ids: Vec<&str> = self.boxes.iter().map(|b| b.id.as_str()).collect();
        ids.sort();
        ids.dedup();
        require(ids.len() == self.boxes.len(), "Each box needs its own id.")?;
        for b in &self.boxes {
            require(matches!(b.turn, 0 | 90 | 180 | 270), "Turn a box by 90° steps only.")?;
            let finite = b.shape.corners().iter().all(|p| p[0].is_finite() && p[1].is_finite());
            require(finite, "A box has an invalid corner.")?;
        }
        Ok(())
    }

    /// Box ids in output order: `order` when it names every box once, else reading order.
    pub fn output_order(&self) -> Vec<String> {
        let mut given = self.order.clone();
        given.sort();
        let mut all: Vec<String> = self.boxes.iter().map(|b| b.id.clone()).collect();
        all.sort();
        if !self.order.is_empty() && given == all {
            return self.order.clone();
        }
        let centres: Vec<([f64; 2], f64)> = self
            .boxes
            .iter()
            .map(|b| {
                let q = b.shape.corners();
                let ys = q.iter().map(|p| p[1]);
                let h = ys.clone().fold(f64::MIN, f64::max) - ys.fold(f64::MAX, f64::min);
                ([q.iter().map(|p| p[0]).sum::<f64>() / 4.0, q.iter().map(|p| p[1]).sum::<f64>() / 4.0], h)
            })
            .collect();
        reading_order(&centres).into_iter().map(|i| self.boxes[i].id.clone()).collect()
    }

    pub fn plan(&self) -> Result<MultiCropPlan> {
        self.validate()?;
        let order = self.output_order();
        let names = if self.naming.stem.is_empty() {
            vec![String::new(); order.len()]
        } else {
            crop_names(&self.naming.stem, &self.naming.ext, order.len() as u32, self.naming.start, &self.naming.existing)
        };
        let t = f64::from(self.trim_px);
        let mut boxes = Vec::new();
        for (i, id) in order.iter().enumerate() {
            let b = self.boxes.iter().find(|b| &b.id == id).expect("order names boxes");
            let (w0, h0) = b.shape.size();
            let (w, h) = (w0 - 2.0 * t, h0 - 2.0 * t);
            require(
                w >= f64::from(MIN_SIDE) && h >= f64::from(MIN_SIDE),
                &format!("Box {} is too small: at least {MIN_SIDE} px a side after trim.", i + 1),
            )?;
            require(w <= f64::from(MAX_SIDE) && h <= f64::from(MAX_SIDE), "A box is too big to save.")?;
            let quad = b.shape.corners();
            let hm = Homography::square_to_quad(quad);
            let map = |u: f64, v: f64| hm.map(u, v);
            // The trimmed quad, through the same mapping the pixels use.
            let corners = [
                map(t / w0, t / h0),
                map((w0 - t) / w0, t / h0),
                map((w0 - t) / w0, (h0 - t) / h0),
                map(t / w0, (h0 - t) / h0),
            ];
            let exact = match b.shape {
                Shape::Rect { cx, cy, w: bw, h: bh, angle_deg } => {
                    let (x0, y0) = (cx - bw / 2.0, cy - bh / 2.0);
                    angle_deg == 0.0
                        && is_whole(x0)
                        && is_whole(y0)
                        && is_whole(bw)
                        && is_whole(bh)
                        && x0 >= -1e-6
                        && y0 >= -1e-6
                        && x0 + bw <= f64::from(self.source.width) + 1e-6
                        && y0 + bh <= f64::from(self.source.height) + 1e-6
                }
                Shape::Quad { .. } => false,
            };
            let (ow, oh) = (w as u32, h as u32);
            let (ow, oh) = if b.turn % 180 == 90 { (oh, ow) } else { (ow, oh) };
            boxes.push(PlannedBox {
                id: id.clone(),
                number: i as u32 + 1,
                name: names[i].clone(),
                width: ow,
                height: oh,
                exact,
                corners,
                turn: b.turn,
            });
        }
        Ok(MultiCropPlan { boxes })
    }
}

/// Indices in reading order: rows top to bottom (a row holds centres within half
/// the median height of its first box), left to right within a row.
pub fn reading_order(centres: &[([f64; 2], f64)]) -> Vec<usize> {
    let mut heights: Vec<f64> = centres.iter().map(|c| c.1).collect();
    heights.sort_by(|a, b| a.total_cmp(b));
    let tolerance = heights.get(heights.len() / 2).copied().unwrap_or(0.0) / 2.0;
    let mut by_y: Vec<usize> = (0..centres.len()).collect();
    by_y.sort_by(|&a, &b| centres[a].0[1].total_cmp(&centres[b].0[1]).then(centres[a].0[0].total_cmp(&centres[b].0[0])));
    let mut out = Vec::new();
    let mut row: Vec<usize> = Vec::new();
    let mut row_y = f64::NAN;
    for i in by_y {
        let y = centres[i].0[1];
        if row.is_empty() || y - row_y <= tolerance {
            if row.is_empty() {
                row_y = y;
            }
            row.push(i);
        } else {
            row.sort_by(|&a, &b| centres[a].0[0].total_cmp(&centres[b].0[0]));
            out.append(&mut row);
            row_y = y;
            row.push(i);
        }
    }
    row.sort_by(|&a, &b| centres[a].0[0].total_cmp(&centres[b].0[0]));
    out.append(&mut row);
    out
}

/// `{stem}-{n}`, zero-padded to the width of the last number when there are 10
/// or more. A name whose stem is already used by any file in the folder (any
/// extension, any case: a sidecar or a different format would pair with it)
/// becomes `{stem}-{n}-2`, `-3`… The others keep their numbers.
pub fn crop_names(stem: &str, ext: &str, count: u32, start: u32, existing: &[String]) -> Vec<String> {
    let last = start + count.saturating_sub(1);
    let width = if count >= 10 { last.to_string().len() } else { 1 };
    let mut taken: Vec<String> = existing.iter().map(|n| stem_of(n).to_lowercase()).collect();
    (0..count)
        .map(|i| {
            let base = format!("{stem}-{:0width$}", start + i);
            let name = free_stem(&base, &taken);
            taken.push(name.to_lowercase());
            if ext.is_empty() { name } else { format!("{name}.{ext}") }
        })
        .collect()
}

/// `{stem}-glued`, then `{stem}-glued-2`… on the same collision rule.
pub fn glue_name(stem: &str, ext: &str, existing: &[String]) -> String {
    let taken: Vec<String> = existing.iter().map(|n| stem_of(n).to_lowercase()).collect();
    let name = free_stem(&format!("{stem}-glued"), &taken);
    if ext.is_empty() { name } else { format!("{name}.{ext}") }
}

fn stem_of(name: &str) -> &str {
    match name.rfind('.') {
        Some(i) if i > 0 => &name[..i],
        _ => name,
    }
}

fn free_stem(base: &str, taken: &[String]) -> String {
    if !taken.contains(&base.to_lowercase()) {
        return base.to_string();
    }
    (2..)
        .map(|n| format!("{base}-{n}"))
        .find(|c| !taken.contains(&c.to_lowercase()))
        .expect("some suffix is free")
}

// ---------------------------------------------------------------------------
// Detection tidy

/// Vision's quads (in upright source pixels, any corner order) become boxes:
/// near-duplicates merged, nested frames dropped, a page around several
/// photos dropped, near-rectangles made rotated rectangles, reading order.
pub fn tidy_boxes(quads: &[[[f64; 2]; 4]], width: u32, height: u32) -> Vec<CropBox> {
    let image_area = f64::from(width) * f64::from(height);
    let mut items: Vec<([[f64; 2]; 4], Aabb)> = quads
        .iter()
        .map(|q| order_corners(*q))
        .map(|q| (q, Aabb::of(&q)))
        .filter(|(q, a)| polygon_area(q) > 64.0 && a.area() < image_area * 0.98)
        .collect();
    // Largest first, so duplicates and nesting keep the outer box.
    items.sort_by(|a, b| b.1.area().total_cmp(&a.1.area()));
    let mut kept: Vec<([[f64; 2]; 4], Aabb)> = Vec::new();
    for (q, a) in items {
        if kept.iter().any(|(_, k)| k.iou(&a) > 0.85) {
            continue;
        }
        kept.push((q, a));
    }
    // A box holding two or more others is a page: drop it. A box inside one
    // other box is that photo's own border: drop the inner one.
    let contains = |outer: &Aabb, inner: &Aabb| inner.intersection(outer) >= 0.9 * inner.area();
    let pages: Vec<usize> = (0..kept.len())
        .filter(|&i| (0..kept.len()).filter(|&j| j != i && contains(&kept[i].1, &kept[j].1)).count() >= 2)
        .collect();
    let survivors: Vec<usize> = (0..kept.len()).filter(|i| !pages.contains(i)).collect();
    let survivors: Vec<usize> = survivors
        .iter()
        .copied()
        .filter(|&j| !survivors.iter().any(|&i| i != j && kept[i].1.area() > kept[j].1.area() && contains(&kept[i].1, &kept[j].1)))
        .collect();
    let shapes: Vec<Shape> = survivors.iter().map(|&i| rectify(kept[i].0)).collect();
    let centres: Vec<([f64; 2], f64)> = shapes
        .iter()
        .map(|s| {
            let q = s.corners();
            let a = Aabb::of(&q);
            ([(a.x0 + a.x1) / 2.0, (a.y0 + a.y1) / 2.0], a.y1 - a.y0)
        })
        .collect();
    reading_order(&centres)
        .into_iter()
        .enumerate()
        .map(|(n, i)| CropBox { id: format!("b{}", n + 1), shape: shapes[i].clone(), turn: 0 })
        .collect()
}

/// Corners clockwise from the top-left (smallest x + y), y down.
pub fn order_corners(q: [[f64; 2]; 4]) -> [[f64; 2]; 4] {
    let c = [q.iter().map(|p| p[0]).sum::<f64>() / 4.0, q.iter().map(|p| p[1]).sum::<f64>() / 4.0];
    let mut v = q.to_vec();
    v.sort_by(|a, b| (a[1] - c[1]).atan2(a[0] - c[0]).total_cmp(&(b[1] - c[1]).atan2(b[0] - c[0])));
    // atan2 with y down runs clockwise on screen; start at the top-left.
    let start = (0..4).min_by(|&a, &b| (v[a][0] + v[a][1]).total_cmp(&(v[b][0] + v[b][1]))).unwrap();
    [v[start], v[(start + 1) % 4], v[(start + 2) % 4], v[(start + 3) % 4]]
}

/// A quad whose corners are all within 3° of square becomes a rotated rect.
pub fn rectify(q: [[f64; 2]; 4]) -> Shape {
    let angle_at = |i: usize| {
        let (p, a, b) = (q[i], q[(i + 3) % 4], q[(i + 1) % 4]);
        let (u, v) = ([a[0] - p[0], a[1] - p[1]], [b[0] - p[0], b[1] - p[1]]);
        let cos = (u[0] * v[0] + u[1] * v[1]) / ((u[0].hypot(u[1])) * (v[0].hypot(v[1]))).max(1e-9);
        cos.clamp(-1.0, 1.0).acos().to_degrees()
    };
    if !(0..4).all(|i| (angle_at(i) - 90.0).abs() <= 3.0) {
        return Shape::Quad { corners: q };
    }
    let d = |a: [f64; 2], b: [f64; 2]| (b[0] - a[0]).hypot(b[1] - a[1]);
    let mut w = (d(q[0], q[1]) + d(q[3], q[2])) / 2.0;
    let mut h = (d(q[0], q[3]) + d(q[1], q[2])) / 2.0;
    let top = (q[1][1] - q[0][1]).atan2(q[1][0] - q[0][0]);
    let bottom = (q[2][1] - q[3][1]).atan2(q[2][0] - q[3][0]);
    let mut angle = ((top + bottom) / 2.0).to_degrees();
    if angle > 45.0 {
        angle -= 90.0;
        std::mem::swap(&mut w, &mut h);
    } else if angle < -45.0 {
        angle += 90.0;
        std::mem::swap(&mut w, &mut h);
    }
    let cx = q.iter().map(|p| p[0]).sum::<f64>() / 4.0;
    let cy = q.iter().map(|p| p[1]).sum::<f64>() / 4.0;
    // Under a tenth of a degree is a straight scan: keep it exact.
    let angle = if angle.abs() < 0.1 { 0.0 } else { (angle * 10.0).round() / 10.0 };
    Shape::Rect { cx, cy, w: w.round(), h: h.round(), angle_deg: angle }
}

fn polygon_area(q: &[[f64; 2]; 4]) -> f64 {
    let mut s = 0.0;
    for i in 0..4 {
        let (a, b) = (q[i], q[(i + 1) % 4]);
        s += a[0] * b[1] - b[0] * a[1];
    }
    s.abs() / 2.0
}

#[derive(Debug, Clone, Copy)]
struct Aabb {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
}
impl Aabb {
    fn of(q: &[[f64; 2]; 4]) -> Self {
        let xs = q.iter().map(|p| p[0]);
        let ys = q.iter().map(|p| p[1]);
        Self {
            x0: xs.clone().fold(f64::MAX, f64::min),
            x1: xs.fold(f64::MIN, f64::max),
            y0: ys.clone().fold(f64::MAX, f64::min),
            y1: ys.fold(f64::MIN, f64::max),
        }
    }
    fn area(&self) -> f64 {
        (self.x1 - self.x0).max(0.0) * (self.y1 - self.y0).max(0.0)
    }
    fn intersection(&self, o: &Aabb) -> f64 {
        let w = self.x1.min(o.x1) - self.x0.max(o.x0);
        let h = self.y1.min(o.y1) - self.y0.max(o.y0);
        w.max(0.0) * h.max(0.0)
    }
    fn iou(&self, o: &Aabb) -> f64 {
        let i = self.intersection(o);
        i / (self.area() + o.area() - i).max(1e-9)
    }
}

// ---------------------------------------------------------------------------
// Pixels

/// Maps the unit square (u right, v down) onto a quad TL, TR, BR, BL.
#[derive(Debug, Clone, Copy)]
pub struct Homography([f64; 8]);
impl Homography {
    pub fn square_to_quad(q: [[f64; 2]; 4]) -> Self {
        let ([x0, y0], [x1, y1], [x2, y2], [x3, y3]) = (q[0], q[1], q[2], q[3]);
        let (dx1, dx2, dx3) = (x1 - x2, x3 - x2, x0 - x1 + x2 - x3);
        let (dy1, dy2, dy3) = (y1 - y2, y3 - y2, y0 - y1 + y2 - y3);
        let (g, h) = if dx3.abs() < 1e-12 && dy3.abs() < 1e-12 {
            (0.0, 0.0)
        } else {
            let det = dx1 * dy2 - dx2 * dy1;
            if det.abs() < 1e-12 {
                (0.0, 0.0)
            } else {
                ((dx3 * dy2 - dx2 * dy3) / det, (dx1 * dy3 - dx3 * dy1) / det)
            }
        };
        Self([x1 - x0 + g * x1, x3 - x0 + h * x3, x0, y1 - y0 + g * y1, y3 - y0 + h * y3, y0, g, h])
    }
    pub fn map(&self, u: f64, v: f64) -> [f64; 2] {
        let [a, b, c, d, e, f, g, h] = self.0;
        let w = g * u + h * v + 1.0;
        [(a * u + b * v + c) / w, (d * u + e * v + f) / w]
    }
}

fn catmull_rom(t: f64) -> [f64; 4] {
    let (t2, t3) = (t * t, t * t * t);
    [
        -0.5 * t3 + t2 - 0.5 * t,
        1.5 * t3 - 2.5 * t2 + 1.0,
        -1.5 * t3 + 2.0 * t2 + 0.5 * t,
        0.5 * t3 - 0.5 * t2,
    ]
}

/// Source rows `y0..y0 + rows` of an RGBA image, held in memory.
struct Band {
    width: usize,
    height: usize,
    y0: usize,
    pixels: Vec<u8>,
}
impl Band {
    fn px(&self, x: isize, y: isize) -> &[u8] {
        let x = x.clamp(0, self.width as isize - 1) as usize;
        let y = (y.clamp(0, self.height as isize - 1) as usize).clamp(self.y0, self.y0 + self.pixels.len() / (self.width * 4) - 1);
        let o = ((y - self.y0) * self.width + x) * 4;
        &self.pixels[o..o + 4]
    }
    /// Bicubic (Catmull-Rom) at a source point in pixel units (centres at +0.5).
    fn sample(&self, x: f64, y: f64, out: &mut [u8]) {
        let (fx, fy) = (x - 0.5, y - 0.5);
        let (ix, iy) = (fx.floor(), fy.floor());
        let (wx, wy) = (catmull_rom(fx - ix), catmull_rom(fy - iy));
        let (ix, iy) = (ix as isize, iy as isize);
        let mut acc = [0.0f64; 4];
        for (j, wyj) in wy.iter().enumerate() {
            if *wyj == 0.0 {
                continue;
            }
            for (i, wxi) in wx.iter().enumerate() {
                if *wxi == 0.0 {
                    continue;
                }
                let p = self.px(ix + i as isize - 1, iy + j as isize - 1);
                let w = wxi * wyj;
                for c in 0..4 {
                    acc[c] += w * f64::from(p[c]);
                }
            }
        }
        // Premultiplied: colour never exceeds alpha.
        let a = acc[3].round().clamp(0.0, 255.0);
        out[3] = a as u8;
        for c in 0..3 {
            out[c] = acc[c].round().clamp(0.0, a) as u8;
        }
    }
}

/// Writes box `box_id` as tightly packed RGBA rows (width × height from the
/// plan) to a new file at `destination`. Exact boxes are copied byte for byte;
/// others are sampled bicubically through the box's perspective map. Reads only
/// the source rows the box covers. Removes the output on error or cancel.
pub fn extract_rgba(
    edit: &MultiCrop,
    box_id: &str,
    source: &Path,
    destination: &Path,
    cancelled: &AtomicBool,
) -> Result<PlannedBox> {
    let plan = edit.plan()?;
    let planned = plan
        .boxes
        .iter()
        .find(|b| b.id == box_id)
        .cloned()
        .ok_or_else(|| MediaError(format!("No box called {box_id}.")))?;
    let (width, height) = (edit.source.width as usize, edit.source.height as usize);
    let row_bytes = width as u64 * 4;
    require(row_bytes <= 256 * 1024 * 1024, "Image rows exceed the processing limit.")?;
    let mut input = File::open(source)?;
    require(input.metadata()?.len() == row_bytes * height as u64, "Decoded pixel file has an unexpected size.")?;
    let b = edit.boxes.iter().find(|b| b.id == box_id).expect("planned");
    let (w0, h0) = b.shape.size();
    let t = f64::from(edit.trim_px);
    let hm = Homography::square_to_quad(b.shape.corners());
    // Pre-turn size.
    let (pw, ph) = if planned.turn % 180 == 90 { (planned.height, planned.width) } else { (planned.width, planned.height) };
    let ys = planned.corners.iter().map(|p| p[1]);
    let lo = (ys.clone().fold(f64::MAX, f64::min).floor() as isize - 3).clamp(0, height as isize - 1) as usize;
    let hi = (ys.fold(f64::MIN, f64::max).ceil() as isize + 3).clamp(0, height as isize - 1) as usize;
    let rows = hi - lo + 1;
    require((rows as u64) * row_bytes <= 1024 * 1024 * 1024, "This box covers too much of the image to process.")?;
    let output = OpenOptions::new().write(true).create_new(true).open(destination)?;
    let result = (|| {
        input.seek(SeekFrom::Start(lo as u64 * row_bytes))?;
        let mut pixels = vec![0u8; rows * width * 4];
        input.read_exact(&mut pixels)?;
        let band = Band { width, height, y0: lo, pixels };
        let mut writer = BufWriter::new(&output);
        let (fw, fh) = (planned.width as usize, planned.height as usize);
        let mut row = vec![0u8; fw * 4];
        let (pw, ph) = (pw as usize, ph as usize);
        let (x0, y0) = if planned.exact {
            let q = planned.corners[0];
            (q[0].round() as isize, q[1].round() as isize)
        } else {
            (0, 0)
        };
        for fy in 0..fh {
            require(!cancelled.load(Ordering::Relaxed), "Export cancelled.")?;
            for fx in 0..fw {
                let (u, v) = match planned.turn {
                    90 => (fy, ph - 1 - fx),
                    180 => (pw - 1 - fx, ph - 1 - fy),
                    270 => (pw - 1 - fy, fx),
                    _ => (fx, fy),
                };
                let out = &mut row[fx * 4..fx * 4 + 4];
                if planned.exact {
                    out.copy_from_slice(band.px(x0 + u as isize, y0 + v as isize));
                } else {
                    let p = hm.map((u as f64 + t + 0.5) / w0, (v as f64 + t + 0.5) / h0);
                    band.sample(p[0], p[1], out);
                }
            }
            writer.write_all(&row)?;
        }
        writer.flush()?;
        drop(writer);
        output.sync_all()?;
        require(!cancelled.load(Ordering::Relaxed), "Export cancelled.")?;
        Ok(planned.clone())
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

    fn rect(id: &str, cx: f64, cy: f64, w: f64, h: f64, angle: f64, turn: u32) -> CropBox {
        CropBox { id: id.into(), shape: Shape::Rect { cx, cy, w, h, angle_deg: angle }, turn }
    }
    fn edit(width: u32, height: u32, boxes: Vec<CropBox>) -> MultiCrop {
        MultiCrop {
            schema_version: 1,
            source: SourceRef { reference: "scan.tif".into(), width, height },
            boxes,
            order: vec![],
            trim_px: 0,
            naming: Naming::default(),
        }
    }
    fn image(width: u32, height: u32) -> Vec<u8> {
        (0..width * height).flat_map(|i| [(i % 251) as u8, (i / 7 % 253) as u8, (i * 3 % 241) as u8, 255]).collect()
    }
    fn run(e: &MultiCrop, id: &str, pixels: &[u8]) -> (PlannedBox, Vec<u8>) {
        let dir = tempfile::tempdir().unwrap();
        let (s, d) = (dir.path().join("s"), dir.path().join("d"));
        std::fs::write(&s, pixels).unwrap();
        let p = extract_rgba(e, id, &s, &d, &AtomicBool::new(false)).unwrap();
        assert_eq!(std::fs::read(&s).unwrap(), pixels, "the source is never written");
        (p, std::fs::read(&d).unwrap())
    }

    #[test]
    fn exact_copies_are_byte_identical_with_every_turn() {
        let (w, h) = (40u32, 30u32);
        let pixels = image(w, h);
        let at = |x: usize, y: usize| &pixels[(y * w as usize + x) * 4..(y * w as usize + x) * 4 + 4];
        for trim in [0u32, 2] {
            for turn in [0, 90, 180, 270] {
                // x 3..27 (24 wide), y 5..25 (20 tall)
                let mut e = edit(w, h, vec![rect("a", 15.0, 15.0, 24.0, 20.0, 0.0, turn)]);
                e.trim_px = trim;
                let (p, out) = run(&e, "a", &pixels);
                assert!(p.exact);
                let (pw, ph) = (24 - 2 * trim as usize, 20 - 2 * trim as usize);
                let (fw, fh) = if turn % 180 == 90 { (ph, pw) } else { (pw, ph) };
                assert_eq!((p.width as usize, p.height as usize), (fw, fh));
                for fy in 0..fh {
                    for fx in 0..fw {
                        let (u, v) = match turn {
                            90 => (fy, ph - 1 - fx),
                            180 => (pw - 1 - fx, ph - 1 - fy),
                            270 => (pw - 1 - fy, fx),
                            _ => (fx, fy),
                        };
                        let o = (fy * fw + fx) * 4;
                        assert_eq!(&out[o..o + 4], at(3 + trim as usize + u, 5 + trim as usize + v), "turn {turn} at {fx},{fy}");
                    }
                }
            }
        }
    }

    #[test]
    fn exhaustive_small_exact_boxes() {
        let (w, h) = (7u32, 6u32);
        let pixels = image(w, h);
        for x0 in 0..w {
            for y0 in 0..h {
                for bw in 1..=(w - x0) {
                    for bh in 1..=(h - y0) {
                        let b = rect("a", f64::from(x0) + f64::from(bw) / 2.0, f64::from(y0) + f64::from(bh) / 2.0, f64::from(bw), f64::from(bh), 0.0, 0);
                        let e = edit(w, h, vec![b.clone()]);
                        // Under 16 px is refused; check the copy through the band directly.
                        assert!(e.plan().is_err());
                        let band = Band { width: w as usize, height: h as usize, y0: 0, pixels: pixels.clone() };
                        let mut out = [0u8; 4];
                        // Bicubic at a pixel centre is that pixel exactly.
                        band.sample(f64::from(x0) + 0.5, f64::from(y0) + 0.5, &mut out);
                        let o = ((y0 * w + x0) * 4) as usize;
                        assert_eq!(&out, &pixels[o..o + 4]);
                    }
                }
            }
        }
    }

    #[test]
    fn rotated_box_samples_inside_and_is_not_exact() {
        let (w, h) = (80u32, 80u32);
        // A flat grey image: any warp of it is the same grey.
        let pixels: Vec<u8> = std::iter::repeat([90u8, 120, 150, 255]).take((w * h) as usize).flatten().collect();
        let e = edit(w, h, vec![rect("a", 40.0, 40.0, 30.0, 20.0, 12.5, 90)]);
        let (p, out) = run(&e, "a", &pixels);
        assert!(!p.exact);
        assert_eq!((p.width, p.height), (20, 30));
        assert!(out.chunks(4).all(|px| px == [90, 120, 150, 255]));
    }

    #[test]
    fn perspective_quad_recovers_a_checkerboard() {
        // A 64 px checkerboard of 16 px squares, drawn into a known perspective
        // by the inverse map, comes back square within a pixel.
        let (w, h) = (200u32, 160u32);
        let quad = [[30.0, 20.0], [170.0, 35.0], [180.0, 140.0], [20.0, 130.0]];
        // Render: for each source pixel, find (u,v) by Newton-free brute force via the inverse homography.
        let inv = invert(quad);
        let mut pixels = vec![0u8; (w * h * 4) as usize];
        for y in 0..h {
            for x in 0..w {
                let [u, v] = inv(f64::from(x) + 0.5, f64::from(y) + 0.5);
                let on = if (0.0..1.0).contains(&u) && (0.0..1.0).contains(&v) {
                    let (cx, cy) = ((u * 64.0 / 16.0) as i32, (v * 64.0 / 16.0) as i32);
                    (cx + cy) % 2 == 0
                } else {
                    false
                };
                let o = ((y * w + x) * 4) as usize;
                pixels[o..o + 4].copy_from_slice(if on { &[255, 255, 255, 255] } else { &[0, 0, 0, 255] });
            }
        }
        let e = edit(w, h, vec![CropBox { id: "q".into(), shape: Shape::Quad { corners: quad }, turn: 0 }]);
        let (p, out) = run(&e, "q", &pixels);
        let (pw, ph) = (p.width as usize, p.height as usize);
        // Sample the centre of each of the 4×4 squares, scaled to the output.
        let mut wrong = 0;
        for sy in 0..4 {
            for sx in 0..4 {
                let x = ((sx as f64 + 0.5) / 4.0 * pw as f64) as usize;
                let y = ((sy as f64 + 0.5) / 4.0 * ph as f64) as usize;
                let v = out[(y * pw + x) * 4];
                let expect = if (sx + sy) % 2 == 0 { 255 } else { 0 };
                if (i32::from(v) - expect).abs() > 40 {
                    wrong += 1;
                }
            }
        }
        assert_eq!(wrong, 0);
        // Edges of squares land within a pixel: column 1/4 of the way across changes colour there.
        let row = ph / 8;
        let edge = (0..pw - 1).find(|&x| (out[(row * pw + x) * 4] > 127) != (out[(row * pw + x + 1) * 4] > 127)).unwrap();
        assert!((edge as f64 + 1.0 - pw as f64 / 4.0).abs() <= 1.5, "edge at {edge} of {pw}");
    }

    fn invert(q: [[f64; 2]; 4]) -> impl Fn(f64, f64) -> [f64; 2] {
        let h = Homography::square_to_quad(q).0;
        let m = [[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], 1.0]];
        let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
        let inv = [
            [(m[1][1] * m[2][2] - m[1][2] * m[2][1]) / det, (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / det, (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / det],
            [(m[1][2] * m[2][0] - m[1][0] * m[2][2]) / det, (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / det, (m[0][2] * m[1][0] - m[0][0] * m[1][2]) / det],
            [(m[1][0] * m[2][1] - m[1][1] * m[2][0]) / det, (m[0][1] * m[2][0] - m[0][0] * m[2][1]) / det, (m[0][0] * m[1][1] - m[0][1] * m[1][0]) / det],
        ];
        move |x, y| {
            let w = inv[2][0] * x + inv[2][1] * y + inv[2][2];
            [(inv[0][0] * x + inv[0][1] * y + inv[0][2]) / w, (inv[1][0] * x + inv[1][1] * y + inv[1][2]) / w]
        }
    }

    #[test]
    fn sizes_trim_minimum_and_validation() {
        let mut e = edit(1000, 800, vec![rect("a", 500.0, 400.0, 300.0, 200.0, 3.0, 0)]);
        e.trim_px = 4;
        let p = e.plan().unwrap();
        assert_eq!((p.boxes[0].width, p.boxes[0].height), (292, 192));
        e.trim_px = 95;
        assert!(e.plan().is_err(), "under 16 px after trim");
        e.trim_px = 0;
        e.boxes[0].turn = 45;
        assert!(e.plan().is_err());
        e.boxes[0].turn = 0;
        e.boxes.push(e.boxes[0].clone());
        assert!(e.plan().is_err(), "duplicate ids");
        let q = Shape::Quad { corners: [[0.0, 0.0], [100.0, 0.0], [110.0, 50.0], [-10.0, 50.0]] };
        assert_eq!(q.size(), (110.0, 51.0));
        let mut v2 = edit(10, 10, vec![rect("a", 5.0, 5.0, 4.0, 4.0, 0.0, 0)]);
        v2.schema_version = 2;
        assert!(v2.plan().is_err());
        assert!(edit(100, 100, vec![]).plan().is_err());
    }

    #[test]
    fn reading_order_of_uneven_rows() {
        // Two rows; the second row's boxes sit a little higher or lower.
        let e = edit(
            1000,
            1000,
            vec![
                rect("d", 700.0, 640.0, 200.0, 200.0, 0.0, 0),
                rect("a", 150.0, 200.0, 200.0, 200.0, 0.0, 0),
                rect("c", 150.0, 610.0, 200.0, 200.0, 0.0, 0),
                rect("b", 700.0, 230.0, 200.0, 200.0, 0.0, 0),
                rect("e", 400.0, 590.0, 200.0, 200.0, 0.0, 0),
            ],
        );
        assert_eq!(e.output_order(), ["a", "b", "c", "e", "d"]);
        let mut given = e.clone();
        given.order = vec!["d".into(), "c".into(), "b".into(), "a".into(), "e".into()];
        assert_eq!(given.output_order()[0], "d");
        given.order.pop();
        assert_eq!(given.output_order()[0], "a", "an incomplete order falls back");
    }

    #[test]
    fn names_pad_and_avoid_collisions() {
        assert_eq!(crop_names("Scan_004", "jpg", 3, 1, &[]), ["Scan_004-1.jpg", "Scan_004-2.jpg", "Scan_004-3.jpg"]);
        let twelve = crop_names("S", "jpg", 12, 1, &[]);
        assert_eq!((twelve[0].as_str(), twelve[11].as_str()), ("S-01.jpg", "S-12.jpg"));
        let existing = vec!["Scan_004.tif".to_string(), "scan_004-1.JPG".to_string(), "Scan_004-3.xmp".to_string()];
        assert_eq!(
            crop_names("Scan_004", "jpg", 3, 1, &existing),
            ["Scan_004-1-2.jpg", "Scan_004-2.jpg", "Scan_004-3-2.jpg"]
        );
        assert_eq!(glue_name("IMG_0012", "jpg", &[]), "IMG_0012-glued.jpg");
        assert_eq!(glue_name("IMG_0012", "jpg", &["IMG_0012-glued.jpg".into(), "IMG_0012-glued-2.heic".into()]), "IMG_0012-glued-3.jpg");
        let mut e = edit(1000, 1000, vec![rect("a", 100.0, 100.0, 100.0, 100.0, 0.0, 0)]);
        e.naming = Naming { stem: "Scan".into(), ext: "jpg".into(), existing: vec![], start: 1 };
        assert_eq!(e.plan().unwrap().boxes[0].name, "Scan-1.jpg");
    }

    #[test]
    fn tidy_merges_drops_nested_and_pages_and_rectifies() {
        let sq = |x: f64, y: f64, w: f64, h: f64| [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];
        let rot = |cx: f64, cy: f64, w: f64, h: f64, deg: f64| Shape::Rect { cx, cy, w, h, angle_deg: deg }.corners();
        let quads = vec![
            sq(600.0, 100.0, 300.0, 200.0),
            sq(50.0, 50.0, 900.0, 700.0), // the page around everything
            sq(100.0, 100.0, 300.0, 200.0),
            sq(102.0, 101.0, 298.0, 199.0), // duplicate
            sq(130.0, 120.0, 240.0, 160.0), // the photo's own inner frame
            rot(250.0, 500.0, 300.0, 200.0, 2.0),
            [[600.0, 400.0], [900.0, 420.0], [870.0, 650.0], [640.0, 600.0]], // not square: stays a quad
        ];
        // Corner order from Vision may start anywhere.
        let mut shuffled = quads.clone();
        shuffled[0] = [quads[0][2], quads[0][3], quads[0][0], quads[0][1]];
        let boxes = tidy_boxes(&shuffled, 1000, 800);
        assert_eq!(boxes.len(), 4, "{boxes:?}");
        assert_eq!(boxes.iter().map(|b| b.id.as_str()).collect::<Vec<_>>(), ["b1", "b2", "b3", "b4"]);
        match &boxes[0].shape {
            Shape::Rect { cx, w, h, angle_deg, .. } => {
                assert!((cx - 250.0).abs() < 2.0);
                assert_eq!((*w, *h, *angle_deg), (300.0, 200.0, 0.0));
            }
            s => panic!("{s:?}"),
        }
        assert!(matches!(boxes[1].shape, Shape::Rect { cx, .. } if (cx - 750.0).abs() < 1.0));
        match &boxes[2].shape {
            Shape::Rect { angle_deg, w, h, .. } => {
                assert!((angle_deg - 2.0).abs() < 0.05);
                assert_eq!((*w, *h), (300.0, 200.0));
            }
            s => panic!("{s:?}"),
        }
        assert!(matches!(boxes[3].shape, Shape::Quad { .. }));
    }

    #[test]
    fn cancel_and_existing_output_are_safe() {
        let (w, h) = (40u32, 40u32);
        let pixels = image(w, h);
        let dir = tempfile::tempdir().unwrap();
        let (s, d) = (dir.path().join("s"), dir.path().join("d"));
        std::fs::write(&s, &pixels).unwrap();
        let e = edit(w, h, vec![rect("a", 20.0, 20.0, 20.0, 20.0, 0.0, 0)]);
        assert!(extract_rgba(&e, "a", &s, &d, &AtomicBool::new(true)).is_err());
        assert!(!d.exists());
        std::fs::write(&d, b"existing").unwrap();
        assert!(extract_rgba(&e, "a", &s, &d, &AtomicBool::new(false)).is_err());
        assert_eq!(std::fs::read(&d).unwrap(), b"existing");
        assert!(extract_rgba(&e, "zz", &s, &dir.path().join("x"), &AtomicBool::new(false)).is_err());
        assert_eq!(std::fs::read(&s).unwrap(), pixels);
    }

    #[test]
    fn schema_round_trip() {
        let json = r#"{"schema_version":1,"source":{"ref":"Scan_004.tif","width":7016,"height":4960},
          "boxes":[{"id":"b1","kind":"rect","cx":1210.5,"cy":980.0,"w":1800,"h":1200,"angle_deg":0.0,"turn":0},
                   {"id":"b4","kind":"quad","corners":[[3000,3000],[4900,3050],[4950,4300],[2950,4250]],"turn":90}],
          "order":[],"trim_px":4}"#;
        let e: MultiCrop = crate::decode(json).unwrap();
        assert_eq!(crate::decode::<MultiCrop>(&crate::encode(&e).unwrap()).unwrap(), e);
        assert_eq!(e.plan().unwrap().boxes.len(), 2);
    }
}
