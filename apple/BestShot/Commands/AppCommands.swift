import Foundation
import Observation

/// Where the phone's screens meet the ⌘K menu. Each screen says what it's
/// showing (`place`, `project`, `triageGrid`), and a command for a screen goes
/// out as a `Request` that the screen showing it carries out, with its own
/// sheets and confirmations, as its own buttons do.
@Observable
@MainActor
final class AppCommands {
    static let shared = AppCommands()

    enum Place: Equatable {
        case home, triage, organise, rank, allMedia, folders, joinVideos, antiCrop, glue, multiCrop
        case project(UUID)
    }

    struct Request: Equatable {
        let id = UUID()
        let command: BestShotCommand
    }

    /// The main menu's choice, as RootView has it.
    var place = Place.home
    /// The project screen open now, with its sort, filter and selection.
    var project: BestShotCommandState.OpenProject?
    /// Triage on the phone is showing the whole set rather than one photo.
    var triageGrid = false
    /// The last command sent to a screen.
    private(set) var request: Request?
    /// Something to tell the user, from a command that ran with no screen of its own to say it.
    var message: String?
    /// Closes the sheet on top the way Esc does: RootView's Esc stack.
    @ObservationIgnored var leaveSheet: () -> Void = {}

    func send(_ command: BestShotCommand) {
        request = Request(command: command)
    }
}

extension BestShotCommandState {
    static let triageOrderKey = "triage.order"
    static let organiseOrderKey = "organise.order"

    /// What the phone shows now, for the menu: the place in the main menu, and
    /// the sessions the phone and the monitor share, through the same library
    /// the monitor uses.
    @MainActor
    static func phone(place: AppCommands.Place, triageGrid: Bool = false, triageCanUndo: Bool = false,
                      project: OpenProject? = nil, library: MonitorLibrary, marks: PhotoMarkStore, rank: RankBoard?,
                      appearance: Appearance = .system, monitorConnected: Bool = false, monitorPaused: Bool = false,
                      textScale: Double = 1, defaults: UserDefaults = .standard) -> BestShotCommandState {
        var s = BestShotCommandState()
        s.display = .phone
        s.appearance = appearance
        s.hasPhotoAccess = library.hasPhotoAccess
        s.labelNames = Dictionary(uniqueKeysWithValues: LabelColour.allCases.map { ($0, library.labelName($0)) })
        s.knownTags = marks.knownTags
        s.monitorConnected = monitorConnected
        s.monitorPaused = monitorPaused
        s.textScale = textScale
        s.projects = library.projects.map { .init(id: $0.id, name: $0.name, count: $0.count) }
        s.sources = library.sources.map { .init(option: $0.option, title: $0.title) }
        s.order = defaults.string(forKey: triageOrderKey).flatMap(SessionOrder.init(rawValue:)) ?? .newest
        s.organiseOrder = defaults.string(forKey: organiseOrderKey).flatMap(SessionOrder.init(rawValue:)) ?? .newest

        s.triageOpen = !library.triageIDs.isEmpty
        s.triageWaiting = library.triageWaiting
        s.organiseOpen = library.organiseOpen && library.organisePhoto != nil
        s.organisePaused = library.organisePhoto != nil && !library.organiseOpen
        s.albums = library.organiseAlbums.map { .init(id: $0.id, title: $0.title, added: $0.added) }
        s.oneAlbum = library.organiseOneAlbum
        if let rank {
            s.rankPool = rank.pool.count
            s.ranked = rank.ranked.count
            s.unranked = rank.unranked.count
            s.canPutRankingBack = rank.cleared != nil
        }

        switch place {
        case .home, .folders: s.screen = .home
        case .triage:
            if library.triageShowing {
                s.screen = triageGrid ? .triageGrid : .triage
                s.canUndo = triageCanUndo
            } else {
                s.screen = .triageStart
            }
        case .organise:
            s.screen = s.organiseOpen ? .organise : .organiseStart
            if s.organiseOpen { s.canUndo = library.organiseCanUndo }
        case .rank: s.screen = rank?.compare == nil ? .rank : .rankCompare
        case .allMedia: s.screen = .allMedia
        case .joinVideos, .antiCrop, .glue, .multiCrop: s.screen = .tool
        case .project:
            s.screen = project == nil ? .home : .project
            s.project = project
        }
        if s.screen == .triage {
            let ids = library.triageIDs
            let at = library.triageIndex
            if ids.indices.contains(at) {
                let id = ids[at]
                let mark = marks.mark(id)
                s.photo = .init(id: id, stars: mark.rating, colour: mark.shownColour(library.decision(id)),
                                favourite: library.isFavourite(id), tags: mark.tags)
            }
        }
        return s
    }
}
