import CryptoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import BestShot

/// Glue and Multi Crop end to end through the Rust core: pixels, names,
/// metadata, and that originals are never written.
final class GlueMultiCropTests: XCTestCase {

  // MARK: - Multi Crop

  func testMultiCropExactBoxIsPixelIdenticalAndTheSourceIsUntouched() throws {
    let workspace = try MediaWorkspace()
    let folder = try folder()
    let source = folder.appendingPathComponent("Scan_004.tif")
    let (w, h) = (64, 48)
    try writeImage(pattern(w, h), width: w, height: h, to: source, type: .tiff, keywords: ["Holiday", "1987"], rated: true, gps: true)
    let before = try hashes(folder)
    let image = try ToolImaging.inspect(source)
    XCTAssertEqual(image.keywords, ["Holiday", "1987"])
    let boxes = [
      CropBoxModel.rect(id: "a", CGRect(x: 4, y: 6, width: 24, height: 20)),
      CropBoxModel(id: "b", cx: 46, cy: 30, w: 20, h: 18, angle: 4),
    ]
    let made = try MultiCropBridge.export(
      source: image, boxes: boxes, trim: 0, format: .png, existing: ToolImaging.names(in: folder),
      workspace: workspace, job: MediaRenderJob(), progress: { _ in })
    XCTAssertEqual(made.map(\.lastPathComponent), ["Scan_004-1.png", "Scan_004-2.png"])
    let original = try rgba(source)
    var expected: [UInt8] = []
    for y in 6..<26 { for x in 4..<28 { expected += original[(y * w + x) * 4..<(y * w + x) * 4 + 4] } }
    XCTAssertEqual(try rgba(made[0]), expected, "an axis-aligned box is an exact copy")
    let second = try XCTUnwrap(CGImageSourceCreateWithURL(made[1] as CFURL, nil))
    let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(second, 0, nil) as? [CFString: Any])
    XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 20)
    XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 18)
    try assertNewFileMetadata(made[0], keywords: ["Holiday", "1987"], derivedFrom: "Scan_004.tif")
    // Published beside the source: never replacing, never touching the original.
    let published = try ToolImaging.publish(made[0], as: made[0].lastPathComponent, in: folder)
    XCTAssertThrowsError(try ToolImaging.publish(made[0], as: made[0].lastPathComponent, in: folder))
    var after = try hashes(folder)
    after.removeValue(forKey: published.lastPathComponent)
    XCTAssertEqual(after, before, "the original's bytes are unchanged")
  }

  func testMultiCropTurnsAndWritesJPEGByDefault() throws {
    UserDefaults.standard.removeObject(forKey: "tools.multicrop.format")
    XCTAssertEqual(ToolOutputFormat.saved("multicrop"), .jpeg)
    let workspace = try MediaWorkspace()
    let folder = try folder()
    let source = folder.appendingPathComponent("Sheet.png")
    try writeImage(pattern(80, 60), width: 80, height: 60, to: source, type: .png)
    let before = try hashes(folder)
    let image = try ToolImaging.inspect(source)
    var box = CropBoxModel.rect(id: "a", CGRect(x: 10, y: 10, width: 40, height: 20))
    box.turn = 90
    let made = try MultiCropBridge.export(
      source: image, boxes: [box], trim: 2, format: .jpeg, existing: [], workspace: workspace,
      job: MediaRenderJob(), progress: { _ in })
    XCTAssertEqual(made.first?.lastPathComponent, "Sheet-1.jpg")
    let out = try XCTUnwrap(CGImageSourceCreateWithURL(made[0] as CFURL, nil))
    let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(out, 0, nil) as? [CFString: Any])
    XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 16, "turned: height becomes width")
    XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 36)
    XCTAssertEqual((props[kCGImagePropertyOrientation] as? Int) ?? 1, 1)
    XCTAssertEqual(try hashes(folder), before)
  }

  func testUseLastCropScalesBoxesToTheNextImage() {
    let box = CropBoxModel.rect(id: "a", CGRect(x: 100, y: 50, width: 200, height: 100))
    let n = box.normalised(width: 1000, height: 500)
    let next = n.scaled(sx: 2000, sy: 1000)
    XCTAssertEqual(next.cx, 400, accuracy: 1e-9)
    XCTAssertEqual(next.w, 400, accuracy: 1e-9)
    XCTAssertEqual(next.h, 200, accuracy: 1e-9)
  }

  func testCornersToggleKeepsTheBox() {
    var box = CropBoxModel(id: "a", cx: 50, cy: 40, w: 30, h: 20, angle: 10)
    let quad = box.quad
    box.toggleCorners()
    XCTAssertFalse(box.rect)
    XCTAssertEqual(box.corners, quad)
    box.toggleCorners()
    XCTAssertTrue(box.rect)
    XCTAssertEqual(box.w, 30, accuracy: 0.5)
    XCTAssertEqual(box.angle, 10, accuracy: 0.1)
  }

  // MARK: - Glue

  func testGlueSideBySideIsExactOutsideTheJoinAndKeepsKeywordsNotStars() throws {
    let workspace = try MediaWorkspace()
    let folder = try folder()
    let a = folder.appendingPathComponent("IMG_0012.tif")
    let b = folder.appendingPathComponent("IMG_0013.tif")
    try writeImage(pattern(20, 30, seed: 1), width: 20, height: 30, to: a, type: .tiff, keywords: ["Beach"], rated: true, gps: true)
    try writeImage(pattern(10, 30, seed: 7), width: 10, height: 30, to: b, type: .tiff, keywords: ["Beach", "Dog"])
    let before = try hashes(folder)
    let images = try [ToolImaging.inspect(a), ToolImaging.inspect(b)]
    var config = GlueConfiguration()
    config.sources = images.map { .init(ref: $0.name, width: $0.width, height: $0.height) }
    config.orientation = "horizontal"
    let plan = try config.plan()
    XCTAssertEqual([plan.width, plan.height], [30, 30])
    let name = mediaGlueName(stem: images[0].stem, ext: "png", existing: ToolImaging.names(in: folder))
    XCTAssertEqual(name, "IMG_0012-glued.png")
    let url = try GlueBridge.export(config: config, images: images, format: .png, name: name, workspace: workspace,
                                    job: MediaRenderJob(), progress: { _ in })
    let (pa, pb, out) = (try rgba(a), try rgba(b), try rgba(url))
    for y in 0..<30 {
      for x in 0..<30 {
        let got = Array(out[(y * 30 + x) * 4..<(y * 30 + x) * 4 + 4])
        let want = x < 20 ? Array(pa[(y * 20 + x) * 4..<(y * 20 + x) * 4 + 4]) : Array(pb[(y * 10 + x - 20) * 4..<(y * 10 + x - 20) * 4 + 4])
        XCTAssertEqual(got, want, "pixel \(x),\(y)")
      }
    }
    try assertNewFileMetadata(url, keywords: ["Beach", "Dog"], derivedFrom: "IMG_0012.tif")
    XCTAssertEqual(try hashes(folder), before, "the originals' bytes are unchanged")
  }

  func testGlueGridFreeAndBlurredBackgroundExport() throws {
    let workspace = try MediaWorkspace()
    let folder = try folder()
    let urls = try (0..<3).map { i -> URL in
      let url = folder.appendingPathComponent("P\(i).png")
      try writeImage(pattern(30, 20, seed: i * 5), width: 30, height: 20, to: url, type: .png)
      return url
    }
    let images = try urls.map { try ToolImaging.inspect($0) }
    var config = GlueConfiguration()
    config.sources = images.map { .init(ref: $0.name, width: $0.width, height: $0.height) }
    config.orientation = "horizontal"
    config.arrangement = "free"
    config.free = [.init(x: 0, y: 0, w: 30), .init(x: 40, y: 15, w: 15), .init(x: 10, y: 30, w: 60)]
    config.background.kind = "blur"
    config.fade_px = 3
    let plan = try config.plan()
    XCTAssertEqual([plan.width, plan.height], [70, 70])
    let url = try GlueBridge.export(config: config, images: images, format: .jpeg, name: "P0-glued.jpg", workspace: workspace,
                                    job: MediaRenderJob(), progress: { _ in })
    let out = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(out, 0, nil) as? [CFString: Any])
    XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 70)
    config.arrangement = "grid"
    config.columns = 2
    XCTAssertEqual(try config.plan().items.count, 3)
  }

  func testStagingTurnsClockwise() throws {
    let workspace = try MediaWorkspace()
    let url = workspace.url("png")
    // Red on the left, blue on the right.
    try writeImage([255, 0, 0, 255, 0, 0, 255, 255], width: 2, height: 1, to: url, type: .png)
    let image = try ToolImaging.inspect(url)
    let staged = workspace.url("rgba")
    let size = try ToolImaging.stage(image, turn: 90, space: CGColorSpace(name: CGColorSpace.sRGB)!, to: staged)
    XCTAssertEqual(size.0, 1)
    XCTAssertEqual(size.1, 2)
    let bytes = [UInt8](try Data(contentsOf: staged))
    XCTAssertEqual(Array(bytes[0..<4]), [255, 0, 0, 255], "a clockwise turn puts the left edge on top")
    XCTAssertEqual(Array(bytes[4..<8]), [0, 0, 255, 255])
  }

  func testLineUpFindsTheOverlap() throws {
    let workspace = try MediaWorkspace()
    let (w, h) = (400, 200)
    // Blocky noise: something for the registration to hold on to.
    var rng = SystemRandomNumberGenerator()
    let blocks = (0..<(w / 8 * h / 8)).map { _ in UInt8.random(in: 0...255, using: &rng) }
    var whole: [UInt8] = []
    for y in 0..<h { for x in 0..<w { let v = blocks[(y / 8) * (w / 8) + x / 8]; whole += [v, 255 &- v, v / 2, 255] } }
    func crop(_ x0: Int, _ x1: Int) -> [UInt8] {
      var out: [UInt8] = []
      for y in 0..<h { out += whole[(y * w + x0) * 4..<(y * w + x1) * 4] }
      return out
    }
    let a = workspace.url("png"), b = workspace.url("png")
    try writeImage(crop(0, 250), width: 250, height: h, to: a, type: .png)
    try writeImage(crop(150, 400), width: 250, height: h, to: b, type: .png)
    let images = try [ToolImaging.inspect(a), ToolImaging.inspect(b)]
    var config = GlueConfiguration()
    config.sources = images.map { .init(ref: $0.name, width: $0.width, height: $0.height) }
    config.orientation = "horizontal"
    let lined = try XCTUnwrap(try GlueBridge.lineUp(config, images: images))
    let join = try XCTUnwrap(lined.seams.first?.join_px)
    XCTAssertEqual(Double(join), -100, accuracy: 3)
    XCTAssertEqual(Double(lined.offsets_px[1]), 0, accuracy: 3)
  }

  // MARK: - Keys and Undo

  private func key(_ text: String) -> KeyEquivalent { KeyEquivalent(Character(text)) }

  func testMultiCropKeys() {
    func c(_ k: KeyEquivalent, _ text: String = "", _ m: EventModifiers = []) -> MultiCropCommand? {
      MultiCropKeymap.command(key: k, characters: text, modifiers: m)
    }
    XCTAssertEqual(c(key("f"), "f"), .find)
    XCTAssertEqual(c(key("n"), "n"), .add)
    XCTAssertEqual(c(key("d"), "d", .command), .duplicate)
    XCTAssertEqual(c(key("r"), "r"), .turn(90))
    XCTAssertEqual(c(key("R"), "R", .shift), .turn(-90))
    XCTAssertEqual(c(key("]"), "]", .command), .turn(90))
    XCTAssertEqual(c(key("["), "["), .rotate(-0.1))
    XCTAssertEqual(c(key("]"), "]", .shift), .rotate(1))
    XCTAssertEqual(c(key("l"), "l"), .useLast)
    XCTAssertEqual(c(key("p"), "p"), .toggleCorners)
    XCTAssertEqual(c(.leftArrow), .move(dx: -1, dy: 0))
    XCTAssertEqual(c(.downArrow, "", .shift), .move(dx: 0, dy: 10))
    XCTAssertEqual(c(.rightArrow, "", .option), .resize(dw: 1, dh: 0))
    XCTAssertEqual(c(.tab), .next)
    XCTAssertEqual(c(.tab, "", .shift), .previous)
    XCTAssertEqual(c(.delete), .remove)
    XCTAssertEqual(c(.return), .make)
    XCTAssertEqual(c(.escape), .escape)
    XCTAssertEqual(c(key("z"), "z", .command), .undo)
    XCTAssertEqual(c(key("z"), "z", [.command, .shift]), .redo)
    XCTAssertEqual(c(key("="), "=", .command), .zoom(.zoomIn))
    XCTAssertEqual(c(key("0"), "0", .command), .zoom(.fit))
    XCTAssertNil(c(key("q"), "q"))
  }

  func testGlueKeys() {
    func c(_ k: KeyEquivalent, _ text: String = "", _ m: EventModifiers = [], vertical: Bool = false, free: Bool = false) -> GlueCommand? {
      GlueKeymap.command(key: k, characters: text, modifiers: m, vertical: vertical, free: free)
    }
    XCTAssertEqual(c(key("o"), "o"), .flipLayout)
    XCTAssertEqual(c(key("m"), "m"), .cycleSize)
    XCTAssertEqual(c(key("a"), "a"), .cycleArrangement)
    XCTAssertEqual(c(.rightArrow), .seam(1))
    XCTAssertEqual(c(.upArrow, "", .shift), .offset(-10))
    XCTAssertEqual(c(.upArrow, vertical: true), .seam(-1), "stacked: up and down move the seam")
    XCTAssertEqual(c(.leftArrow, vertical: true), .offset(-1))
    XCTAssertEqual(c(.leftArrow, free: true), .move(dx: -1, dy: 0))
    XCTAssertEqual(c(.leftArrow, "", .command), .moveEarlier)
    XCTAssertEqual(c(key("-"), "-"), .join(10), "less overlap")
    XCTAssertEqual(c(key("="), "="), .join(-10), "more overlap")
    XCTAssertEqual(c(key("]"), "]"), .fade(10))
    XCTAssertEqual(c(key("r"), "r"), .turn(90))
    XCTAssertEqual(c(key("R"), "R", .shift), .turn(-90))
    XCTAssertEqual(c(key("l"), "l"), .lineUp)
    XCTAssertEqual(c(key("-"), "-", .command), .zoom(.zoomOut))
    XCTAssertEqual(c(.return), .glue)
    XCTAssertEqual(c(.escape), .escape)
  }

  func testEditHistoryOneDragIsOneStep() {
    var history = EditHistory<Int>()
    history.record(0, now: 1)
    history.begin(1)
    history.end(5)
    XCTAssertEqual(history.undo(5), 1)
    XCTAssertEqual(history.undo(1), 0)
    XCTAssertNil(history.undo(0))
    XCTAssertEqual(history.redo(0), 1)
    history.record(1, now: 2)
    XCTAssertFalse(history.canRedo, "a new change clears Redo")
  }

  // MARK: - Helpers

  private func assertNewFileMetadata(_ url: URL, keywords: [String], derivedFrom: String, file: StaticString = #filePath, line: UInt = #line) throws {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let meta = try XCTUnwrap(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    XCTAssertEqual(ToolImaging.keywords(source: source, properties: props), keywords, "keywords carried", file: file, line: line)
    XCTAssertNil(CGImageMetadataCopyTagWithPath(meta, nil, "xmp:Rating" as CFString), "no stars on a new file", file: file, line: line)
    XCTAssertNil(CGImageMetadataCopyTagWithPath(meta, nil, "xmp:Label" as CFString), "no label on a new file", file: file, line: line)
    let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
    XCTAssertEqual(gps?[kCGImagePropertyGPSLatitude] as? Double, 51.5, "location kept", file: file, line: line)
    let derived = CGImageMetadataCopyStringValueWithPath(meta, nil, "xmpMM:DerivedFrom.stRef:filePath" as CFString) as String?
    XCTAssertEqual(derived, derivedFrom, file: file, line: line)
  }

  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("BestShot-tooltest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func hashes(_ folder: URL) throws -> [String: String] {
    var out: [String: String] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
      let data = try Data(contentsOf: folder.appendingPathComponent(name))
      out[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    return out
  }

  private func pattern(_ w: Int, _ h: Int, seed: Int = 0) -> [UInt8] {
    var p: [UInt8] = []
    for y in 0..<h { for x in 0..<w { p += [UInt8((x * 9 + seed * 13) % 256), UInt8((y * 11 + seed) % 256), UInt8((x * y + seed) % 256), 255] } }
    return p
  }

  private func writeImage(
    _ pixels: [UInt8], width: Int, height: Int, to url: URL, type: UTType, keywords: [String] = [], rated: Bool = false, gps: Bool = false
  ) throws {
    let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
    let image = try XCTUnwrap(
      CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    let meta = CGImageMetadataCreateMutable()
    if !keywords.isEmpty, let tag = CGImageMetadataTagCreate(
      kCGImageMetadataNamespaceDublinCore, kCGImageMetadataPrefixDublinCore, "subject" as CFString, .arrayUnordered, keywords as CFArray) {
      CGImageMetadataSetTagWithPath(meta, nil, "dc:subject" as CFString, tag)
    }
    if rated {
      CGImageMetadataSetValueWithPath(meta, nil, "xmp:Rating" as CFString, "5" as CFString)
      CGImageMetadataSetValueWithPath(meta, nil, "xmp:Label" as CFString, "Red" as CFString)
    }
    if gps {
      _ = CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyGPSDictionary, kCGImagePropertyGPSLatitude, 51.5 as CFNumber)
      _ = CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyGPSDictionary, kCGImagePropertyGPSLatitudeRef, "N" as CFString)
      _ = CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeOriginal, "2024:06:01 10:00:00" as CFString)
    }
    CGImageDestinationAddImageAndMetadata(dest, image, meta, nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
  }

  private func rgba(_ url: URL) throws -> [UInt8] {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { data in
      let context = try XCTUnwrap(
        CGContext(
          data: data.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels
  }
}
