import CoreGraphics
import Foundation
import Vision

/// One crop box as the editor holds it, in upright source pixels: a rotated
/// rectangle, or four corners (TL, TR, BR, BL of the photo as it comes out).
struct CropBoxModel: Equatable, Identifiable, Sendable {
  var id: String
  var rect = true
  var cx = 0.0
  var cy = 0.0
  var w = 0.0
  var h = 0.0
  /// Degrees, clockwise.
  var angle = 0.0
  var corners: [CGPoint] = []
  /// Output turn, clockwise: 0, 90, 180, 270.
  var turn = 0

  static func rect(id: String, _ r: CGRect) -> CropBoxModel {
    CropBoxModel(id: id, cx: r.midX, cy: r.midY, w: r.width, h: r.height)
  }

  /// The four corners, whichever kind.
  var quad: [CGPoint] {
    guard rect else { return corners }
    let a = angle * .pi / 180
    let (s, c) = (sin(a), cos(a))
    func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: cx + x * c - y * s, y: cy + x * s + y * c) }
    return [pt(-w / 2, -h / 2), pt(w / 2, -h / 2), pt(w / 2, h / 2), pt(-w / 2, h / 2)]
  }
  var centre: CGPoint {
    let q = quad
    return CGPoint(x: q.map(\.x).reduce(0, +) / 4, y: q.map(\.y).reduce(0, +) / 4)
  }
  var bounds: CGRect {
    let q = quad
    let xs = q.map(\.x), ys = q.map(\.y)
    return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
  }

  mutating func move(by d: CGVector) {
    if rect {
      cx += d.dx
      cy += d.dy
    } else {
      corners = corners.map { CGPoint(x: $0.x + d.dx, y: $0.y + d.dy) }
    }
  }

  /// Rectangle ⇄ four corners.
  mutating func toggleCorners() {
    if rect {
      corners = quad
      rect = false
    } else {
      let q = corners
      func d(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(b.x - a.x, b.y - a.y) }
      w = ((d(q[0], q[1]) + d(q[3], q[2])) / 2).rounded()
      h = ((d(q[0], q[3]) + d(q[1], q[2])) / 2).rounded()
      angle = (atan2(q[1].y - q[0].y, q[1].x - q[0].x) * 180 / .pi * 10).rounded() / 10
      let c = centre
      cx = c.x
      cy = c.y
      rect = true
    }
  }

  /// The core's JSON shape for this box.
  var json: [String: Any] {
    var out: [String: Any] = ["id": id, "turn": turn]
    if rect {
      out["kind"] = "rect"
      out["cx"] = cx
      out["cy"] = cy
      out["w"] = w.rounded()
      out["h"] = h.rounded()
      out["angle_deg"] = angle
    } else {
      out["kind"] = "quad"
      out["corners"] = corners.map { [$0.x, $0.y] }
    }
    return out
  }

  init(id: String, rect: Bool = true, cx: Double = 0, cy: Double = 0, w: Double = 0, h: Double = 0, angle: Double = 0, corners: [CGPoint] = [], turn: Int = 0) {
    self.id = id
    self.rect = rect
    self.cx = cx
    self.cy = cy
    self.w = w
    self.h = h
    self.angle = angle
    self.corners = corners
    self.turn = turn
  }

  init?(json: [String: Any]) {
    guard let id = json["id"] as? String else { return nil }
    self.id = id
    turn = json["turn"] as? Int ?? 0
    if json["kind"] as? String == "quad", let c = json["corners"] as? [[Double]], c.count == 4 {
      rect = false
      corners = c.map { CGPoint(x: $0[0], y: $0[1]) }
    } else {
      cx = (json["cx"] as? NSNumber)?.doubleValue ?? 0
      cy = (json["cy"] as? NSNumber)?.doubleValue ?? 0
      w = (json["w"] as? NSNumber)?.doubleValue ?? 0
      h = (json["h"] as? NSNumber)?.doubleValue ?? 0
      angle = (json["angle_deg"] as? NSNumber)?.doubleValue ?? 0
    }
  }

  /// The box in proportion to the image, for Use last crop on another image.
  func normalised(width: Int, height: Int) -> CropBoxModel {
    scaled(sx: 1 / Double(width), sy: 1 / Double(height))
  }
  func scaled(sx: Double, sy: Double) -> CropBoxModel {
    var b = self
    b.cx *= sx
    b.cy *= sy
    b.w *= sx
    b.h *= sy
    b.corners = corners.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
    return b
  }
}

struct MultiCropPlannedBox: Decodable, Equatable {
  let id: String
  let number: Int
  let name: String
  let width: Int
  let height: Int
  let exact: Bool
  let turn: Int
}
struct MultiCropPlan: Decodable {
  let boxes: [MultiCropPlannedBox]
}

enum MultiCropBridge {
  static func config(
    source: ToolImage, boxes: [CropBoxModel], trim: Int, stem: String = "", ext: String = "", existing: [String] = []
  ) throws -> String {
    let object: [String: Any] = [
      "schema_version": 1,
      "source": ["ref": source.name, "width": source.width, "height": source.height],
      "boxes": boxes.map(\.json),
      "trim_px": trim,
      "naming": ["stem": stem, "ext": ext, "existing": existing, "start": 1],
    ]
    return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
  }

  static func plan(source: ToolImage, boxes: [CropBoxModel], trim: Int, stem: String = "", ext: String = "", existing: [String] = []) throws -> MultiCropPlan {
    let json = try config(source: source, boxes: boxes, trim: trim, stem: stem, ext: ext, existing: existing)
    return try JSONDecoder().decode(MultiCropPlan.self, from: Data(mediaMulticropPlan(configJson: json).utf8))
  }

  /// Vision rectangles on the preview, tidied by the core into boxes.
  static func find(in source: ToolImage) throws -> [CropBoxModel] {
    let request = VNDetectRectanglesRequest()
    request.maximumObservations = 20
    request.minimumSize = 0.08
    request.minimumAspectRatio = 0.2
    request.quadratureTolerance = 20
    request.minimumConfidence = 0.6
    let handler = VNImageRequestHandler(cgImage: source.preview, options: [:])
    try handler.perform([request])
    var observations: [VNRectangleObservation] = request.results ?? []
    if observations.isEmpty {
      // One print on a table: the document finder is the fallback.
      let document = VNDetectDocumentSegmentationRequest()
      try handler.perform([document])
      observations = document.results ?? []
    }
    let (w, h) = (Double(source.width), Double(source.height))
    // Vision is normalised with the origin at the bottom left.
    func px(_ p: CGPoint) -> [Double] { [p.x * w, (1 - p.y) * h] }
    let quads = observations.map { [px($0.topLeft), px($0.topRight), px($0.bottomRight), px($0.bottomLeft)] }
    let json = String(decoding: try JSONSerialization.data(withJSONObject: quads), as: UTF8.self)
    let tidy = try mediaMulticropTidy(quadsJson: json, width: UInt32(source.width), height: UInt32(source.height))
    let list = try JSONSerialization.jsonObject(with: Data(tidy.utf8)) as? [[String: Any]] ?? []
    return list.compactMap(CropBoxModel.init(json:))
  }

  /// Makes one new file per box into `workspace` (named as they'll be
  /// published), in output order. The source is only read.
  static func export(
    source: ToolImage, boxes: [CropBoxModel], trim: Int, format: ToolOutputFormat, existing: [String],
    workspace: MediaWorkspace, job: MediaRenderJob, progress: @escaping @Sendable (Double) -> Void
  ) throws -> [URL] {
    let json = try config(source: source, boxes: boxes, trim: trim, stem: source.stem, ext: format.ext, existing: existing)
    let plan = try JSONDecoder().decode(MultiCropPlan.self, from: Data(mediaMulticropPlan(configJson: json).utf8))
    let space = ToolImaging.workingSpace([source])
    let staged = workspace.url("rgba")
    let folder = workspace.directory.appendingPathComponent("made-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var made: [URL] = []
    defer { try? FileManager.default.removeItem(at: staged) }
    do {
      try ToolImaging.stage(source, space: space, to: staged)
      progress(0.25)
      for (i, box) in plan.boxes.enumerated() {
        try Task.checkCancellation()
        let cut = workspace.url("rgba")
        defer { try? FileManager.default.removeItem(at: cut) }
        try job.multicropExtract(configJson: json, boxId: box.id, source: staged.path, destination: cut.path)
        let out = folder.appendingPathComponent(box.name)
        let meta = ToolImaging.metadata(
          from: source, keywords: source.keywords, derivedFrom: source.name, sources: [source.name], cropIndex: box.number)
        try ToolImaging.encode(
          rgba: cut, width: box.width, height: box.height, space: space, format: format, flatten: source.hasAlpha,
          metadata: meta, to: out)
        made.append(out)
        progress(0.25 + 0.75 * Double(i + 1) / Double(plan.boxes.count))
      }
    } catch {
      // A cancelled or failed run leaves nothing half-made.
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
    return made
  }
}
