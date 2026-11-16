import Foundation

/// Tidies what PhotoKit lists. A library can hold several albums with one name,
/// from another device or an app making its own, and each comes back as its own
/// collection. Nothing here touches the albums themselves.
enum AlbumList {
    private static func key(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// One per name in each folder, the fullest of each, in name order. Albums
    /// with one name in different folders are different albums, and all stay.
    static func unique<Album>(_ albums: [Album], title: (Album) -> String?, count: (Album) -> Int,
                              folder: (Album) -> String? = { _ in nil }) -> [Album] {
        var fullest: [String: Album] = [:]
        var unnamed: [Album] = []
        for album in albums {
            guard let name = title(album).map(key), !name.isEmpty else {
                unnamed.append(album)
                continue
            }
            let place = name + "\u{0}" + (folder(album).map(key) ?? "")
            if let kept = fullest[place], count(kept) >= count(album) { continue }
            fullest[place] = album
        }
        let named = fullest.values.sorted {
            let byName = (title($0) ?? "").localizedStandardCompare(title($1) ?? "")
            if byName != .orderedSame { return byName == .orderedAscending }
            return (folder($0) ?? "").localizedStandardCompare(folder($1) ?? "") == .orderedAscending
        }
        return named + unnamed
    }

    /// The album a new name would duplicate, if there is one. A new album is
    /// made at the top level, so one there with the name comes first.
    static func existing<Album>(named name: String, in albums: [Album], title: (Album) -> String?,
                                folder: (Album) -> String? = { _ in nil }) -> Album? {
        let same = albums.filter { title($0).map(key) == key(name) }
        return same.first { folder($0) == nil } ?? same.first
    }

    /// How an album reads in a list: "Lisbon · Imported from Google", or just its
    /// name at the top level.
    static func label(title: String?, folder: String?) -> String {
        let name = title ?? "Album"
        guard let folder, !folder.trimmingCharacters(in: .whitespaces).isEmpty else { return name }
        return "\(name) · \(folder)"
    }

    // MARK: Choosing an album to go through

    /// The albums Triage or Organise can go through: never an empty one, and
    /// only those whose name or folder holds what's typed. An album whose count
    /// isn't known yet is left out until it is.
    static func sources<Album>(_ albums: [Album], query: String, title: (Album) -> String?,
                               folder: (Album) -> String? = { _ in nil }, count: (Album) -> Int?) -> [Album] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return albums.filter { album in
            guard let n = count(album), n > 0 else { return false }
            guard !q.isEmpty else { return true }
            return (title(album) ?? "").localizedCaseInsensitiveContains(q)
                || (folder(album) ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    /// What ↵ starts with: the album with exactly the name typed (one outside any
    /// folder first), or else the only one that matches. Never a guess between
    /// several.
    static func sourceToStart<Album>(_ albums: [Album], query: String, title: (Album) -> String?,
                                     folder: (Album) -> String? = { _ in nil }, count: (Album) -> Int?) -> Album? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let matches = sources(albums, query: q, title: title, folder: folder, count: count)
        if let exact = existing(named: q, in: matches, title: title, folder: folder) { return exact }
        return matches.count == 1 ? matches[0] : nil
    }
    // MARK: Albums like a new name

    /// Albums whose names look like `name`, best first, so a new album isn't
    /// made beside one that's already there: "lisbon" finds "Lisbon 2023",
    /// "grand kids" finds "Grandkids", "Lisbn" finds "Lisbon". Accents, case and
    /// punctuation don't count. Nothing for fewer than two letters.
    static func similar<Album>(to name: String, in albums: [Album], title: (Album) -> String?,
                               limit: Int = 6) -> [Album] {
        let typed = fold(name)
        guard typed.filter(\.isLetter).count + typed.filter(\.isNumber).count >= 2 else { return [] }
        let scored = albums.enumerated().compactMap { i, album -> (Album, Int, Int)? in
            guard let t = title(album), let score = likeness(typed, fold(t)) else { return nil }
            return (album, score, i)
        }
        return scored.sorted { ($0.1, $1.2) > ($1.1, $0.2) }.prefix(limit).map(\.0)
    }

    /// Lower case, no accents, words split on anything that isn't a letter or digit.
    private static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(plain.map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// How alike two folded names are, or nil when they aren't.
    static func likeness(_ typed: String, _ title: String) -> Int? {
        guard !typed.isEmpty, !title.isEmpty else { return nil }
        let a = typed.replacingOccurrences(of: " ", with: "")
        let b = title.replacingOccurrences(of: " ", with: "")
        if a == b { return 100 }                                     // "Grand Kids" and "Grandkids"
        if b.hasPrefix(a) { return 80 }
        if b.contains(a) || (a.count >= 4 && a.contains(b)) { return 70 }
        // A word typed starts a word of the name, or the other way round.
        let typedWords: [String] = typed.components(separatedBy: " ").filter { $0.count >= 3 }
        let titleWords: [String] = title.components(separatedBy: " ").filter { $0.count >= 3 }
        var best: Int?
        for w in typedWords {
            for t in titleWords {
                if t.hasPrefix(w) || w.hasPrefix(t) { best = max(best ?? 0, 60) }
                else if w.count >= 4, t.count >= 4, distance(w, t) <= (max(w.count, t.count) >= 7 ? 2 : 1) {
                    best = max(best ?? 0, 50)                         // "Lisbn" and "Lisbon"
                }
            }
        }
        if let best { return best }
        // A slip in the whole name.
        if a.count >= 4, distance(a, b) <= (max(a.count, b.count) >= 8 ? 2 : 1) { return 45 }
        return nil
    }

    /// Letters to add, take away or change to turn one into the other.
    static func distance(_ x: String, _ y: String) -> Int {
        let a = Array(x), b = Array(y)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let was = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = was
            }
        }
        return row[b.count]
    }
}
