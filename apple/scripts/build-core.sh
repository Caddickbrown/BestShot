#!/usr/bin/env bash
# Builds the shared Rust core (core/) for iOS and macOS and produces:
#   apple/Frameworks/BestShotCore.xcframework   (static library + C headers)
#   apple/BestShot/Generated/BestShotCore.swift (UniFFI Swift bindings)
# Run on a Mac with Rust installed (https://rustup.rs), before `xcodegen generate`.
set -euo pipefail

APPLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="$APPLE_DIR/../core"
OUT_FW="$APPLE_DIR/Frameworks/BestShotCore.xcframework"
OUT_SWIFT="$APPLE_DIR/BestShot/Generated"
WORK="$CORE_DIR/target/apple"
LIB=libbestshot_ffi.a

MAC_TARGETS=(aarch64-apple-darwin x86_64-apple-darwin)
IOS_TARGET=aarch64-apple-ios
SIM_TARGETS=(aarch64-apple-ios-sim x86_64-apple-ios)

cd "$CORE_DIR"
rustup target add "${MAC_TARGETS[@]}" "$IOS_TARGET" "${SIM_TARGETS[@]}" >/dev/null

export MACOSX_DEPLOYMENT_TARGET=14.0
export IPHONEOS_DEPLOYMENT_TARGET=17.0
for target in "${MAC_TARGETS[@]}" "$IOS_TARGET" "${SIM_TARGETS[@]}"; do
  echo "==> cargo build --target $target"
  cargo build -p bestshot-ffi --release --target "$target"
done

rm -rf "$WORK" && mkdir -p "$WORK/macos" "$WORK/sim" "$WORK/headers" "$WORK/bindings"

echo "==> Generating Swift bindings"
cargo run -q -p bestshot-ffi --bin uniffi-bindgen -- generate \
  --library "target/aarch64-apple-darwin/release/libbestshot_ffi.dylib" \
  --language swift --out-dir "$WORK/bindings"

cp "$WORK/bindings/BestShotCoreFFI.h" "$WORK/headers/"
cp "$WORK/bindings/BestShotCoreFFI.modulemap" "$WORK/headers/module.modulemap"
mkdir -p "$OUT_SWIFT"
cp "$WORK/bindings/BestShotCore.swift" "$OUT_SWIFT/BestShotCore.swift"

echo "==> Universal libraries"
lipo -create $(for t in "${MAC_TARGETS[@]}"; do echo "target/$t/release/$LIB"; done) -output "$WORK/macos/$LIB"
lipo -create $(for t in "${SIM_TARGETS[@]}"; do echo "target/$t/release/$LIB"; done) -output "$WORK/sim/$LIB"

echo "==> XCFramework"
rm -rf "$OUT_FW"
mkdir -p "$(dirname "$OUT_FW")"
xcodebuild -create-xcframework \
  -library "$WORK/macos/$LIB" -headers "$WORK/headers" \
  -library "target/$IOS_TARGET/release/$LIB" -headers "$WORK/headers" \
  -library "$WORK/sim/$LIB" -headers "$WORK/headers" \
  -output "$OUT_FW"

echo "Done: $OUT_FW and $OUT_SWIFT/BestShotCore.swift"
