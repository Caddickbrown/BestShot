//! Glue: 2–10 photos into one new photo, in a line, a grid or a free
//! ("jagged") layout, with a gap or an overlap, a straight or feathered fade
//! at each seam, and a colour or blurred background.
//!
//! `plan` places every photo in whole output pixels. The platform stages each
//! photo already turned and scaled to its planned size, so `compose_rgba` works
//! 1:1: pixels outside fades and fills are copied exactly.
use crate::{require, Result};
use serde::{Deserialize, Serialize};
use std::fs::{File, OpenOptions};
use std::io::{BufReader, BufWriter, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

pub const MAX_PHOTOS: usize = 10;
pub const MAX_SIDE: i64 = 65_500;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GlueSource {
    #[serde(rename = "ref")]
    pub reference: String,
    pub width: u32,
    pub height: u32,
    /// Clockwise quarter turns applied before layout: 0, 90, 180, 270.
    #[serde(default)]
    pub turn: u32,
}
impl GlueSource {
    /// Size after the turn.
    pub fn upright(&self) -> (f64, f64) {
        if self.turn % 180 == 90 {
            (f64::from(self.height), f64::from(self.width))
        } else {
            (f64::from(self.width), f64::from(self.height))
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum Orientation {
    #[default]
    Auto,
    Horizontal,
    Vertical,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum Arrangement {
    #[default]
    Line,
    Grid,
    Free,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum SizeMode {
    #[default]
    MatchSmaller,
    MatchLarger,
    Keep,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum Align {
    Start,
    #[default]
    Centre,
    End,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum OffsetFill {
    #[default]
    Crop,
    Pad,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Background {
    /// "colour" or "blur".
    #[serde(default = "colour_kind")]
    pub kind: String,
    /// `#RRGGBB`.
    #[serde(default = "white")]
    pub colour: String,
}
fn colour_kind() -> String {
    "colour".into()
}
fn white() -> String {
    "#FFFFFF".into()
}
impl Default for Background {
    fn default() -> Self {
        Self { kind: colour_kind(), colour: white() }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Seam {
    /// Where the change happens inside the overlap, 0 (start) to 1 (end).
    #[serde(default = "half")]
    pub position: f64,
    /// This join's own gap (+) or overlap (−), overriding `join_px` (Line up sets these).
    #[serde(default)]
    pub join_px: Option<i32>,
}
fn half() -> f64 {
    0.5
}
/// A photo's place in a free layout: top-left and width in output pixels; the
/// height follows from the photo's shape.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct FreePlace {
    pub x: f64,
    pub y: f64,
    pub w: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Glue {
    pub schema_version: u32,
    pub sources: Vec<GlueSource>,
    #[serde(default)]
    pub orientation: Orientation,
    #[serde(default)]
    pub arrangement: Arrangement,
    /// Photos per row (per column when vertical) in a grid; 0 picks a near-square grid.
    #[serde(default)]
    pub columns: u32,
    #[serde(default)]
    pub size: SizeMode,
    #[serde(default)]
    pub align: Align,
    /// Gap (positive) or overlap (negative) between neighbours.
    #[serde(default)]
    pub join_px: i32,
    /// Fade width across a seam (0: a straight cut). In Free, a feather on the edges of photos over others.
    #[serde(default)]
    pub fade_px: u32,
    #[serde(default)]
    pub seams: Vec<Seam>,
    /// Cross-axis slide of each photo (line layouts).
    #[serde(default)]
    pub offsets_px: Vec<i32>,
    #[serde(default)]
    pub offset_fill: OffsetFill,
    #[serde(default)]
    pub border_px: u32,
    #[serde(default)]
    pub background: Background,
    #[serde(default)]
    pub free: Vec<FreePlace>,
    /// Allocation guard for the canvas, in pixels. 0: 400 MP.
    #[serde(default)]
    pub max_pixels: u64,
}

/// A rising fade along x (left) or y (top), or a falling one (right, bottom),
/// from `a` to `b` in output pixels. `a == b` is a straight cut.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Ramp {
    pub a: f64,
    pub b: f64,
}
#[derive(Debug, Clone, Copy, PartialEq, Default, Serialize, Deserialize)]
pub struct Ramps {
    pub left: Option<Ramp>,
    pub top: Option<Ramp>,
    pub right: Option<Ramp>,
    pub bottom: Option<Ramp>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Placement {
    /// Index into `sources`.
    pub index: usize,
    pub x: i64,
    pub y: i64,
    pub w: u32,
    pub h: u32,
    /// Planned size over upright size.
    pub scale: f64,
    pub ramps: Ramps,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct JoinPlan {
    /// Positive: gap. Negative: overlap.
    pub join_px: i64,
    pub seam_px: f64,
    pub ramp: Option<Ramp>,
    /// "x" (a vertical seam line) or "y".
    pub axis: String,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GluePlan {
    pub orientation: Orientation,
    pub width: u32,
    pub height: u32,
    /// In drawing order: later ones are on top.
    pub items: Vec<Placement>,
    pub joins: Vec<JoinPlan>,
    /// Indices of photos scaled up past 150%.
    pub upscaled: Vec<usize>,
    /// The largest overlap each join allows (line layouts), for the slider.
    pub max_overlap_px: i64,
}

#[derive(Clone, Copy)]
struct Item {
    index: usize,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    ramps: Ramps,
}

impl Glue {
    pub fn resolved_orientation(&self) -> Orientation {
        match self.orientation {
            Orientation::Auto => {
                // Closest to square: smallest |ln(aspect)|, ties side by side.
                let side = self.line_aspect(false);
                let stack = self.line_aspect(true);
                if stack.ln().abs() + 1e-9 < side.ln().abs() {
                    Orientation::Vertical
                } else {
                    Orientation::Horizontal
                }
            }
            o => o,
        }
    }

    /// Output aspect of a butted Match-smaller line, for auto layout.
    fn line_aspect(&self, vertical: bool) -> f64 {
        let dims: Vec<(f64, f64)> = self.sources.iter().map(|s| s.upright()).map(|(w, h)| if vertical { (h, w) } else { (w, h) }).collect();
        let h = dims.iter().map(|d| d.1).fold(f64::MAX, f64::min);
        let w: f64 = dims.iter().map(|d| d.0 * h / d.1).sum();
        if vertical { h / w } else { w / h }
    }

    fn validate(&self) -> Result<()> {
        require(self.schema_version == 1, "Unsupported Glue version; use version 1.")?;
        require(self.sources.len() >= 2, "Choose at least two photos to glue.")?;
        require(self.sources.len() <= MAX_PHOTOS, "Glue takes up to 10 photos.")?;
        for s in &self.sources {
            require(s.width > 0 && s.height > 0, "A photo has no pixels.")?;
            require(matches!(s.turn, 0 | 90 | 180 | 270), "Turn a photo by 90° steps only.")?;
        }
        require(self.join_px.unsigned_abs() <= 100_000, "The join is too wide.")?;
        require(self.border_px <= 2_000, "The border is at most 2,000 px.")?;
        require(self.background.kind == "colour" || self.background.kind == "blur", "Choose a colour or blurred background.")?;
        parse_colour(&self.background.colour)?;
        for s in &self.seams {
            require((0.0..=1.0).contains(&s.position), "A seam sits inside its overlap.")?;
        }
        Ok(())
    }

    pub fn plan(&self) -> Result<GluePlan> {
        self.validate()?;
        let orientation = self.resolved_orientation();
        let vertical = orientation == Orientation::Vertical;
        let (mut items, joins, max_overlap) = match self.arrangement {
            Arrangement::Free => (self.free_items()?, vec![], 0),
            Arrangement::Line => self.line_items(vertical)?,
            Arrangement::Grid => self.grid_items(vertical)?,
        };
        // Whole pixels, then the canvas is the bounding box (or the offset band) plus the border.
        for it in &mut items {
            it.x = it.x.round();
            it.y = it.y.round();
            it.w = it.w.round().max(1.0);
            it.h = it.h.round().max(1.0);
        }
        let (mut x0, mut y0) = (f64::MAX, f64::MAX);
        let (mut x1, mut y1) = (f64::MIN, f64::MIN);
        for it in &items {
            x0 = x0.min(it.x);
            y0 = y0.min(it.y);
            x1 = x1.max(it.x + it.w);
            y1 = y1.max(it.y + it.h);
        }
        let offsets = self.offsets_px.iter().any(|&o| o != 0);
        if self.arrangement == Arrangement::Line && offsets && self.offset_fill == OffsetFill::Crop && self.size != SizeMode::Keep {
            // The band every photo covers, across the join.
            let (lo, hi) = if vertical {
                (items.iter().map(|i| i.x).fold(f64::MIN, f64::max), items.iter().map(|i| i.x + i.w).fold(f64::MAX, f64::min))
            } else {
                (items.iter().map(|i| i.y).fold(f64::MIN, f64::max), items.iter().map(|i| i.y + i.h).fold(f64::MAX, f64::min))
            };
            let least = items.iter().map(|i| if vertical { i.w } else { i.h }).fold(f64::MAX, f64::min);
            require(hi - lo >= least * 0.1, "The photos barely line up: slide them closer together.")?;
            if vertical {
                x0 = lo;
                x1 = hi;
            } else {
                y0 = lo;
                y1 = hi;
            }
        }
        let border = f64::from(self.border_px);
        let (dx, dy) = (border - x0, border - y0);
        let width = (x1 - x0 + 2.0 * border) as i64;
        let height = (y1 - y0 + 2.0 * border) as i64;
        require(width <= MAX_SIDE && height <= MAX_SIDE, &format!("Too big to glue: {width} × {height} px, 65,500 px a side at most. Try Match smaller."))?;
        let limit = if self.max_pixels == 0 { 400_000_000 } else { self.max_pixels };
        let pixels = (width * height) as u64;
        require(
            pixels <= limit,
            &format!("Too big to glue at this size: {} MP, {} MP at most here. Try Match smaller.", pixels / 1_000_000, limit / 1_000_000),
        )?;
        let shift = |r: Option<Ramp>, d: f64| r.map(|r| Ramp { a: r.a + d, b: r.b + d });
        let mut upscaled = Vec::new();
        let placements = items
            .iter()
            .map(|it| {
                let (uw, _) = self.sources[it.index].upright();
                let scale = it.w / uw;
                if scale > 1.5 && !upscaled.contains(&it.index) {
                    upscaled.push(it.index);
                }
                Placement {
                    index: it.index,
                    x: (it.x + dx) as i64,
                    y: (it.y + dy) as i64,
                    w: it.w as u32,
                    h: it.h as u32,
                    scale,
                    ramps: Ramps {
                        left: shift(it.ramps.left, dx),
                        right: shift(it.ramps.right, dx),
                        top: shift(it.ramps.top, dy),
                        bottom: shift(it.ramps.bottom, dy),
                    },
                }
            })
            .collect();
        let joins = joins
            .into_iter()
            .map(|mut j: JoinPlan| {
                let d = if j.axis == "x" { dx } else { dy };
                j.seam_px += d;
                j.ramp = shift(j.ramp, d);
                j
            })
            .collect();
        Ok(GluePlan { orientation, width: width as u32, height: height as u32, items: placements, joins, upscaled, max_overlap_px: max_overlap })
    }

    fn join_at(&self, k: usize) -> (i32, f64) {
        let seam = self.seams.get(k).copied().unwrap_or(Seam { position: 0.5, join_px: None });
        (seam.join_px.unwrap_or(self.join_px), seam.position)
    }

    /// One row of photos (indices), laid out horizontally from x = 0 with
    /// joins `first_join..`. Returns items, joins and the row's largest allowed overlap.
    fn row(&self, indices: &[usize], first_join: usize, vertical: bool, offsets: bool) -> Result<(Vec<Item>, Vec<JoinPlan>, i64)> {
        let dims: Vec<(f64, f64)> = indices
            .iter()
            .map(|&i| self.sources[i].upright())
            .map(|(w, h)| if vertical { (h, w) } else { (w, h) })
            .collect();
        let target = match self.size {
            SizeMode::MatchSmaller => dims.iter().map(|d| d.1).fold(f64::MAX, f64::min),
            SizeMode::MatchLarger => dims.iter().map(|d| d.1).fold(f64::MIN, f64::max),
            SizeMode::Keep => 0.0,
        };
        let sized: Vec<(f64, f64)> = dims
            .iter()
            .map(|&(w, h)| if self.size == SizeMode::Keep { (w, h) } else { ((w * target / h).round(), target) })
            .collect();
        let tallest = sized.iter().map(|s| s.1).fold(0.0, f64::max);
        let mut items = Vec::new();
        let mut joins = Vec::new();
        let mut x = 0.0;
        let mut max_overlap = i64::MAX;
        for (n, (&index, &(w, h))) in indices.iter().zip(&sized).enumerate() {
            let mut ramps = Ramps::default();
            if n > 0 {
                let (join, position) = self.join_at(first_join + n - 1);
                let narrower = w.min(sized[n - 1].0);
                let allowed = (narrower / 2.0).floor() as i64;
                max_overlap = max_overlap.min(allowed);
                require(i64::from(-join) <= allowed, "An overlap can be at most half the narrower photo.")?;
                let prev_end = x;
                x += f64::from(join);
                let overlap = (prev_end - x).max(0.0);
                let seam = x + overlap * position;
                let ramp = if overlap > 0.0 {
                    let f = f64::from(self.fade_px).min(overlap);
                    // Keep the fade inside the overlap.
                    let a = (seam - f / 2.0).max(x);
                    let b = (a + f).min(prev_end);
                    let a = b - f;
                    Some(Ramp { a, b })
                } else {
                    None
                };
                ramps.left = ramp;
                joins.push(JoinPlan { join_px: i64::from(join), seam_px: if overlap > 0.0 { seam } else { x - f64::from(join.max(0)) / 2.0 }, ramp, axis: "x".into() });
            }
            let base = match self.align {
                Align::Start => 0.0,
                Align::Centre => ((tallest - h) / 2.0).round(),
                Align::End => tallest - h,
            };
            let offset = if offsets { f64::from(self.offsets_px.get(index).copied().unwrap_or(0)) } else { 0.0 };
            items.push(Item { index, x, y: base + offset, w, h, ramps });
            x += w;
        }
        Ok((items, joins, if max_overlap == i64::MAX { 0 } else { max_overlap }))
    }

    fn line_items(&self, vertical: bool) -> Result<(Vec<Item>, Vec<JoinPlan>, i64)> {
        let indices: Vec<usize> = (0..self.sources.len()).collect();
        let (items, joins, max) = self.row(&indices, 0, vertical, true)?;
        Ok((items.into_iter().map(|i| transpose(i, vertical)).collect(), joins.into_iter().map(|j| transpose_join(j, vertical)).collect(), max))
    }

    fn grid_items(&self, vertical: bool) -> Result<(Vec<Item>, Vec<JoinPlan>, i64)> {
        let n = self.sources.len();
        let columns = if self.columns == 0 { (n as f64).sqrt().ceil() as usize } else { (self.columns as usize).clamp(1, n) };
        let indices: Vec<usize> = (0..n).collect();
        let mut rows = Vec::new();
        let mut join_index = 0;
        for chunk in indices.chunks(columns) {
            rows.push((chunk.len(), self.row(chunk, join_index, vertical, false)?));
            join_index += chunk.len().saturating_sub(1);
        }
        let width_of = |items: &[Item]| items.last().map(|l| l.x + l.w).unwrap_or(0.0);
        let full: Vec<f64> = rows.iter().filter(|r| r.0 == columns || rows.len() == 1).map(|r| width_of(&r.1 .0)).collect();
        let target = match self.size {
            SizeMode::MatchSmaller => full.iter().copied().fold(f64::MAX, f64::min),
            SizeMode::MatchLarger => full.iter().copied().fold(f64::MIN, f64::max),
            SizeMode::Keep => full.iter().copied().fold(f64::MIN, f64::max),
        };
        let mut all = Vec::new();
        let mut joins = Vec::new();
        let mut y = 0.0;
        let mut first_height = None;
        let mut max_overlap = i64::MAX;
        let (row_join, row_position) = (self.join_px, 0.5);
        let mut previous_bottom = 0.0;
        let mut first_join_of_row = 0;
        for (r, (count, (items, row_joins, row_max))) in rows.into_iter().enumerate() {
            max_overlap = max_overlap.min(row_max.max(0));
            let w = width_of(&items);
            let gaps: f64 = row_joins.iter().map(|j| j.join_px as f64).sum();
            let row_h0 = items.iter().map(|i| i.h).fold(0.0, f64::max);
            let mut s = if self.size == SizeMode::Keep { 1.0 } else { ((target - gaps) / (w - gaps)).max(0.01) };
            if count < columns && self.size != SizeMode::Keep {
                if let Some(fh) = first_height {
                    // A short last row matches the first row's height rather than stretching.
                    s = s.min(fh / row_h0);
                }
            }
            let mut scaled: Vec<Item> = Vec::new();
            let mut inner: Vec<JoinPlan> = Vec::new();
            let mut x = 0.0;
            for (n, it) in items.iter().enumerate() {
                if n > 0 {
                    x += row_joins[n - 1].join_px as f64;
                }
                let mut item = Item { x, y: 0.0, w: (it.w * s).round(), h: (it.h * s).round(), ..*it };
                if n > 0 {
                    // Rebuild the seam and its ramp at the scaled size.
                    let prev = scaled.last().map(|p: &Item| p.x + p.w).unwrap_or(0.0);
                    let overlap = (prev - x).max(0.0);
                    let f = f64::from(self.fade_px).min(overlap);
                    let position = self.join_at(first_join_of_row + n - 1).1;
                    let seam = x + overlap * position;
                    let a = (seam - f / 2.0).max(x);
                    let b = (a + f).min(prev);
                    item.ramps.left = if overlap > 0.0 { Some(Ramp { a: b - f, b }) } else { None };
                    let join = row_joins[n - 1].join_px;
                    inner.push(JoinPlan { join_px: join, seam_px: if overlap > 0.0 { seam } else { x - join.max(0) as f64 / 2.0 }, ramp: item.ramps.left, axis: "x".into() });
                }
                x += item.w;
                scaled.push(item);
            }
            let row_w = x;
            let row_h = scaled.iter().map(|i| i.h).fold(0.0, f64::max);
            let shift = match self.align {
                Align::Start => 0.0,
                Align::Centre => ((target - row_w) / 2.0).round().max(0.0),
                Align::End => (target - row_w).max(0.0),
            };
            if r > 0 {
                let allowed = (row_h.min(first_height.unwrap_or(row_h)) / 2.0).floor() as i64;
                max_overlap = max_overlap.min(allowed);
                require(i64::from(-row_join) <= allowed, "An overlap can be at most half the narrower photo.")?;
                y = previous_bottom + f64::from(row_join);
            }
            let overlap = if r > 0 { (previous_bottom - y).max(0.0) } else { 0.0 };
            let top = if overlap > 0.0 {
                let f = f64::from(self.fade_px).min(overlap);
                let seam = y + overlap * row_position;
                let a = (seam - f / 2.0).max(y);
                let b = (a + f).min(previous_bottom);
                Some(Ramp { a: b - f, b })
            } else {
                None
            };
            if r > 0 {
                joins.push(JoinPlan { join_px: i64::from(row_join), seam_px: if overlap > 0.0 { y + overlap * row_position } else { y - f64::from(row_join.max(0)) / 2.0 }, ramp: top, axis: "y".into() });
            }
            for mut it in scaled {
                let base = match self.align {
                    Align::Start => 0.0,
                    Align::Centre => ((row_h - it.h) / 2.0).round(),
                    Align::End => row_h - it.h,
                };
                it.x += shift;
                if let Some(l) = it.ramps.left.as_mut() {
                    l.a += shift;
                    l.b += shift;
                }
                it.y = y + base;
                it.ramps.top = top;
                all.push(it);
            }
            for mut j in inner {
                j.seam_px += shift;
                if let Some(r) = j.ramp.as_mut() {
                    r.a += shift;
                    r.b += shift;
                }
                joins.push(j);
            }
            first_join_of_row += count.saturating_sub(1);
            first_height.get_or_insert(row_h);
            previous_bottom = y + row_h;
        }
        Ok((all.into_iter().map(|i| transpose(i, vertical)).collect(), joins.into_iter().map(|j| transpose_join(j, vertical)).collect(), if max_overlap == i64::MAX { 0 } else { max_overlap }))
    }

    fn free_items(&self) -> Result<Vec<Item>> {
        require(self.free.len() == self.sources.len(), "A free layout needs a place for every photo.")?;
        let f = f64::from(self.fade_px);
        self.sources
            .iter()
            .zip(&self.free)
            .enumerate()
            .map(|(index, (s, p))| {
                require(p.x.is_finite() && p.y.is_finite() && p.w.is_finite() && p.w >= 1.0, "A photo has an invalid place.")?;
                let (uw, uh) = s.upright();
                let (w, h) = (p.w.round(), (p.w * uh / uw).round().max(1.0));
                let (x, y) = (p.x.round(), p.y.round());
                let ramps = if index > 0 && f > 0.0 {
                    let f = f.min(w / 2.0).min(h / 2.0);
                    Ramps {
                        left: Some(Ramp { a: x, b: x + f }),
                        top: Some(Ramp { a: y, b: y + f }),
                        right: Some(Ramp { a: x + w - f, b: x + w }),
                        bottom: Some(Ramp { a: y + h - f, b: y + h }),
                    }
                } else {
                    Ramps::default()
                };
                Ok(Item { index, x, y, w, h, ramps })
            })
            .collect()
    }
}

fn transpose(i: Item, vertical: bool) -> Item {
    if !vertical {
        return i;
    }
    Item {
        index: i.index,
        x: i.y,
        y: i.x,
        w: i.h,
        h: i.w,
        ramps: Ramps { left: i.ramps.top, top: i.ramps.left, right: i.ramps.bottom, bottom: i.ramps.right },
    }
}
fn transpose_join(mut j: JoinPlan, vertical: bool) -> JoinPlan {
    if vertical {
        j.axis = if j.axis == "x" { "y".into() } else { "x".into() };
    }
    j
}

pub fn parse_colour(text: &str) -> Result<[u8; 3]> {
    let hex = text.trim_start_matches('#');
    require(hex.len() == 6 && hex.chars().all(|c| c.is_ascii_hexdigit()), "Colours are #RRGGBB.")?;
    let v = u32::from_str_radix(hex, 16).expect("checked");
    Ok([(v >> 16) as u8, (v >> 8) as u8, v as u8])
}

#[inline]
fn smoothstep(t: f64) -> f64 {
    let t = t.clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}
fn rising(r: Option<Ramp>, c: f64) -> f64 {
    match r {
        None => 1.0,
        Some(Ramp { a, b }) if b <= a => {
            if c < a { 0.0 } else { 1.0 }
        }
        Some(Ramp { a, b }) => smoothstep((c - a) / (b - a)),
    }
}
fn falling(r: Option<Ramp>, c: f64) -> f64 {
    match r {
        None => 1.0,
        Some(Ramp { a, b }) if b <= a => {
            if c >= b { 0.0 } else { 1.0 }
        }
        Some(Ramp { a, b }) => 1.0 - smoothstep((c - a) / (b - a)),
    }
}
/// The weight of a photo at output pixel (x, y), from its ramps. Public so a
/// shell can draw the same fade in a preview.
pub fn weight(r: &Ramps, x: u32, y: u32) -> f64 {
    let (cx, cy) = (f64::from(x) + 0.5, f64::from(y) + 0.5);
    rising(r.left, cx) * falling(r.right, cx) * rising(r.top, cy) * falling(r.bottom, cy)
}

/// A small, blurred, hole-filled copy of the photos, for the blurred background.
struct BlurField {
    w: usize,
    h: usize,
    k: f64,
    px: Vec<[f32; 4]>,
}
impl BlurField {
    fn build(plan: &GluePlan, inputs: &mut [File], cancelled: &AtomicBool) -> Result<Self> {
        let longest = f64::from(plan.width.max(plan.height));
        let k = (longest / 192.0).max(1.0);
        let w = ((f64::from(plan.width) / k).ceil() as usize).max(1);
        let h = ((f64::from(plan.height) / k).ceil() as usize).max(1);
        let mut px = vec![[0f32; 4]; w * h];
        for (n, it) in plan.items.iter().enumerate() {
            let row_bytes = it.w as usize * 4;
            let mut row = vec![0u8; row_bytes];
            let file = &mut inputs[n];
            for ly in 0..h {
                require(!cancelled.load(Ordering::Relaxed), "Export cancelled.")?;
                let cy = ((ly as f64 + 0.5) * k) as i64 - it.y;
                if cy < 0 || cy >= i64::from(it.h) {
                    continue;
                }
                file.seek(SeekFrom::Start(cy as u64 * row_bytes as u64))?;
                file.read_exact(&mut row)?;
                for lx in 0..w {
                    let cx = ((lx as f64 + 0.5) * k) as i64 - it.x;
                    if cx < 0 || cx >= i64::from(it.w) {
                        continue;
                    }
                    let p = &row[cx as usize * 4..cx as usize * 4 + 4];
                    let dst = &mut px[ly * w + lx];
                    let a = f32::from(p[3]) / 255.0;
                    for c in 0..4 {
                        dst[c] = f32::from(p[c]) / 255.0 + dst[c] * (1.0 - a);
                    }
                }
            }
        }
        let filled = push_pull(&px, w, h);
        let radius = (w.max(h) / 24).max(1);
        let mut blurred = filled;
        for _ in 0..3 {
            blurred = box_blur(&blurred, w, h, radius);
        }
        Ok(Self { w, h, k, px: blurred })
    }
    fn at(&self, x: u32, y: u32) -> [f32; 4] {
        let fx = ((f64::from(x) + 0.5) / self.k - 0.5).clamp(0.0, (self.w - 1) as f64);
        let fy = ((f64::from(y) + 0.5) / self.k - 0.5).clamp(0.0, (self.h - 1) as f64);
        let (x0, y0) = (fx.floor() as usize, fy.floor() as usize);
        let (x1, y1) = ((x0 + 1).min(self.w - 1), (y0 + 1).min(self.h - 1));
        let (tx, ty) = ((fx - x0 as f64) as f32, (fy - y0 as f64) as f32);
        let mut out = [0f32; 4];
        for c in 0..4 {
            let top = self.px[y0 * self.w + x0][c] * (1.0 - tx) + self.px[y0 * self.w + x1][c] * tx;
            let bottom = self.px[y1 * self.w + x0][c] * (1.0 - tx) + self.px[y1 * self.w + x1][c] * tx;
            out[c] = top * (1.0 - ty) + bottom * ty;
        }
        out
    }
}

/// Fills transparent pixels from coarser levels (premultiplied), so the photos'
/// colours spread out to the canvas edges; the result is opaque.
fn push_pull(px: &[[f32; 4]], w: usize, h: usize) -> Vec<[f32; 4]> {
    if w <= 1 && h <= 1 {
        let p = px[0];
        return vec![if p[3] > 1e-4 { [p[0] / p[3], p[1] / p[3], p[2] / p[3], 1.0] } else { [0.5, 0.5, 0.5, 1.0] }];
    }
    let (cw, ch) = (w.div_ceil(2), h.div_ceil(2));
    let mut coarse = vec![[0f32; 4]; cw * ch];
    for y in 0..ch {
        for x in 0..cw {
            let mut acc = [0f32; 4];
            let mut n = 0.0;
            for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let (sx, sy) = (2 * x + dx, 2 * y + dy);
                if sx < w && sy < h {
                    for c in 0..4 {
                        acc[c] += px[sy * w + sx][c];
                    }
                    n += 1.0;
                }
            }
            coarse[y * cw + x] = acc.map(|v| v / n);
        }
    }
    let coarse = push_pull(&coarse, cw, ch);
    let mut out = vec![[0f32; 4]; w * h];
    for y in 0..h {
        for x in 0..w {
            let p = px[y * w + x];
            let c = coarse[(y / 2) * cw + x / 2];
            let a = p[3].min(1.0);
            out[y * w + x] = [p[0] + c[0] * (1.0 - a), p[1] + c[1] * (1.0 - a), p[2] + c[2] * (1.0 - a), 1.0];
        }
    }
    out
}

fn box_blur(px: &[[f32; 4]], w: usize, h: usize, r: usize) -> Vec<[f32; 4]> {
    let mut tmp = vec![[0f32; 4]; w * h];
    for y in 0..h {
        for x in 0..w {
            let (lo, hi) = (x.saturating_sub(r), (x + r).min(w - 1));
            let mut acc = [0f32; 4];
            for sx in lo..=hi {
                for c in 0..4 {
                    acc[c] += px[y * w + sx][c];
                }
            }
            tmp[y * w + x] = acc.map(|v| v / (hi - lo + 1) as f32);
        }
    }
    let mut out = vec![[0f32; 4]; w * h];
    for y in 0..h {
        for x in 0..w {
            let (lo, hi) = (y.saturating_sub(r), (y + r).min(h - 1));
            let mut acc = [0f32; 4];
            for sy in lo..=hi {
                for c in 0..4 {
                    acc[c] += tmp[sy * w + x][c];
                }
            }
            out[y * w + x] = acc.map(|v| v / (hi - lo + 1) as f32);
        }
    }
    out
}

/// Composites the plan into tightly packed premultiplied RGBA rows at
/// `destination` (a new file). `inputs[i]` is the staged pixels of
/// `plan.items[i]`, exactly `w × h`. Memory is about one row per photo (plus a
/// small field for the blurred background). Removes the output on error or cancel.
pub fn compose_rgba(edit: &Glue, inputs: &[PathBuf], destination: &Path, cancelled: &AtomicBool) -> Result<GluePlan> {
    let plan = edit.plan()?;
    require(inputs.len() == plan.items.len(), "Every photo needs its staged pixels.")?;
    let mut files = Vec::new();
    for (it, path) in plan.items.iter().zip(inputs) {
        let f = File::open(path)?;
        require(f.metadata()?.len() == u64::from(it.w) * u64::from(it.h) * 4, "A staged photo has an unexpected size.")?;
        files.push(f);
    }
    let output = OpenOptions::new().write(true).create_new(true).open(destination)?;
    let result = (|| {
        let blur = if edit.background.kind == "blur" { Some(BlurField::build(&plan, &mut files, cancelled)?) } else { None };
        let mut readers: Vec<BufReader<File>> = files
            .into_iter()
            .map(|mut f| {
                f.seek(SeekFrom::Start(0))?;
                Ok(BufReader::with_capacity(1 << 20, f))
            })
            .collect::<Result<_>>()?;
        let [r, g, b] = parse_colour(&edit.background.colour)?;
        let (w, h) = (plan.width as usize, plan.height as usize);
        let mut writer = BufWriter::with_capacity(1 << 20, &output);
        let mut row = vec![0u8; w * 4];
        let mut rows: Vec<Vec<u8>> = plan.items.iter().map(|it| vec![0u8; it.w as usize * 4]).collect();
        for y in 0..h {
            require(!cancelled.load(Ordering::Relaxed), "Export cancelled.")?;
            match &blur {
                None => {
                    for px in row.chunks_exact_mut(4) {
                        px.copy_from_slice(&[r, g, b, 255]);
                    }
                }
                Some(field) => {
                    for (x, px) in row.chunks_exact_mut(4).enumerate() {
                        let c = field.at(x as u32, y as u32);
                        px.copy_from_slice(&[(c[0] * 255.0).round() as u8, (c[1] * 255.0).round() as u8, (c[2] * 255.0).round() as u8, 255]);
                    }
                }
            }
            for (n, it) in plan.items.iter().enumerate() {
                let iy = y as i64 - it.y;
                if iy < 0 || iy >= i64::from(it.h) {
                    continue;
                }
                readers[n].read_exact(&mut rows[n])?;
                let src = &rows[n];
                let x_start = it.x.max(0) as usize;
                let x_end = ((it.x + i64::from(it.w)) as usize).min(w);
                let (vy, plain) = (y as u32, it.ramps.left.is_none() && it.ramps.right.is_none() && it.ramps.top.is_none() && it.ramps.bottom.is_none());
                let ty = rising(it.ramps.top, f64::from(vy) + 0.5) * falling(it.ramps.bottom, f64::from(vy) + 0.5);
                for x in x_start..x_end {
                    let sx = (x as i64 - it.x) as usize * 4;
                    let s = &src[sx..sx + 4];
                    let f = if plain { 1.0 } else { ty * rising(it.ramps.left, x as f64 + 0.5) * falling(it.ramps.right, x as f64 + 0.5) };
                    let d = &mut row[x * 4..x * 4 + 4];
                    if f >= 1.0 && s[3] == 255 {
                        d.copy_from_slice(s);
                    } else if f > 0.0 {
                        let a = f64::from(s[3]) / 255.0 * f;
                        for c in 0..4 {
                            d[c] = (f64::from(s[c]) * f + f64::from(d[c]) * (1.0 - a)).round().clamp(0.0, 255.0) as u8;
                        }
                    }
                }
            }
            writer.write_all(&row)?;
        }
        writer.flush()?;
        drop(writer);
        output.sync_all()?;
        require(!cancelled.load(Ordering::Relaxed), "Export cancelled.")?;
        Ok(plan.clone())
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

    fn src(w: u32, h: u32) -> GlueSource {
        GlueSource { reference: format!("{w}x{h}"), width: w, height: h, turn: 0 }
    }
    fn glue(sources: Vec<GlueSource>) -> Glue {
        Glue {
            schema_version: 1,
            sources,
            orientation: Orientation::Auto,
            arrangement: Arrangement::Line,
            columns: 0,
            size: SizeMode::MatchSmaller,
            align: Align::Centre,
            join_px: 0,
            fade_px: 0,
            seams: vec![],
            offsets_px: vec![],
            offset_fill: OffsetFill::Crop,
            border_px: 0,
            background: Background::default(),
            free: vec![],
            max_pixels: 0,
        }
    }

    #[test]
    fn auto_layout_is_closest_to_square() {
        assert_eq!(glue(vec![src(4000, 6000), src(4000, 6000)]).resolved_orientation(), Orientation::Horizontal);
        assert_eq!(glue(vec![src(6000, 4000), src(6000, 4000)]).resolved_orientation(), Orientation::Vertical);
        assert_eq!(glue(vec![src(4000, 6000), src(6000, 4000)]).resolved_orientation(), Orientation::Horizontal);
        assert_eq!(glue(vec![src(100, 100), src(100, 100)]).resolved_orientation(), Orientation::Horizontal, "ties side by side");
        let mut turned = glue(vec![src(6000, 4000), src(6000, 4000)]);
        turned.sources[0].turn = 90;
        turned.sources[1].turn = 270;
        assert_eq!(turned.resolved_orientation(), Orientation::Horizontal);
    }

    #[test]
    fn canvas_sizes_for_size_modes_joins_and_border() {
        let mut g = glue(vec![src(400, 600), src(200, 200)]);
        let p = g.plan().unwrap();
        assert_eq!((p.width, p.height), (333, 200));
        assert_eq!(p.items[0].w, 133);
        g.size = SizeMode::MatchLarger;
        let p = g.plan().unwrap();
        assert_eq!((p.width, p.height), (1000, 600));
        assert_eq!(p.upscaled, vec![1]);
        g.size = SizeMode::Keep;
        g.align = Align::End;
        let p = g.plan().unwrap();
        assert_eq!((p.width, p.height), (600, 600));
        assert_eq!((p.items[1].x, p.items[1].y), (400, 400));
        g.size = SizeMode::MatchSmaller;
        g.join_px = 20;
        g.border_px = 10;
        let p = g.plan().unwrap();
        assert_eq!((p.width, p.height), (133 + 20 + 200 + 20, 220));
        assert_eq!(p.items[1].x, 10 + 133 + 20);
        g.join_px = -60;
        let p = g.plan().unwrap();
        assert_eq!(p.width, 133 + 200 - 60 + 20);
        assert_eq!(p.max_overlap_px, 66);
        g.join_px = -67;
        assert!(g.plan().is_err(), "overlap past half the narrower photo");
    }

    #[test]
    fn ramps_at_known_pixels() {
        let mut g = glue(vec![src(100, 50), src(100, 50)]);
        g.orientation = Orientation::Horizontal;
        g.join_px = -40;
        g.fade_px = 20;
        let p = g.plan().unwrap();
        let r = p.items[1].ramps.left.unwrap();
        // Overlap 60..100, seam at 80, fade 70..90.
        assert_eq!((r.a, r.b), (70.0, 90.0));
        let ramps = p.items[1].ramps;
        assert_eq!(weight(&ramps, 69, 0), 0.0);
        assert!((weight(&ramps, 79, 0) + weight(&ramps, 80, 0) - 1.0).abs() < 1e-9, "½ at the seam");
        assert_eq!(weight(&ramps, 90, 0), 1.0);
        g.fade_px = 0;
        let ramps = g.plan().unwrap().items[1].ramps;
        assert_eq!((weight(&ramps, 79, 0), weight(&ramps, 80, 0)), (0.0, 1.0), "a straight cut at the seam");
        g.seams = vec![Seam { position: 0.0, join_px: None }];
        assert_eq!(g.plan().unwrap().items[1].ramps.left.unwrap().a, 60.0);
        g.seams = vec![Seam { position: 1.0, join_px: Some(-10) }];
        let p = g.plan().unwrap();
        assert_eq!(p.width, 190, "a join's own value wins");
        assert_eq!(p.items[1].ramps.left.unwrap().a, 100.0);
        // Vertical: the same ramp runs down.
        g.orientation = Orientation::Vertical;
        g.seams = vec![];
        g.join_px = -20;
        g.fade_px = 10;
        let p = g.plan().unwrap();
        assert_eq!((p.width, p.height), (100, 80));
        assert!(p.items[1].ramps.top.is_some() && p.items[1].ramps.left.is_none());
        assert_eq!(p.joins[0].axis, "y");
    }

    #[test]
    fn offsets_crop_to_the_shared_band_or_pad() {
        let mut g = glue(vec![src(100, 100), src(100, 100)]);
        g.orientation = Orientation::Horizontal;
        g.offsets_px = vec![0, -12];
        let p = g.plan().unwrap();
        assert_eq!((p.width, p.height), (200, 88));
        assert_eq!((p.items[0].y, p.items[1].y), (0, -12));
        g.offset_fill = OffsetFill::Pad;
        assert_eq!(g.plan().unwrap().height, 112);
        g.offset_fill = OffsetFill::Crop;
        g.offsets_px = vec![0, 95];
        assert!(g.plan().is_err(), "under 10% shared");
    }

    #[test]
    fn grid_and_free_layouts() {
        let mut g = glue((0..5).map(|_| src(300, 200)).collect());
        g.orientation = Orientation::Horizontal;
        g.arrangement = Arrangement::Grid;
        let p = g.plan().unwrap();
        // 3 columns, 2 rows; the short row keeps the first row's height, centred.
        assert_eq!((p.width, p.height), (900, 400));
        assert_eq!((p.items[3].x, p.items[3].y, p.items[3].w), (150, 200, 300));
        g.join_px = 10;
        let p = g.plan().unwrap();
        assert_eq!((p.width, p.height), (920, 410));
        g.join_px = -20;
        g.fade_px = 10;
        let p = g.plan().unwrap();
        assert!(p.items[4].ramps.top.is_some() && p.items[4].ramps.left.is_some());
        assert_eq!(p.joins.iter().filter(|j| j.axis == "y").count(), 1);
        g.orientation = Orientation::Vertical;
        g.join_px = 0;
        let p = g.plan().unwrap();
        assert_eq!((p.width, p.height), (600, 600), "columns of three when vertical");

        let mut f = glue(vec![src(400, 200), src(100, 300), src(200, 200)]);
        f.arrangement = Arrangement::Free;
        assert!(f.plan().is_err());
        f.free = vec![FreePlace { x: 0.0, y: 0.0, w: 400.0 }, FreePlace { x: 350.0, y: -50.0, w: 50.0 }, FreePlace { x: -30.0, y: 180.0, w: 100.0 }];
        f.border_px = 5;
        f.fade_px = 8;
        let p = f.plan().unwrap();
        assert_eq!((p.width, p.height), (430 + 10, 330 + 10));
        assert_eq!((p.items[0].x, p.items[0].y), (35, 55));
        assert_eq!((p.items[1].w, p.items[1].h), (50, 150));
        assert!(p.items[0].ramps.left.is_none(), "the bottom photo isn't feathered");
        assert!(p.items[2].ramps.right.is_some());
    }

    #[test]
    fn validation_and_limits() {
        assert!(glue(vec![src(10, 10)]).plan().is_err());
        assert!(glue((0..11).map(|_| src(10, 10)).collect()).plan().is_err());
        assert!(glue(vec![src(10, 10), src(0, 10)]).plan().is_err());
        let mut g = glue(vec![src(40000, 30000), src(40000, 30000)]);
        g.orientation = Orientation::Horizontal;
        assert!(g.plan().is_err(), "over 65,500 px");
        let mut g = glue(vec![src(10000, 10000), src(10000, 10000)]);
        g.max_pixels = 100_000_000;
        assert!(g.plan().unwrap_err().0.contains("200 MP"));
        let mut g = glue(vec![src(10, 10), src(10, 10)]);
        g.background.colour = "red".into();
        assert!(g.plan().is_err());
        g.background.colour = "#00ff00".into();
        g.schema_version = 2;
        assert!(g.plan().is_err());
        g.schema_version = 1;
        assert_eq!(crate::decode::<Glue>(&crate::encode(&g).unwrap()).unwrap(), g);
        let minimal: Glue = crate::decode(r#"{"schema_version":1,"sources":[{"ref":"a","width":4,"height":6},{"ref":"b","width":4,"height":6}]}"#).unwrap();
        assert_eq!(minimal.plan().unwrap().width, 8);
    }

    fn pixels(w: u32, h: u32, seed: u32) -> Vec<u8> {
        (0..w * h).flat_map(|i| [((i + seed) % 251) as u8, ((i * 7 + seed) % 253) as u8, ((i * 3) % 241) as u8, 255]).collect()
    }
    fn compose(g: &Glue, staged: &[Vec<u8>]) -> (GluePlan, Vec<u8>) {
        let dir = tempfile::tempdir().unwrap();
        let paths: Vec<PathBuf> = staged
            .iter()
            .enumerate()
            .map(|(i, p)| {
                let path = dir.path().join(format!("in{i}"));
                std::fs::write(&path, p).unwrap();
                path
            })
            .collect();
        let out = dir.path().join("out");
        let plan = compose_rgba(g, &paths, &out, &AtomicBool::new(false)).unwrap();
        for (p, s) in paths.iter().zip(staged) {
            assert_eq!(&std::fs::read(p).unwrap(), s, "inputs are never written");
        }
        (plan, std::fs::read(out).unwrap())
    }

    #[test]
    fn exact_copy_outside_fades_exhaustive_small() {
        for w0 in 2..6u32 {
            for w1 in 2..6u32 {
                for join in -(w0.min(w1) as i32 / 2)..=3 {
                    for fade in 0..3u32 {
                        let mut g = glue(vec![src(w0, 4), src(w1, 4)]);
                        g.orientation = Orientation::Horizontal;
                        g.size = SizeMode::Keep;
                        g.join_px = join;
                        g.fade_px = fade;
                        g.background.colour = "#102030".into();
                        let staged = vec![pixels(w0, 4, 1), pixels(w1, 4, 99)];
                        let (plan, out) = compose(&g, &staged);
                        let wd = plan.width as usize;
                        for y in 0..4usize {
                            for x in 0..wd {
                                let got = &out[(y * wd + x) * 4..(y * wd + x) * 4 + 4];
                                let second = &plan.items[1];
                                let in1 = (x as i64) >= second.x;
                                let w1v = weight(&second.ramps, x as u32, y as u32);
                                if in1 && w1v >= 1.0 {
                                    let sx = (x as i64 - second.x) as usize;
                                    assert_eq!(got, &staged[1][(y * w1 as usize + sx) * 4..][..4]);
                                } else if (x as u32) < w0 && (!in1 || w1v == 0.0) {
                                    assert_eq!(got, &staged[0][(y * w0 as usize + x) * 4..][..4]);
                                } else if !in1 && x as u32 >= w0 {
                                    assert_eq!(got, &[0x10, 0x20, 0x30, 255], "gap is the background");
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn fade_blends_and_border_fills() {
        let mut g = glue(vec![src(20, 2), src(20, 2)]);
        g.orientation = Orientation::Horizontal;
        g.join_px = -10;
        g.fade_px = 10;
        g.border_px = 1;
        g.background.colour = "#000000".into();
        let a: Vec<u8> = std::iter::repeat([200u8, 0, 0, 255]).take(40).flatten().collect();
        let b: Vec<u8> = std::iter::repeat([0u8, 0, 200, 255]).take(40).flatten().collect();
        let (plan, out) = compose(&g, &[a, b]);
        assert_eq!((plan.width, plan.height), (32, 4));
        let px = |x: usize, y: usize| &out[(y * 32 + x) * 4..(y * 32 + x) * 4 + 4];
        assert_eq!(px(0, 0), &[0, 0, 0, 255]);
        assert_eq!(px(5, 1), &[200, 0, 0, 255]);
        assert_eq!(px(28, 2), &[0, 0, 200, 255]);
        let mid = px(16, 1);
        assert!(mid[0] > 40 && mid[2] > 40 && mid[3] == 255, "{mid:?}");
    }

    #[test]
    fn blurred_background_fills_everything_opaque() {
        let mut g = glue(vec![src(30, 10), src(10, 30)]);
        g.arrangement = Arrangement::Free;
        g.free = vec![FreePlace { x: 0.0, y: 0.0, w: 30.0 }, FreePlace { x: 50.0, y: 20.0, w: 10.0 }];
        g.background.kind = "blur".into();
        let red: Vec<u8> = std::iter::repeat([220u8, 10, 10, 255]).take(300).flatten().collect();
        let blue: Vec<u8> = std::iter::repeat([10u8, 10, 220, 255]).take(300).flatten().collect();
        let (plan, out) = compose(&g, &[red, blue]);
        assert_eq!((plan.width, plan.height), (60, 50));
        assert!(out.chunks(4).all(|p| p[3] == 255));
        let px = |x: usize, y: usize| out[(y * 60 + x) * 4..(y * 60 + x) * 4 + 4].to_vec();
        // Empty corner near the red photo leans red; near the blue one leans blue.
        let (near_red, near_blue) = (px(5, 45), px(58, 2));
        assert!(near_red[0] > near_red[2] || near_blue[2] > near_blue[0]);
        assert_eq!(px(5, 5), vec![220, 10, 10, 255], "photos stay exact");
    }

    #[test]
    fn cancel_and_wrong_inputs_leave_nothing() {
        let g = glue(vec![src(4, 4), src(4, 4)]);
        let dir = tempfile::tempdir().unwrap();
        let a = dir.path().join("a");
        std::fs::write(&a, pixels(4, 4, 0)).unwrap();
        let out = dir.path().join("out");
        assert!(compose_rgba(&g, &[a.clone(), a.clone()], &out, &AtomicBool::new(true)).is_err());
        assert!(!out.exists());
        assert!(compose_rgba(&g, &[a.clone()], &out, &AtomicBool::new(false)).is_err());
        std::fs::write(dir.path().join("short"), [0u8; 3]).unwrap();
        assert!(compose_rgba(&g, &[a.clone(), dir.path().join("short")], &out, &AtomicBool::new(false)).is_err());
        assert!(!out.exists());
    }
}
