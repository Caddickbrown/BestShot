import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO handles Apple formats and EXIF; Rust owns the exact same cut used by
/// preview and export. An explicit sRGB RGBA8 pipeline preserves alpha, and the
/// resulting PNG has an sRGB profile. HDR/wide gamut are explicitly converted.
enum AntiCropBridge {
  struct Source {
    let url: URL
    let width: Int
    let height: Int
    let preview: CGImage
  }
  static let maxDecodedBytes = 256 * 1024 * 1024
  static func inspect(_ url: URL) throws -> Source {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let w = props[kCGImagePropertyPixelWidth] as? Int,
      let h = props[kCGImagePropertyPixelHeight] as? Int,
      let preview = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 1600,
        ] as CFDictionary)
    else {
      throw MediaToolError.message(
        "This image could not be decoded. Choose a supported JPEG, HEIC, PNG or TIFF.")
    }
    let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
    let swaps = (5...8).contains(orientation)
    return Source(url: url, width: swaps ? h : w, height: swaps ? w : h, preview: preview)
  }
  static func export(
    source: Source, edit: AntiCropConfiguration, workspace: MediaWorkspace, job: MediaRenderJob,
    progress: @escaping @Sendable (Double) -> Void
  ) throws -> URL {
    let geometry = try edit.plan(width: source.width, height: source.height)
    let bytes = source.width.multipliedReportingOverflow(by: source.height)
    guard !bytes.overflow, bytes.partialValue <= maxDecodedBytes / 4 else {
      throw MediaToolError.message(
        "This image exceeds the 256 MB decoded-image limit. Choose an image below 64 megapixels.")
    }
    try MediaWorkspace.requireSpace(at: workspace.directory, bytes: Int64(bytes.partialValue) * 16)
    let raw = workspace.url("rgba")
    let cut = workspace.url("rgba")
    let temporary = workspace.url("partial.png")
    defer { for url in [raw, cut, temporary] { try? FileManager.default.removeItem(at: url) } }
    try Task.checkCancellation()
    try writeNormalizedPixels(source: source, raw: raw, byteCount: bytes.partialValue * 4)
    progress(0.3)
    try Task.checkCancellation()
    try job.cropRgba(
      configJson: edit.json(), width: UInt32(source.width), height: UInt32(source.height),
      source: raw.path, destination: cut.path)
    progress(0.65)
    try Task.checkCancellation()
    guard let colour = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw MediaToolError.message("sRGB colour space unavailable.")
    }
    let pixels = try Data(contentsOf: cut, options: .mappedIfSafe)
    guard let provider = CGDataProvider(data: pixels as CFData),
      let image = CGImage(
        width: geometry.width, height: geometry.height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: geometry.width * 4, space: colour,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
      let destination = CGImageDestinationCreateWithURL(
        temporary as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
      throw MediaToolError.message("Unable to create the PNG export.")
    }
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw MediaToolError.message("PNG export failed. Check available storage.")
    }
    try Task.checkCancellation()
    let finished = workspace.url("png")
    try FileManager.default.moveItem(at: temporary, to: finished)
    progress(1)
    return finished
  }
  private static func writeNormalizedPixels(source: Source, raw: URL, byteCount: Int) throws {
    guard let input = CIImage(contentsOf: source.url, options: [.applyOrientationProperty: true]),
      let colour = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw MediaToolError.message("Unable to decode the full-resolution image.") }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
    defer { buffer.deallocate() }
    let context = CIContext(options: [
      .workingColorSpace: colour, .outputColorSpace: colour, .cacheIntermediates: false,
    ])
    defer { context.clearCaches() }
    context.render(
      input, toBitmap: buffer, rowBytes: source.width * 4,
      bounds: input.extent, format: .RGBA8, colorSpace: colour)
    try Task.checkCancellation()
    let handle = try FileHandle(forWritingTo: create(raw))
    do {
      for offset in stride(from: 0, to: byteCount, by: 1024 * 1024) {
        try Task.checkCancellation()
        try handle.write(
          contentsOf: Data(
            bytesNoCopy: buffer.advanced(by: offset), count: min(1024 * 1024, byteCount - offset),
            deallocator: .none))
      }
      try handle.close()
    } catch {
      try? handle.close()
      throw error
    }
  }
  private static func create(_ url: URL) throws -> URL {
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
      throw MediaToolError.message("Cannot create a temporary pixel file.")
    }
    return url
  }
}
