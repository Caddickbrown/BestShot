#if os(iOS)
import SwiftUI
import UIKit

// MARK: - The ⌘K menu's glue
//
// What it lists is BestShotCommands.swift; the keys, recents, steps and previews
// are the kit's (kit/swift/CommandPalette.swift). This says what each command
// does, on whichever display it was opened for, and draws the panel over the
// phone. On the monitor, MonitorViews.swift draws the same panel.
//
// Three ways in: ⌘K with a keyboard (on the monitor, `/` too), and "Commands"
// in a ⋯ menu, which brings up the on-screen keyboard and takes taps.

@MainActor
enum BestShotCommandMenu {
    static let host: CommandHost<BestShotCommandList> = {
        let host = CommandHost<BestShotCommandList>()
        host.list = { BestShotCommandList(state: state) }
        host.monitorShows = { monitorShows }
        host.leaveSheet = { AppCommands.shared.leaveSheet() }
        host.recents = CommandRecents(key: "bestshot.commands.recents")
        host.perform = { run($0) }
        // A preview, and putting it back: only the look, with the menu still open.
        host.preview = { command in
            if case .appearance(let look) = command { UserDefaults.standard.set(look.rawValue, forKey: Appearance.key) }
        }
        host.overlay = { AnyView(PhoneCommandOverlay()) }
        return host
    }()

    /// The display the menu was last listed for. A command runs there.
    private static var display = BestShotCommandState.Display.phone

    static var isOpen: Bool { host.menu != nil }

    private static var desk: MonitorDesk? { MonitorDisplay.shared.desk }

    /// The monitor is up and showing things, so the menu is drawn there and acts there.
    static var monitorShows: Bool {
        guard let desk else { return false }
        return desk.isConnected && !desk.isPaused && !desk.isLocked
    }

    /// Once, at launch, after the desk is made.
    static func install() {
        CommandResponders.install()
        _ = host
        desk?.onMenu = { host.toggle() }
    }

    private static var appearance: Appearance {
        UserDefaults.standard.string(forKey: Appearance.key).flatMap(Appearance.init(rawValue:)) ?? .fallback
    }

    /// What's on screen, as the list wants it: the monitor's when it's showing, otherwise the phone's.
    static var state: BestShotCommandState {
        guard let desk else { return BestShotCommandState() }
        if monitorShows {
            display = .monitor
            return desk.commandState(appearance: appearance)
        }
        display = .phone
        if desk.library.sources.count <= TriageSourceOption.quick.count { desk.library.reloadSources() }
        let app = AppCommands.shared
        return .phone(place: app.place, triageGrid: app.triageGrid,
                      triageCanUndo: TriageHolder.shared.session?.canUndo ?? false, project: app.project,
                      library: desk.library, marks: desk.marks, rank: RankHolder.shared.board, appearance: appearance,
                      monitorConnected: desk.isConnected, monitorPaused: desk.isPaused, textScale: desk.textScale)
    }

    static func run(_ command: BestShotCommand) {
        guard let desk else { return }
        if display == .monitor {
            desk.run(command)
        } else {
            phone(command, desk: desk)
        }
    }

    /// On the phone's screens. Anything with a sheet or a confirmation of its own
    /// goes to the screen that has it, as its button would.
    private static func phone(_ command: BestShotCommand, desk: MonitorDesk) {
        let app = AppCommands.shared
        let library = desk.library
        let triage = TriageHolder.shared.session
        let board = RankHolder.shared.board
        let defaults = UserDefaults.standard
        func say(_ task: @escaping @MainActor () async -> String?) {
            Task { if let said = await task(), !said.isEmpty { app.message = said } }
        }
        switch command {
        case .go, .project, .joinVideos, .antiCrop, .newProject, .renameProject, .deleteProject:
            app.send(command)

        case .stars, .colour, .noColour, .toggleTag:
            if let id = triage?.current?.localIdentifier { desk.mark(id, with: command) }
        case .favourite: triage?.toggleFavourite()
        case .keep: Theme.Motion.run(Theme.Motion.snap) { triage?.keep() }
        case .markDelete: Theme.Motion.run(Theme.Motion.snap) { triage?.delete() }
        case .skip: triage?.skip()
        case .undo:
            if app.place == .organise { say { await library.undoOrganise() } } else { triage?.undo() }
        case .grid, .finishTriage:
            app.send(command)

        case .triageOrder(let order): defaults.set(order.rawValue, forKey: BestShotCommandState.triageOrderKey)
        case .startTriage(let source):
            app.send(.go(.triage))
            let order = defaults.string(forKey: BestShotCommandState.triageOrderKey).flatMap(SessionOrder.init(rawValue:)) ?? .newest
            say { await library.startTriage(order: order, source: source) }
        case .resumeTriage:
            app.send(.go(.triage))
            library.resumeTriage()

        case .rankCompare(let scope): board?.startCompare(scope: scope)
        case .saveRankAlbum:
            let ids = board?.ranked ?? []
            say { await library.saveRankAlbum(ids) }
        case .clearRanking:
            board?.clear()
            app.message = "Ranking cleared. To put it back, choose Put the ranking back in Commands."
        case .restoreRanking: board?.restoreCleared()
        case .compareChoose(let choice): board?.compare?.choose(choice)
        case .compareUndo: board?.compare?.undo()
        case .compareSave: board?.finishCompare(save: true)

        case .organiseOrder(let order): defaults.set(order.rawValue, forKey: BestShotCommandState.organiseOrderKey)
        case .startOrganise(let source):
            app.send(.go(.organise))
            let order = defaults.string(forKey: BestShotCommandState.organiseOrderKey).flatMap(SessionOrder.init(rawValue:)) ?? .newest
            say { await library.startOrganise(order: order, source: source) }
        case .organiseFolder:
            // The phone's folder picker, as the monitor asks for it; what's picked starts Organise on both.
            app.send(.go(.organise))
            desk.run(.organiseFolder)
        case .resumeOrganise:
            app.send(.go(.organise))
            library.resumeOrganise()
        case .addToAlbum(let id): Task { await library.addToAlbum(id) }
        case .newAlbum(let name): Task { await library.newAlbum(name) }
        case .nextPhoto: library.nextOrganised()
        case .skipPhoto: library.skipOrganised()
        case .oneAlbum(let on): library.organiseOneAlbum = on
        case .doneOrganising: library.leaveOrganise()

        case .importPhotos, .importFiles, .compareProject, .projectSort, .projectFilter, .gridSize, .selecting,
             .selectAll, .tagSelected, .downloadSelected, .joinSelected, .deleteSelected, .exportJSON, .exportCSV,
             .downloadAll, .clearProjectRankings:
            app.send(command)

        case .appearance(let look): defaults.set(look.rawValue, forKey: Appearance.key)
        case .renameLabel(let colour, let name): app.message = library.renameLabel(colour, to: name)
        case .textSize(let by): desk.adjustTextScale(by)
        case .pause: desk.togglePause()

        // The monitor's own screens: never listed on the phone.
        case .allKeys, .zoom, .pinCompare, .swapSides, .info, .nextUndecided, .filters, .filterStatus, .filterStars,
             .filterTag, .filtersOff, .moveRanked:
            break
        }
    }
}

/// The menu's own window: the panel over the dimmed page, unless the monitor
/// has it. Tapping outside closes it.
private struct PhoneCommandOverlay: View {
    @ObservedObject private var host = BestShotCommandMenu.host
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(host.onMonitor ? 0.001 : 0.25).ignoresSafeArea()
                .onTapGesture { host.close() }
                .accessibilityLabel("Close the menu")
                .accessibilityAddTraits(.isButton)
            if let menu = host.menu {
                if host.onMonitor {
                    VStack {
                        Spacer()
                        Text("The menu is on the monitor. Tap here to close it.")
                            .font(.mono(14)).foregroundStyle(Theme.table.muted)
                            .padding(12)
                            .background(Theme.table.paper)
                            .overlay(Rectangle().stroke(Theme.table.rule, lineWidth: 1))
                            .padding(16)
                    }
                    .allowsHitTesting(false)
                } else {
                    CommandPanel(menu: menu, palette: Theme.table, text: 15, caption: 11, rowHeight: 50,
                                 touch: host.byTouch, showsKeys: !host.byTouch,
                                 choose: { host.choose($0) }, hover: { host.highlight($0) },
                                 back: { host.back() }, close: { host.close() })
                        .frame(maxWidth: 620)
                        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
                        .padding(.horizontal, 16)
                        .padding(.top, sizeClass == .compact ? 8 : 40)
                }
            }
        }
    }
}

/// "Commands" for a ⋯ menu, in BestShot's words.
struct CommandsMenuItem: View {
    var body: some View { CommandMenuItem(title: "Commands") }
}
#endif
