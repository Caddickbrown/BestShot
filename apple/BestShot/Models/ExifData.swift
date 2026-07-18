import Foundation

/// Camera / image metadata extracted at import time, mirroring the EXIF panel
/// in the web app's fullscreen viewer. Stored inline on `MediaItem` as a
/// Codable value.
struct ExifData: Codable, Hashable {
    var make: String?
    var model: String?
    var lens: String?
    var aperture: String?        // e.g. "f/2.8"
    var shutterSpeed: String?    // e.g. "1/250 s"
    var iso: String?             // e.g. "ISO 400"
    var focalLength: String?     // e.g. "35 mm"
    var dateTaken: Date?
    var pixelWidth: Int?
    var pixelHeight: Int?

    var isEmpty: Bool {
        make == nil && model == nil && lens == nil && aperture == nil &&
        shutterSpeed == nil && iso == nil && focalLength == nil &&
        dateTaken == nil && pixelWidth == nil && pixelHeight == nil
    }

    /// Ordered list of populated fields for display, `(label, value)`.
    var displayRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let v = dimensionsString { rows.append(("Dimensions", v)) }
        if let v = make { rows.append(("Make", v)) }
        if let v = model { rows.append(("Model", v)) }
        if let v = lens { rows.append(("Lens", v)) }
        if let v = focalLength { rows.append(("Focal length", v)) }
        if let v = aperture { rows.append(("Aperture", v)) }
        if let v = shutterSpeed { rows.append(("Shutter", v)) }
        if let v = iso { rows.append(("ISO", v)) }
        if let d = dateTaken {
            rows.append(("Taken", d.formatted(date: .abbreviated, time: .shortened)))
        }
        return rows
    }

    var dimensionsString: String? {
        guard let w = pixelWidth, let h = pixelHeight else { return nil }
        return "\(w) × \(h)"
    }
}
