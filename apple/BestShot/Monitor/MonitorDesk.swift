import SwiftUI
import Observation

/// One of the monitor's screens. The stack always starts at `home`, the main
/// menu, so Esc has a way down from anywhere.
enum MonitorPane: Hashable {
    case home
    case triage, loupe, grid, filters
    case rank, rankCompare
    case organiseHome, organise
    case media(project: UUID?), mediaPhoto(project: UUID?)
    case projects
    case settings
}

/// What ↵ does on a row.
enum MonitorRowAction: Equatable {
    case none
    case section(MonitorSection)
    case allowPhotos
    case order(SessionOrder), source(TriageSourceOption), startTriage, resumeTriage
    case status(MonitorFilter.Status), stars(Int), tag(String), clearFilters
    case compare(RankScope), saveAlbum
    case organiseOrder(SessionOrder), organiseSource(TriageSourceOption), organiseFolder, startOrganise, resumeOrganise
    case album(String), newAlbum
    case project(UUID), allMedia, mediaItem
    case rename(LabelColour), textSize, pause
}

/// One line of a list. Lists are all the same thing on the monitor, so they all
/// scroll, keep the lit row in view and answer to the same keys.
struct MonitorRow: Identifiable, Equatable {
    let id: String
    var title: String
    var detail: String?
    /// The heading this row sits under.
    var group: String?
    /// A small photo beside the row.
    var photo: String?
    /// Filled in for a choice: on or off.
    var isOn: Bool?
    var action = MonitorRowAction.none
}

/// A word being typed on the monitor. There's no field there to type in, so the
/// keys build it here.
struct MonitorEntry: Equatable {
    enum Kind: Hashable {
        case tag
        case rename(LabelColour)
        case album
    }

    let kind: Kind
    let title: String
    var text: String
    /// What's known that starts with the text.
    var suggestions: [String] = []
}

/// The way out of Triage. Nothing starts lit, so a stray ↵ does nothing, and the
/// delete itself is the existing one: `TriageSession.commitDeletions`, which puts
/// up the system's own confirmation and moves photos to Recently Deleted.
struct MonitorFinish: Equatable {
    enum Choice: Equatable { case delete, finish, keepGoing }

    var choices: [Choice]
    var chosen: Choice?
    var isDeleting = false
    var message: String?
}

enum MonitorOverlay: Equatable {
    case palette(MonitorPalette)
    case help
    case entry(MonitorEntry)
    case finish(MonitorFinish)
}

/// One imported photo from a project.
struct MonitorMediaItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    /// In the order the list shows them.
    let tags: [String]
}

/// Where the desk gets what it shows and where its changes go: Photos and the
/// sessions on a phone, a stand-in in the tests. Everything a change could lose
/// is held behind this, not by the monitor, so the monitor can come and go.
@MainActor
protocol MonitorLibrary: AnyObject {
    // Photos access
    var hasPhotoAccess: Bool { get }
    var canAskForPhotoAccess: Bool { get }
    func askForPhotoAccess() async

    // Triage
    var triageIDs: [String] { get }
    var triageIndex: Int { get set }
    /// How many are marked to delete.
    var triageWaiting: Int { get }
    func decision(_ id: String) -> ReviewDecision
    func setDecision(_ decision: ReviewDecision, _ id: String)
    func isFavourite(_ id: String) -> Bool
    /// The current photo's heart.
    func toggleFavourite()
    var sources: [(option: TriageSourceOption, title: String)] { get }
    func reloadSources()
    /// Nil when it started, or what to tell the user.
    func startTriage(order: SessionOrder, source: TriageSourceOption) async -> String?
    /// Back to the start: a session with deletes marked waits to be resumed.
    func leaveTriage()
    func resumeTriage()
    /// The existing confirm path. The number deleted, 0 if it was turned down.
    func commitDeletions() async -> Int
    func endTriage()
    func details(_ id: String) -> [String]

    // Rank
    func rankBoard() async -> RankBoard?
    func saveRankAlbum(_ ids: [String]) async -> String

    // Organise
    var organisePhoto: String? { get }
    var organiseProgress: String { get }
    var organiseAlbums: [(id: String, title: String, added: Bool)] { get }
    func startOrganise(order: SessionOrder, source: TriageSourceOption) async -> String?
    /// The photo files in a folder chosen in Files on the phone, as the phone's
    /// own Organise screen starts them. Nil when it started, or what to tell the user.
    func startOrganise(folder: URL, order: SessionOrder) async -> String?
    func addToAlbum(_ id: String) async
    func newAlbum(_ title: String) async
    func nextOrganised()
    func skipOrganised()
    func leaveOrganise()

    // Imported media
    var projects: [(id: UUID, name: String, count: Int)] { get }
    func media(project: UUID?) -> [MonitorMediaItem]

    // Settings
    func labelName(_ colour: LabelColour) -> String
    /// Nil when it saved, or what went wrong.
    func renameLabel(_ colour: LabelColour, to name: String) -> String?
    var versionText: String { get }

    // Pictures
    func picture(_ id: String, longEdge: CGFloat, fill: Bool) -> AnyView
    func warm(_ ids: [String], longEdge: CGFloat)
}

/// Everything the monitor is doing: what's up, what's lit, and what a key does.
/// No UIKit and no window in here, so all of it runs in the Mac tests. It outlives
/// the monitor's window: unplugged, nothing here changes, and plugged back in the
/// same screen comes up.
@Observable
@MainActor
final class MonitorDesk {
    static let textScales: [Double] = [0.8, 0.9, 1, 1.12, 1.25, 1.4, 1.7]
    static let zoomSteps: [CGFloat] = [1, 2, 4]
    private static let scaleKey = "monitor.textScale"

    let library: MonitorLibrary
    let marks: PhotoMarkStore

    // The display, told by whoever owns it.
    var isConnected = false
    /// The phone is locked or BestShot isn't in front on it. Starts true: no
    /// photo goes up until the phone says it can.
    private(set) var isLocked = true
    private(set) var isPaused = false
    private(set) var textScale: Double
    /// A sheet is up on the phone, and the keys are its until it goes.
    var phoneSheetUp = false
    /// The phone needn't stay awake for a paused monitor.
    var onPause: () -> Void = {}

    // Where it's at
    private(set) var stack: [MonitorPane] = [.home]
    private(set) var overlay: MonitorOverlay?
    private var selection: [MonitorPane: String] = [:]
    private(set) var helpRow = 0
    private(set) var notice: String?

    // Triage settings
    private(set) var order = SessionOrder.newest
    private(set) var source = TriageSourceOption.allPhotos
    private(set) var organiseOrder = SessionOrder.newest
    private(set) var organiseSource = TriageSourceOption.allPhotos
    /// Organise from a folder in Files instead of Photos. The folder is chosen on
    /// the phone, since a picker can't show on the monitor.
    private(set) var organiseFolder: URL?
    private(set) var organiseFromFolder = false
    /// The phone is to show its folder picker. Its window watches this.
    private(set) var wantsFolder = false
    static let folderPrompt = "Choose the folder on your phone."

    // Looking at photos
    private(set) var filter = MonitorFilter()
    /// A photo that stopped matching the filter stays up until you move on.
    private var held: String?
    private(set) var zoom: CGFloat = 1
    private(set) var pan = CGPoint.zero
    private(set) var pinned: String?
    private(set) var showInfo = false
    /// Set by the view, for up and down in the grid.
    var gridColumns = 6
    /// Set by the view, for asking Photos for the size it will show.
    var photoEdge: CGFloat = 2600
    private var warming: Task<Void, Never>?
    private var undoStack: [(id: String, mark: PhotoMark, decision: ReviewDecision)] = []
    private var drafts: [MonitorEntry.Kind: String] = [:]

    // Other sections
    private(set) var board: RankBoard?
    private(set) var mediaItems: [MonitorMediaItem] = []
    private(set) var mediaIndex = 0

    /// What's running on behalf of a key, for the tests to wait on.
    private(set) var work: Task<Void, Never>?

    private func spawn(_ body: @escaping @MainActor () async -> Void) {
        work = Task { await body() }
    }

    init(library: MonitorLibrary, marks: PhotoMarkStore) {
        self.library = library
        self.marks = marks
        let saved = UserDefaults.standard.double(forKey: Self.scaleKey)
        textScale = saved == 0 ? 1 : saved
    }

    // MARK: - The state of things

    /// The screen on top. Triage ended on the phone leaves nothing to look at, so
    /// its screens read as home until the stack catches up.
    var pane: MonitorPane {
        let top = stack.last ?? .home
        if library.triageIDs.isEmpty, top == .loupe || top == .grid || top == .filters { return .triage }
        if top == .rankCompare, board?.compare == nil { return .rank }
        return top
    }

    var isJudging: Bool { [.loupe, .rankCompare].contains(pane) || isMediaPhoto }

    private var isMediaPhoto: Bool {
        if case .mediaPhoto = pane { return true }
        return false
    }

    var situation: MonitorSituation { situation(under: overlay) }

    private func situation(under overlay: MonitorOverlay?) -> MonitorSituation {
        var s = MonitorSituation()
        if isLocked {
            s.surface = .locked
            return s
        }
        if isPaused {
            s.surface = .paused
            return s
        }
        if phoneSheetUp {
            s.surface = .phoneSheet
            return s
        }
        s.canStepBack = pane != .home
        s.hasPhoto = current != nil
        s.canUndo = !undoStack.isEmpty
        s.inTriage = !library.triageIDs.isEmpty
        switch overlay {
        case .palette:
            s.surface = .palette
        case .help:
            s.surface = .help
        case .entry(let entry):
            s.surface = .entry
            s.entryHasText = !entry.text.trimmingCharacters(in: .whitespaces).isEmpty
            s.entryCanComplete = !entry.suggestions.isEmpty
        case .finish(let finish):
            s.surface = .finish
            s.finishChosen = finish.chosen != nil
            s.finishBusy = finish.isDeleting
        case nil:
            switch pane {
            case .loupe:
                s.surface = .loupe
                s.zoomed = zoom > 1
                s.comparing = pinned != nil
                s.canStepBack = true
            case .grid:
                s.surface = .grid
            case .rankCompare:
                s.surface = .rankCompare
                s.canStepBack = true
            case .mediaPhoto:
                s.surface = .mediaPhoto
                s.hasMediaNeighbours = mediaItems.count > 1
            default:
                s.surface = .list
                let rows = rows
                s.rowCount = rows.count
                s.rowOpens = (litRow?.action ?? .none) != .none
                s.ranking = pane == .rank && litRow?.photo != nil
                s.canCompare = pane == .rank && (board?.pool.count ?? 0) > 1
                s.organising = pane == .organise && library.organisePhoto != nil
            }
        }
        return s
    }

    var keys: [MonitorBinding] { MonitorKeymap.bindings(for: situation) }

    /// The keys of what's underneath, for the list of all keys.
    var pageKeys: [MonitorBinding] { MonitorKeymap.bindings(for: situation(under: nil)) }

    // MARK: - Keys

    /// Every key. False sends it on to the rest of the app.
    @discardableResult
    func handle(_ press: MonitorPress) -> Bool {
        guard isConnected else { return false }
        // Nothing moves on a monitor that isn't showing it.
        if isLocked { return true }
        let situation = situation
        guard let action = MonitorKeymap.action(for: press, in: situation) else {
            // A paused monitor shows nothing, and an open panel keeps its keys.
            switch situation.surface {
            case .paused, .finish, .palette, .entry, .help: return true
            default: return false
            }
        }
        // A sheet on the phone has first claim on Esc, in `EscapeStack`.
        if situation.surface == .phoneSheet { return false }
        perform(action)
        return true
    }

    /// Held down, this key would keep going.
    func repeats(_ press: MonitorPress) -> Bool {
        MonitorKeymap.action(for: press, in: situation)?.repeats ?? false
    }

    /// For `EscapeStack`: true if Esc was the monitor's. At home it isn't, and the
    /// phone hears it.
    func stepBackFromEscape() -> Bool {
        guard isConnected else { return false }
        return handle(MonitorPress(.escape))
    }

    func perform(_ action: MonitorAction) {
        notice = wantsFolder ? Self.folderPrompt : nil
        // The monitor's own: they work whatever's up.
        switch action {
        case .pause:
            togglePause()
            return
        case .textSize(let by):
            adjustTextScale(by)
            return
        default: break
        }
        switch overlay {
        case .palette: paletteAction(action)
        case .entry: entryAction(action)
        case .finish: finishAction(action)
        case .help: helpAction(action)
        case nil: pageAction(action)
        }
    }

    private func helpAction(_ action: MonitorAction) {
        switch action {
        case .move(let by): helpRow = min(max(0, helpRow + by), max(0, pageKeys.count - 1))
        case .escape: overlay = nil
        default: break
        }
    }

    private func pageAction(_ action: MonitorAction) {
        switch action {
        case .escape: stepBack()
        case .pause, .textSize: break
        case .menu: openMenu()
        case .help:
            helpRow = 0
            overlay = .help
        case .section(let section): go(to: section)
        case .undo: undo()
        case .move(let by): move(by)
        case .moveRow(let by): moveRanked(by)
        case .page(let by): page(by)
        case .first: jump(toEnd: false)
        case .last: jump(toEnd: true)
        case .open: open()
        case .rate(let stars): rate(stars)
        case .label(let colour): toggle(colour)
        case .clearMark: clearColour()
        case .favourite: library.toggleFavourite()
        case .tag: beginEntry(.tag, title: "Tag")
        case .zoom: cycleZoom()
        case .pan(let x, let y): panBy(x: x, y: y)
        case .compare: toggleCompare()
        case .swapCompare: swapCompare()
        case .grid: toggleGrid()
        case .filters: push(.filters)
        case .info: showInfo.toggle()
        case .finish: openFinish()
        case .nextUnreviewed(let by): nextUnreviewed(by)
        case .choose(let choice): board?.compare?.choose(choice)
        case .compareUndo: board?.compare?.undo()
        case .startCompare: startCompare(.all)
        case .nextPhoto: library.nextOrganised()
        case .skipPhoto: library.skipOrganised()
        case .newAlbum: beginEntry(.album, title: "New album")
        case .type, .deleteLetter, .complete, .submit: break
        }
    }

    // MARK: - Esc

    /// Each press closes what's on top, then steps back, so a few from anywhere
    /// reach home. It only ever lets go: nothing marked is touched on the way.
    private func stepBack() {
        if zoom > 1 {
            resetZoom()
        } else if pinned != nil {
            pinned = nil
        } else if showInfo, pane == .loupe {
            showInfo = false
        } else if pane == .rankCompare {
            board?.finishCompare(save: true)
            popPane()
        } else {
            popPane()
        }
    }

    private func popPane() {
        if stack.count > 1 { stack.removeLast() }
        // Dropped out of a session on the phone, or back past the loupe.
        while stack.count > 1, library.triageIDs.isEmpty, [.loupe, .grid, .filters].contains(stack.last!) {
            stack.removeLast()
        }
        if stack.last == .home || stack.last == .triage { arrivedHome() }
    }

    private func arrivedHome() {
        library.leaveTriage()
        library.leaveOrganise()
        library.reloadSources()
        pinned = nil
        resetZoom()
    }

    private func push(_ pane: MonitorPane) {
        if stack.last != pane { stack.append(pane) }
    }

    /// A section sits straight on home, so Esc from it is one press.
    private func go(to section: MonitorSection) {
        pinned = nil
        resetZoom()
        switch section {
        case .triage:
            if library.triageIDs.isEmpty {
                stack = [.home, .triage]
                arrivedHome()
            } else {
                resumeTriage()
            }
        case .rank:
            stack = [.home, .rank]
            spawn { await self.loadBoard() }
        case .organise:
            // An open session comes straight up, with its start screen under it so
            // Esc reaches the sources and a new start.
            if library.organisePhoto == nil { stack = [.home, .organiseHome] } else { openOrganise() }
        case .allMedia:
            stack = [.home, .media(project: nil)]
            mediaItems = library.media(project: nil)
        case .projects:
            stack = [.home, .projects]
        case .settings:
            stack = [.home, .settings]
        }
    }

    func loadBoard() async {
        board = await library.rankBoard()
    }

    // MARK: - Lists

    /// The list on screen, if the screen is a list.
    var rows: [MonitorRow] {
        switch pane {
        case .home: return menuRows
        case .triage: return triageRows
        case .filters: return filterRows
        case .rank: return rankRows
        case .organiseHome: return organiseHomeRows
        case .organise: return organiseRows
        case .media: return mediaItems.map { item in
            MonitorRow(id: item.id, title: item.title, detail: item.detail, photo: item.id, action: .mediaItem)
        }
        case .projects: return projectRows
        case .settings: return settingsRows
        default: return []
        }
    }

    var litRowID: String? { litRow?.id }

    var litRow: MonitorRow? {
        let rows = rows
        if let id = selection[pane], let row = rows.first(where: { $0.id == id }) { return row }
        return rows.first { [.startTriage, .resumeTriage, .resumeOrganise].contains($0.action) } ?? rows.first
    }

    private func select(_ row: MonitorRow?) {
        guard let row else { return }
        selection[pane] = row.id
    }

    private func moveRow(by: Int) {
        let rows = rows
        guard !rows.isEmpty else { return }
        let at = rows.firstIndex { $0.id == litRow?.id } ?? 0
        select(rows[min(max(0, at + by), rows.count - 1)])
    }

    private func move(_ by: Int) {
        switch pane {
        case .loupe, .grid: step(by)
        case .mediaPhoto:
            mediaIndex = min(max(0, mediaIndex + by), max(0, mediaItems.count - 1))
        default: moveRow(by: by)
        }
    }

    private func page(_ by: Int) {
        if pane == .grid { step(by * max(1, gridColumns)) } else { moveRow(by: by * 10) }
    }

    private func jump(toEnd: Bool) {
        switch pane {
        case .loupe, .grid:
            let visible = visible
            if let index = toEnd ? visible.last : visible.first { show(index) }
        default:
            let rows = rows
            select(toEnd ? rows.last : rows.first)
        }
    }

    private func open() {
        if pane == .grid {
            stack.removeLast()
            push(.loupe)
            return
        }
        guard let row = litRow else { return }
        run(row)
    }

    private func run(_ row: MonitorRow) {
        switch row.action {
        case .none: break
        case .section(let section): go(to: section)
        case .allowPhotos: spawn { [library] in await library.askForPhotoAccess() }
        case .order(let new): order = new
        case .source(let new): source = new
        case .startTriage: spawn { await self.startTriage() }
        case .resumeTriage: resumeTriage()
        case .status(let status): filter.status = status; held = nil
        case .stars(let stars): filter.minimumStars = stars; held = nil
        case .tag(let tag):
            if filter.tags.remove(tag) == nil { filter.tags.insert(tag) }
            held = nil
        case .clearFilters: filter = MonitorFilter(); held = nil
        case .compare(let scope): startCompare(scope)
        case .saveAlbum: saveAlbum()
        case .organiseOrder(let new): organiseOrder = new
        case .organiseSource(let new): organiseSource = new; organiseFromFolder = false
        case .organiseFolder: askForFolder()
        case .startOrganise: spawn { await self.startOrganise() }
        case .resumeOrganise: openOrganise()
        case .album(let id): spawn { [library] in await library.addToAlbum(id) }
        case .newAlbum: beginEntry(.album, title: "New album")
        case .project(let id):
            mediaItems = library.media(project: id)
            push(.media(project: id))
        case .allMedia: go(to: .allMedia)
        case .mediaItem:
            guard case .media(let project) = pane else { return }
            mediaIndex = mediaItems.firstIndex { $0.id == row.id } ?? 0
            push(.mediaPhoto(project: project))
        case .rename(let colour): beginEntry(.rename(colour), title: "Name for \(colour.title)", text: library.labelName(colour))
        case .textSize: adjustTextScale(textScale >= (Self.textScales.last ?? 1) ? -Self.textScales.count : 1)
        case .pause: togglePause()
        }
    }

    /// The main menu: every section, the same ones ⌘1–6 reach.
    private var menuRows: [MonitorRow] {
        MonitorSection.allCases.map { section in
            MonitorRow(id: "section-\(section.rawValue)", title: section.title, detail: menuDetail(section),
                       action: .section(section))
        }
    }

    private func menuDetail(_ section: MonitorSection) -> String {
        switch section {
        case .triage:
            guard !library.triageIDs.isEmpty else { return "Keep or delete, photo by photo" }
            let waiting = library.triageWaiting
            return waiting > 0 ? "Resume · \(waiting) marked to delete" : "Resume"
        case .rank: return "Put your keepers in order"
        case .organise: return library.organisePhoto == nil ? "File photos into albums" : "Resume"
        case .allMedia: return "Everything imported into projects"
        case .projects: return "\(library.projects.count) project\(library.projects.count == 1 ? "" : "s")"
        case .settings: return "Label names, text size"
        }
    }

    private var triageRows: [MonitorRow] {
        guard library.hasPhotoAccess else {
            if library.canAskForPhotoAccess {
                return [MonitorRow(id: "allow", title: "Allow access to Photos",
                                   detail: "The question comes up on the phone", action: .allowPhotos)]
            }
            return [MonitorRow(id: "denied", title: "BestShot can't see your photos",
                               detail: "Turn on access in Settings on the phone")]
        }
        var rows = choiceRows(order: order, source: source, orderAction: MonitorRowAction.order, sourceAction: MonitorRowAction.source)
        if library.triageIDs.isEmpty {
            rows.append(MonitorRow(id: "start", title: "Start Triage", group: "Go", action: .startTriage))
        } else {
            let waiting = library.triageWaiting
            rows.append(MonitorRow(id: "resume", title: "Resume Triage",
                                   detail: waiting > 0 ? "\(waiting) marked to delete" : nil, group: "Go", action: .resumeTriage))
        }
        return rows
    }

    private func choiceRows(order: SessionOrder, source: TriageSourceOption,
                            orderAction: (SessionOrder) -> MonitorRowAction,
                            sourceAction: (TriageSourceOption) -> MonitorRowAction) -> [MonitorRow] {
        let orders = SessionOrder.allCases.map {
            MonitorRow(id: "order-\($0.rawValue)", title: $0.title, group: "Order", isOn: $0 == order, action: orderAction($0))
        }
        let sources = library.sources.map { item in
            MonitorRow(id: "source-\(item.option)", title: item.title, group: "Source",
                       isOn: item.option == source, action: sourceAction(item.option))
        }
        return orders + sources
    }

    private var filterRows: [MonitorRow] {
        var rows = MonitorFilter.Status.allCases.map {
            MonitorRow(id: "status-\($0.rawValue)", title: $0.title, group: "Show", isOn: $0 == filter.status, action: .status($0))
        }
        rows += (0...5).map { n in
            MonitorRow(id: "stars-\(n)", title: n == 0 ? "Any" : "\(starText(n)) or more", group: "Stars",
                       isOn: n == filter.minimumStars, action: .stars(n))
        }
        rows += marks.knownTags.map {
            MonitorRow(id: "tag-\($0)", title: $0, group: "Tags", isOn: filter.tags.contains($0), action: .tag($0))
        }
        rows.append(MonitorRow(id: "clear", title: "Clear filters", detail: "\(visible.count) of \(library.triageIDs.count) showing",
                               group: "All", action: .clearFilters))
        return rows
    }

    private var rankRows: [MonitorRow] {
        guard let board else { return [] }
        var rows: [MonitorRow] = []
        if board.pool.count > 1 {
            rows.append(MonitorRow(id: "compare-all", title: "Compare all", group: "Rank", action: .compare(.all)))
            if !board.unranked.isEmpty {
                rows.append(MonitorRow(id: "compare-new", title: "Compare the unranked", group: "Rank", action: .compare(.unranked)))
            }
        }
        if !board.ranked.isEmpty {
            rows.append(MonitorRow(id: "save-album", title: "Save as album", detail: "BestShot · Ranked, in Photos", group: "Rank", action: .saveAlbum))
        }
        rows += board.ranked.enumerated().map { i, id in
            MonitorRow(id: id, title: "\(i + 1)", detail: board.media.caption(id), group: "Ranked", photo: id)
        }
        rows += board.unranked.map {
            MonitorRow(id: $0, title: board.media.caption($0), group: "Not ranked yet", photo: $0)
        }
        return rows
    }

    private var organiseHomeRows: [MonitorRow] {
        guard library.hasPhotoAccess else { return triageRows }
        var rows = choiceRows(order: organiseOrder, source: organiseSource, orderAction: MonitorRowAction.organiseOrder,
                              sourceAction: MonitorRowAction.organiseSource)
        if organiseFromFolder {
            for i in rows.indices where rows[i].group == "Source" { rows[i].isOn = false }
        }
        rows.append(MonitorRow(id: "source-folder", title: organiseFolder?.lastPathComponent ?? "A folder in Files…",
                               detail: organiseFolder == nil ? "Chosen on the phone" : "A folder in Files · ↵ to choose another",
                               group: "Folder", isOn: organiseFromFolder, action: .organiseFolder))
        if library.organisePhoto != nil {
            rows.append(MonitorRow(id: "resume-organise", title: "Resume Organising", detail: library.organiseProgress,
                                   group: "Go", action: .resumeOrganise))
        }
        rows.append(MonitorRow(id: "start-organise", title: library.organisePhoto == nil ? "Start Organising" : "Start Again",
                               detail: organiseStartDetail, group: "Go", action: .startOrganise))
        return rows
    }

    /// What Start would go through, so the choice is plain before ↵.
    private var organiseStartDetail: String {
        let from = organiseFromFolder ? organiseFolder?.lastPathComponent
            : library.sources.first { $0.option == organiseSource }?.title
        return [from ?? organiseSource.title, organiseOrder.title].joined(separator: " · ")
    }

    private var organiseRows: [MonitorRow] {
        guard library.organisePhoto != nil else {
            return [MonitorRow(id: "done", title: "All done", detail: "Every photo here has been filed")]
        }
        var rows = library.organiseAlbums.map {
            MonitorRow(id: "album-\($0.id)", title: $0.title, group: "Add to album", isOn: $0.added, action: .album($0.id))
        }
        rows.append(MonitorRow(id: "new-album", title: "New album", group: "Add to album", action: .newAlbum))
        return rows
    }

    private var projectRows: [MonitorRow] {
        var rows = [MonitorRow(id: "all", title: "All Media", action: .allMedia)]
        rows += library.projects.map {
            MonitorRow(id: $0.id.uuidString, title: $0.name, detail: "\($0.count) item\($0.count == 1 ? "" : "s")", action: .project($0.id))
        }
        return rows
    }

    private var settingsRows: [MonitorRow] {
        var rows = LabelColour.allCases.map {
            MonitorRow(id: "name-\($0.slug)", title: library.labelName($0), detail: $0.title, group: "Colour labels", action: .rename($0))
        }
        rows.append(MonitorRow(id: "size", title: "Text size", detail: "\(Int((textScale * 100).rounded()))%", group: "Monitor", action: .textSize))
        rows.append(MonitorRow(id: "pause", title: "Pause", detail: "Blanks the monitor", group: "Monitor", action: .pause))
        rows.append(MonitorRow(id: "version", title: "BestShot", detail: library.versionText, group: "About"))
        return rows
    }

    // MARK: - Triage

    private func startTriage() async {
        notice = await library.startTriage(order: order, source: source)
        guard !library.triageIDs.isEmpty else { return }
        filter = MonitorFilter()
        held = nil
        undoStack = []
        restoreRedMarks()
        resumeTriage()
    }

    private func resumeTriage() {
        library.resumeTriage()
        restoreRedMarks()
        stack = [.home, .triage, .loupe]
    }

    /// A red mark means delete, whatever happened to the decision behind it (a
    /// turned-down confirmation clears those), so a mark is never quietly lost.
    private func restoreRedMarks() {
        for id in library.triageIDs where marks.mark(id).colour == .red && library.decision(id) == .undecided {
            library.setDecision(.deleted, id)
        }
    }

    /// Photos waiting for the confirmation.
    var pendingIDs: [String] { library.triageIDs.filter { library.decision($0) == .deleted } }

    /// Session positions that pass the filter, with a held photo kept in place.
    var visible: [Int] {
        let ids = library.triageIDs
        guard filter.isActive else { return Array(ids.indices) }
        return ids.indices.filter { ids[$0] == held || filter.matches(marks.mark(ids[$0]), colour: colour(ids[$0])) }
    }

    /// Where the session is, within what exists.
    private var triagePosition: Int { min(library.triageIndex, max(0, library.triageIDs.count - 1)) }

    /// The photo on screen. With the filter leaving nothing, there isn't one.
    var current: String? {
        let ids = library.triageIDs
        guard !ids.isEmpty, pane == .loupe || pane == .grid else { return nil }
        let visible = visible
        if visible.contains(triagePosition) { return ids[triagePosition] }
        return visible.first { $0 > triagePosition }.map { ids[$0] } ?? visible.last.map { ids[$0] }
    }

    var position: (at: Int, of: Int)? {
        guard let current, let index = library.triageIDs.firstIndex(of: current) else { return nil }
        let visible = visible
        return ((visible.firstIndex(of: index) ?? 0) + 1, visible.count)
    }

    func colour(_ id: String) -> LabelColour? { marks.mark(id).shownColour(library.decision(id)) }

    private func show(_ index: Int) {
        library.triageIndex = index
        held = nil
        resetZoom()
        warmNeighbours()
    }

    /// Stops at the ends, so holding an arrow can't run off into the summary.
    private func step(_ by: Int) {
        guard let current, let index = library.triageIDs.firstIndex(of: current) else { return }
        let visible = visible
        guard let at = visible.firstIndex(of: index) else { return }
        show(visible[min(max(0, at + by), visible.count - 1)])
    }

    private func nextUnreviewed(_ by: Int) {
        guard let current, let index = library.triageIDs.firstIndex(of: current) else { return }
        let ids = library.triageIDs
        let visible = visible
        guard let at = visible.firstIndex(of: index), visible.count > 1 else { return }
        for k in 1..<visible.count {
            let next = visible[(at + by * k + visible.count * k) % visible.count]
            if colour(ids[next]) == nil, library.decision(ids[next]) == .undecided {
                show(next)
                return
            }
        }
        notice = "Every photo here has a colour."
    }

    /// Once the keys pause, so a held arrow doesn't load every photo it passes.
    private func warmNeighbours() {
        warming?.cancel()
        warming = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let current, let index = library.triageIDs.firstIndex(of: current) else { return }
            let visible = visible
            guard let at = visible.firstIndex(of: index) else { return }
            let ids = library.triageIDs
            let near = (at - 1...at + 3).compactMap { visible.indices.contains($0) ? ids[visible[$0]] : nil }
            library.warm(near, longEdge: photoEdge)
        }
    }

    private func change(_ id: String, _ body: (inout PhotoMark) -> ReviewDecision?) {
        var mark = marks.mark(id)
        let before = mark
        let decision = library.decision(id)
        let new = body(&mark)
        guard mark != before || (new != nil && new != decision) else { return }
        undoStack.append((id, before, decision))
        marks.set(mark, for: id)
        if let new { library.setDecision(new, id) }
        holdIfFiltered(id)
    }

    /// A mark that takes the photo out of the filter doesn't whip it away.
    private func holdIfFiltered(_ id: String) {
        guard filter.isActive else { return }
        if !filter.matches(marks.mark(id), colour: colour(id)) { held = id }
    }

    private func rate(_ stars: Int) {
        guard let id = current else { return }
        change(id) {
            $0.rating = stars
            return nil
        }
    }

    /// Stays on the photo, so a second press can clear it, as it does in Folders.
    private func toggle(_ colour: LabelColour) {
        guard let id = current else { return }
        let shown = self.colour(id)
        change(id) {
            if shown == colour {
                $0.colour = nil
                return .undecided
            }
            $0.colour = colour
            return colour.decision
        }
    }

    private func clearColour() {
        guard let id = current else { return }
        change(id) {
            $0.colour = nil
            return .undecided
        }
    }

    private func undo() {
        guard let last = undoStack.popLast() else { return }
        marks.set(last.mark, for: last.id)
        library.setDecision(last.decision, last.id)
        if let index = library.triageIDs.firstIndex(of: last.id) { show(index) }
    }

    private func toggleGrid() {
        if pane == .grid {
            stack.removeLast()
            push(.loupe)
        } else {
            pinned = nil
            resetZoom()
            stack.removeLast()
            push(.grid)
        }
    }

    // MARK: - Zoom and compare

    private func resetZoom() {
        zoom = 1
        pan = .zero
    }

    private func cycleZoom() {
        let at = Self.zoomSteps.firstIndex(of: zoom) ?? 0
        zoom = Self.zoomSteps[(at + 1) % Self.zoomSteps.count]
        if zoom == 1 { pan = .zero }
    }

    private func panBy(x: Int, y: Int) {
        pan = CGPoint(x: min(1, max(-1, pan.x + CGFloat(x) * 0.15)), y: min(1, max(-1, pan.y + CGFloat(y) * 0.15)))
    }

    /// Pins this photo on the left. The arrows then walk the right.
    private func toggleCompare() {
        if pinned != nil {
            pinned = nil
            return
        }
        guard let id = current else { return }
        pinned = id
        step(1)
    }

    private func swapCompare() {
        guard let left = pinned, let right = current, let index = library.triageIDs.firstIndex(of: left) else { return }
        pinned = right
        show(index)
    }

    // MARK: - Finish

    private func openFinish() {
        guard !library.triageIDs.isEmpty else { return }
        restoreRedMarks()
        let waiting = library.triageWaiting
        overlay = .finish(MonitorFinish(choices: waiting > 0 ? [.delete, .keepGoing] : [.finish, .keepGoing]))
    }

    private func finishAction(_ action: MonitorAction) {
        guard case .finish(var finish) = overlay, !finish.isDeleting else { return }
        switch action {
        case .escape: overlay = nil
        case .move(let by):
            let at = finish.choices.firstIndex { $0 == finish.chosen }
            let next = at.map { min(max(0, $0 + by), finish.choices.count - 1) } ?? (by > 0 ? 0 : finish.choices.count - 1)
            finish.chosen = finish.choices[next]
            overlay = .finish(finish)
        case .submit:
            switch finish.chosen {
            case .delete: spawn { await self.commit() }
            case .finish:
                overlay = nil
                library.endTriage()
                stack = [.home, .triage]
                arrivedHome()
            case .keepGoing: overlay = nil
            case nil: break
            }
        default: break
        }
    }

    /// The photos go only by the session's own commit: the system asks, on the
    /// phone, and they land in Recently Deleted. Turned down, every mark is put
    /// back, since the session forgets them.
    func commit() async {
        guard case .finish(var finish) = overlay, finish.chosen == .delete, !finish.isDeleting else { return }
        finish.isDeleting = true
        finish.message = nil
        overlay = .finish(finish)
        let waiting = pendingIDs
        let deleted = await library.commitDeletions()
        if deleted > 0 {
            marks.remove(waiting)
            undoStack = []
            overlay = nil
            library.endTriage()
            stack = [.home, .triage]
            arrivedHome()
            notice = "\(deleted) photo\(deleted == 1 ? "" : "s") moved to Recently Deleted."
        } else {
            for id in waiting { library.setDecision(.deleted, id) }
            finish.isDeleting = false
            finish.chosen = nil
            finish.message = "Nothing was deleted. The photos are still marked."
            overlay = .finish(finish)
        }
    }

    // MARK: - Rank

    private func startCompare(_ scope: RankScope) {
        guard let board, board.pool.count > 1 else { return }
        board.startCompare(scope: scope)
        if board.compare != nil { stack.append(.rankCompare) }
    }

    private func moveRanked(_ by: Int) {
        guard let board, let id = litRow?.photo else { return }
        var order = board.ranked
        if let at = order.firstIndex(of: id) {
            let to = min(max(0, at + by), order.count - 1)
            order.remove(at: at)
            order.insert(id, at: to)
        } else {
            order.append(id)
        }
        board.save(poolOrder: order)
    }

    private func saveAlbum() {
        guard let board else { return }
        let ids = board.ranked
        spawn { self.notice = await self.library.saveRankAlbum(ids) }
    }

    // MARK: - Organise

    /// ↵ on "A folder in Files…": the phone shows its picker, and the monitor
    /// says so until it goes.
    private func askForFolder() {
        wantsFolder = true
        notice = Self.folderPrompt
    }

    /// The phone's picker went, picked or not. The result follows.
    func folderPickerClosed() {
        wantsFolder = false
        if notice == Self.folderPrompt { notice = nil }
    }

    /// Picked on the phone: Organise starts on it, as the phone's own screen does.
    func folderPicked(_ folder: URL) {
        wantsFolder = false
        organiseFolder = folder
        organiseFromFolder = true
        notice = nil
        spawn { await self.startOrganise() }
    }

    /// Cancelled on the phone, or the picker failed: the monitor stays put.
    func folderNotPicked(_ problem: String? = nil) {
        wantsFolder = false
        notice = problem ?? "No folder chosen."
    }

    private func startOrganise() async {
        if organiseFromFolder, let folder = organiseFolder {
            notice = await library.startOrganise(folder: folder, order: organiseOrder)
        } else {
            notice = await library.startOrganise(order: organiseOrder, source: organiseSource)
        }
        if notice == nil, library.organisePhoto != nil { openOrganise() }
    }

    /// Into the session, with its start screen under it. Back there, Resume is lit.
    private func openOrganise() {
        selection[.organiseHome] = nil
        stack = [.home, .organiseHome, .organise]
    }

    // MARK: - Typing

    private func beginEntry(_ kind: MonitorEntry.Kind, title: String, text: String = "") {
        guard kind != .tag || current != nil else { return }
        var entry = MonitorEntry(kind: kind, title: title, text: drafts[kind] ?? text)
        entry.suggestions = suggestions(for: entry)
        overlay = .entry(entry)
    }

    /// Autocomplete, from the tags already in use, minus what's on the photo.
    private func suggestions(for entry: MonitorEntry) -> [String] {
        guard entry.kind == .tag else { return [] }
        let typed = entry.text.trimmingCharacters(in: .whitespaces).lowercased()
        let mark = current.map(marks.mark) ?? PhotoMark()
        return marks.knownTags.filter { !mark.has(tag: $0) && (typed.isEmpty || $0.lowercased().hasPrefix(typed)) }
            .prefix(6).map { $0 }
    }

    private func entryAction(_ action: MonitorAction) {
        guard case .entry(var entry) = overlay else { return }
        switch action {
        case .type(let text): entry.text += text.filter { !$0.isNewline }
        case .deleteLetter: if !entry.text.isEmpty { entry.text.removeLast() }
        case .complete: if let first = entry.suggestions.first { entry.text = first }
        case .submit:
            commitEntry(entry)
            return
        case .escape:
            closeEntry(entry)
            return
        default: return
        }
        entry.suggestions = suggestions(for: entry)
        overlay = .entry(entry)
    }

    /// As in the viewer, a tag being typed is added rather than lost. Other words
    /// wait for next time.
    private func closeEntry(_ entry: MonitorEntry) {
        if entry.kind == .tag, !entry.text.trimmingCharacters(in: .whitespaces).isEmpty {
            commitEntry(entry)
            return
        }
        drafts[entry.kind] = entry.text.isEmpty ? nil : entry.text
        overlay = nil
    }

    private func commitEntry(_ entry: MonitorEntry) {
        let text = entry.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        drafts[entry.kind] = nil
        overlay = nil
        switch entry.kind {
        case .tag: toggleTag(text)
        case .rename(let colour): notice = library.renameLabel(colour, to: text)
        case .album: spawn { [library] in await library.newAlbum(text) }
        }
    }

    /// A tag the photo has already comes off, which is how one is removed.
    private func toggleTag(_ tag: String) {
        guard let id = current else { return }
        change(id) {
            if $0.has(tag: tag) {
                $0.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
            } else {
                $0.tags.append(tag)
            }
            return nil
        }
    }

    // MARK: - The menu

    private func openMenu() {
        var rows = MonitorSection.allCases.map {
            MonitorMenuRow(id: "section-\($0.rawValue)", title: $0.title, detail: "⌘\($0.rawValue)", action: .section($0))
        }
        if !library.triageIDs.isEmpty {
            rows.append(MonitorMenuRow(id: "grid", title: "Grid", detail: "g", action: .grid))
            rows.append(MonitorMenuRow(id: "filters", title: "Filters", detail: "f", action: .filters))
            if filter.isActive {
                rows.append(MonitorMenuRow(id: "clear", title: "Clear filters", action: .clearFilters))
            }
            rows.append(MonitorMenuRow(id: "finish", title: "Finish Triage", detail: "Asks first", action: .finish))
            rows += MonitorFilter.Status.allCases.map {
                MonitorMenuRow(id: "status-\($0.rawValue)", title: "Show \($0.title.lowercased())", action: .status($0))
            }
            rows += marks.knownTags.map { MonitorMenuRow(id: "tag-\($0)", title: "Show tag \($0)", action: .tag($0)) }
        }
        rows.append(MonitorMenuRow(id: "keys", title: "All keys", detail: "?", action: .help))
        rows.append(MonitorMenuRow(id: "pause", title: "Pause monitor", detail: "⌥⌘P", action: .pause))
        rows += library.projects.map { MonitorMenuRow(id: "project-\($0.id)", title: $0.name, detail: "Project", action: .project($0.id)) }
        overlay = .palette(MonitorPalette(rows))
    }

    private func paletteAction(_ action: MonitorAction) {
        guard case .palette(var palette) = overlay else { return }
        switch action {
        case .move(let by): palette.move(by)
        case .type(let text): palette.type(text)
        case .deleteLetter: palette.backspace()
        case .escape, .menu:
            overlay = nil
            return
        case .submit:
            guard let row = palette.lit else { return }
            overlay = nil
            run(row.action)
            return
        default: return
        }
        overlay = .palette(palette)
    }

    private func run(_ action: MonitorMenuAction) {
        switch action {
        case .section(let section): go(to: section)
        case .project(let id):
            stack = [.home, .projects]
            mediaItems = library.media(project: id)
            push(.media(project: id))
        case .filters: stackForPhotos(); push(.filters)
        case .clearFilters: filter = MonitorFilter(); held = nil
        case .grid: stackForPhotos(); toggleGrid()
        case .help:
            helpRow = 0
            overlay = .help
        case .pause: togglePause()
        case .status(let status):
            filter.status = status
            held = nil
            stackForPhotos()
        case .tag(let tag):
            filter.tags = [tag]
            held = nil
            stackForPhotos()
        case .finish: openFinish()
        }
    }

    /// From anywhere, to the photo walk.
    private func stackForPhotos() {
        if pane != .loupe, pane != .grid { resumeTriage() }
    }

    // MARK: - The display

    func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        if locked { dropChoice() }
    }

    /// A chosen row doesn't wait behind a blank screen for a stray ↵.
    private func dropChoice() {
        if case .finish(var finish) = overlay, !finish.isDeleting {
            finish.chosen = nil
            overlay = .finish(finish)
        }
    }

    func togglePause() {
        guard isConnected else { return }
        isPaused.toggle()
        if isPaused { dropChoice() }
        onPause()
    }

    /// The monitor has gone. Only the pause goes with it: everything else is
    /// waiting here for when it's back, and the session is the phone's to carry on.
    func monitorLeft() {
        isPaused = false
    }

    func adjustTextScale(_ by: Int) {
        let i = Self.textScales.firstIndex { $0 >= textScale - 0.001 } ?? 2
        textScale = Self.textScales[min(Self.textScales.count - 1, max(0, i + by))]
        UserDefaults.standard.set(textScale, forKey: Self.scaleKey)
    }
}

/// A photo's stars as text: `★★★☆☆`.
func starText(_ rating: Int) -> String {
    String(repeating: "★", count: rating) + String(repeating: "☆", count: max(0, 5 - rating))
}
