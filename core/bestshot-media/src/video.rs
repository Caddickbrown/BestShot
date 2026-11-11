//! Millisecond timeline: crossfades overlap, black fades remain sequential.
use crate::{require, MediaError, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransitionKind {
    HardCut,
    Crossfade,
    FadeThroughBlack,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioMode {
    Crossfade,
    HardCut,
    Mute,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Transition {
    #[serde(rename = "type")]
    pub kind: TransitionKind,
    pub duration_ms: u64,
    pub audio: AudioMode,
}
impl Default for Transition {
    fn default() -> Self {
        Self {
            kind: TransitionKind::HardCut,
            duration_ms: 0,
            audio: AudioMode::HardCut,
        }
    }
}
impl Transition {
    fn validate(&self) -> Result<()> {
        require(
            if self.kind == TransitionKind::HardCut {
                self.duration_ms == 0
            } else {
                (100..=5000).contains(&self.duration_ms)
            },
            "Hard cuts require 0 ms; fades require 100–5000 ms.",
        )
    }
    fn overlap(&self) -> u64 {
        if self.kind == TransitionKind::Crossfade {
            self.duration_ms
        } else {
            0
        }
    }
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Clip {
    pub id: String,
    pub source_ref: String,
    pub in_ms: u64,
    pub out_ms: u64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Output {
    pub width: u32,
    pub height: u32,
    pub fit_mode: String,
    pub frame_rate: u32,
    pub codec: String,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct JoinOverride {
    pub after_clip_id: String,
    pub transition: Transition,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VideoJoin {
    pub schema_version: u32,
    pub clips: Vec<Clip>,
    pub output: Output,
    pub default_transition: Transition,
    pub join_overrides: Vec<JoinOverride>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Placement {
    pub id: String,
    pub start_ms: u64,
    pub duration_ms: u64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Timeline {
    pub duration_ms: u64,
    pub clips: Vec<Placement>,
    pub joins: Vec<Transition>,
}
impl VideoJoin {
    pub fn plan(&self) -> Result<Timeline> {
        require(
            self.schema_version == 1,
            "Unsupported video edit version; use version 1.",
        )?;
        require(self.clips.len() >= 2, "Add at least two video clips.")?;
        require(
            self.output.width >= 2
                && self.output.height >= 2
                && self.output.width <= 8192
                && self.output.height <= 8192
                && self.output.width % 2 == 0
                && self.output.height % 2 == 0,
            "Choose even output dimensions between 2 and 8192 pixels.",
        )?;
        require(
            self.output.fit_mode == "contain",
            "Only Fit with padding is supported.",
        )?;
        require(
            [24, 25, 30, 50, 60].contains(&self.output.frame_rate),
            "Choose 24, 25, 30, 50 or 60 fps.",
        )?;
        require(
            ["h264", "hevc"].contains(&self.output.codec.as_str()),
            "Choose H.264 or HEVC.",
        )?;
        self.default_transition.validate()?;
        let mut ids = HashSet::new();
        for clip in &self.clips {
            require(
                !clip.id.is_empty() && ids.insert(&clip.id),
                "Each clip must have a unique identifier.",
            )?;
            require(
                !clip.source_ref.is_empty() && clip.out_ms > clip.in_ms,
                "Each clip needs a source and a positive duration.",
            )?;
        }
        let mut overrides = HashSet::new();
        for join in &self.join_overrides {
            require(
                self.clips[..self.clips.len() - 1]
                    .iter()
                    .any(|c| c.id == join.after_clip_id)
                    && overrides.insert(&join.after_clip_id),
                "Join overrides must identify distinct clips with a following clip.",
            )?;
            join.transition.validate()?;
        }
        let joins: Vec<_> = self.clips[..self.clips.len() - 1]
            .iter()
            .map(|c| {
                self.join_overrides
                    .iter()
                    .find(|j| j.after_clip_id == c.id)
                    .map(|j| j.transition.clone())
                    .unwrap_or_else(|| self.default_transition.clone())
            })
            .collect();
        let mut placements = Vec::new();
        let mut cursor: u64 = 0;
        for (i, c) in self.clips.iter().enumerate() {
            let duration = c.out_ms - c.in_ms;
            // Reserve footage for sequential black fades too, so fades cannot collide.
            let footprint = |t: &Transition, incoming: bool| match t.kind {
                TransitionKind::HardCut => 0,
                TransitionKind::Crossfade => t.duration_ms,
                TransitionKind::FadeThroughBlack => {
                    if incoming {
                        t.duration_ms - t.duration_ms / 2
                    } else {
                        t.duration_ms / 2
                    }
                }
            };
            let incoming = if i > 0 {
                footprint(&joins[i - 1], true)
            } else {
                0
            };
            let outgoing = if i < joins.len() {
                footprint(&joins[i], false)
            } else {
                0
            };
            require(incoming + outgoing <= duration, &format!("Clip {} is too short for its fades. Shorten the transition or choose a hard cut.",i+1))?;
            if i > 0 {
                cursor -= joins[i - 1].overlap();
            }
            placements.push(Placement {
                id: c.id.clone(),
                start_ms: cursor,
                duration_ms: duration,
            });
            cursor = cursor
                .checked_add(duration)
                .ok_or_else(|| MediaError("Timeline duration overflow.".into()))?;
        }
        Ok(Timeline {
            duration_ms: cursor,
            clips: placements,
            joins,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn config(kind: TransitionKind, duration: u64) -> VideoJoin {
        VideoJoin {
            schema_version: 1,
            clips: (0..3)
                .map(|i| Clip {
                    id: i.to_string(),
                    source_ref: i.to_string(),
                    in_ms: 0,
                    out_ms: 10000,
                })
                .collect(),
            output: Output {
                width: 1920,
                height: 1080,
                fit_mode: "contain".into(),
                frame_rate: 30,
                codec: "h264".into(),
            },
            default_transition: Transition {
                kind,
                duration_ms: duration,
                audio: AudioMode::Crossfade,
            },
            join_overrides: vec![],
        }
    }
    #[test]
    fn timeline_semantics_and_overrides() {
        assert_eq!(
            config(TransitionKind::HardCut, 0)
                .plan()
                .unwrap()
                .duration_ms,
            30000
        );
        let c = config(TransitionKind::Crossfade, 1000);
        let p = c.plan().unwrap();
        assert_eq!(p.duration_ms, 28000);
        assert_eq!(
            p.clips.iter().map(|c| c.start_ms).collect::<Vec<_>>(),
            [0, 9000, 18000]
        );
        assert_eq!(
            config(TransitionKind::FadeThroughBlack, 1000)
                .plan()
                .unwrap()
                .duration_ms,
            30000
        );
        let mut c = c;
        c.join_overrides.push(JoinOverride {
            after_clip_id: "0".into(),
            transition: Transition::default(),
        });
        assert_eq!(c.plan().unwrap().duration_ms, 29000);
        assert_eq!(
            crate::decode::<VideoJoin>(&crate::encode(&c).unwrap()).unwrap(),
            c
        );
    }
    #[test]
    fn impossible_overlaps_and_bad_overrides_rejected() {
        let mut c = config(TransitionKind::Crossfade, 1000);
        c.clips[1].out_ms = 1999;
        assert!(c.plan().is_err());
        c.clips[1].out_ms = 2000;
        assert!(c.plan().is_ok());
        c.join_overrides.push(JoinOverride {
            after_clip_id: "2".into(),
            transition: Transition::default(),
        });
        assert!(c.plan().is_err());
    }
    #[test]
    fn short_sequential_fades_and_invalid_config_rejected() {
        let mut c = config(TransitionKind::FadeThroughBlack, 1001);
        c.clips[1].out_ms = 1000;
        assert!(c.plan().is_err());
        c.clips[1].out_ms = 1001;
        assert!(c.plan().is_ok());
        c.schema_version = 2;
        assert!(c.plan().is_err());
        c.schema_version = 1;
        c.output.width = 1919;
        assert!(c.plan().is_err());
        c.output.width = 1920;
        c.clips[1].id = c.clips[0].id.clone();
        assert!(c.plan().is_err());
    }
}
