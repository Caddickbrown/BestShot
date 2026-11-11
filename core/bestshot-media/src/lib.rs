//! Versioned local media edits. Platform decoders/renderers consume these plans.
pub mod image;
pub mod video;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MediaError(pub String);
impl std::fmt::Display for MediaError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}
impl std::error::Error for MediaError {}
impl From<std::io::Error> for MediaError {
    fn from(e: std::io::Error) -> Self {
        Self(e.to_string())
    }
}
pub type Result<T> = std::result::Result<T, MediaError>;
pub(crate) fn require(ok: bool, message: &str) -> Result<()> {
    if ok {
        Ok(())
    } else {
        Err(MediaError(message.into()))
    }
}
pub fn decode<T: for<'a> Deserialize<'a>>(json: &str) -> Result<T> {
    serde_json::from_str(json).map_err(|e| MediaError(format!("Invalid media configuration: {e}")))
}
pub fn encode<T: Serialize>(value: &T) -> Result<String> {
    serde_json::to_string(value).map_err(|e| MediaError(e.to_string()))
}
