//! Shared vectors: any shell (Swift, a later Linux UI) can replay these JSON
//! files against its own bridge and must get the same plans.
//! `BLESS=1 cargo test -p bestshot-media --test vectors` rewrites the expected
//! values after a deliberate change.
use bestshot_media::{glue, multicrop};
use serde_json::{json, Value};
use std::path::PathBuf;

fn path(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/vectors").join(name)
}

fn check(name: &str, run: impl Fn(&Value) -> Value) {
    let file = path(name);
    let mut doc: Value = serde_json::from_str(&std::fs::read_to_string(&file).unwrap()).unwrap();
    let bless = std::env::var("BLESS").is_ok();
    for case in doc["cases"].as_array_mut().unwrap() {
        let got = run(case);
        if bless {
            case["expect"] = got;
        } else {
            assert_eq!(got, case["expect"], "{name}: {}", case["name"]);
        }
    }
    if bless {
        std::fs::write(&file, serde_json::to_string_pretty(&doc).unwrap() + "\n").unwrap();
    }
}

#[test]
fn glue_vectors() {
    check("glue.json", |case| {
        let config: glue::Glue = serde_json::from_value(case["config"].clone()).unwrap();
        match config.plan() {
            Ok(p) => json!({
                "width": p.width, "height": p.height, "orientation": p.orientation,
                "items": p.items.iter().map(|i| json!([i.index, i.x, i.y, i.w, i.h])).collect::<Vec<_>>(),
                "ramps": p.items.iter().map(|i| serde_json::to_value(i.ramps).unwrap()).collect::<Vec<_>>(),
                "upscaled": p.upscaled, "max_overlap_px": p.max_overlap_px,
            }),
            Err(e) => json!({ "error": e.0 }),
        }
    });
}

#[test]
fn multicrop_vectors() {
    check("multicrop.json", |case| {
        if let Some(quads) = case.get("tidy") {
            let quads: Vec<[[f64; 2]; 4]> = serde_json::from_value(quads.clone()).unwrap();
            let size = &case["size"];
            let boxes = multicrop::tidy_boxes(&quads, size[0].as_u64().unwrap() as u32, size[1].as_u64().unwrap() as u32);
            return serde_json::to_value(boxes).unwrap();
        }
        let config: multicrop::MultiCrop = serde_json::from_value(case["config"].clone()).unwrap();
        match config.plan() {
            Ok(p) => json!(p.boxes.iter().map(|b| json!({
                "id": b.id, "number": b.number, "name": b.name, "width": b.width, "height": b.height, "exact": b.exact
            })).collect::<Vec<_>>()),
            Err(e) => json!({ "error": e.0 }),
        }
    });
}
