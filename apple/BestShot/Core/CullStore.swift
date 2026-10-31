import Foundation

/// A per-folder review decision. Raw values match the Linux app's JSON.
enum CullDecision: String, Codable, Hashable {
    case keep
    case reject
}

/// `<folder>/.bestshot-cull.json`, shared byte-for-byte in meaning with the
/// Linux app (`desktop/src-tauri/src/store.rs`), so a folder can be culled on
/// either machine:
///
///     { "version": 1,
///       "decisions": { "trip/IMG_0001.HEIC": "keep", ... },
///       "ranking": ["trip/IMG_0001.HEIC", ...] }
///
/// Keys are paths relative to the folder, always `/`-separated.
struct CullStore: Codable, Equatable {
    static let fileName = ".bestshot-cull.json"

    var version: Int = 1
    /// Relative path -> decision. Unreviewed files have no entry.
    var decisions: [String: CullDecision] = [:]
    /// Relative paths in rank order, best first.
    var ranking: [String] = []

    init(version: Int = 1, decisions: [String: CullDecision] = [:], ranking: [String] = []) {
        self.version = version
        self.decisions = decisions
        self.ranking = ranking
    }

    // Missing fields default, like serde's `#[serde(default)]`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        decisions = try c.decodeIfPresent([String: CullDecision].self, forKey: .decisions) ?? [:]
        ranking = try c.decodeIfPresent([String].self, forKey: .ranking) ?? []
    }

    static func url(in root: URL) -> URL {
        root.appendingPathComponent(fileName)
    }

    /// Loads the store for `root`. A missing file is an empty store. An
    /// unreadable one is set aside (never silently overwritten) and a warning
    /// is returned.
    static func load(from root: URL) -> (store: CullStore, warning: String?) {
        let file = url(in: root)
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return (CullStore(), nil)
        } catch {
            return (CullStore(), "Couldn't read saved decisions: \(error.localizedDescription)")
        }
        do {
            return (try JSONDecoder().decode(CullStore.self, from: data), nil)
        } catch {
            let backup = root.appendingPathComponent(fileName + ".corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: file, to: backup)
            return (CullStore(),
                    "Saved decisions were unreadable; moved them to \(backup.lastPathComponent) and started fresh.")
        }
    }

    /// Atomically writes the store (temporary file + rename).
    func save(to root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: Self.url(in: root), options: .atomic)
    }

    /// Forgets decisions and ranking entries for files that no longer exist.
    /// Returns true if anything was removed.
    @discardableResult
    mutating func pruneMissing(in root: URL) -> Bool {
        let fm = FileManager.default
        let exists = { (rel: String) in fm.fileExists(atPath: root.appendingPathComponent(rel).path) }
        let before = (decisions.count, ranking.count)
        decisions = decisions.filter { exists($0.key) }
        ranking = ranking.filter(exists)
        return (decisions.count, ranking.count) != before
    }
}
