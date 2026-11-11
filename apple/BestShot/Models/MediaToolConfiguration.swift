import Foundation

/// Versioned editing documents contain local references. Reopening asks for the
/// sources again; temporary URLs and Photos identifiers are never portable paths.
struct AntiCropConfiguration: Codable, Equatable {
  var schema_version = 1
  var source_ref = "image"
  var axis = "horizontal"
  var remove_start_px = 1
  var remove_end_px = 2
  var join_mode = "hard"
  var blend_width_px = 0
  var output_format = "png"

  func plan(width: Int, height: Int) throws -> CropGeometry {
    guard let w = UInt32(exactly: width), let h = UInt32(exactly: height) else {
      throw MediaToolError.message("Unsupported image dimensions.")
    }
    return try JSONDecoder().decode(
      CropGeometry.self,
      from: Data(
        mediaAntiCropPlan(
          configJson: json(), width: w, height: h
        ).utf8))
  }
  func json() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
}
struct CropGeometry: Decodable {
  let width: Int
  let height: Int
  let seam_px: Int
}
struct VideoTransition: Codable, Equatable {
  var type = "hard_cut"
  var duration_ms = 0
  var audio = "hard_cut"
  static let kinds = ["hard_cut", "crossfade", "fade_through_black"]
  static func title(_ value: String) -> String {
    switch value {
    case "crossfade": return "Crossfade"
    case "fade_through_black": return "Fade through black"
    default: return "Hard cut"
    }
  }
  mutating func setKind(_ kind: String) {
    type = kind
    duration_ms = kind == "hard_cut" ? 0 : max(100, duration_ms == 0 ? 500 : duration_ms)
    audio = kind == "hard_cut" ? "hard_cut" : "crossfade"
  }
}
struct VideoJoinConfiguration: Codable {
  struct Clip: Codable {
    var id: String
    var source_ref: String
    var in_ms = 0
    var out_ms: Int
  }
  struct Output: Codable {
    var width = 1920
    var height = 1080
    var fit_mode = "contain"
    var frame_rate = 30
    var codec = "h264"
  }
  struct Override: Codable {
    var after_clip_id: String
    var transition: VideoTransition
  }
  var schema_version = 1
  var clips: [Clip] = []
  var output = Output()
  var default_transition = VideoTransition()
  var join_overrides: [Override] = []
  func json() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
  func plan() throws -> VideoTimeline {
    try JSONDecoder().decode(
      VideoTimeline.self, from: Data(mediaVideoPlan(configJson: json()).utf8))
  }
}
struct VideoTimeline: Decodable {
  struct Placement: Decodable {
    let id: String
    let start_ms: Int
    let duration_ms: Int
  }
  let duration_ms: Int
  let clips: [Placement]
  let joins: [VideoTransition]
}

enum MediaToolError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}
