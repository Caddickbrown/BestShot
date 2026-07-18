import Foundation

/// Whether a media item is a still image or a video.
enum MediaType: String, Codable, Hashable {
    case image
    case video
}

/// Gallery filter mirroring the web app's "All / Photos / Videos" toggle.
enum MediaFilter: String, CaseIterable, Identifiable {
    case all
    case photos
    case videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .photos: return "Photos"
        case .videos: return "Videos"
        }
    }

    func matches(_ item: MediaItem) -> Bool {
        switch self {
        case .all: return true
        case .photos: return item.mediaType == .image
        case .videos: return item.mediaType == .video
        }
    }
}

/// Sort options mirroring the web app dropdown.
enum SortOption: String, CaseIterable, Identifiable {
    case rank
    case nameAsc
    case nameDesc
    case dateNewest
    case dateOldest
    case sizeLargest
    case sizeSmallest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rank: return "Rank"
        case .nameAsc: return "Name (A–Z)"
        case .nameDesc: return "Name (Z–A)"
        case .dateNewest: return "Date (Newest)"
        case .dateOldest: return "Date (Oldest)"
        case .sizeLargest: return "Size (Largest)"
        case .sizeSmallest: return "Size (Smallest)"
        }
    }

    /// A comparator for two media items. Unranked items sort after ranked ones
    /// when sorting by rank (matching the web app, where "New" items trail).
    func comparator(_ a: MediaItem, _ b: MediaItem) -> Bool {
        switch self {
        case .rank:
            switch (a.rank, b.rank) {
            case let (ra?, rb?): return ra < rb
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            }
        case .nameAsc:
            return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
        case .nameDesc:
            return a.filename.localizedStandardCompare(b.filename) == .orderedDescending
        case .dateNewest:
            return a.importedAt > b.importedAt
        case .dateOldest:
            return a.importedAt < b.importedAt
        case .sizeLargest:
            return a.fileSize > b.fileSize
        case .sizeSmallest:
            return a.fileSize < b.fileSize
        }
    }
}

/// Thumbnail grid density, mirroring the S / M / L buttons.
enum GridSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }

    /// Minimum cell width used with an adaptive `LazyVGrid`.
    var minCellWidth: CGFloat {
        switch self {
        case .small: return 90
        case .medium: return 140
        case .large: return 220
        }
    }
}

/// Which items a comparison session ranks.
enum ComparisonScope: String {
    /// Compare every item in the project from scratch.
    case all
    /// Only place the unranked ("New") items relative to the existing order.
    case unranked
}
