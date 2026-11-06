//! Colour labels and how `xmp:Label` text maps to them.
//!
//! `xmp:Label` is free text, and in Bridge the names are per-user settings, so
//! the mapping is data. Only the plain colour words are recognised out of the
//! box. Bridge's default names are offered as suggestions in Import from
//! Bridge and apply once saved: guessing here could turn someone's renamed
//! "Select" into a red, and red means bin.

use crate::atomic;
use crate::store::Decision;
use crate::xmp::Fields;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Colour {
    Red,
    Yellow,
    Green,
    Blue,
    Purple,
}

impl Colour {
    pub const ALL: [Colour; 5] = [Colour::Red, Colour::Yellow, Colour::Green, Colour::Blue, Colour::Purple];

    pub fn word(self) -> &'static str {
        match self {
            Colour::Red => "Red",
            Colour::Yellow => "Yellow",
            Colour::Green => "Green",
            Colour::Blue => "Blue",
            Colour::Purple => "Purple",
        }
    }

    /// Green is Keep and red is Reject; the others aren't decisions.
    pub fn decision(self) -> Option<Decision> {
        match self {
            Colour::Green => Some(Decision::Keep),
            Colour::Red => Some(Decision::Reject),
            _ => None,
        }
    }

    pub fn for_decision(decision: Decision) -> Colour {
        match decision {
            Decision::Keep => Colour::Green,
            Decision::Reject => Colour::Red,
        }
    }
}

fn key(text: &str) -> String {
    text.trim().to_lowercase()
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LabelConfig {
    pub version: u32,
    /// The text written to `xmp:Label` for each colour.
    pub names: BTreeMap<Colour, String>,
    /// Label text found in files (lowercased) -> colour. A `null` colour means
    /// "not a colour", which also overrides `names` and the colour words.
    pub aliases: BTreeMap<String, Option<Colour>>,
}

impl Default for LabelConfig {
    fn default() -> Self {
        Self {
            version: 1,
            names: Colour::ALL.iter().map(|c| (*c, c.word().to_string())).collect(),
            aliases: BTreeMap::new(),
        }
    }
}

impl LabelConfig {
    pub fn name(&self, colour: Colour) -> &str {
        self.names.get(&colour).map_or(colour.word(), String::as_str)
    }

    pub fn colour_of(&self, text: &str) -> Option<Colour> {
        let k = key(text);
        if k.is_empty() {
            return None;
        }
        if let Some(mapped) = self.aliases.get(&k) {
            return *mapped;
        }
        Colour::ALL
            .iter()
            .find(|c| key(self.name(**c)) == k)
            .or_else(|| Colour::ALL.iter().find(|c| key(c.word()) == k))
            .copied()
    }

    /// `xmp:Label` first, then `photoshop:LabelColor`, with two limits. A label
    /// mapped to "not a colour" means that, whatever else the file says. And a
    /// label BestShot can't map can't be turned red by the fallback: Bridge writes
    /// `Select` with `LabelColor="Red"`, red means reject here, and a pick must
    /// never be binned on a guess. With no label text at all, LabelColor decides.
    pub fn colour_for(&self, fields: &Fields) -> Option<Colour> {
        let fallback = fields.label_color.as_deref().and_then(|t| self.colour_of(t));
        let Some(label) = fields.label.as_deref().map(str::trim).filter(|l| !l.is_empty()) else {
            return fallback;
        };
        if let Some(colour) = self.colour_of(label) {
            return Some(colour);
        }
        if matches!(self.aliases.get(&key(label)), Some(None)) {
            return None;
        }
        fallback.filter(|colour| *colour != Colour::Red)
    }

    /// Renames a colour. Files already written with the old name keep their
    /// colour, through an alias.
    pub fn rename(&mut self, colour: Colour, name: &str) -> Result<(), String> {
        let name = name.trim();
        if name.is_empty() {
            return Err("A label needs a name.".into());
        }
        if let Some(other) = Colour::ALL.iter().find(|c| **c != colour && key(self.name(**c)) == key(name)) {
            return Err(format!("{} already uses the name “{name}”.", other.word()));
        }
        let old = self.name(colour).to_string();
        if key(&old) != key(name) {
            self.aliases.insert(key(&old), Some(colour));
        }
        self.aliases.remove(&key(name));
        self.names.insert(colour, name.to_string());
        Ok(())
    }

    pub fn map(&mut self, text: &str, colour: Option<Colour>) {
        self.aliases.insert(key(text), colour);
    }
}

/// What Bridge's default label names and the colour words suggest, for the
/// import screen to offer. Nothing is mapped until it's saved there.
pub fn suggestion(text: &str) -> Option<Colour> {
    match key(text).as_str() {
        "select" | "red" => Some(Colour::Red),
        "second" | "yellow" => Some(Colour::Yellow),
        "approved" | "green" => Some(Colour::Green),
        "review" | "blue" => Some(Colour::Blue),
        "to do" | "purple" => Some(Colour::Purple),
        _ => None,
    }
}

/// Loads the mapping. A missing file means the defaults; an unreadable one is
/// set aside (never overwritten) with a warning.
pub fn load(path: &Path) -> (LabelConfig, Option<String>) {
    let text = match fs::read_to_string(path) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return (LabelConfig::default(), None),
        Err(e) => return (LabelConfig::default(), Some(format!("Couldn't read label settings: {e}"))),
    };
    match serde_json::from_str(&text) {
        Ok(config) => (config, None),
        Err(e) => {
            let backup = path.with_extension("json.corrupt");
            let _ = fs::rename(path, &backup);
            (
                LabelConfig::default(),
                Some(format!("Label settings were unreadable ({e}); moved them to {} and started fresh.", backup.display())),
            )
        }
    }
}

pub fn save(path: &Path, config: &LabelConfig) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_vec_pretty(config).map_err(std::io::Error::other)?;
    atomic::replace(path, &json)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn colour_words_work_but_bridge_names_wait_for_a_mapping() {
        let c = LabelConfig::default();
        assert_eq!(c.colour_of("Green"), Some(Colour::Green));
        assert_eq!(c.colour_of(" red "), Some(Colour::Red));
        assert_eq!(c.colour_of("Select"), None, "never guess a delete");
        assert_eq!(c.colour_of(""), None);
        assert_eq!(suggestion("Select"), Some(Colour::Red));
        assert_eq!(suggestion("To Do"), Some(Colour::Purple));
        assert_eq!(suggestion("Portfolio"), None);
    }

    #[test]
    fn a_renamed_bridge_maps_however_the_user_says() {
        let mut c = LabelConfig::default();
        // Bridge's defaults turned on their head.
        c.map("Select", Some(Colour::Green));
        c.map("Binned", Some(Colour::Red));
        c.map("Red", None);
        assert_eq!(c.colour_of("SELECT"), Some(Colour::Green));
        assert_eq!(c.colour_of("binned"), Some(Colour::Red));
        assert_eq!(c.colour_of("Red"), None, "an explicit null beats the colour word");
    }

    #[test]
    fn the_fallback_never_guesses_red_and_not_a_colour_means_it() {
        let mut c = LabelConfig::default();
        let f = |label: &str, color: &str| Fields {
            label: Some(label.to_string()),
            label_color: Some(color.to_string()),
            ..Default::default()
        };
        assert_eq!(c.colour_for(&f("Select", "Red")), None, "a pick would go in the bin");
        assert_eq!(c.colour_for(&f("  ", "Red")), Some(Colour::Red), "no label text: LabelColor decides");
        c.map("Select", None);
        assert_eq!(c.colour_for(&f("Select", "Yellow")), None, "the reader said not a colour");
        c.map("Select", Some(Colour::Red));
        assert_eq!(c.colour_for(&f("Select", "Green")), Some(Colour::Red), "a mapping is an answer");
    }

    #[test]
    fn label_color_is_the_fallback() {
        let mut c = LabelConfig::default();
        let f = |label: &str, color: &str| Fields {
            label: (!label.is_empty()).then(|| label.to_string()),
            label_color: (!color.is_empty()).then(|| color.to_string()),
            ..Default::default()
        };
        assert_eq!(c.colour_for(&f("", "Yellow")), Some(Colour::Yellow));
        assert_eq!(c.colour_for(&f("Unknown", "Yellow")), Some(Colour::Yellow));
        c.map("Mine", Some(Colour::Blue));
        assert_eq!(c.colour_for(&f("Mine", "Yellow")), Some(Colour::Blue));
    }

    #[test]
    fn renaming_keeps_old_files_and_refuses_clashes() {
        let mut c = LabelConfig::default();
        c.rename(Colour::Green, "Keep").unwrap();
        assert_eq!(c.name(Colour::Green), "Keep");
        assert_eq!(c.colour_of("keep"), Some(Colour::Green));
        c.rename(Colour::Green, "Good").unwrap();
        assert_eq!(c.colour_of("Keep"), Some(Colour::Green), "written under the old name");
        assert!(c.rename(Colour::Red, "good").is_err());
        assert!(c.rename(Colour::Red, "  ").is_err());
    }

    #[test]
    fn saves_as_open_json_and_survives_corruption() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("sub/labels.json");
        assert_eq!(load(&path).0, LabelConfig::default());

        let mut c = LabelConfig::default();
        c.map("Second", Some(Colour::Yellow));
        c.rename(Colour::Red, "Bin").unwrap();
        save(&path, &c).unwrap();
        assert_eq!(load(&path), (c, None));
        assert!(fs::read_to_string(&path).unwrap().contains("\"second\": \"yellow\""));

        fs::write(&path, "{ nope").unwrap();
        let (fresh, warning) = load(&path);
        assert_eq!(fresh, LabelConfig::default());
        assert!(warning.is_some() && path.with_extension("json.corrupt").exists());
    }
}
