import Foundation
import CryptoKit

/// Owns all on-disk media I/O. Media files live under
/// `Application Support/BestShotMedia/<projectID>/<filename>` and thumbnails
/// under `Application Support/BestShotThumbs/<projectID>/<filename>.<ext>`.
///
/// This mirrors the web app's "files on disk + JSON sidecar metadata" split:
/// SwiftData holds the metadata, the filesystem holds the bytes.
final class MediaStore {
    static let shared = MediaStore()

    let mediaRoot: URL
    let thumbRoot: URL

    private let fm = FileManager.default

    private init() {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        mediaRoot = base.appendingPathComponent("BestShotMedia", isDirectory: true)
        thumbRoot = base.appendingPathComponent("BestShotThumbs", isDirectory: true)
        try? fm.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
        try? fm.createDirectory(at: thumbRoot, withIntermediateDirectories: true)
    }

    // MARK: - Path helpers

    func absoluteMediaURL(for relativePath: String) -> URL {
        mediaRoot.appendingPathComponent(relativePath)
    }

    func absoluteThumbURL(for relativePath: String) -> URL {
        thumbRoot.appendingPathComponent(relativePath)
    }

    private func projectFolder(_ projectID: UUID, root: URL) -> URL {
        let url = root.appendingPathComponent(projectID.uuidString, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Import

    /// Copy raw bytes into the project folder, resolving name collisions by
    /// appending " (n)". Returns `(relativePath, uniqueFilename)`.
    func storeMedia(data: Data, preferredName: String, projectID: UUID) throws -> (relativePath: String, filename: String) {
        let folder = projectFolder(projectID, root: mediaRoot)
        let unique = uniqueName(for: preferredName, in: folder)
        let dest = folder.appendingPathComponent(unique)
        try data.write(to: dest, options: .atomic)
        return ("\(projectID.uuidString)/\(unique)", unique)
    }

    func storeThumbnail(data: Data, filename: String, projectID: UUID) throws -> String {
        let folder = projectFolder(projectID, root: thumbRoot)
        let name = "\(filename).heic"
        let dest = folder.appendingPathComponent(name)
        try data.write(to: dest, options: .atomic)
        return "\(projectID.uuidString)/\(name)"
    }

    private func uniqueName(for name: String, in folder: URL) -> String {
        let candidate = folder.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var i = 1
        while true {
            let trial = ext.isEmpty ? "\(stem) (\(i))" : "\(stem) (\(i)).\(ext)"
            if !fm.fileExists(atPath: folder.appendingPathComponent(trial).path) {
                return trial
            }
            i += 1
        }
    }

    // MARK: - Delete

    func deleteMedia(relativePath: String, thumbnailRelativePath: String?) {
        try? fm.removeItem(at: absoluteMediaURL(for: relativePath))
        if let t = thumbnailRelativePath {
            try? fm.removeItem(at: absoluteThumbURL(for: t))
        }
    }

    func deleteProjectFolder(projectID: UUID) {
        try? fm.removeItem(at: mediaRoot.appendingPathComponent(projectID.uuidString))
        try? fm.removeItem(at: thumbRoot.appendingPathComponent(projectID.uuidString))
    }

    // MARK: - Hashing (duplicate detection)

    func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
