import Photos

/// The sets Photos keeps for itself that are worth going through on their own.
enum SmartSource: String, CaseIterable, Hashable {
    case screenshots, selfies, favourites, livePhotos, portraits

    var subtype: PHAssetCollectionSubtype {
        switch self {
        case .screenshots: return .smartAlbumScreenshots
        case .selfies: return .smartAlbumSelfPortraits
        case .favourites: return .smartAlbumFavorites
        case .livePhotos: return .smartAlbumLivePhotos
        case .portraits: return .smartAlbumDepthEffect
        }
    }
}

/// Selectable triage source. Albums are referenced by local identifier so the
/// value stays `Hashable` for the picker.
enum TriageSourceOption: Hashable {
    case allPhotos
    case smart(SmartSource)
    case album(String)

    static let screenshots = TriageSourceOption.smart(.screenshots)

    /// The sources shown as rows on a start screen, so they're seen, not found.
    static let quick: [TriageSourceOption] = [.allPhotos] + SmartSource.allCases.map(TriageSourceOption.smart)

    var title: String {
        switch self {
        case .allPhotos: return "All Photos"
        case .smart(.screenshots): return "Screenshots"
        case .smart(.selfies): return "Selfies"
        case .smart(.favourites): return "Favourites"
        case .smart(.livePhotos): return "Live Photos"
        case .smart(.portraits): return "Portraits"
        case .album: return "Album"
        }
    }

    var symbol: String {
        switch self {
        case .allPhotos: return "photo.on.rectangle"
        case .smart(.screenshots): return "camera.viewfinder"
        case .smart(.selfies): return "person.crop.square"
        case .smart(.favourites): return "heart"
        case .smart(.livePhotos): return "livephoto"
        case .smart(.portraits): return "person.and.background.dotted"
        case .album: return "rectangle.stack"
        }
    }
}
