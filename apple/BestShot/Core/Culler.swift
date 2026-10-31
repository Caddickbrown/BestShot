import Foundation

/// Applying a cull: moving rejected items (and their companions) out of the
/// way. Port of `desktop/src-tauri/src/cull.rs`.
enum Culler {

    enum Mode {
        /// The system Trash, so everything stays recoverable.
        case trash
        /// `<root>/_Rejected/<original relative path>`.
        case folder
    }

    struct Failure: Hashable {
        let rel: String
        let error: String
    }

    struct Outcome {
        /// Items culled successfully.
        var items = 0
        /// Files moved, including companions.
        var files = 0
        var bytes: Int64 = 0
        /// Relative paths of the items that were culled.
        var culled: [String] = []
        var failed: [Failure] = []
    }

    static func apply(root: URL, rejects: [FolderItem], mode: Mode) -> Outcome {
        let fm = FileManager.default
        var out = Outcome()
        for item in rejects {
            let rels = [item.rel] + item.companions
            let existing = rels.filter { fm.fileExists(atPath: root.appendingPathComponent($0).path) }
            let bytes = existing.reduce(Int64(0)) { sum, rel in
                let attrs = try? fm.attributesOfItem(atPath: root.appendingPathComponent(rel).path)
                return sum + ((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
            }
            do {
                for rel in existing {
                    let source = root.appendingPathComponent(rel)
                    switch mode {
                    case .trash:
                        try fm.trashItem(at: source, resultingItemURL: nil)
                    case .folder:
                        let dest = uniqueURL(root.appendingPathComponent(FolderLibrary.rejectDir).appendingPathComponent(rel))
                        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fm.moveItem(at: source, to: dest)
                    }
                }
                out.items += 1
                out.files += existing.count
                out.bytes += bytes
                out.culled.append(item.rel)
            } catch {
                out.failed.append(Failure(rel: item.rel, error: error.localizedDescription))
            }
        }
        return out
    }

    /// `photo.jpg` -> `photo (1).jpg` -> `photo (2).jpg` ... until unused.
    static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var n = 1
        while true {
            let name = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
