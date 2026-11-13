import Foundation
import Observation

/// Stars, a colour and tags for a photo in the Photos library, which has nowhere
/// to hold them. Folders keep theirs in XMP beside the file (the Rust catalog);
/// a PHAsset has no file, and these ids mean nothing off Apple platforms, so this
/// stays in Swift, as open JSON in Application Support.
struct PhotoMark: Codable, Equatable {
    var rating = 0
    var colourSlug: String?
    var tags: [String] = []

    var colour: LabelColour? {
        get { colourSlug.flatMap(LabelColour.init(slug:)) }
        set { colourSlug = newValue?.slug }
    }

    var isEmpty: Bool { rating == 0 && colourSlug == nil && tags.isEmpty }

    func has(tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// Red is the only colour that can end in a delete, so the decision has the
    /// last word: a photo waiting to go always shows red and one kept never does.
    func shownColour(_ decision: ReviewDecision) -> LabelColour? {
        switch decision {
        case .deleted: return .red
        case .kept: return colour == nil || colour == .red ? .green : colour
        case .skipped, .undecided: return colour
        }
    }
}

extension LabelColour {
    /// Dan's flow: green good keep, yellow maybe, red delete. Yellow is a skip, so
    /// it comes round again. Blue and purple say nothing about keeping.
    var decision: ReviewDecision {
        switch self {
        case .green: return .kept
        case .yellow: return .skipped
        case .red: return .deleted
        case .blue, .purple: return .undecided
        }
    }
}

/// Every photo's mark. Each change is saved as it's made, so a pulled cable or a
/// crash can't take one with it.
@Observable
@MainActor
final class PhotoMarkStore {
    private struct File: Codable {
        var version = 1
        var marks: [String: PhotoMark]
    }

    /// The one store for the app: Triage on the phone and the monitor share it,
    /// so neither writes over the other's file.
    static let shared = PhotoMarkStore()

    private(set) var marks: [String: PhotoMark] = [:]
    /// Something went wrong reading or saving, in words for the screen.
    private(set) var warning: String?

    private let url: URL
    private let writes = DispatchQueue(label: "com.caddickbrown.bestshot.photo-marks")

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BestShot/photo-marks.json")
    }

    init(url: URL = PhotoMarkStore.defaultURL) {
        self.url = url
        load()
    }

    /// Missing is empty. A file that can't be read isn't: it's moved aside for
    /// rescue, never written over.
    private func load() {
        guard let data = try? Data(contentsOf: url) else {
            if FileManager.default.fileExists(atPath: url.path) { setAside() }
            return
        }
        do {
            marks = try JSONDecoder().decode(File.self, from: data).marks
        } catch {
            setAside()
        }
    }

    private func setAside() {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        warning = "Couldn't read the saved marks. The file is kept as \(aside.lastPathComponent)."
    }

    func mark(_ id: String) -> PhotoMark { marks[id] ?? PhotoMark() }

    func set(_ mark: PhotoMark, for id: String) {
        marks[id] = mark.isEmpty ? nil : mark
        save()
    }

    func remove(_ ids: [String]) {
        for id in ids { marks[id] = nil }
        save()
    }

    /// Tags in use, most used first, for autocomplete.
    var knownTags: [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for tag in marks.values.flatMap(\.tags) {
            counts[tag.lowercased(), default: (tag, 0)].count += 1
        }
        return counts.values.sorted { ($0.count, $1.name) > ($1.count, $0.name) }.map(\.name)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(File(marks: marks)) else { return }
        let url = url
        writes.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                let words = "Couldn't save the marks: \(error.localizedDescription)"
                Task { @MainActor in self?.warning = words }
            }
        }
    }

    /// Waits for what's been written, for anything about to rely on the file.
    func flush() { writes.sync {} }
}

/// What the monitor's walk through a session is narrowed to.
struct MonitorFilter: Equatable {
    enum Status: String, CaseIterable, Identifiable {
        case all, undecided, green, yellow, red, blue

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All photos"
            case .undecided: return "No colour yet"
            case .green: return "Green, keep"
            case .yellow: return "Yellow, maybe"
            case .red: return "Red, to delete"
            case .blue: return "Blue"
            }
        }
    }

    var status = Status.all
    var minimumStars = 0
    /// Any of these.
    var tags: Set<String> = []

    var isActive: Bool { self != MonitorFilter() }

    func matches(_ mark: PhotoMark, colour: LabelColour?) -> Bool {
        if mark.rating < minimumStars { return false }
        if !tags.isEmpty, !tags.contains(where: mark.has(tag:)) { return false }
        switch status {
        case .all: return true
        case .undecided: return colour == nil
        case .green: return colour == .green
        case .yellow: return colour == .yellow
        case .red: return colour == .red
        case .blue: return colour == .blue
        }
    }
}
