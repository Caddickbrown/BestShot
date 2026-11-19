import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// What Glue and Multi Crop share on the platform side: opening a photo
// upright, staging its pixels for the Rust core, and writing the new file with
// the metadata it should carry. Sources are only ever read.

/// The format a new file is written in. JPEG unless chosen otherwise (Dan, 19 Nov).
enum ToolOutputFormat: String, CaseIterable, Codable, Sendable {
  case jpeg, heic, png, tiff
  var ext: String {
    switch self {
    case .jpeg: return "jpg"
    case .heic: return "heic"
    case .png: return "png"
    case .tiff: return "tif"
    }
  }
  var type: UTType {
    switch self {
    case .jpeg: return .jpeg
    case .heic: return .heic
    case .png: return .png
    case .tiff: return .tiff
    }
  }
  var title: String {
    switch self {
    case .jpeg: return "JPEG"
    case .heic: return "HEIC"
    case .png: return "PNG"
    case .tiff: return "TIFF"
    }
  }
  var lossy: Bool { self == .jpeg || self == .heic }
  /// Kept per tool between launches.
  static func saved(_ tool: String) -> ToolOutputFormat {
    UserDefaults.standard.string(forKey: "tools.\(tool).format").flatMap(Self.init(rawValue:)) ?? .jpeg
  }
  func save(_ tool: String) { UserDefaults.standard.set(rawValue, forKey: "tools.\(tool).format") }
}

/// A photo opened for a tool: upright size, a preview for the editor, and what
/// the new files take from it. `url` is read; `origin` names it and says where
/// files made beside it go.
struct ToolImage: @unchecked Sendable, Identifiable {
  let id = UUID()
  let url: URL
  let origin: URL
  let width: Int
  let height: Int
  let preview: CGImage
  let hasAlpha: Bool
  let wide: Bool
  let properties: [CFString: Any]
  let keywords: [String]

  var stem: String { origin.deletingPathExtension().lastPathComponent }
  var name: String { origin.lastPathComponent }
  /// Preview pixels per source pixel.
  var previewScale: CGFloat { CGFloat(preview.width) / CGFloat(max(width, 1)) }
}

enum ToolImaging {
  /// 67 MP on iPhone and iPad, 256 MP on the Mac (allocation guards, spec 0.4).
  #if os(macOS)
  static let maxSourcePixels = 256_000_000
  static let maxOutputPixels: UInt64 = 400_000_000
  #else
  static let maxSourcePixels = 67_108_864
  static let maxOutputPixels: UInt64 = 100_000_000
  #endif
  static let previewSide = 2048

  static func inspect(_ url: URL, origin: URL? = nil, extraKeywords: [String] = []) throws -> ToolImage {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let w = props[kCGImagePropertyPixelWidth] as? Int,
      let h = props[kCGImagePropertyPixelHeight] as? Int,
      let preview = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: previewSide,
        ] as CFDictionary)
    else {
      throw MediaToolError.message(
        "This image could not be opened. Choose a JPEG, HEIC, PNG, TIFF or raw photo.")
    }
    let pixels = w.multipliedReportingOverflow(by: h)
    guard !pixels.overflow, pixels.partialValue <= maxSourcePixels else {
      let mp = pixels.overflow ? Int.max : pixels.partialValue / 1_000_000
      #if os(macOS)
      throw MediaToolError.message("This image is \(mp) MP, \(maxSourcePixels / 1_000_000) MP at most.")
      #else
      throw MediaToolError.message(
        "This image is \(mp) MP, \(maxSourcePixels / 1_000_000) MP at most on iPhone and iPad. Open it on the Mac.")
      #endif
    }
    let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
    let swaps = (5...8).contains(orientation)
    let alpha = (props[kCGImagePropertyHasAlpha] as? Bool) ?? false
    let wide = preview.colorSpace?.isWideGamutRGB ?? false
    var keywords = Self.keywords(source: source, properties: props)
    for k in extraKeywords where !keywords.contains(k) { keywords.append(k) }
    return ToolImage(
      url: url, origin: origin ?? url, width: swaps ? h : w, height: swaps ? w : h,
      preview: preview, hasAlpha: alpha, wide: wide, properties: props, keywords: keywords)
  }

  /// dc:subject from the embedded XMP, else IPTC keywords.
  static func keywords(source: CGImageSource, properties: [CFString: Any]) -> [String] {
    var out: [String] = []
    if let meta = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
      let tag = CGImageMetadataCopyTagWithPath(meta, nil, "dc:subject" as CFString),
      let values = CGImageMetadataTagCopyValue(tag) as? [Any]
    {
      for v in values {
        if let s = v as? String {
          out.append(s)
        } else if CFGetTypeID(v as CFTypeRef) == CGImageMetadataTagGetTypeID(),
          let s = CGImageMetadataTagCopyValue(v as! CGImageMetadataTag) as? String
        {
          out.append(s)
        }
      }
    }
    if out.isEmpty, let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
      if let list = iptc[kCGImagePropertyIPTCKeywords] as? [String] { out = list }
      if let one = iptc[kCGImagePropertyIPTCKeywords] as? String { out = [one] }
    }
    var seen = Set<String>()
    return out.filter { seen.insert($0).inserted }
  }

  /// Display P3 when any source is wide gamut, else sRGB (spec 0.4).
  static func workingSpace(_ images: [ToolImage]) -> CGColorSpace {
    let name = images.contains(where: \.wide) ? CGColorSpace.displayP3 : CGColorSpace.sRGB
    return CGColorSpace(name: name) ?? CGColorSpaceCreateDeviceRGB()
  }

  /// A preview turned by quarter turns, for the editor.
  static func turned(_ image: CGImage, _ turn: Int) -> CGImage {
    guard turn % 360 != 0 else { return image }
    let ci = CIImage(cgImage: image).oriented(orientation(turn))
    let context = CIContext(options: [.cacheIntermediates: false])
    return context.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: image.colorSpace) ?? image
  }

  /// A clockwise quarter turn as the orientation that applies it.
  static func orientation(_ turn: Int) -> CGImagePropertyOrientation {
    switch ((turn % 360) + 360) % 360 {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
  }

  /// Decodes the full image upright, turns it, scales it to exactly
  /// `size` (Lanczos) when given, and writes tightly packed premultiplied RGBA8
  /// in `space` to a new file. Returns the staged size.
  @discardableResult
  static func stage(
    _ image: ToolImage, turn: Int = 0, size: (Int, Int)? = nil, space: CGColorSpace, to destination: URL
  ) throws -> (Int, Int) {
    let scoped = image.url.startAccessingSecurityScopedResource()
    defer { if scoped { image.url.stopAccessingSecurityScopedResource() } }
    guard var ci = CIImage(contentsOf: image.url, options: [.applyOrientationProperty: true]) else {
      throw MediaToolError.message("Unable to decode the full-resolution image.")
    }
    if turn % 360 != 0 { ci = ci.oriented(orientation(turn)) }
    ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
    let natural = (Int(ci.extent.width.rounded()), Int(ci.extent.height.rounded()))
    let (w, h) = size ?? natural
    guard w > 0, h > 0 else { throw MediaToolError.message("The image has no pixels.") }
    if (w, h) != natural {
      let sx = CGFloat(w) / ci.extent.width
      let sy = CGFloat(h) / ci.extent.height
      let filter = CIFilter(name: "CILanczosScaleTransform")
      filter?.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
      filter?.setValue(sy, forKey: kCIInputScaleKey)
      filter?.setValue(sx / sy, forKey: kCIInputAspectRatioKey)
      guard let scaled = filter?.outputImage else { throw MediaToolError.message("Unable to scale the photo.") }
      ci = scaled
    }
    let byteCount = w * h * 4
    try MediaWorkspace.requireSpace(at: destination.deletingLastPathComponent(), bytes: Int64(byteCount) * 2)
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
    defer { buffer.deallocate() }
    let context = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space, .cacheIntermediates: false])
    defer { context.clearCaches() }
    context.render(ci, toBitmap: buffer, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: space)
    try Task.checkCancellation()
    guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
      throw MediaToolError.message("Cannot create a temporary pixel file.")
    }
    let handle = try FileHandle(forWritingTo: destination)
    defer { try? handle.close() }
    for offset in stride(from: 0, to: byteCount, by: 1 << 20) {
      try Task.checkCancellation()
      try handle.write(
        contentsOf: Data(bytesNoCopy: buffer.advanced(by: offset), count: min(1 << 20, byteCount - offset), deallocator: .none))
    }
    return (w, h)
  }

  /// What the new file carries (spec 0.3, decisions of 19 Nov): capture date,
  /// camera and lens, location and DPI from `source`; keywords; where it came
  /// from. Never stars, labels, the thumbnail, maker notes or develop settings.
  static func metadata(from source: ToolImage, keywords: [String], derivedFrom: String, sources: [String], cropIndex: Int? = nil) -> CGMutableImageMetadata {
    let meta = CGImageMetadataCreateMutable()
    let props = source.properties
    let exifKeys: [CFString] = [
      kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifDateTimeDigitized,
      kCGImagePropertyExifOffsetTimeOriginal, kCGImagePropertyExifSubsecTimeOriginal,
      kCGImagePropertyExifExposureTime, kCGImagePropertyExifFNumber, kCGImagePropertyExifISOSpeedRatings,
      kCGImagePropertyExifFocalLength, kCGImagePropertyExifFocalLenIn35mmFilm, kCGImagePropertyExifLensMake,
      kCGImagePropertyExifLensModel, kCGImagePropertyExifExposureBiasValue, kCGImagePropertyExifFlash,
    ]
    let tiffKeys: [CFString] = [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFDateTime]
    func copy(_ dictionary: CFString, _ keys: [CFString]?) {
      guard let d = props[dictionary] as? [CFString: Any] else { return }
      for (key, value) in d where keys?.contains(key) ?? true {
        _ = CGImageMetadataSetValueMatchingImageProperty(meta, dictionary, key, value as CFTypeRef)
      }
    }
    copy(kCGImagePropertyExifDictionary, exifKeys)
    copy(kCGImagePropertyTIFFDictionary, tiffKeys)
    copy(kCGImagePropertyGPSDictionary, nil)
    if let dpi = props[kCGImagePropertyDPIWidth] as? Double ?? (props[kCGImagePropertyDPIWidth] as? Int).map(Double.init) {
      let dpiY = props[kCGImagePropertyDPIHeight] as? Double ?? dpi
      _ = CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFXResolution, dpi as CFNumber)
      _ = CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFYResolution, dpiY as CFNumber)
      _ = CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFResolutionUnit, 2 as CFNumber)
    }
    if !keywords.isEmpty,
      let tag = CGImageMetadataTagCreate(
        kCGImageMetadataNamespaceDublinCore, kCGImageMetadataPrefixDublinCore, "subject" as CFString,
        .arrayUnordered, keywords as CFArray)
    {
      CGImageMetadataSetTagWithPath(meta, nil, "dc:subject" as CFString, tag)
    }
    let mm = "http://ns.adobe.com/xap/1.0/mm/" as CFString
    let stRef = "http://ns.adobe.com/xap/1.0/sType/ResourceRef#" as CFString
    let ours = "https://caddickbrown.com/ns/bestshot/1.0/" as CFString
    CGImageMetadataRegisterNamespaceForPrefix(meta, mm, "xmpMM" as CFString, nil)
    CGImageMetadataRegisterNamespaceForPrefix(meta, stRef, "stRef" as CFString, nil)
    CGImageMetadataRegisterNamespaceForPrefix(meta, ours, "bestshot" as CFString, nil)
    if let path = CGImageMetadataTagCreate(stRef, "stRef" as CFString, "filePath" as CFString, .string, derivedFrom as CFString),
      let derived = CGImageMetadataTagCreate(mm, "xmpMM" as CFString, "DerivedFrom" as CFString, .structure, ["filePath": path] as CFDictionary)
    {
      CGImageMetadataSetTagWithPath(meta, nil, "xmpMM:DerivedFrom" as CFString, derived)
    }
    if !sources.isEmpty,
      let tag = CGImageMetadataTagCreate(ours, "bestshot" as CFString, "Sources" as CFString, .arrayOrdered, sources as CFArray)
    {
      CGImageMetadataSetTagWithPath(meta, nil, "bestshot:Sources" as CFString, tag)
    }
    if let cropIndex,
      let tag = CGImageMetadataTagCreate(ours, "bestshot" as CFString, "CropIndex" as CFString, .string, String(cropIndex) as CFString)
    {
      CGImageMetadataSetTagWithPath(meta, nil, "bestshot:CropIndex" as CFString, tag)
    }
    return meta
  }

  /// Encodes staged RGBA as a new file. Lossy formats lose alpha, flattened
  /// onto white. Orientation is 1: the pixels are already upright.
  static func encode(
    rgba: URL, width: Int, height: Int, space: CGColorSpace, format: ToolOutputFormat, quality: Double = 0.92,
    flatten: Bool, metadata: CGImageMetadata, to destination: URL
  ) throws {
    let pixels = try Data(contentsOf: rgba, options: .alwaysMapped)
    guard pixels.count == width * height * 4, let provider = CGDataProvider(data: pixels as CFData),
      var image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw MediaToolError.message("Unable to read the made pixels.") }
    if format.lossy && flatten {
      guard
        let context = CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      else { throw MediaToolError.message("Not enough memory to flatten this image.") }
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      if let flat = context.makeImage() { image = flat }
    }
    guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, 1, nil) else {
      throw MediaToolError.message("\(format.title) can't be written here. Choose JPEG in the options.")
    }
    var options: [CFString: Any] = [:]
    if format.lossy { options[kCGImageDestinationLossyCompressionQuality] = quality }
    CGImageDestinationAddImageAndMetadata(dest, image, metadata, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: destination)
      throw MediaToolError.message("Couldn't write the \(format.title). Check free storage.")
    }
  }

  /// File names in a folder, for the core's collision rule.
  static func names(in directory: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
  }

  /// Puts a finished file in `directory` under `name`, never replacing
  /// anything: the copy fails if the name was taken in the meantime.
  static func publish(_ file: URL, as name: String, in directory: URL) throws -> URL {
    let destination = directory.appendingPathComponent(name)
    var coordinationError: NSError?
    var copyError: Error?
    NSFileCoordinator().coordinate(writingItemAt: destination, options: [], error: &coordinationError) { target in
      do { try FileManager.default.copyItem(at: file, to: target) } catch { copyError = error }
    }
    if let error = coordinationError ?? copyError.map({ $0 as NSError }) { throw error }
    return destination
  }

  /// Takes made files back: to the Trash on the Mac, gone from the workspace elsewhere.
  static func takeBack(_ urls: [URL]) {
    for url in urls {
      #if os(macOS)
      try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
      #else
      try? FileManager.default.removeItem(at: url)
      #endif
    }
  }
}
