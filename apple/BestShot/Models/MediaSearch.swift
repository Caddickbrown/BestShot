import Foundation

/// What the search box looks through: everything shown beside a photo, so
/// anything you can read there, you can find. Every word has to be somewhere.
enum MediaSearch {
    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func matches(_ query: String, filename: String, tags: [String], comment: String, project: String?) -> Bool {
        let words = folded(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = folded(([filename, comment, project ?? ""] + tags).joined(separator: "\n"))
        return words.allSatisfy { haystack.contains($0) }
    }

    static func matches(_ query: String, item: MediaItem) -> Bool {
        matches(query, filename: item.filename, tags: item.tags, comment: item.comment, project: item.project?.name)
    }
}
