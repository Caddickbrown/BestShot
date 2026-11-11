import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

struct ToolVideoClip: Identifiable {
  let id: String
  let url: URL
  let name: String
  let startMS: Int
  let durationMS: Int
  let width: Int
  let height: Int
  let fps: Float
  let hasAudio: Bool
  let isHDR: Bool
  let thumbnail: CGImage?

  static func inspect(url: URL, name: String) async throws -> Self {
    let asset = AVURLAsset(url: url)
    guard try await asset.load(.isPlayable),
      let video = try await asset.loadTracks(withMediaType: .video).first
    else {
      throw MediaToolError.message("\(name) does not contain a playable video track.")
    }
    let size = try await video.load(.naturalSize)
    let transform = try await video.load(.preferredTransform)
    let rect = CGRect(origin: .zero, size: size).applying(transform)
    let range = try await video.load(.timeRange)
    guard range.start.seconds.isFinite, range.end.seconds.isFinite,
      range.start.seconds >= 0, range.end.seconds < 1_000_000_000,
      rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
      rect.width <= 32768, rect.height <= 32768
    else {
      throw MediaToolError.message("\(name) has unsupported dimensions or timing metadata.")
    }
    let reportedFPS = try await video.load(.nominalFrameRate)
    let fps: Float = reportedFPS.isFinite && reportedFPS > 0 ? reportedFPS : 30
    let audio = try await asset.loadTracks(withMediaType: .audio)
    let descriptions = try await video.load(.formatDescriptions)
    let hdr = descriptions.contains { description in
      let transfer =
        CMFormatDescriptionGetExtension(
          description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        ?? ""
      return transfer.contains("2084") || transfer.contains("HLG") || transfer.contains("2100")
    }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 180, height: 120)
    let thumb = try? await generator.image(at: range.start).image
    let startMS = max(0, Int((range.start.seconds * 1000).rounded(.up)))
    let endMS = Int((range.end.seconds * 1000).rounded(.down))
    guard endMS > startMS else {
      throw MediaToolError.message("\(name) has no usable video duration.")
    }
    return Self(
      id: UUID().uuidString, url: url, name: name, startMS: startMS, durationMS: endMS - startMS,
      width: Int(abs(rect.width).rounded()), height: Int(abs(rect.height).rounded()), fps: fps,
      hasAudio: !audio.isEmpty, isHDR: hdr, thumbnail: thumb)
  }
}

struct VideoJoinComposition {
  let composition: AVMutableComposition
  let video: AVMutableVideoComposition
  let audio: AVMutableAudioMix
  let durationMS: Int
  func playerItem() -> AVPlayerItem {
    let item = AVPlayerItem(asset: composition)
    item.videoComposition = video
    item.audioMix = audio
    return item
  }
}

enum VideoJoinService {
  static func time(_ ms: Int) -> CMTime { CMTime(value: Int64(ms), timescale: 1000) }
  static func range(_ start: Int, _ end: Int) -> CMTimeRange {
    CMTimeRange(start: time(start), end: time(end))
  }
  static func build(clips: [ToolVideoClip], config: VideoJoinConfiguration) async throws
    -> VideoJoinComposition
  {
    let plan = try config.plan()
    guard clips.map(\.id) == config.clips.map(\.id) else {
      throw MediaToolError.message("The source order changed. Preview again.")
    }
    let composition = AVMutableComposition()
    var tracks: [AVMutableCompositionTrack] = []
    var transforms: [CGAffineTransform] = []
    var audioParameters: [AVMutableAudioMixInputParameters] = []
    let outputSize = CGSize(width: config.output.width, height: config.output.height)
    for (i, clip) in clips.enumerated() {
      try Task.checkCancellation()
      let asset = AVURLAsset(url: clip.url)
      guard let source = try await asset.loadTracks(withMediaType: .video).first,
        let track = composition.addMutableTrack(
          withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
      else {
        throw MediaToolError.message("Unable to compose \(clip.name).")
      }
      let placement = plan.clips[i]
      let sourceRange = range(config.clips[i].in_ms, config.clips[i].out_ms)
      let available = try await source.load(.timeRange)
      guard CMTimeRangeContainsTimeRange(available, otherRange: sourceRange) else {
        throw MediaToolError.message(
          "\(clip.name) is shorter than the saved edit. Re-add the source.")
      }
      try track.insertTimeRange(sourceRange, of: source, at: time(placement.start_ms))
      tracks.append(track)
      let natural = try await source.load(.naturalSize)
      let preferred = try await source.load(.preferredTransform)
      let upright = CGRect(origin: .zero, size: natural).applying(preferred)
      let scale = min(outputSize.width / upright.width, outputSize.height / upright.height)
      let transform = preferred.concatenating(
        CGAffineTransform(translationX: -upright.minX, y: -upright.minY)
      )
      .concatenating(CGAffineTransform(scaleX: scale, y: scale))
      .concatenating(
        CGAffineTransform(
          translationX: (outputSize.width - upright.width * scale) / 2,
          y: (outputSize.height - upright.height * scale) / 2))
      transforms.append(transform)
      if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
        let audioTrack = composition.addMutableTrack(
          withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      {
        let availableAudio = try await sourceAudio.load(.timeRange)
        let usable = CMTimeRangeGetIntersection(sourceRange, otherRange: availableAudio)
        if usable.duration > .zero {
          let offset = CMTimeSubtract(usable.start, sourceRange.start)
          try audioTrack.insertTimeRange(
            usable, of: sourceAudio, at: CMTimeAdd(time(placement.start_ms), offset))
          let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
          applyAudio(parameters, index: i, plan: plan)
          audioParameters.append(parameters)
        }
      }
    }
    // Split at every start/end/fade boundary. Each instruction describes only
    // the tracks present in that interval, eliminating stale black frames.
    var boundaries: Set<Int> = [0, plan.duration_ms]
    for (i, placement) in plan.clips.enumerated() {
      boundaries.insert(placement.start_ms)
      boundaries.insert(placement.start_ms + placement.duration_ms)
      if i > 0 {
        let t = plan.joins[i - 1]
        if t.type == "fade_through_black" {
          boundaries.insert(placement.start_ms + t.duration_ms - t.duration_ms / 2)
        }
      }
      if i < plan.joins.count {
        let t = plan.joins[i]
        if t.type == "fade_through_black" {
          boundaries.insert(placement.start_ms + placement.duration_ms - t.duration_ms / 2)
        }
      }
    }
    let sorted = boundaries.sorted()
    var instructions: [AVMutableVideoCompositionInstruction] = []
    for (start, end) in zip(sorted, sorted.dropFirst()) where end > start {
      let instruction = AVMutableVideoCompositionInstruction()
      instruction.timeRange = range(start, end)
      instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
      var layers: [AVMutableVideoCompositionLayerInstruction] = []
      for (i, p) in plan.clips.enumerated()
      where p.start_ms < end && p.start_ms + p.duration_ms > start {
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: tracks[i])
        layer.setTransform(transforms[i], at: time(start))
        let a = opacity(index: i, at: start, plan: plan)
        let b = opacity(index: i, at: end, plan: plan)
        layer.setOpacityRamp(fromStartOpacity: a, toEndOpacity: b, timeRange: range(start, end))
        layers.append(layer)
      }
      // Earlier/outgoing track is on top. Incoming is opaque beneath it:
      // source-over compositing gives complementary crossfade weights.
      instruction.layerInstructions = layers
      instructions.append(instruction)
    }
    let video = AVMutableVideoComposition()
    video.renderSize = outputSize
    video.frameDuration = CMTime(value: 1, timescale: Int32(config.output.frame_rate))
    video.instructions = instructions
    video.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
    video.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
    video.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
    let audio = AVMutableAudioMix()
    audio.inputParameters = audioParameters
    return VideoJoinComposition(
      composition: composition, video: video, audio: audio, durationMS: plan.duration_ms)
  }
  static func opacity(index: Int, at ms: Int, plan: VideoTimeline) -> Float {
    let p = plan.clips[index]
    var value: Float = 1
    if index > 0 {
      let t = plan.joins[index - 1]
      if t.type == "fade_through_black" {
        value = min(value, Float(ms - p.start_ms) / Float(t.duration_ms - t.duration_ms / 2))
      }
    }
    if index < plan.joins.count {
      let t = plan.joins[index]
      let duration =
        t.type == "crossfade"
        ? t.duration_ms : t.type == "fade_through_black" ? t.duration_ms / 2 : 0
      if duration > 0 {
        value = min(value, Float(p.start_ms + p.duration_ms - ms) / Float(duration))
      }
    }
    return min(1, max(0, value))
  }
  private static func applyAudio(
    _ parameters: AVMutableAudioMixInputParameters, index: Int, plan: VideoTimeline
  ) {
    let p = plan.clips[index]
    parameters.setVolume(1, at: time(p.start_ms))
    if index > 0 {
      let t = plan.joins[index - 1]
      let d =
        t.type == "crossfade"
        ? t.duration_ms : t.type == "fade_through_black" ? t.duration_ms - t.duration_ms / 2 : 0
      if d > 0 {
        if t.audio == "crossfade" {
          parameters.setVolumeRamp(
            fromStartVolume: 0, toEndVolume: 1, timeRange: range(p.start_ms, p.start_ms + d))
        } else if t.audio == "mute" {
          parameters.setVolume(0, at: time(p.start_ms))
          parameters.setVolume(1, at: time(p.start_ms + d))
        } else if t.type == "crossfade" {
          parameters.setVolume(0, at: time(p.start_ms))
          parameters.setVolume(1, at: time(p.start_ms + d / 2))
        }
      }
    }
    if index < plan.joins.count {
      let t = plan.joins[index]
      let d =
        t.type == "crossfade"
        ? t.duration_ms : t.type == "fade_through_black" ? t.duration_ms / 2 : 0
      let end = p.start_ms + p.duration_ms
      if d > 0 {
        if t.audio == "crossfade" {
          parameters.setVolumeRamp(
            fromStartVolume: 1, toEndVolume: 0, timeRange: range(end - d, end))
        } else if t.audio == "mute" {
          parameters.setVolume(0, at: time(end - d))
        } else if t.type == "crossfade" {
          parameters.setVolume(0, at: time(end - d + d / 2))
        }
      }
    }
  }
  static func exporter(_ built: VideoJoinComposition, codec: String, destination: URL) throws
    -> AVAssetExportSession
  {
    let preset =
      codec == "hevc" ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
    guard let session = AVAssetExportSession(asset: built.composition, presetName: preset),
      session.supportedFileTypes.contains(.mp4)
    else {
      throw MediaToolError.message(
        "The selected codec cannot export these clips to MP4. Try H.264 or different source files.")
    }
    session.outputURL = destination
    session.outputFileType = .mp4
    session.videoComposition = built.video
    session.audioMix = built.audio
    session.shouldOptimizeForNetworkUse = false
    return session
  }
}
