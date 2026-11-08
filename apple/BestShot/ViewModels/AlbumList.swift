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
}
