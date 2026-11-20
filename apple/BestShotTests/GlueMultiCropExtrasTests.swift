import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import BestShot

/// The RGBA bytes of a block of an image `width` pixels wide: columns `xs`,
/// rows `ys`. Typed step by step so the test target type-checks quickly.
func pixelBlock(_ pixels: [UInt8], width: Int, xs: Range<Int>, ys: [Int]) -> [UInt8] {
  var out: [UInt8] = []
  for y in ys {
    let start: Int = (y * width + xs.lowerBound) * 4
    let end: Int = (y * width + xs.upperBound) * 4
    out.append(contentsOf: pixels[start..<end])
  }
  return out
}

/// The v1 leftovers: Multi Crop's output strip, snapping, renumbering and
/// leaving boxes out; Glue's seam drag, before view and per-join fade; and
/// both editors on the monitor's keys.
@MainActor
final class GlueMultiCropExtrasTests: XCTestCase {

  // MARK: - Multi Crop: leave out, renumber

  func testABoxLeftOutIsNotMadeAndTheRestRenumber() throws {
    let session = MultiCropSession()
    session.source = try image(64, 48)
    session.edit.boxes = [
      .rect(id: "a", CGRect(x: 2, y: 2, width: 20, height: 20)),
      .rect(id: "b", CGRect(x: 30, y: 2, width: 20, height: 20)),
      .rect(id: "c", CGRect(x: 2, y: 26, width: 20, height: 20)),
    ]
    XCTAssertEqual(session.plan?.boxes.map(\.id), ["a", "b", "c"])
    session.toggleOff("b")
    XCTAssertEqual(session.plan?.boxes.map(\.id), ["a", "c"], "left out: not planned, so not made")
    XCTAssertEqual(session.numbers, ["a": 1, "c": 2])
    XCTAssertTrue(session.isOff("b"))
    session.undo()
    XCTAssertFalse(session.isOff("b"), "one step of Undo")
    session.toggleOff("b")
    session.toggleOff("b")
    XCTAssertEqual(session.plan?.boxes.count, 3)
    // Every box out: nothing to make.
    for id in ["a", "b", "c"] { session.toggleOff(id) }
    XCTAssertNil(session.plan)
  }

  func testRenumberTakesBoxesInTheOrderPicked() throws {
    let session = MultiCropSession()
    session.source = try image(64, 48)
    session.edit.boxes = [
      .rect(id: "a", CGRect(x: 2, y: 2, width: 20, height: 20)),
      .rect(id: "b", CGRect(x: 30, y: 2, width: 20, height: 20)),
      .rect(id: "c", CGRect(x: 2, y: 26, width: 20, height: 20)),
    ]
    session.perform(.renumber)
    XCTAssertEqual(session.renumbering, [])
    session.pick("c")
    session.pick("c")
    XCTAssertEqual(session.renumbering, ["c"], "a box is picked once")
    session.pick("a")
    session.pick("b")
    XCTAssertNil(session.renumbering, "the last box ends it")
    XCTAssertEqual(session.plan?.boxes.map(\.id), ["c", "a", "b"])
    XCTAssertEqual(session.numbers["c"], 1)
    // A new box goes on the end; Esc part-way keeps what was picked first.
    session.edit.boxes.append(.rect(id: "d", CGRect(x: 30, y: 26, width: 20, height: 20)))
    XCTAssertEqual(session.plan?.boxes.map(\.id), ["c", "a", "b", "d"])
    session.perform(.renumber)
    session.pick("d")
    session.perform(.escape)
    XCTAssertNil(session.renumbering)
    XCTAssertEqual(session.plan?.boxes.map(\.id), ["d", "c", "a", "b"])
    session.undo()
    XCTAssertEqual(session.plan?.boxes.map(\.id), ["c", "a", "b", "d"], "a renumber is one step of Undo")
  }

  // MARK: - Multi Crop: the output strip

  func testStripThumbnailsAreTheMadePixels() throws {
    let workspace = try MediaWorkspace()
    let (w, h) = (64, 48)
    let source = try image(w, h)
    var turned = CropBoxModel.rect(id: "b", CGRect(x: 30, y: 4, width: 20, height: 16))
    turned.turn = 90
    let boxes = [CropBoxModel.rect(id: "a", CGRect(x: 4, y: 6, width: 24, height: 20)), turned]
    let thumbs = MultiCropBridge.thumbnails(source: source, boxes: boxes, trim: 0, workspace: workspace)
    let a = try XCTUnwrap(thumbs["a"])
    XCTAssertEqual([a.width, a.height], [24, 20], "the preview is the whole image here, so full size")
    XCTAssertEqual([thumbs["b"]?.width, thumbs["b"]?.height], [16, 20], "turned as it will be saved")
    let original = pixels(source.preview)
    let expected: [UInt8] = pixelBlock(original, width: w, xs: 4..<28, ys: Array(6..<26))
    XCTAssertEqual(pixels(a), expected, "the strip shows the exact copy the file gets")
    // A box too small to make has no thumbnail, and doesn't stop the others.
    let tiny = CropBoxModel.rect(id: "t", CGRect(x: 0, y: 0, width: 3, height: 3))
    let some = MultiCropBridge.thumbnails(source: source, boxes: boxes + [tiny], trim: 0, workspace: workspace)
    XCTAssertNil(some["t"])
    XCTAssertNotNil(some["a"])
  }

  // MARK: - Multi Crop: snapping

  func testSnapMovesEdgesOntoImageEdgesAndOtherBoxes() {
    let lines = CropSnap.Lines(xs: [0, 100, 40], ys: [0, 80, 10], widths: [30], heights: [20])
    // 3 px from the left edge of the image: snaps there.
    XCTAssertEqual(CropSnap.shift(CGRect(x: 3, y: 30, width: 20, height: 20), to: lines, reach: 6), CGVector(dx: -3, dy: 0))
    // Right edge 2 px short of another box's left edge (40), bottom 1 px past 80.
    XCTAssertEqual(CropSnap.shift(CGRect(x: 18, y: 61, width: 20, height: 20), to: lines, reach: 6), CGVector(dx: 2, dy: -1))
    // Out of reach: nothing moves.
    XCTAssertEqual(CropSnap.shift(CGRect(x: 50, y: 30, width: 20, height: 20), to: lines, reach: 6), .zero)
    // The nearer of two lines wins.
    XCTAssertEqual(CropSnap.value(38, to: [40, 35], reach: 6), 40)
    XCTAssertEqual(CropSnap.value(36, to: [40, 35], reach: 6), 35)
    XCTAssertEqual(CropSnap.value(50, to: [40], reach: 6), 50)
  }

  func testSnapLinesComeFromTheImageAndTheOtherBoxes() {
    let boxes = [
      CropBoxModel.rect(id: "a", CGRect(x: 10, y: 20, width: 30, height: 40)),
      CropBoxModel.rect(id: "b", CGRect(x: 50, y: 20, width: 30, height: 40)),
      CropBoxModel(id: "r", cx: 50, cy: 50, w: 10, h: 10, angle: 12),
    ]
    let lines = CropSnap.lines(boxes: boxes, except: "b", width: 200, height: 100)
    XCTAssertTrue(Set(lines.xs).isSuperset(of: [0, 200, 10, 40]))
    XCTAssertTrue(Set(lines.ys).isSuperset(of: [0, 100, 20, 60]))
    XCTAssertFalse(lines.xs.contains(50), "not the box being dragged")
    XCTAssertEqual(lines.xs.count, 6, "the image, a, and the turned box's bounds")
    XCTAssertEqual(lines.widths, [30], "only straight boxes give sizes")
    XCTAssertEqual(lines.heights, [40])
  }

  func testMultiCropNewKeys() {
    func c(_ k: KeyEquivalent, _ text: String, _ m: EventModifiers = []) -> MultiCropCommand? {
      MultiCropKeymap.command(key: k, characters: text, modifiers: m)
    }
    XCTAssertEqual(c(KeyEquivalent("3"), "#", .shift), .renumber)
    XCTAssertEqual(c(KeyEquivalent("v"), "v"), .toggleStrip)
    XCTAssertEqual(c(.space, " "), .toggleOff)
  }

  // MARK: - Glue: seam, before, per-join fade

  func testDraggingASeamMovesItInsideItsOverlap() throws {
    var config = GlueConfiguration()
    config.sources = [.init(ref: "a", width: 100, height: 50), .init(ref: "b", width: 100, height: 50)]
    config.orientation = "horizontal"
    config.join_px = -40
    let plan = try config.plan()
    XCTAssertEqual(plan.joins[0].seam_px, 80)
    XCTAssertEqual(GlueSession.seamHit(plan, at: CGPoint(x: 84, y: 10), reach: 6, line: true), 0)
    XCTAssertNil(GlueSession.seamHit(plan, at: CGPoint(x: 90, y: 10), reach: 6, line: true))
    XCTAssertNil(GlueSession.seamHit(plan, at: CGPoint(x: 80, y: 10), reach: 6, line: false), "only a line's seams drag")
    var moved = GlueSession.seamMoved(config, plan: plan, join: 0, by: 10)
    XCTAssertEqual(try moved.plan().joins[0].seam_px, 90)
    moved = GlueSession.seamMoved(moved, plan: try moved.plan(), join: 0, by: 500)
    XCTAssertEqual(moved.seams[0].position, 1, "kept inside the overlap")
    config.join_px = 10
    XCTAssertNil(GlueSession.seamHit(try config.plan(), at: CGPoint(x: 105, y: 10), reach: 6, line: true), "a gap has no seam")
  }

  func testBeforeIsTheSamePhotosButtedWithNothingSet() throws {
    var config = GlueConfiguration()
    config.sources = [.init(ref: "a", width: 100, height: 50), .init(ref: "b", width: 100, height: 50)]
    config.orientation = "horizontal"
    config.join_px = -40
    config.fade_px = 20
    config.border_px = 10
    config.offsets_px = [0, 6]
    config.seams = [.init(position: 0.2, join_px: -30, fade_px: 4)]
    let before = try config.before.plan()
    XCTAssertEqual([before.width, before.height], [200, 50])
    XCTAssertEqual(before.items.map(\.x), [0, 100])
    XCTAssertEqual(config.before.orientation, "horizontal", "the layout stays")
    config.arrangement = "free"
    XCTAssertEqual(config.before.arrangement, "line")
  }

  func testEachJoinCanHaveItsOwnFade() throws {
    var config = GlueConfiguration()
    config.sources = (0..<3).map { .init(ref: "\($0)", width: 100, height: 50) }
    config.orientation = "horizontal"
    config.join_px = -40
    config.fade_px = 20
    config.seams = [.init(), .init(fade_px: 0)]
    let plan = try config.plan()
    XCTAssertEqual(plan.items[1].ramps.left.map { $0.b - $0.a }, 20)
    XCTAssertEqual(plan.items[2].ramps.left.map { $0.b - $0.a }, 0, "its own straight edge")
  }

  func testGlueSessionJoinFadeAndEscape() throws {
    let session = GlueSession()
    session.images = [try image(100, 50), try image(100, 50)]
    session.edit.sources = session.images.map { .init(ref: $0.name, width: $0.width, height: $0.height) }
    session.edit.orientation = "horizontal"
    session.edit.join_px = -40
    session.edit.fade_px = 20
    XCTAssertNil(session.focusedJoin)
    session.focused = 1
    XCTAssertEqual(session.focusedJoin, 0)
    session.perform(.joinFade(10))
    XCTAssertEqual(session.fade(atJoin: 0), 30)
    XCTAssertTrue(session.hasOwnFade(0))
    XCTAssertEqual(session.edit.fade_px, 20, "the shared fade is unchanged")
    session.setJoinFade(0, nil)
    XCTAssertFalse(session.hasOwnFade(0))
    session.perform(.before(true))
    XCTAssertEqual(session.shownPlan?.width, 200)
    XCTAssertEqual(session.plan?.width, 160)
    XCTAssertTrue(session.perform(.escape))
    XCTAssertFalse(session.before, "Esc leaves before first")
    XCTAssertTrue(session.perform(.escape))
    XCTAssertNil(session.focused)
    XCTAssertFalse(session.perform(.escape), "nothing left to close here")
  }

  func testGlueNewKeys() {
    func c(_ k: KeyEquivalent, _ text: String, _ m: EventModifiers = []) -> GlueCommand? {
      GlueKeymap.command(key: k, characters: text, modifiers: m, vertical: false, free: false)
    }
    XCTAssertEqual(c(KeyEquivalent("\\"), "\\"), .before(nil))
    XCTAssertEqual(c(KeyEquivalent("]"), "]", .option), .joinFade(10))
    XCTAssertEqual(c(KeyEquivalent("["), "[", .option), .joinFade(-10))
    XCTAssertEqual(c(KeyEquivalent("]"), "]"), .fade(10))
  }

  // MARK: - Monitor Mode

  func testMonitorKeysReachTheOpenTool() throws {
    let desk = MonitorDesk(library: FakeMonitorLibrary(), marks: PhotoMarkStore(url: FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathComponent("marks.json")))
    desk.isConnected = true
    desk.setLocked(false)
    let session = MultiCropSession()
    session.source = try image(64, 48)
    session.edit.boxes = [.rect(id: "a", CGRect(x: 2, y: 2, width: 20, height: 20)),
                          .rect(id: "b", CGRect(x: 30, y: 2, width: 20, height: 20))]
    ToolHolder.shared.show(.multiCrop(session))
    defer { ToolHolder.shared.hide(session) }
    XCTAssertEqual(desk.situation.surface, .tool)
    XCTAssertEqual(desk.situation.tool, .multiCrop)
    XCTAssertTrue(desk.keys.contains { $0.label.contains("Renumber") }, "the hint bar shows the editor's keys")
    XCTAssertTrue(desk.handle(MonitorPress(.tab)))
    XCTAssertEqual(session.focused, "a")
    XCTAssertTrue(desk.handle(MonitorPress(.right, .shift)))
    XCTAssertEqual(session.box("a")?.cx, 22)
    XCTAssertTrue(desk.handle(MonitorPress(.char("3"), .shift, text: "#")))
    XCTAssertEqual(session.renumbering, [])
    XCTAssertTrue(desk.handle(MonitorPress(.escape)))
    XCTAssertNil(session.renumbering)
    session.focused = "a"
    XCTAssertTrue(desk.handle(MonitorPress(.char(" "), text: " ")))
    XCTAssertTrue(session.isOff("a"))
    XCTAssertTrue(desk.handle(MonitorPress(.char("z"), .command)))
    XCTAssertFalse(session.isOff("a"), "⌘Z is the editor's Undo while it's up")
    // Esc with nothing focused and nowhere to close: the phone hears it.
    session.focused = nil
    XCTAssertFalse(desk.handle(MonitorPress(.escape)))
    ToolHolder.shared.hide(session)
    XCTAssertNotEqual(desk.situation.surface, .tool)
  }

  func testMonitorKeysReachGlue() throws {
    let desk = MonitorDesk(library: FakeMonitorLibrary(), marks: PhotoMarkStore(url: FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathComponent("marks.json")))
    desk.isConnected = true
    desk.setLocked(false)
    let session = GlueSession()
    session.images = [try image(100, 50), try image(100, 50)]
    session.edit.sources = session.images.map { .init(ref: $0.name, width: $0.width, height: $0.height) }
    ToolHolder.shared.show(.glue(session))
    defer { ToolHolder.shared.hide(session) }
    XCTAssertEqual(desk.situation.tool, .glue)
    let wasVertical = session.vertical
    XCTAssertTrue(desk.handle(MonitorPress(.char("o"), text: "o")))
    XCTAssertEqual(session.vertical, !wasVertical, "o flips the layout")
    XCTAssertTrue(desk.handle(MonitorPress(.char("\\"), text: "\\")))
    XCTAssertTrue(session.before, "on the monitor, \\ switches before on and off")
    XCTAssertTrue(desk.handle(MonitorPress(.char("\\"), text: "\\")))
    XCTAssertFalse(session.before)
    XCTAssertTrue(desk.handle(MonitorPress(.char("="), .command)))
    XCTAssertGreaterThan(session.zoom, 1)
  }

  func testMonitorPressBecomesEditorKeys() {
    let shiftR = ToolKeyPress(MonitorPress(.char("r"), .shift, text: "R"))
    XCTAssertEqual(shiftR.characters, "R")
    XCTAssertEqual(shiftR.modifiers, .shift)
    let chord = ToolKeyPress(MonitorPress(.char("["), .command))
    XCTAssertEqual(chord.characters, "[")
    XCTAssertEqual(chord.modifiers, .command)
    XCTAssertEqual(ToolKeyPress(MonitorPress(.backspace)).key, .delete)
    XCTAssertEqual(ToolKeyPress(MonitorPress(.enter)).key, .return)
    XCTAssertEqual(ToolKeyPress(MonitorPress(.left, .option)).key, .leftArrow)
  }

  // MARK: - Helpers

  private func image(_ w: Int, _ h: Int) throws -> ToolImage {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("BestShot-extras-\(UUID().uuidString).png")
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    var p: [UInt8] = []
    for y in 0..<h { for x in 0..<w { p += [UInt8((x * 9) % 256), UInt8((y * 11) % 256), UInt8((x * y) % 256), 255] } }
    let provider = try XCTUnwrap(CGDataProvider(data: Data(p) as CFData))
    let cg = try XCTUnwrap(CGImage(
      width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, cg, nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
    return try ToolImaging.inspect(url)
  }

  private func pixels(_ image: CGImage) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
    out.withUnsafeMutableBytes { data in
      let context = CGContext(
        data: data.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return out
  }
}
