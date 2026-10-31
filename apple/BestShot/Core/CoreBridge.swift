import Foundation

// Swift-side glue for the shared Rust core (`core/`, bound by UniFFI in
// `Generated/BestShotCore.swift`). Folder scanning, `.bestshot-cull.json`,
// culling and ranking all run in Rust, the same code the Linux app uses.

/// Sends files to the Trash for `applyCull`. The Rust `trash` crate's macOS
/// method doesn't work inside the App Sandbox, so Swift does this part.
final class FileManagerTrasher: Trasher, @unchecked Sendable {
    func trash(path: String) -> String? {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

extension FolderItem: Identifiable {
    public var id: String { rel }
    var filename: String { (rel as NSString).lastPathComponent }
    var directory: String { (rel as NSString).deletingLastPathComponent }
    var modified: Date { Date(timeIntervalSince1970: TimeInterval(mtime)) }
    var isVideo: Bool { kind == .video }
}

extension CullStore {
    static var empty: CullStore { CullStore(version: 1, decisions: [:], ranking: []) }
}

extension CoreError {
    var message: String {
        switch self {
        case .Io(let message): return message
        }
    }
}
