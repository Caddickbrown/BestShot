import Foundation
import SwiftData
import UniformTypeIdentifiers

/// One file the user asked to import (from Photos or Files).
struct ImportCandidate: Identifiable {
    let id = UUID()
    var filename: String
    var data: Data
    var mediaType: MediaType
}

struct ImportResult {
    var added: Int = 0
    /// Filenames skipped because an identical file already existed in the project.
    var duplicates: [String] = []
}

/// Copies imported media onto disk, generates thumbnails + EXIF, and creates
/// `MediaItem` records. Heavy work (hashing, thumbnailing) runs off the main
/// actor; SwiftData mutations happen on the main actor.
@MainActor
enum ImportService {

    /// Precomputed, disk-independent parts of an item so the expensive work can
    /// run off the main actor before we touch SwiftData.
    private struct Prepared {
        var filename: String
        var data: Data
        var mediaType: MediaType
        var hash: String
        var thumbnail: Data?
        var exif: ExifData?
    }

    static func importItems(
        _ candidates: [ImportCandidate],
        into project: Project,
        context: ModelContext,
        skipDuplicates: Bool = true
    ) async -> ImportResult {
        let existingHashes = Set(project.items.map(\.contentHash))
        let projectID = project.uuid
        var result = ImportResult()

        for candidate in candidates {
            // Expensive work off the main actor.
            let prepared = await Task.detached(priority: .userInitiated) { () -> Prepared in
                let hash = MediaStore.shared.sha256Hex(candidate.data)
                var thumb: Data?
                var exif: ExifData?
                if candidate.mediaType == .image {
                    thumb = ThumbnailService.imageThumbnail(from: candidate.data)
                    exif = ExifExtractor.extract(from: candidate.data)
                }
                return Prepared(
                    filename: candidate.filename,
                    data: candidate.data,
                    mediaType: candidate.mediaType,
                    hash: hash,
                    thumbnail: thumb,
                    exif: exif
                )
            }.value

            if skipDuplicates, existingHashes.contains(prepared.hash) {
                result.duplicates.append(prepared.filename)
                continue
            }

            do {
                let stored = try MediaStore.shared.storeMedia(
                    data: prepared.data,
                    preferredName: prepared.filename,
                    projectID: projectID
                )

                var thumbPath: String?
                var thumbData = prepared.thumbnail
                // Videos need the file on disk before a frame can be grabbed.
                if prepared.mediaType == .video {
                    let url = MediaStore.shared.absoluteMediaURL(for: stored.relativePath)
                    thumbData = await ThumbnailService.videoThumbnail(url: url)
                }
                if let td = thumbData {
                    thumbPath = try? MediaStore.shared.storeThumbnail(
                        data: td, filename: stored.filename, projectID: projectID
                    )
                }

                let item = MediaItem(
                    filename: stored.filename,
                    relativePath: stored.relativePath,
                    mediaType: prepared.mediaType,
                    fileSize: prepared.data.count,
                    contentHash: prepared.hash,
                    thumbnailRelativePath: thumbPath,
                    exif: prepared.exif
                )
                item.project = project
                context.insert(item)
                result.added += 1
            } catch {
                // Skip files that fail to write; continue with the rest.
                continue
            }
        }

        try? context.save()
        return result
    }

    /// Infer a media type from a file extension / UTType.
    static func mediaType(forExtension ext: String) -> MediaType {
        let lower = ext.lowercased()
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "webm", "m4v", "wmv", "flv", "3gp", "qt"]
        if videoExts.contains(lower) { return .video }
        if let type = UTType(filenameExtension: lower) {
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        }
        return .image
    }
}
