import Foundation

/// Tidies what PhotoKit lists. A library can hold several albums with one name,
/// from another device or an app making its own, and each comes back as its own
/// collection. Nothing here touches the albums themselves.
enum AlbumList {
    private static func key(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// One per name, the fullest of each, in name order.
    static func unique<Album>(_ albums: [Album], title: (Album) -> String?, count: (Album) -> Int) -> [Album] {
        var fullest: [String: Album] = [:]
        var unnamed: [Album] = []
        for album in albums {
            guard let name = title(album).map(key), !name.isEmpty else {
                unnamed.append(album)
                continue
            }
            if let kept = fullest[name], count(kept) >= count(album) { continue }
            fullest[name] = album
        }
        let named = fullest.values.sorted {
            (title($0) ?? "").localizedStandardCompare(title($1) ?? "") == .orderedAscending
        }
        return named + unnamed
    }

    /// The album a new name would duplicate, if there is one.
    static func existing<Album>(named name: String, in albums: [Album], title: (Album) -> String?) -> Album? {
        albums.first { title($0).map(key) == key(name) }
    }
}
