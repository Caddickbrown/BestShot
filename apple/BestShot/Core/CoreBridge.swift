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

extension LabelColour: CaseIterable, Identifiable {
    public static var allCases: [LabelColour] { [.red, .yellow, .green, .blue, .purple] }
    public var id: String { slug }

    /// Lowercase name, as in `labels.json` and the Triage export.
    var slug: String {
        switch self {
        case .red: return "red"
        case .yellow: return "yellow"
        case .green: return "green"
        case .blue: return "blue"
        case .purple: return "purple"
        }
    }

    var title: String { slug.capitalized }

    /// The key that sets this colour. Purple has none: 1-5 are stars and 0
    /// clears, which leaves four digits.
    var key: String? {
        switch self {
        case .red: return "6"
        case .yellow: return "7"
        case .green: return "8"
        case .blue: return "9"
        case .purple: return nil
        }
    }

    init?(slug: String) {
        guard let match = Self.allCases.first(where: { $0.slug == slug }) else { return nil }
        self = match
    }
}

extension FolderFilter {
    /// Matches everything.
    static var all: FolderFilter {
        FolderFilter(status: .all, stars: .any, labels: [], keywords: [], anyKeyword: false)
    }

    var isActive: Bool { self != .all }
}

extension CoreError {
    var message: String {
        switch self {
        case .Io(let message): return message
        }
    }
}
