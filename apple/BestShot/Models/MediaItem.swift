import Foundation
import SwiftData

/// A single photo or video within a project.
///
/// The media bytes and generated thumbnail live on disk under the app's
/// Application Support container (see `MediaStore`); this model stores only
/// metadata and the *relative* paths so the store stays small and export/ZIP
/// stays simple.
@Model
final class MediaItem {
    /// Stable identifier for UI selection. (Named `uuid` rather than `id` to
    /// avoid clashing with SwiftData's `persistentModelID`-based `Identifiable`.)
    @Attribute(.unique) var uuid: UUID

    /// Original file name (used for display, search, and export).
    var filename: String
    /// Path relative to the media root, e.g. "<projectID>/<filename>".
    var relativePath: String
    /// Path relative to the thumbnail root, if a thumbnail was generated.
    var thumbnailRelativePath: String?

    var mediaTypeRaw: String
    /// nil == unranked ("New"). Otherwise 0-based position in the ranking.
    var rank: Int?

    var tags: [String]
    var comment: String
    var fileSize: Int
    var importedAt: Date
    /// SHA-256 hex of the file bytes, used for duplicate detection within a project.
    var contentHash: String

    /// Inline EXIF metadata (Codable). nil for videos or when unavailable.
    var exif: ExifData?

    var project: Project?

    init(
        filename: String,
        relativePath: String,
        mediaType: MediaType,
        fileSize: Int,
        contentHash: String,
        thumbnailRelativePath: String? = nil,
        exif: ExifData? = nil
    ) {
        self.uuid = UUID()
        self.filename = filename
        self.relativePath = relativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.mediaTypeRaw = mediaType.rawValue
        self.rank = nil
        self.tags = []
        self.comment = ""
        self.fileSize = fileSize
        self.importedAt = .now
        self.contentHash = contentHash
        self.exif = exif
    }

    // MARK: Derived

    var mediaType: MediaType {
        get { MediaType(rawValue: mediaTypeRaw) ?? .image }
        set { mediaTypeRaw = newValue.rawValue }
    }

    var isRanked: Bool { rank != nil }

    /// Absolute on-disk URL to the media file.
    var fileURL: URL { MediaStore.shared.absoluteMediaURL(for: relativePath) }

    /// Absolute on-disk URL to the thumbnail, if any.
    var thumbnailURL: URL? {
        thumbnailRelativePath.map { MediaStore.shared.absoluteThumbURL(for: $0) }
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}
