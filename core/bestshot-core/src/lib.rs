//! BestShot's shared core, used by the Linux (Tauri) app directly and by the
//! iOS/macOS app through `bestshot-ffi`:
//!
//! - [`library`]: scanning a folder into reviewable items (Live Photo grouping)
//! - [`store`]: the per-folder `.bestshot-cull.json` (decisions + ranking)
//! - [`cull`]: moving rejects to the Trash or a `_Rejected` folder
//! - [`rank`]: pairwise Compare with transitive inference
//! - [`xmp`]: reading and minimally editing XMP packets
//! - [`embedded`]: XMP inside JPEG, TIFF, DNG and PNG files
//! - [`labels`]: colour labels and the `xmp:Label` text that maps to them
//! - [`atomic`]: replacing a file atomically
//! - [`catalog`]: a folder's metadata: the index, marking, filters, sorting

pub mod atomic;
pub mod catalog;
pub mod cull;
pub mod embedded;
pub mod labels;
pub mod library;
pub mod rank;
pub mod store;
pub mod xmp;
