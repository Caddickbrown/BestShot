import Foundation

// MARK: - Everything BestShot can do, as the ⌘K menu lists it
//
// Dan, 17 Nov: "I should always be able to do any action from it." The list is
// built from a plain `BestShotCommandState`, so the tests build it exactly as
// the app does (MonitorDesk.commandState on the monitor, CommandMenu.swift's
// phone state on the phone). The rules, keys, recents and steps are the kit's
// (kit/swift/CommandPalette.swift); this file only says what's on the menu.
//
// One list for both displays, but never a command for a screen the display in
// front of you doesn't draw: the monitor has no Tools or project imports, and
// the phone has no monitor loupe, zoom or filters.

/// Everything the menu can make happen.
enum BestShotCommand: Equatable {
    // Places
    case go(MonitorSection)
    case project(UUID)
    case joinVideos, antiCrop
    case allKeys

    // The photo on screen
    case stars(Int)
    case colour(LabelColour)
    case noColour
    case favourite
    case toggleTag(String)
    /// The phone's Triage card.
    case keep, markDelete, skip
    case undo
    /// The monitor's loupe.
    case zoom, pinCompare, swapSides, info
    case grid
    case nextUndecided(Int)
    /// Opens the way out, which asks before anything is deleted.
    case finishTriage

    // Filters (the monitor's)
    case filters
    case filterStatus(MonitorFilter.Status)
    case filterStars(Int)
    case filterTag(String)
    case filtersOff

    // Starting Triage
    case triageOrder(SessionOrder)
    case startTriage(TriageSourceOption)
    case resumeTriage

    // Rank
    case rankCompare(RankScope)
    case saveRankAlbum
    case clearRanking, restoreRanking
    /// The monitor's lit photo, up or down.
    case moveRanked(Int)
    case compareChoose(RankChoice)
    case compareUndo
    case compareSave

    // Organise
    case organiseOrder(SessionOrder)
    case startOrganise(TriageSourceOption)
    case organiseFolder
    case resumeOrganise
    case addToAlbum(String)
    case newAlbum(String)
    case nextPhoto, skipPhoto
    case oneAlbum(Bool)
    case doneOrganising

    // Projects
    case newProject(String)
    case renameProject(UUID, String)
    case deleteProject(UUID)
    case importPhotos, importFiles
    case compareProject(ComparisonScope)
    case projectSort(SortOption)
    case projectFilter(MediaFilter)
    case gridSize(GridSize)
    case selecting(Bool)
    case selectAll
    case tagSelected(String)
    case downloadSelected, joinSelected, deleteSelected
    case exportJSON, exportCSV, downloadAll
    case clearProjectRankings
    /// The monitor removed a project: the phone stops showing it, if it is.
    case projectRemoved(UUID)

    // Imported media, on the monitor
    case findMedia(String)
    case setMediaTags(String, [String])
    case noteMedia(String, String)
    case slideshow

    // Triage start, on the monitor
    case runTags([String])
    case deleteWaiting, keepWaiting
    /// Compare on the monitor, ended without keeping the answers.
    case compareDiscard

    // Settings
    case appearance(Appearance)
    case renameLabel(LabelColour, String)
    case textSize(Int)
    case pause
}

/// What the menu needs to know, as plain values.
struct BestShotCommandState: Equatable {
    enum Display: Equatable { case phone, monitor }

    enum Screen: Equatable {
        case home
        case triageStart, triage, triageGrid, filters
        case rank, rankCompare
        case organiseStart, organise
        case allMedia, mediaPhoto, projects, project
        case settings, tool
    }

    struct Photo: Equatable {
        var id: String
        var stars = 0
        var colour: LabelColour?
        var favourite = false
        var tags: [String] = []
    }

    struct Source: Equatable {
        var option: TriageSourceOption
        var title: String
    }

    struct Album: Equatable {
        var id: String
        var title: String
        var added = false
    }

    struct Project: Equatable {
        var id: UUID
        var name: String
        var count = 0
        /// What Delete says first.
        var removal = ""
    }

    /// An imported photo or video, lit on the monitor's list or open there.
    struct MediaItem: Equatable {
        var id: String
        var title: String
        var tags: [String] = []
        var note = ""
    }

    /// The project on the phone's screen.
    struct OpenProject: Equatable {
        var id: UUID
        var name: String
        var count = 0
        var unranked = 0
        var sort = SortOption.rank
        var filter = MediaFilter.all
        var grid = GridSize.medium
        var selecting = false
        var selected = 0
        var canJoin = false
        var removal = ""
    }

    var display = Display.phone
    var screen = Screen.home
    /// The photo the commands at the top act on.
    var photo: Photo?
    var labelNames: [LabelColour: String] = [:]
    var knownTags: [String] = []
    var canUndo = false
    var hasPhotoAccess = true

    // Triage
    var triageOpen = false
    var triageWaiting = 0
    var order = SessionOrder.newest
    var sources: [Source] = []
    var zoomed = false
    var comparing = false
    var showingInfo = false
    var filter = MonitorFilter()

    // Rank
    var rankPool = 0
    var ranked = 0
    var unranked = 0
    var canPutRankingBack = false
    /// The monitor's Rank list has a photo lit.
    var rankLit: String?

    // Organise
    var organiseOpen = false
    var organisePaused = false
    var organiseOrder = SessionOrder.newest
    var albums: [Album] = []
    var oneAlbum = false

    // Projects
    var projects: [Project] = []
    var project: OpenProject?
    /// The monitor's Projects list: the project lit there.
    var litProject: Project?

    // Imported media, on the monitor
    var mediaItem: MediaItem?
    var mediaSort = SortOption.dateNewest
    var mediaFilter = MediaFilter.all
    var mediaQuery = ""
    var mediaShown = 0
    var slideshow = false

    // Starting Triage, on the monitor
    var runTags: [String] = []
    /// Marked to delete by a run that ended early.
    var waitingDeletes = 0

    // Settings
    var appearance = Appearance.system
    var monitorConnected = false
    var monitorPaused = false
    var textScale = 1.0

    func name(_ colour: LabelColour) -> String { labelNames[colour] ?? colour.title }
}

struct BestShotCommandList: CommandList {
    typealias Row = CommandRow<BestShotCommand>
    var state: BestShotCommandState

    private var onMonitor: Bool { state.display == .monitor }

    func prompt(stage: String?) -> String { "Do anything, or go anywhere" }

    func rows(stage: String?, typing: Bool) -> [Row] {
        var out: [Row] = []
        if let photo = state.photo { out += photoRows(photo) }
        out += screenRows
        out += places
        out += settingsRows
        return out
    }

    // MARK: - The photo on screen

    private func photoRows(_ photo: BestShotCommandState.Photo) -> [Row] {
        let here = "This photo"
        var rows: [Row] = []
        // monitor-alt: the colours below are the monitor's Keep (8 green) and Mark to delete (6 red); ] is next
        if !onMonitor && state.screen == .triage {
            rows += [
                Row("photo.keep", "Keep", detail: "Swipe right", symbol: "checkmark", step: .run(.keep),
                    synonyms: ["yes", "save", "green"], context: here),
                Row("photo.bin", "Mark to delete", detail: "Deleted only when you finish, after iOS asks",
                    symbol: "trash", step: .run(.markDelete), synonyms: ["bin", "reject", "no", "red"],
                    destructive: true, undoable: true, context: here),
                Row("photo.skip", "Skip", detail: "Comes round again next time", symbol: "forward",
                    step: .run(.skip), synonyms: ["later", "pass"], context: here),
            ]
        }
        let stars = (0...5).map { n in
            Row("stars.\(n)", n == 0 ? "No stars" : "\(n) star\(n == 1 ? "" : "s")", detail: onMonitor ? "\(n)" : nil,
                symbol: n == 0 ? "star.slash" : "star.fill", step: .run(.stars(n)),
                synonyms: [n == 0 ? "unrate" : starText(n), "\(n)"], isCurrent: photo.stars == n)
        }
        rows.append(Row("photo.stars", "Stars…", detail: photo.stars == 0 ? "None" : starText(photo.stars),
                        symbol: "star", step: .pick(CommandPick(prompt: "How many stars?", choices: stars)),
                        synonyms: ["rate", "rating"], context: here))
        for colour in LabelColour.allCases {
            let word = colour.title.lowercased()
            let name = state.name(colour)
            rows.append(Row.toggle("photo.colour.\(colour.slug)", isOn: photo.colour == colour,
                                   turnOn: "Mark \(word)", turnOff: "Take \(word) off",
                                   detail: [name == colour.title ? nil : name, onMonitor ? colour.monitorKey : nil]
                                       .compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                                   symbol: "circle.fill", action: .colour(colour),
                                   synonyms: [name, "colour", "color", "label", colour == .green ? "keep" : "",
                                              colour == .yellow ? "maybe" : "", colour == .red ? "reject" : ""]
                                       .filter { !$0.isEmpty },
                                   context: here))
        }
        if photo.colour != nil {
            rows.append(Row("photo.nocolour", "Take the colour off", detail: onMonitor ? "u" : nil, symbol: "circle.slash",
                            step: .run(.noColour), synonyms: ["clear colour", "unlabel", "no colour"], context: here))
        }
        rows.append(Row.toggle("photo.favourite", isOn: photo.favourite, turnOn: "Favourite", turnOff: "Unfavourite",
                               detail: onMonitor ? "h" : nil, symbol: "heart", action: .favourite,
                               synonyms: ["heart", "love", "like"], context: here))
        rows.append(tagRow(photo, context: here))
        for tag in photo.tags {
            rows.append(Row("photo.untag.\(tag)", "Take tag “\(tag)” off", symbol: "tag.slash", step: .run(.toggleTag(tag)),
                            synonyms: ["untag", "remove tag"], context: here))
        }
        if onMonitor && (state.screen == .triage || state.screen == .triageGrid) {
            if state.screen == .triage {
                rows += [
                    Row("photo.zoom", state.zoomed ? "Zoom further, or back out" : "Zoom in", detail: "z",
                        symbol: "plus.magnifyingglass", step: .run(.zoom), synonyms: ["closer", "magnify", "100%"], context: here),
                    Row.toggle("photo.compare", isOn: state.comparing, turnOn: "Compare with the next photo",
                               turnOff: "Stop comparing", detail: "c", symbol: "rectangle.split.2x1", action: .pinCompare,
                               synonyms: ["side by side", "pin"], context: here),
                ]
                if state.comparing {
                    rows.append(Row("photo.swap", "Swap sides", detail: "⇥", symbol: "arrow.left.arrow.right",
                                    step: .run(.swapSides), synonyms: ["switch"], context: here))
                }
                rows.append(Row.toggle("photo.info", isOn: state.showingInfo, turnOn: "Show photo info",
                                       turnOff: "Hide photo info", detail: "i", symbol: "info.circle", action: .info,
                                       synonyms: ["details", "exif", "date"], context: here))
            }
            rows += [
                Row("photo.next", "Next with no colour", detail: "]", symbol: "arrow.right.to.line", step: .run(.nextUndecided(1)),
                    synonyms: ["undecided", "unreviewed"], context: here),
                Row("photo.previous", "Previous with no colour", detail: "[", symbol: "arrow.left.to.line",
                    step: .run(.nextUndecided(-1)), synonyms: ["undecided", "unreviewed", "back"], context: here),
            ]
        }
        return rows
    }

    /// Tag…: type one, or pick one already in use. A tag the photo has comes off.
    private func tagRow(_ photo: BestShotCommandState.Photo, context: String) -> Row {
        let known = state.knownTags.filter { !photo.tags.contains($0) }.map {
            Row("tag.\($0)", "Tag “\($0)”", symbol: "tag", step: .run(.toggleTag($0)))
        }
        return Row("photo.tag", "Tag…", detail: onMonitor ? "t" : nil, symbol: "tag",
                   step: .ask(CommandAsk(prompt: "A tag for this photo", suggestions: known, symbol: "tag",
                                         title: { "Tag “\($0)”" },
                                         make: { text in
                                             let t = text.trimmingCharacters(in: .whitespaces)
                                             return t.isEmpty ? nil : .toggleTag(t)
                                         })),
                   synonyms: ["keyword", "label"], context: context)
    }

    // MARK: - What's on screen

    private var screenRows: [Row] {
        var rows: [Row] = []
        switch state.screen {
        case .triage, .triageGrid, .filters:
            rows += triageRows
        case .triageStart:
            rows += triageStartRows
        case .rank, .rankCompare:
            rows += rankRows
        case .organise, .organiseStart:
            rows += organiseRows
        case .project:
            if let project = state.project { rows += onMonitor ? monitorProjectRows(project) : projectRows(project) }
        case .allMedia where onMonitor:
            rows += mediaListRows
            if let item = state.mediaItem { rows += mediaItemRows(item) }
        case .mediaPhoto where onMonitor:
            if let item = state.mediaItem { rows += mediaItemRows(item) }
            rows.append(Row.toggle("media.slideshow", isOn: state.slideshow, turnOn: "Start slideshow", turnOff: "Stop slideshow",
                                   detail: "p", symbol: "play.rectangle", action: .slideshow,
                                   synonyms: ["play", "auto", "advance"]))
        case .projects where onMonitor:
            if let p = state.litProject {
                rows += [renameRow(id: p.id, name: p.name, context: "“\(p.name)”"),
                         deleteRow(id: p.id, name: p.name, removal: p.removal, context: "“\(p.name)”")]
            }
        default:
            break
        }
        if state.canUndo {
            rows.append(Row("undo", "Undo", detail: "⌘Z", symbol: "arrow.uturn.backward", step: .run(.undo),
                            synonyms: ["take back", "revert"]))
        }
        return rows
    }

    private var triageRows: [Row] {
        var rows: [Row] = []
        rows.append(Row.toggle("triage.grid", isOn: state.screen == .triageGrid, turnOn: onMonitor ? "Grid" : "See the whole set",
                               turnOff: "Back to the photo", detail: onMonitor ? "g" : nil, symbol: "square.grid.2x2",
                               action: .grid, synonyms: ["grid", "all photos", "contact sheet", "loupe", "photo"]))
        if onMonitor {
            rows.append(Row("triage.filters", "Filters", detail: "f", symbol: "line.3.horizontal.decrease.circle",
                            step: .run(.filters), synonyms: ["show", "only"]))
            rows.append(statusPick)
            rows.append(starsFilterPick)
            if !state.knownTags.isEmpty { rows.append(tagFilterPick) }
            if state.filter.isActive {
                rows.append(Row("triage.filtersoff", "Turn filters off", detail: "Show every photo again",
                                symbol: "line.3.horizontal.decrease.circle", step: .run(.filtersOff),
                                synonyms: ["clear filters", "reset filters", "show all"]))
            }
        }
        let waiting = state.triageWaiting
        rows.append(Row("triage.finish", "Finish Triage…",
                        detail: waiting > 0 ? "\(waiting) marked to delete · asks first" : "Asks first",
                        symbol: "flag.checkered", step: .run(.finishTriage), synonyms: ["done", "end", "commit"]))
        return rows
    }

    private var statusPick: Row {
        let choices = MonitorFilter.Status.allCases.map {
            // A filter only shows them: "Red, to delete" would read as a delete.
            Row("show.\($0.rawValue)", $0 == .red ? "Red, marked to go" : $0.title, symbol: "eye",
                step: .run(.filterStatus($0)), synonyms: [$0.title], isCurrent: state.filter.status == $0)
        }
        return Row("triage.show", "Show…", detail: state.filter.status.title, symbol: "eye",
                   step: .pick(CommandPick(prompt: "Which photos?", choices: choices)), synonyms: ["filter", "only"])
    }

    private var starsFilterPick: Row {
        let choices = (0...5).map { n in
            Row("min.\(n)", n == 0 ? "Any stars" : "\(n) star\(n == 1 ? "" : "s") or more", detail: n == 0 ? nil : starText(n),
                symbol: "star", step: .run(.filterStars(n)), isCurrent: state.filter.minimumStars == n)
        }
        return Row("triage.minstars", "At least…", detail: state.filter.minimumStars == 0 ? "Any stars" : starText(state.filter.minimumStars),
                   symbol: "star", step: .pick(CommandPick(prompt: "How many stars at least?", choices: choices)),
                   synonyms: ["stars filter", "minimum", "rating"])
    }

    /// Each choice turns that tag on or off, so two tags can be on at once.
    private var tagFilterPick: Row {
        let choices = state.knownTags.map { tag in
            Row("tagfilter.\(tag)", tag, detail: state.filter.tags.contains(tag) ? "On · choose to turn off" : nil,
                symbol: "tag", step: .run(.filterTag(tag)), isCurrent: state.filter.tags.contains(tag))
        }
        let on = state.filter.tags.sorted().joined(separator: ", ")
        return Row("triage.tagfilter", "Filter by tag…", detail: on.isEmpty ? nil : on, symbol: "tag",
                   step: .pick(CommandPick(prompt: "Which tags?", choices: choices)), synonyms: ["show tag", "only tag"])
    }

    private var triageStartRows: [Row] {
        guard state.hasPhotoAccess else { return [] }
        var rows: [Row] = []
        if state.triageOpen {
            let waiting = state.triageWaiting
            rows.append(Row("triage.resume", "Resume Triage", detail: waiting > 0 ? "\(waiting) marked to delete" : nil,
                            symbol: "play", step: .run(.resumeTriage), synonyms: ["continue", "carry on"]))
        } else {
            rows.append(sourcePick(id: "triage.start", title: "Start Triage…", verb: "Triage", command: BestShotCommand.startTriage))
        }
        rows.append(orderPick(id: "triage.order", order: state.order, command: BestShotCommand.triageOrder))
        if onMonitor {
            rows.append(runTagsRow)
            if state.waitingDeletes > 0 && !state.triageOpen {
                let n = state.waitingDeletes
                let photos = "\(n) photo\(n == 1 ? "" : "s")"
                rows.append(Row("triage.waiting.delete", "Delete the \(photos) waiting…",
                                detail: "From a run that ended early · iOS asks on the phone", symbol: "trash",
                                step: .confirm(CommandConfirm(prompt: "Delete the \(photos) waiting?", title: "Delete them",
                                                              detail: "They go to Recently Deleted once you confirm on the phone.",
                                                              action: .deleteWaiting)),
                                synonyms: ["waiting", "ended early", "bin"], destructive: true,
                                onPhone: "Confirm the delete on the phone."))
                rows.append(Row("triage.waiting.keep", "Keep the \(photos) waiting", detail: "They come up in the next run",
                                symbol: "arrow.uturn.backward", step: .run(.keepWaiting), synonyms: ["waiting", "release", "undecide"]))
            }
        }
        return rows
    }

    /// "Tag what you keep": tags every photo kept in the next run gets.
    private var runTagsRow: Row {
        let tags = state.runTags
        let typed = tags.joined(separator: ", ")
        let known = state.knownTags.filter { tag in !tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }.map { tag in
            Row("runtag.\(tag)", "Add “\(tag)”", symbol: "tag", step: .run(.runTags(tags + [tag])))
        }
        return Row("triage.runtags", "Tag what you keep…", detail: tags.isEmpty ? "None" : typed, symbol: "tag",
                   step: .ask(CommandAsk(prompt: "Tags, with commas between", initial: typed, suggestions: known, symbol: "tag",
                                         title: { $0.isEmpty ? "No tags for this run" : "Tag what I keep “\($0)”" },
                                         make: { text in
                                             let new = TriageTags.parse(text)
                                             return new == tags ? nil : .runTags(new)
                                         })),
                   synonyms: ["run tags", "keep tags", "keyword"])
    }

    private func sourcePick(id: String, title: String, verb: String,
                            command: (TriageSourceOption) -> BestShotCommand, extra: [Row] = []) -> Row {
        let choices = state.sources.map { source in
            Row("source.\(source.option)", source.title, detail: { if case .album = source.option { return "Album" } else { return nil } }(),
                symbol: { if case .album = source.option { return "rectangle.stack" } else { return "photo.on.rectangle" } }(),
                step: .run(command(source.option)))
        }
        return Row(id, title, symbol: "play", step: .pick(CommandPick(prompt: "\(verb) which photos?", choices: choices + extra,
                                                                      nothing: "No source or album by that name.")),
                   synonyms: ["begin", "source", "album"])
    }

    private func orderPick(id: String, order: SessionOrder, command: (SessionOrder) -> BestShotCommand) -> Row {
        let choices = SessionOrder.allCases.map {
            Row("order.\($0.rawValue)", $0.title, symbol: "arrow.up.arrow.down", step: .run(command($0)), isCurrent: $0 == order)
        }
        return Row(id, "Order…", detail: order.title, symbol: "arrow.up.arrow.down",
                   step: .pick(CommandPick(prompt: "Which first?", choices: choices)), synonyms: ["sort", "newest", "oldest", "random"])
    }

    private var rankRows: [Row] {
        var rows: [Row] = []
        if state.screen == .rankCompare {
            // The phone's Compare is a screen over everything with its own buttons; a
            // command chosen there would close it first, so only the way out is listed.
            guard onMonitor else {
                return [Row("compare.save", "Save and stop comparing", symbol: "checkmark", step: .run(.compareSave),
                            synonyms: ["done", "finish", "exit"])]
            }
            return [
                Row("compare.left", "Left is better", detail: "←", symbol: "arrow.left", step: .run(.compareChoose(.left)),
                    synonyms: ["choose left", "first"]),
                Row("compare.right", "Right is better", detail: "→", symbol: "arrow.right", step: .run(.compareChoose(.right)),
                    synonyms: ["choose right", "second"]),
                Row("compare.skip", "Can't choose, skip this pair", detail: "Space", symbol: "forward",
                    step: .run(.compareChoose(.skip)), synonyms: ["same", "tie", "pass"]),
                Row("compare.undo", "Take back the last answer", detail: "⌫", symbol: "arrow.uturn.backward",
                    step: .run(.compareUndo), synonyms: ["undo"]),
                Row("compare.save", "Save and stop comparing", detail: "esc", symbol: "checkmark",
                    step: .run(.compareSave), synonyms: ["done", "finish", "exit"]),
                Row("compare.discard", "Stop without saving…", symbol: "xmark",
                    step: .confirm(CommandConfirm(prompt: "Stop and forget these answers?", title: "Stop without saving",
                                                  detail: "The ranking stays as it was before this run.", symbol: "xmark",
                                                  action: .compareDiscard)),
                    synonyms: ["cancel", "discard", "abandon", "quit"], destructive: true),
            ]
        }
        if state.rankPool > 1 {
            rows.append(Row("rank.compareall", "Compare all", detail: "\(state.rankPool) photos", symbol: "arrow.left.arrow.right",
                            step: .run(.rankCompare(.all)), synonyms: ["rank", "pairs", "start"]))
            if state.unranked > 0 {
                rows.append(Row("rank.comparenew", "Compare the unranked", detail: "\(state.unranked) not ranked yet",
                                symbol: "arrow.left.arrow.right", step: .run(.rankCompare(.unranked)), synonyms: ["new", "rest"]))
            }
        }
        if state.ranked > 0 {
            rows.append(Row("rank.album", "Save ranking as an album", detail: "BestShot · Ranked, in Photos",
                            symbol: "rectangle.stack.badge.plus", step: .run(.saveRankAlbum), synonyms: ["export", "photos album"]))
            rows.append(Row("rank.clear", "Clear ranking", detail: onMonitor ? "⌘Z puts it back" : "Undo puts it back", symbol: "xmark.circle",
                            step: .run(.clearRanking), synonyms: ["reset", "start over", "unrank"],
                            destructive: true, undoable: true))
        }
        if state.canPutRankingBack {
            rows.append(Row("rank.restore", "Put the ranking back", symbol: "arrow.uturn.backward",
                            step: .run(.restoreRanking), synonyms: ["undo clear", "restore"]))
        }
        if onMonitor, let lit = state.rankLit {
            rows.append(Row("rank.up", "Move up", detail: "⌥↑", symbol: "arrow.up", step: .run(.moveRanked(-1)),
                            synonyms: ["higher", "better"], context: "Lit photo · \(lit)"))
            rows.append(Row("rank.down", "Move down", detail: "⌥↓", symbol: "arrow.down", step: .run(.moveRanked(1)),
                            synonyms: ["lower", "worse"], context: "Lit photo · \(lit)"))
        }
        return rows
    }

    private var organiseRows: [Row] {
        guard state.hasPhotoAccess else { return [] }
        if state.screen == .organise {
            guard state.organiseOpen else { return [] }
            let here = "This photo"
            var rows: [Row] = []
            do {
                let albums = state.albums.map { album in
                    Row("album.\(album.id)", album.title,
                        detail: album.added ? (state.oneAlbum ? "In it" : "In it · choose to take it out") : nil,
                        symbol: album.added ? "checkmark.rectangle.stack" : "rectangle.stack",
                        step: .run(.addToAlbum(album.id)), isCurrent: album.added)
                }
                rows.append(Row("organise.add", "Add to album…", detail: state.oneAlbum ? "Then the next photo" : nil,
                                symbol: "rectangle.stack.badge.plus",
                                step: .pick(CommandPick(prompt: "Which album?", choices: albums + [newAlbumRow(id: "album.new")],
                                                        nothing: "No album by that name. New album… makes one.")),
                                synonyms: ["file", "put in", "album"], context: here))
            }
            rows.append(newAlbumRow(id: "organise.new", context: here))
            rows += [
                Row("organise.next", "Next photo", detail: onMonitor ? "→" : nil, symbol: "arrow.right", step: .run(.nextPhoto),
                    synonyms: ["done with this", "advance"], context: here),
                Row("organise.skip", "Skip photo", detail: onMonitor ? "Space" : "Comes round again",
                    symbol: "forward", step: .run(.skipPhoto), synonyms: ["later", "pass"], context: here),
                Row.toggle("organise.onealbum", isOn: state.oneAlbum, turnOn: "One album, then next",
                           turnOff: "Several albums per photo", symbol: "1.circle", action: .oneAlbum(!state.oneAlbum),
                           synonyms: ["single album", "mode"]),
                Row("organise.done", "Done organising", detail: "Resume later from the start screen", symbol: "checkmark",
                    step: .run(.doneOrganising), synonyms: ["leave", "stop", "finish", "pause"]),
            ]
            return rows
        }
        var rows: [Row] = []
        if state.organisePaused {
            rows.append(Row("organise.resume", "Resume Organising", symbol: "play", step: .run(.resumeOrganise),
                            synonyms: ["continue", "carry on"]))
        }
        let folder = Row("source.folder", "A folder in Files…", detail: "Chosen on the phone", symbol: "folder",
                         step: .run(.organiseFolder), synonyms: ["files", "icloud", "camera import"])
        rows.append(sourcePick(id: "organise.start", title: state.organisePaused ? "Start Organising again…" : "Start Organising…",
                               verb: "Organise", command: BestShotCommand.startOrganise, extra: [folder]))
        rows.append(orderPick(id: "organise.order", order: state.organiseOrder, command: BestShotCommand.organiseOrder))
        return rows
    }

    /// New album…: the name typed, or an album already there with a name like it.
    private func newAlbumRow(id: String, context: String? = nil) -> Row {
        let like = state.albums.map {
            Row("like.\($0.id)", "Add to “\($0.title)”", detail: $0.added ? "In it" : "There already", symbol: "rectangle.stack",
                step: .run(.addToAlbum($0.id)))
        }
        return Row(id, "New album…", detail: onMonitor ? "n" : nil, symbol: "plus.rectangle.on.rectangle",
                   step: .ask(CommandAsk(prompt: "The new album's name", suggestions: like, symbol: "plus",
                                         title: { "Make “\($0)” and add the photo" },
                                         make: { text in
                                             let t = text.trimmingCharacters(in: .whitespaces)
                                             return t.isEmpty ? nil : .newAlbum(t)
                                         })),
                   synonyms: ["create album", "make album"], context: context)
    }

    private func projectRows(_ p: BestShotCommandState.OpenProject) -> [Row] {
        let here = "“\(p.name)”"
        var rows: [Row] = [
            Row("project.importphotos", "Import from Photos", symbol: "photo.on.rectangle", step: .run(.importPhotos),
                synonyms: ["add", "library"], context: here),
            Row("project.importfiles", "Import from Files", symbol: "folder", step: .run(.importFiles),
                synonyms: ["add", "icloud"], context: here),
        ]
        if p.count > 1 {
            rows.append(Row("project.compareall", "Compare all", symbol: "arrow.left.arrow.right", step: .run(.compareProject(.all)),
                            synonyms: ["rank", "pairs"], context: here))
            if p.unranked > 0 {
                rows.append(Row("project.comparenew", "Compare the new ones", detail: "\(p.unranked) new",
                                symbol: "arrow.left.arrow.right", step: .run(.compareProject(.unranked)),
                                synonyms: ["unranked", "rank"], context: here))
            }
        }
        let sorts = SortOption.allCases.map {
            Row("sort.\($0.rawValue)", $0.title, symbol: "arrow.up.arrow.down", step: .run(.projectSort($0)), isCurrent: p.sort == $0)
        }
        let filters = MediaFilter.allCases.map {
            Row("filter.\($0.rawValue)", $0.title, symbol: "line.3.horizontal.decrease", step: .run(.projectFilter($0)),
                isCurrent: p.filter == $0)
        }
        let sizes = GridSize.allCases.map { size in
            Row("grid.\(size.rawValue)", ["small": "Small", "medium": "Medium", "large": "Large"][size.rawValue] ?? size.label,
                symbol: "square.grid.3x3", step: .run(.gridSize(size)), isCurrent: p.grid == size)
        }
        rows += [
            Row("project.sort", "Sort by…", detail: p.sort.title, symbol: "arrow.up.arrow.down",
                step: .pick(CommandPick(prompt: "Sort by what?", choices: sorts)), synonyms: ["order"], context: here),
            Row("project.filter", "Show…", detail: p.filter.title, symbol: "line.3.horizontal.decrease",
                step: .pick(CommandPick(prompt: "Show what?", choices: filters)), synonyms: ["filter", "photos", "videos"],
                context: here),
            Row("project.grid", "Grid size…", detail: p.grid.label, symbol: "square.grid.3x3",
                step: .pick(CommandPick(prompt: "How big?", choices: sizes)), synonyms: ["thumbnails", "tiles", "zoom"],
                context: here),
            Row.toggle("project.select", isOn: p.selecting, turnOn: "Select", turnOff: "Done selecting",
                       states: ("\(p.selected) chosen", "Off"), symbol: "checkmark.circle", action: .selecting(!p.selecting),
                       synonyms: ["choose", "pick", "bulk"], context: here),
        ]
        if p.selecting {
            rows.append(Row("project.selectall", "Select all", symbol: "checkmark.circle.fill", step: .run(.selectAll),
                            synonyms: ["everything"], context: here))
            if p.selected > 0 {
                rows.append(Row("project.tagselected", "Tag the chosen…", detail: "\(p.selected) chosen", symbol: "tag",
                                step: .ask(CommandAsk(prompt: "A tag for the chosen", symbol: "tag", title: { "Tag them “\($0)”" },
                                                      make: { text in
                                                          let t = text.trimmingCharacters(in: .whitespaces)
                                                          return t.isEmpty ? nil : .tagSelected(t)
                                                      })),
                                synonyms: ["keyword", "bulk tag"], context: here))
                rows.append(Row("project.downloadselected", "Download the chosen (ZIP)", symbol: "archivebox",
                                step: .run(.downloadSelected), synonyms: ["share", "export", "zip"], context: here))
                if p.canJoin {
                    rows.append(Row("project.join", "Join the chosen videos", symbol: "film.stack", step: .run(.joinSelected),
                                    synonyms: ["merge", "combine"], context: here))
                }
                rows.append(Row("project.deleteselected", "Delete the chosen…", detail: "Asks first", symbol: "trash",
                                step: .run(.deleteSelected), confirms: true, synonyms: ["remove", "bin"], destructive: true,
                                context: here))
            }
        }
        rows += [
            Row("project.json", "Export JSON", symbol: "curlybraces", step: .run(.exportJSON), synonyms: ["share", "data"], context: here),
            Row("project.csv", "Export CSV", symbol: "tablecells", step: .run(.exportCSV), synonyms: ["share", "spreadsheet"], context: here),
            Row("project.zip", "Download all (ZIP)", symbol: "archivebox", step: .run(.downloadAll), synonyms: ["share", "export", "zip"],
                context: here),
            Row("project.clearranks", "Clear rankings…", detail: "Asks first", symbol: "arrow.uturn.backward",
                step: .run(.clearProjectRankings), confirms: true, synonyms: ["reset", "unrank"], destructive: true, context: here),
            Row("project.rename", "Rename…", symbol: "pencil",
                step: .ask(CommandAsk(prompt: "A new name", initial: p.name, title: { "Rename to “\($0)”" },
                                      make: { text in
                                          let t = text.trimmingCharacters(in: .whitespaces)
                                          return t.isEmpty || t == p.name ? nil : .renameProject(p.id, t)
                                      })),
                synonyms: ["name", "title"], context: here),
            Row("project.delete", "Delete project…", detail: "Asks first · its photos move to Files", symbol: "trash",
                step: .run(.deleteProject(p.id)), confirms: true, synonyms: ["remove", "bin"], destructive: true, context: here),
        ]
        return rows
    }

    // MARK: - Projects and imported media, on the monitor
    //
    // The phone's project screen has pickers, a share sheet and alerts; the monitor
    // gets the same actions as steps in the palette: typed names, picks, ticks and
    // a confirm in place of the alert. Only the imports need the phone.

    private func renameRow(id: UUID, name: String, context: String) -> Row {
        Row("project.rename", "Rename…", detail: onMonitor ? "r" : nil, symbol: "pencil",
            step: .ask(CommandAsk(prompt: "A new name", initial: name, title: { "Rename to “\($0)”" },
                                  make: { text in
                                      let t = text.trimmingCharacters(in: .whitespaces)
                                      return t.isEmpty || t == name ? nil : .renameProject(id, t)
                                  })),
            synonyms: ["name", "title", "rename project"], context: context)
    }

    /// The phone's alert, as a question in the palette: Return deletes, Esc backs out.
    private func deleteRow(id: UUID, name: String, removal: String, context: String) -> Row {
        Row("project.delete", "Delete project…", detail: onMonitor ? "⌘⌫ · asks first" : "Asks first · its photos move to Files",
            symbol: "trash",
            step: .confirm(CommandConfirm(prompt: "Delete “\(name)”?", title: "Delete the project",
                                          detail: removal.isEmpty ? "Its photos move to Files." : removal, action: .deleteProject(id))),
            synonyms: ["remove", "bin", "delete project"], destructive: true, context: context)
    }

    private func monitorProjectRows(_ p: BestShotCommandState.OpenProject) -> [Row] {
        let here = "“\(p.name)”"
        var rows: [Row] = []
        if p.count > 1 {
            rows.append(Row("project.compareall", "Compare all", detail: "c", symbol: "arrow.left.arrow.right",
                            step: .run(.compareProject(.all)), synonyms: ["rank", "pairs"], context: here))
            if p.unranked > 0 {
                rows.append(Row("project.comparenew", "Compare the new ones", detail: "\(p.unranked) new",
                                symbol: "arrow.left.arrow.right", step: .run(.compareProject(.unranked)),
                                synonyms: ["unranked", "rank"], context: here))
            }
        }
        rows += [
            Row("project.importphotos", "Import from Photos…", detail: "Chosen on the phone", symbol: "photo.on.rectangle",
                step: .run(.importPhotos), synonyms: ["add", "library"], context: here,
                onPhone: "Choose the photos on the phone."),
            Row("project.importfiles", "Import from Files…", detail: "Chosen on the phone", symbol: "folder",
                step: .run(.importFiles), synonyms: ["add", "icloud"], context: here,
                onPhone: "Choose the files on the phone."),
        ]
        rows += mediaListRows
        if let item = state.mediaItem { rows += mediaItemRows(item) }
        if p.count > 0 {
            rows.append(Row("project.clearranks", "Clear rankings…", symbol: "arrow.uturn.backward",
                            step: .confirm(CommandConfirm(prompt: "Clear the rankings in “\(p.name)”?", title: "Clear rankings",
                                                          detail: "Every photo here goes back to unranked.", symbol: "arrow.uturn.backward",
                                                          action: .clearProjectRankings)),
                            synonyms: ["reset", "unrank"], destructive: true, context: here))
        }
        rows.append(renameRow(id: p.id, name: p.name, context: here))
        rows.append(deleteRow(id: p.id, name: p.name, removal: p.removal, context: here))
        return rows
    }

    /// Sort, show and find, for a project or All Media.
    private var mediaListRows: [Row] {
        let sort = state.project?.sort ?? state.mediaSort
        let filter = state.project?.filter ?? state.mediaFilter
        let sorts = SortOption.allCases.map {
            Row("sort.\($0.rawValue)", $0.title, symbol: "arrow.up.arrow.down", step: .run(.projectSort($0)), isCurrent: sort == $0)
        }
        let filters = MediaFilter.allCases.map {
            Row("filter.\($0.rawValue)", $0.title, symbol: "line.3.horizontal.decrease", step: .run(.projectFilter($0)),
                isCurrent: filter == $0)
        }
        let query = state.mediaQuery
        var rows: [Row] = [
            Row("project.sort", "Sort by…", detail: [sort.title, "s"].joined(separator: " · "), symbol: "arrow.up.arrow.down",
                step: .pick(CommandPick(prompt: "Sort by what?", choices: sorts)), synonyms: ["order"]),
            Row("project.filter", "Show…", detail: [filter.title, "f"].joined(separator: " · "), symbol: "line.3.horizontal.decrease",
                step: .pick(CommandPick(prompt: "Show what?", choices: filters)), synonyms: ["filter", "photos", "videos"]),
            Row("media.find", "Find a photo…", detail: query.isEmpty ? "Names, tags, notes" : "“\(query)” · \(state.mediaShown) found",
                symbol: "magnifyingglass",
                step: .ask(CommandAsk(prompt: "Names, tags or notes", initial: query, symbol: "magnifyingglass",
                                      title: { "Find “\($0)”" },
                                      make: { text in
                                          let t = text.trimmingCharacters(in: .whitespaces)
                                          return t.isEmpty || t == query ? nil : .findMedia(t)
                                      })),
                synonyms: ["search", "look for"]),
        ]
        if !query.isEmpty {
            rows.append(Row("media.findoff", "Stop finding “\(query)”", detail: "Show them all again", symbol: "xmark.circle",
                            step: .run(.findMedia("")), synonyms: ["clear search", "show all"]))
        }
        return rows
    }

    /// The lit or open item: tags, ticked, with new ones typed in; and notes.
    private func mediaItemRows(_ item: BestShotCommandState.MediaItem) -> [Row] {
        let here = item.title
        let known = state.knownTags + item.tags.filter { tag in !state.knownTags.contains(tag) }
        let options = known.map { CommandOption($0, $0) }
        var rows: [Row] = [
            Row("media.tags", "Tags…", detail: [item.tags.isEmpty ? "None" : item.tags.joined(separator: ", "), "t"]
                    .joined(separator: " · "),
                symbol: "tag",
                step: .multi(CommandMulti(prompt: "Which tags?", options: options, ticked: item.tags,
                                          adds: { "New tag “\($0)”" },
                                          make: { ticks in
                                              let tags = ticks.ids + ticks.added
                                              return tags == item.tags ? nil : .setMediaTags(item.id, tags)
                                          })),
                synonyms: ["tag", "keyword", "label", "untag"], context: here),
            Row("media.note", item.note.isEmpty ? "Add a note…" : "Edit the note…", detail: item.note.isEmpty ? "e" : "“\(item.note)” · e",
                symbol: "note.text",
                step: .ask(CommandAsk(prompt: "A note for this photo", initial: item.note, symbol: "note.text",
                                      title: { "Note: “\($0)”" },
                                      make: { text in text == item.note ? nil : .noteMedia(item.id, text) })),
                synonyms: ["notes", "comment", "caption"], context: here),
        ]
        if !item.note.isEmpty {
            rows.append(Row("media.noteoff", "Clear the note", detail: "⌘Z puts it back", symbol: "note",
                            step: .run(.noteMedia(item.id, "")), synonyms: ["remove note", "delete comment"],
                            destructive: true, undoable: true, context: here))
        }
        return rows
    }

    // MARK: - Places

    private var places: [Row] {
        var rows: [Row] = []
        let sections: [MonitorSection] = onMonitor ? MonitorSection.allCases : [.triage, .organise, .rank, .allMedia, .settings]
        for section in sections {
            rows.append(Row("go.\(section.rawValue)", "Go to \(section.title)", detail: onMonitor ? "⌘\(section == .settings ? "," : "\(section.rawValue)")" : nil,
                            symbol: Self.symbol(section), step: .run(.go(section)), search: section.title,
                            synonyms: ["go to", "open"] + Self.synonyms(section)))
        }
        if !state.projects.isEmpty {
            let choices = state.projects.map {
                Row("project.\($0.id.uuidString)", $0.name, detail: "\($0.count) item\($0.count == 1 ? "" : "s")",
                    symbol: "folder", step: .run(.project($0.id)), isCurrent: state.project?.id == $0.id)
            }
            rows.append(Row("go.project", "Open project…", symbol: "folder",
                            step: .pick(CommandPick(prompt: "Which project?", choices: choices, nothing: "No project by that name.")),
                            synonyms: ["find", "go to", "projects"]))
        }
        rows.append(Row("project.new", "New project…", detail: onMonitor && state.screen == .projects ? "n" : nil, symbol: "plus",
                        step: .ask(CommandAsk(prompt: "The new project's name", symbol: "plus", title: { "Make the project “\($0)”" },
                                              make: { text in
                                                  let t = text.trimmingCharacters(in: .whitespaces)
                                                  return t.isEmpty ? nil : .newProject(t)
                                              })),
                        synonyms: ["create", "add project"]))
        #if os(iOS)
        // The tools are screens of their own, with pickers: chosen on the monitor, they open on the phone.
        let tools = onMonitor ? "The tool opens on the phone." : nil
        rows.append(Row("go.joinvideos", "Join Videos", detail: onMonitor ? "On the phone" : nil, symbol: "film.stack",
                        step: .run(.joinVideos), synonyms: ["tools", "merge", "combine", "video"], onPhone: tools))
        rows.append(Row("go.anticrop", "Anti-Crop", detail: onMonitor ? "On the phone" : nil, symbol: "rectangle.split.2x1",
                        step: .run(.antiCrop), synonyms: ["tools", "band", "cut", "remove middle"], onPhone: tools))
        #endif
        if onMonitor {
            rows.append(Row("keys", "All keys", detail: "?", symbol: "keyboard", step: .run(.allKeys),
                            synonyms: ["help", "shortcuts"]))
        }
        return rows
    }

    private static func symbol(_ section: MonitorSection) -> String {
        switch section {
        case .triage: return "rectangle.stack.badge.person.crop"
        case .rank: return "list.number"
        case .organise: return "folder.badge.plus"
        case .allMedia: return "square.grid.2x2"
        case .projects: return "folder"
        case .settings: return "gearshape"
        }
    }

    private static func synonyms(_ section: MonitorSection) -> [String] {
        switch section {
        case .triage: return ["cull", "review", "keep or delete"]
        case .rank: return ["order", "best"]
        case .organise: return ["albums", "file"]
        case .allMedia: return ["library", "imported", "everything"]
        case .projects: return ["imported"]
        case .settings: return ["preferences", "options", "labels"]
        }
    }

    // MARK: - Settings

    private var settingsRows: [Row] {
        let looks = Appearance.allCases.map {
            Row("look.\($0.rawValue)", $0.title, symbol: "circle.lefthalf.filled", step: .run(.appearance($0)),
                preview: .appearance($0), isCurrent: state.appearance == $0)
        }
        var rows: [Row] = [
            Row("appearance", "Appearance…", detail: state.appearance.title, symbol: "circle.lefthalf.filled",
                step: .pick(CommandPick(prompt: "Light or dark?", choices: looks, revert: .appearance(state.appearance))),
                synonyms: ["theme", "dark mode", "light mode", "look", "night"]),
        ]
        let labels = LabelColour.allCases.map { colour in
            let name = state.name(colour)
            return Row("label.\(colour.slug)", name, detail: name == colour.title ? nil : colour.title, symbol: "circle.fill",
                       step: .ask(CommandAsk(prompt: "A name for \(colour.title.lowercased())", initial: name,
                                             title: { "Call \(colour.title.lowercased()) “\($0)”" },
                                             make: { text in
                                                 let t = text.trimmingCharacters(in: .whitespaces)
                                                 return t.isEmpty || t == name ? nil : .renameLabel(colour, t)
                                             })))
        }
        rows.append(Row("labels", "Rename a colour label…", symbol: "tag",
                        step: .pick(CommandPick(prompt: "Which colour?", choices: labels, searchable: false)),
                        synonyms: ["label names", "colour names", "color names"]))
        if state.monitorConnected {
            rows.append(Row.toggle("monitor.pause", isOn: state.monitorPaused, turnOn: "Pause monitor", turnOff: "Resume monitor",
                                   states: ("Paused", "Showing"), detail: "⌥⌘P", symbol: "pause.rectangle", action: .pause,
                                   synonyms: ["blank", "hide screen"]))
            let percent = "\(Int((state.textScale * 100).rounded()))%"
            if state.textScale < (MonitorDesk.textScales.last ?? 1) - 0.001 {
                rows.append(Row("monitor.larger", "Monitor text larger", detail: "⌥⌘= · now \(percent)", symbol: "textformat.size.larger",
                                step: .run(.textSize(1)), synonyms: ["bigger", "zoom in", "text size"]))
            }
            if state.textScale > (MonitorDesk.textScales.first ?? 1) + 0.001 {
                rows.append(Row("monitor.smaller", "Monitor text smaller", detail: "⌥⌘− · now \(percent)", symbol: "textformat.size.smaller",
                                step: .run(.textSize(-1)), synonyms: ["zoom out", "text size"]))
            }
        }
        return rows
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension LabelColour {
    /// The monitor's key: the phone's, and `p` for purple, which has no digit.
    var monitorKey: String? { key ?? (self == .purple ? "p" : nil) }
}
