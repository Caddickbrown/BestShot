import Photos

/// The sets Photos keeps for itself that are worth going through on their own.
enum SmartSource: String, CaseIterable, Hashable {
    case screenshots, selfies, favourites, livePhotos, portraits, hidden

    var subtype: PHAssetCollectionSubtype {
        switch self {
        case .screenshots: return .smartAlbumScreenshots
        case .selfies: return .smartAlbumSelfPortraits
        case .favourites: return .smartAlbumFavorites
        case .livePhotos: return .smartAlbumLivePhotos
        case .portraits: return .smartAlbumDepthEffect
        case .hidden: return .smartAlbumAllHidden
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
        case .smart(.hidden): return "Hidden"
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
        case .smart(.hidden): return "eye.slash"
        case .album: return "rectangle.stack"
        }
    }
}

extension TriageSourceOption {
    /// Photos' Hidden album: behind Face ID, as it is in Photos.
    var isHidden: Bool { self == .smart(.hidden) }
}

extension TriageSourceOption {
    /// Since iOS 16 Photos gives apps no hidden photo while Settings › Apps ›
    /// Photos › Use Face ID is on (the default), even when asked with
    /// includeHiddenAssets, and doesn't say so: Hidden just counts 0.
    static let hiddenLockedNote =
        "Photos keeps hidden photos from apps while Settings › Apps › Photos › Use Face ID is on. Turn it off to go through Hidden here."

    /// The count beside a source. Hidden at 0 shows none: it's more likely
    /// locked by Photos than empty, and BestShot can't tell which.
    func countText(_ n: Int?) -> String? {
        guard let n else { return nil }
        if isHidden && n == 0 { return nil }
        return "\(n)"
    }

    /// Why Hidden shows no count, when it doesn't.
    func countNote(_ n: Int?) -> String? {
        isHidden && n == 0 ? Self.hiddenLockedNote : nil
    }

    /// The message for a session that found nothing.
    func nothingFound(_ fallback: String) -> String {
        isHidden ? "Nothing to go through in Hidden. " + Self.hiddenLockedNote : fallback
    }
}
