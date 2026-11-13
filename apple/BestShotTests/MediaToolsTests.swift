import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import BestShot

final class MediaToolsTests: XCTestCase {
  func testAntiCropBridgePreservesPixelOrderAndAlphaOnBothAxes() throws {
    let workspace = try MediaWorkspace()
    let width = 8
    let height = 6
    var pixels = [UInt8]()
    for y in 0..<height {
      for x in 0..<width {
        pixels += [UInt8(x * 28), UInt8(y * 40), UInt8((x + y) * 16), x == 0 ? 0 : 255]
      }
    }
    let sourceURL = workspace.url("png")
    try writeImage(pixels, width: width, height: height, to: sourceURL)
    let source = try AntiCropBridge.inspect(sourceURL)
    for axis in ["horizontal", "vertical"] {
      var edit = AntiCropConfiguration()
      edit.axis = axis
      edit.remove_start_px = 2
      edit.remove_end_px = 4
      let url = try AntiCropBridge.export(
        source: source, edit: edit, workspace: workspace, job: MediaRenderJob(), progress: { _ in })
      let output = try AntiCropBridge.inspect(url)
      XCTAssertEqual(output.width, width - (axis == "vertical" ? 2 : 0))
      XCTAssertEqual(output.height, height - (axis == "horizontal" ? 2 : 0))
      let original = try rgba(sourceURL)
      var expected = [UInt8]()
      for y in 0..<height {
        for x in 0..<width {
          let c = axis == "horizontal" ? y : x
          if !(2..<4).contains(c) {
            let offset = (y * width + x) * 4
            expected += original[offset..<offset + 4]
          }
        }
      }
      XCTAssertEqual(
        try rgba(url), expected, "Retained pixels or row orientation changed for \(axis)")
    }
  }
  func testRotatedImageCoordinatesMatchUprightPreview() throws {
    let workspace = try MediaWorkspace()
    let sourceURL = workspace.url("tiff")
    var pixels: [UInt8] = []
    for i in 0..<48 {
      pixels.append(contentsOf: [UInt8(i * 4), UInt8(i * 3), UInt8(i * 2), UInt8(255)])
    }
    try writeImage(pixels, width: 8, height: 6, to: sourceURL, orientation: 6, type: .tiff)
    let source = try AntiCropBridge.inspect(sourceURL)
    XCTAssertEqual(source.width, 6)
    XCTAssertEqual(source.height, 8)
    var edit = AntiCropConfiguration()
    edit.remove_start_px = 2
    edit.remove_end_px = 4
    let url = try AntiCropBridge.export(
      source: source, edit: edit, workspace: workspace, job: MediaRenderJob(), progress: { _ in })
    let output = try AntiCropBridge.inspect(url)
    XCTAssertEqual(output.width, 6)
    XCTAssertEqual(output.height, 6)
    let upright = try rgba(source.preview)
    var expected: [UInt8] = []
    for y in [0, 1, 4, 5, 6, 7] { expected += upright[y * 6 * 4..<(y + 1) * 6 * 4] }
    XCTAssertEqual(try rgba(url), expected)
  }
  func testCancelledImageExportDoesNotPublishOrAlterOriginal() throws {
    let workspace = try MediaWorkspace()
    let url = workspace.url("png")
    try writeImage([UInt8](repeating: 255, count: 8 * 6 * 4), width: 8, height: 6, to: url)
    let original = try Data(contentsOf: url)
    let job = MediaRenderJob()
    job.cancel()
    var edit = AntiCropConfiguration()
    edit.remove_start_px = 2
    edit.remove_end_px = 4
    XCTAssertThrowsError(
      try AntiCropBridge.export(
        source: AntiCropBridge.inspect(url), edit: edit, workspace: workspace, job: job,
        progress: { _ in }))
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: workspace.directory.path).count, 1)
  }
  func testTimelinePlanAcrossUniFFIAndPerJoinOverride() throws {
    var config = VideoJoinConfiguration()
    config.clips = (0..<3).map { .init(id: "\($0)", source_ref: "\($0)", out_ms: 10000) }
    config.default_transition = VideoTransition(
      type: "crossfade", duration_ms: 1000, audio: "crossfade")
    XCTAssertEqual(try config.plan().duration_ms, 28000)
    config.join_overrides = [
      .init(
        after_clip_id: "0",
        transition: VideoTransition(type: "fade_through_black", duration_ms: 1000, audio: "mute"))
    ]
    XCTAssertEqual(try config.plan().duration_ms, 29000)
  }
  func testVideoExportsCutsCrossfadesBlackFadesAndRotation() async throws {
    let workspace = try MediaWorkspace()
    let first = try await video(workspace: workspace, red: true)
    let second = try await video(workspace: workspace, red: false)
    let sources = [
      try await ToolVideoClip.inspect(url: first, name: "a.mov"),
      try await ToolVideoClip.inspect(url: second, name: "b.mov"),
    ]
    XCTAssertEqual(sources[0].width, 48)
    XCTAssertEqual(sources[0].height, 64)
    for kind in VideoTransition.kinds {
      var config = VideoJoinConfiguration()
      config.clips = sources.map {
        .init(id: $0.id, source_ref: $0.name, in_ms: $0.startMS, out_ms: $0.startMS + $0.durationMS)
      }
      config.output.width = 48
      config.output.height = 64
      config.default_transition = VideoTransition(
        type: kind, duration_ms: kind == "hard_cut" ? 0 : 400, audio: "crossfade")
      let built = try await VideoJoinService.build(clips: sources, config: config)
      let url = workspace.url("mp4")
      let session = try VideoJoinService.exporter(built, codec: "h264", destination: url)
      await session.export()
      XCTAssertEqual(session.status, .completed, "\(kind): \(String(describing:session.error))")
      let asset = AVURLAsset(url: url)
      let duration = try await asset.load(.duration)
      XCTAssertEqual(
        duration.seconds, Double(try config.plan().duration_ms) / 1000, accuracy: 1 / 30)
      let loaded = try await asset.loadTracks(withMediaType: .video)
      let track = try XCTUnwrap(loaded.first)
      let size = try await track.load(.naturalSize)
      XCTAssertEqual(size, CGSize(width: 48, height: 64))
      let generator = AVAssetImageGenerator(asset: asset)
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = .zero
      let center = try await generator.image(
        at: CMTime(seconds: kind == "crossfade" ? 0.8 : 1, preferredTimescale: 600)
      ).image
      let centerBytes = try rgba(center)
      let offset: Int = ((center.height / 2) * center.width + center.width / 2) * 4
      if kind == "fade_through_black" {
        XCTAssertLessThan(Int(centerBytes[offset]) + Int(centerBytes[offset + 2]), 45)
      } else if kind == "crossfade" {
        XCTAssertGreaterThan(centerBytes[offset], 50)
        XCTAssertGreaterThan(centerBytes[offset + 2], 50)
      } else {
        XCTAssertGreaterThan(centerBytes[offset + 2], 150)
      }
    }
  }
  func testMixedAudioFormatsAndSilentMiddleClipExportInSync() async throws {
    let workspace = try MediaWorkspace()
    let silent = try await video(workspace: workspace, red: true)
    let mono = try await withAudio(silent, workspace: workspace, rate: 48000, channels: 1)
    let stereo = try await withAudio(silent, workspace: workspace, rate: 44100, channels: 2)
    let clips = [
      try await ToolVideoClip.inspect(url: mono, name: "mono"),
      try await ToolVideoClip.inspect(url: silent, name: "silent"),
      try await ToolVideoClip.inspect(url: stereo, name: "stereo"),
    ]
    XCTAssertFalse(clips[1].hasAudio)
    var config = VideoJoinConfiguration()
    config.clips = clips.map {
      .init(id: $0.id, source_ref: $0.name, in_ms: $0.startMS, out_ms: $0.startMS + $0.durationMS)
    }
    config.output.width = 48
    config.output.height = 64
    config.default_transition = VideoTransition(
      type: "crossfade", duration_ms: 200, audio: "crossfade")
    let built = try await VideoJoinService.build(clips: clips, config: config)
    XCTAssertEqual(built.audio.inputParameters.count, 2)
    let destination = workspace.url("mp4")
    let exporter = try VideoJoinService.exporter(built, codec: "h264", destination: destination)
    await exporter.export()
    XCTAssertEqual(exporter.status, .completed, "\(String(describing:exporter.error))")
    let asset = AVURLAsset(url: destination)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(duration.seconds, 2.6, accuracy: 1 / 30)
    let audio = try await asset.loadTracks(withMediaType: .audio)
    XCTAssertEqual(audio.count, 1)
    let audioRange = try await XCTUnwrap(audio.first).load(.timeRange)
    XCTAssertEqual(audioRange.end.seconds, 2.6, accuracy: 0.06)
  }
  @MainActor
  func testVideoSessionCancellationCleansPartialOutput() async throws {
    let workspace = try MediaWorkspace()
    let source = try await video(workspace: workspace, red: true)
    let originalSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
    let session = VideoJoinSession()
    session.add(Array(repeating: source, count: 12))
    for _ in 0..<1000 {
      if !session.busy { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertFalse(session.busy)
    XCTAssertEqual(session.clips.count, 12, session.error ?? "Import failed")
    session.render(export: true)
    // Yield until the exporter is active, rather than cancelling only setup.
    for _ in 0..<1000 {
      if session.phase == "Exporting MP4…" || !session.busy { break }
      try await Task.sleep(for: .milliseconds(1))
    }
    XCTAssertEqual(session.phase, "Exporting MP4…")
    session.cancel()
    for _ in 0..<1000 {
      if !session.busy { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertFalse(session.busy)
    XCTAssertNil(session.result)
    let directory = try XCTUnwrap(session.clips.first?.url.deletingLastPathComponent())
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    XCTAssertFalse(
      files.contains { $0.lastPathComponent.contains("partial") || $0.pathExtension == "mp4" })
    XCTAssertEqual(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, originalSize)
  }
  @MainActor
  func testOneDragOfAHandleIsOneStepOfUndo() throws {
    let workspace = try MediaWorkspace()
    let image = workspace.url("png")
    try writeImage([UInt8](repeating: 255, count: 8 * 6 * 4), width: 8, height: 6, to: image)
    let session = AntiCropSession()
    session.source = try AntiCropBridge.inspect(image)
    session.reset()
    let before = session.edit
    session.beginAdjusting()
    for end in [4, 5] {
      let old = session.edit
      session.edit.remove_end_px = end
      session.record(old)
    }
    session.endAdjusting()
    XCTAssertTrue(session.canUndo)
    session.undo()
    session.record(session.edit)
    XCTAssertEqual(session.edit, before)
    XCTAssertFalse(session.canUndo)
  }

  private func withAudio(_ movie: URL, workspace: MediaWorkspace, rate: Int, channels: Int)
    async throws -> URL
  {
    let wave = workspace.url("wav")
    var data = Data()
    func text(_ value: String) { data.append(contentsOf: value.utf8) }
    func u16(_ value: Int) {
      var v = UInt16(value).littleEndian
      withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    func u32(_ value: Int) {
      var v = UInt32(value).littleEndian
      withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    let byteCount = rate * channels * 2
    text("RIFF")
    u32(36 + byteCount)
    text("WAVEfmt ")
    u32(16)
    u16(1)
    u16(channels)
    u32(rate)
    u32(rate * channels * 2)
    u16(channels * 2)
    u16(16)
    text("data")
    u32(byteCount)
    for sample in 0..<rate {
      var v = Int16(sin(Double(sample) * 440 * 2 * Double.pi / Double(rate)) * 8000).littleEndian
      for _ in 0..<channels { withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
    }
    try data.write(to: wave)
    let composition = AVMutableComposition()
    let videoSource = AVURLAsset(url: movie)
    let audioSource = AVURLAsset(url: wave)
    let videos = try await videoSource.loadTracks(withMediaType: .video)
    let audios = try await audioSource.loadTracks(withMediaType: .audio)
    let videoTrack = try XCTUnwrap(
      composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
    let original = try XCTUnwrap(videos.first)
    try videoTrack.insertTimeRange(
      CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)),
      of: original, at: .zero)
    videoTrack.preferredTransform = try await original.load(.preferredTransform)
    let audioTrack = try XCTUnwrap(
      composition.addMutableTrack(
        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
    try audioTrack.insertTimeRange(
      CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)),
      of: XCTUnwrap(audios.first), at: .zero)
    let destination = workspace.url("mov")
    let exporter = try XCTUnwrap(
      AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
    exporter.outputURL = destination
    exporter.outputFileType = .mov
    await exporter.export()
    XCTAssertEqual(exporter.status, .completed)
    return destination
  }
  private func video(workspace: MediaWorkspace, red: Bool) async throws -> URL {
    let url = workspace.url("mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
      ])
    input.transform = CGAffineTransform(rotationAngle: .pi / 2)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
      ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<30 {
      while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
      var buffer: CVPixelBuffer?
      CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32ARGB, nil, &buffer)
      let pixels = try XCTUnwrap(buffer)
      CVPixelBufferLockBaseAddress(pixels, [])
      let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(
        to: UInt8.self)
      let stride = CVPixelBufferGetBytesPerRow(pixels)
      for y in 0..<48 {
        for x in 0..<64 {
          let p = y * stride + x * 4
          bytes[p] = 255
          bytes[p + 1] = red ? 240 : 0
          bytes[p + 2] = 0
          bytes[p + 3] = red ? 0 : 240
        }
      }
      CVPixelBufferUnlockBaseAddress(pixels, [])
      XCTAssertTrue(
        adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
    }
    writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
    input.markAsFinished()
    await writer.finishWriting()
    XCTAssertEqual(writer.status, .completed)
    return url
  }
  private func writeImage(
    _ pixels: [UInt8], width: Int, height: Int, to url: URL, orientation: Int = 1,
    type: UTType = .png
  ) throws {
    let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
    let image = try XCTUnwrap(
      CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let dest = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(
      dest, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
  }
  private func rgba(_ url: URL) throws -> [UInt8] {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try rgba(XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)))
  }
  private func rgba(_ image: CGImage) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { data in
      let context = try XCTUnwrap(
        CGContext(
          data: data.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
          bytesPerRow: image.width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels
  }
}
