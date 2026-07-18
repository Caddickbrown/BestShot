import Foundation
import ImageIO

/// Extracts EXIF metadata from image data using ImageIO, mirroring the camera
/// info shown in the web app's fullscreen viewer.
enum ExifExtractor {

    static func extract(from data: Data) -> ExifData? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        var exif = ExifData()

        exif.pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        exif.pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue

        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            exif.make = tiff[kCGImagePropertyTIFFMake] as? String
            exif.model = tiff[kCGImagePropertyTIFFModel] as? String
        }

        if let ex = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let lens = ex[kCGImagePropertyExifLensModel] as? String {
                exif.lens = lens
            }
            if let f = ex[kCGImagePropertyExifFNumber] as? NSNumber {
                exif.aperture = String(format: "f/%.1f", f.doubleValue)
            }
            if let exposure = ex[kCGImagePropertyExifExposureTime] as? NSNumber {
                exif.shutterSpeed = formatShutter(exposure.doubleValue)
            }
            if let isoArray = ex[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber],
               let iso = isoArray.first {
                exif.iso = "ISO \(iso.intValue)"
            }
            if let focal = ex[kCGImagePropertyExifFocalLength] as? NSNumber {
                exif.focalLength = String(format: "%.0f mm", focal.doubleValue)
            }
            if let dateString = ex[kCGImagePropertyExifDateTimeOriginal] as? String {
                exif.dateTaken = exifDateFormatter.date(from: dateString)
            }
        }

        return exif.isEmpty ? nil : exif
    }

    private static func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.1f s", seconds)
        } else if seconds > 0 {
            return "1/\(Int((1.0 / seconds).rounded())) s"
        }
        return "\(seconds) s"
    }

    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
