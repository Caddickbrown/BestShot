//! BestShot's shared core, used by the Linux (Tauri) app directly and by the
//! iOS/macOS app through `bestshot-ffi`:
//!
//! - [`library`]: scanning a folder into reviewable items (Live Photo grouping)
//! - [`store`]: the per-folder `.bestshot-cull.json` (decisions + ranking)
//! - [`cull`]: moving rejects to the Trash or a `_Rejected` folder
//! - [`rank`]: pairwise Compare with transitive inference

pub mod cull;
pub mod library;
pub mod rank;
pub mod store;
