import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Glue's edit, the same JSON the core plans (bestshot-media `glue.rs`).
struct GlueConfiguration: Codable, Equatable {
  struct Source: Codable, Equatable {
    var ref: String
    var width: Int
    var height: Int
    var turn = 0
  }
  struct Seam: Codable, Equatable {
    var position = 0.5
    var join_px: Int?
  }
  struct Place: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
  }
  struct Background: Codable, Equatable {
    var kind = "colour"
    var colour = "#FFFFFF"
  }
  var schema_version = 1
  var sources: [Source] = []
  /// auto, horizontal, vertical
  var orientation = "auto"
  /// line, grid, free
  var arrangement = "line"
  var columns = 0
  /// match_smaller, match_larger, keep
  var size = "match_smaller"
  var align = "centre"
  var join_px = 0
  var fade_px = 0
  var seams: [Seam] = []
  var offsets_px: [Int] = []
  var offset_fill = "crop"
  var border_px = 0
  var background = Background()
  var free: [Place] = []
  var max_pixels: UInt64 = ToolImaging.maxOutputPixels

  func json() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
  func plan() throws -> GluePlan {
    try JSONDecoder().decode(GluePlan.self, from: Data(mediaGluePlan(configJson: json()).utf8))
  }
}

struct GlueRamp: Codable, Equatable {
  let a: Double
  let b: Double
}
struct GlueRamps: Codable, Equatable {
  let left: GlueRamp?
  let top: GlueRamp?
  let right: GlueRamp?
  let bottom: GlueRamp?
}
struct GluePlacement: Codable, Equatable {
  let index: Int
  let x: Int
  let y: Int
  let w: Int
  let h: Int
  let scale: Double
  let ramps: GlueRamps
  var frame: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}
struct GlueJoin: Codable, Equatable {
  let join_px: Int
  let seam_px: Double
  let ramp: GlueRamp?
  let axis: String
}
struct GluePlan: Codable, Equatable {
  let orientation: String
  let width: Int
  let height: Int
  let items: [GluePlacement]
  let joins: [GlueJoin]
  let upscaled: [Int]
  let max_overlap_px: Int
}

enum GlueBridge {
  /// Line up (Vision): each neighbouring pair's overlap and cross-axis offset
  /// from a pure translation between their previews at planned size. Nil when
  /// the result isn't plausible, and nothing changes.
  static func lineUp(_ config: GlueConfiguration, images: [ToolImage]) throws -> GlueConfiguration? {
    let plan = try config.plan()
    guard config.arrangement == "line" else { return nil }
    let vertical = plan.orientation == "vertical"
    var out = config
    out.offsets_px = Array(repeating: 0, count: config.sources.count)
    out.seams = (0..<max(config.sources.count - 1, 0)).map { k in config.seams.indices.contains(k) ? config.seams[k] : .init() }
    var offset = 0
    for k in 0..<(plan.items.count - 1) {
      let (a, b) = (plan.items[k], plan.items[k + 1])
      guard let ra = scaledPreview(images[a.index], turn: config.sources[a.index].turn, width: a.w, height: a.h),
        let rb = scaledPreview(images[b.index], turn: config.sources[b.index].turn, width: b.w, height: b.h)
      else { return nil }
      let request = VNTranslationalImageRegistrationRequest(targetedCGImage: rb.image, options: [:])
      try VNImageRequestHandler(cgImage: ra.image, options: [:]).perform([request])
      guard let t = request.results?.first?.alignmentTransform else { return nil }
      // Vision's y runs up; the shift is in preview pixels.
      let tx = Double(t.tx) / ra.scale
      let ty = -Double(t.ty) / ra.scale
      let along = vertical ? ty : tx
      let across = vertical ? tx : ty
      let length = vertical ? Double(a.h) : Double(a.w)
      let overlap = Int((length - along).rounded())
      let narrower = vertical ? min(a.h, b.h) : min(a.w, b.w)
      guard overlap > 0, overlap <= narrower / 2 else { return nil }
      out.seams[k].join_px = -overlap
      offset += Int(across.rounded())
      out.offsets_px[b.index] = offset
    }
    out.offset_fill = "crop"
    if (try? out.plan()) == nil { return nil }
    return out
  }

  private static func scaledPreview(_ image: ToolImage, turn: Int, width: Int, height: Int) -> (image: CGImage, scale: Double)? {
    let turned = ToolImaging.turned(image.preview, turn)
    // Vision works best near a megapixel; keep the planned shape.
    let scale = min(1, 1024 / Double(max(width, height)))
    let (w, h) = (max(1, Int(Double(width) * scale)), max(1, Int(Double(height) * scale)))
    guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(turned, in: CGRect(x: 0, y: 0, width: w, height: h))
    return context.makeImage().map { ($0, scale) }
  }

  /// Stages every photo at its planned size, composites in the core and
  /// writes the new file into `workspace` under `name`. Sources are only read.
  static func export(
    config: GlueConfiguration, images: [ToolImage], format: ToolOutputFormat, name: String,
    workspace: MediaWorkspace, job: MediaRenderJob, progress: @escaping @Sendable (Double) -> Void
  ) throws -> URL {
    let plan = try config.plan()
    let space = ToolImaging.workingSpace(images)
    let canvasBytes = Int64(plan.width) * Int64(plan.height) * 4
    let stagedBytes = plan.items.reduce(Int64(0)) { $0 + Int64($1.w) * Int64($1.h) * 4 }
    try MediaWorkspace.requireSpace(at: workspace.directory, bytes: canvasBytes * 2 + stagedBytes)
    var staged: [URL] = []
    let composed = workspace.url("rgba")
    defer { for url in staged + [composed] { try? FileManager.default.removeItem(at: url) } }
    for (i, item) in plan.items.enumerated() {
      try Task.checkCancellation()
      let url = workspace.url("rgba")
      staged.append(url)
      try ToolImaging.stage(images[item.index], turn: config.sources[item.index].turn, size: (item.w, item.h), space: space, to: url)
      progress(0.7 * Double(i + 1) / Double(plan.items.count))
    }
    try job.glueCompose(configJson: config.json(), inputs: staged.map(\.path), destination: composed.path)
    progress(0.85)
    try Task.checkCancellation()
    let folder = workspace.directory.appendingPathComponent("made-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let out = folder.appendingPathComponent(name)
    // The union of keywords, in first-seen order.
    var keywords: [String] = []
    for image in images { for k in image.keywords where !keywords.contains(k) { keywords.append(k) } }
    let meta = ToolImaging.metadata(
      from: images[0], keywords: keywords, derivedFrom: images[0].name, sources: images.map(\.name))
    do {
      try ToolImaging.encode(
        rgba: composed, width: plan.width, height: plan.height, space: space, format: format,
        flatten: false, metadata: meta, to: out)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
    progress(1)
    return out
  }
}
