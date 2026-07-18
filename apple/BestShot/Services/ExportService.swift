import Foundation

/// Exports project data as JSON or CSV, and bundles media into a ZIP, mirroring
/// the web app's Export / Download features. ZIP creation uses
/// `NSFileCoordinator`'s `.forUploading` option — no third-party dependency.
enum ExportService {

    // MARK: - JSON / CSV

    struct ExportItem: Codable {
        var filename: String
        var rank: Int?
        var type: String
        var tags: [String]
        var comment: String
        var fileSize: Int
        var importedAt: Date
    }

    struct ExportPayload: Codable {
        var project: String
        var projectDescription: String
        var exportedAt: Date
        var items: [ExportItem]
    }

    static func jsonData(for project: Project, now: Date = .now) throws -> Data {
        let items = project.sortedItems(by: .rank).map {
            ExportItem(
                filename: $0.filename,
                rank: $0.rank,
                type: $0.mediaType.rawValue,
                tags: $0.tags,
                comment: $0.comment,
                fileSize: $0.fileSize,
                importedAt: $0.importedAt
            )
        }
        let payload = ExportPayload(
            project: project.name,
            projectDescription: project.projectDescription,
            exportedAt: now,
            items: items
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func csvData(for project: Project) -> Data {
        var rows = ["rank,filename,type,tags,comment,size_bytes"]
        for item in project.sortedItems(by: .rank) {
            let rank = item.rank.map { String($0 + 1) } ?? ""
            let tags = item.tags.joined(separator: "; ")
            let cols = [rank, item.filename, item.mediaType.rawValue, tags, item.comment, String(item.fileSize)]
                .map(csvEscape)
            rows.append(cols.joined(separator: ","))
        }
        return Data(rows.joined(separator: "\n").utf8)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// Write bytes to a temporary file and return its URL (for ShareLink / fileExporter).
    static func writeTemp(_ data: Data, filename: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BestShotExport", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - ZIP

    /// One file to include in an archive. Built on the main actor from
    /// `MediaItem`s so the ZIP work can safely run off-actor.
    struct ZipEntry: Sendable {
        var sourceURL: URL
        var filename: String
    }

    /// Produce a ZIP archive containing the given media files and return its URL.
    /// Files are first staged into a temp folder so the archive has clean names.
    static func zipMedia(entries: [ZipEntry], archiveName: String) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("BestShotZip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for entry in entries {
            guard fm.fileExists(atPath: entry.sourceURL.path) else { continue }
            let dest = uniqueDestination(for: entry.filename, in: staging)
            try? fm.copyItem(at: entry.sourceURL, to: dest)
        }

        // NSFileCoordinator's forUploading option produces a zip of the folder.
        var coordError: NSError?
        var zippedURL: URL?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: staging, options: [.forUploading], error: &coordError) { tempZip in
            let out = fm.temporaryDirectory.appendingPathComponent("\(archiveName).zip")
            try? fm.removeItem(at: out)
            do {
                try fm.copyItem(at: tempZip, to: out)
                zippedURL = out
            } catch {
                zippedURL = nil
            }
        }
        if let error = coordError { throw error }
        guard let url = zippedURL else {
            throw NSError(domain: "BestShot.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP archive."])
        }
        return url
    }

    private static func uniqueDestination(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var i = 1
        repeat {
            let trial = ext.isEmpty ? "\(stem) (\(i))" : "\(stem) (\(i)).\(ext)"
            candidate = folder.appendingPathComponent(trial)
            i += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }
}
