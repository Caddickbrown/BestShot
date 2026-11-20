import SwiftUI
import SwiftData

/// Top-level navigation. A sidebar lists projects plus an "All Media" entry;
/// the detail pane shows the selected project's gallery. Adapts to a stack on
/// iPhone and a split view on iPad / Mac automatically.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Project.sortIndex), SortDescriptor(\Project.createdAt)])
    private var projects: [Project]

    /// Nothing chosen: the app opens on its main menu, the sidebar.
    @State private var selection: SidebarSelection?
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var showingWhatsNew = false
    @State private var escapes = EscapeStack()
    /// On a phone, which column is showing. The menu, the sidebar, is home.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    /// On an iPad, the menu stays in sight beside what's open.
    @State private var columns = NavigationSplitViewVisibility.all
    // Kept here so Esc can close their sheets without losing what's typed.
    @State private var projectName = ""
    @State private var projectDescription = ""
    @State private var labelDrafts: [LabelColour: String] = [:]
    // A project being renamed or deleted, from the menu or its own screen.
    @State private var renaming: Project?
    @State private var newName = ""
    @State private var deleting: Project?
    @State private var projectProblem: String?
    /// The ⌘K menu's requests and what the screens tell it.
    @State private var commands = AppCommands.shared
    /// Re-taps of the place already open (GUIDE, 19 Nov): the pane beside the
    /// sidebar scrolls back to its top. Only beside it: on a phone the menu is a
    /// screen of its own, and a row tapped there opens the place.
    @State private var reselects = TabReselect<SidebarSelection>()
    @Environment(\.horizontalSizeClass) private var sizeClass

    enum SidebarSelection: Hashable {
        case triage
        case organise
        case rank
        case folders
        case allMedia
        case joinVideos
        case antiCrop
        case glue
        case multiCrop
        case project(UUID)
    }

    // Built in stages (split view, sheets, alerts, commands) so each part
    // type-checks on its own; one long chain was too slow for CI's compiler.
    var body: some View {
        withCommands(withAlerts(withSheets(splitView)))
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            sidebar
        } detail: {
            detailView
                .environment(\.showRank, ShowRankAction { selection = .rank })
                .environment(\.reselectSignal, selection.map { reselects.signal($0) } ?? 0)
                #if os(iOS)
                .toolbar {
                    // In the bar's ⋯ menu. A project has its own Options menu, with Commands in it.
                    if commandsInBar {
                        ToolbarItem(placement: .secondaryAction) { CommandsMenuItem() }
                    }
                }
                #endif
        }
    }

    private var sidebar: some View {
        List(selection: $selection.reselecting { place in
            if let place, sizeClass != .compact { reselects.tapped(place, current: place) }
        }) {
            MenuSection("Review") {
                MenuRow("Triage", systemImage: "rectangle.stack.badge.person.crop")
                    .tag(SidebarSelection.triage)
                MenuRow("Organise", systemImage: "folder.badge.plus")
                    .tag(SidebarSelection.organise)
                MenuRow("Rank", systemImage: "list.number")
                    .tag(SidebarSelection.rank)
            }
            #if os(macOS)
            MenuSection("Folders") {
                MenuRow("Cull a folder", systemImage: "folder")
                    .tag(SidebarSelection.folders)
            }
            #endif
            #if os(iOS)
            // iPhone and iPad only for now: the Mac and the other apps don't have them.
            MenuSection("Tools") {
                MenuRow("Join Videos", systemImage: "film.stack")
                    .tag(SidebarSelection.joinVideos)
                MenuRow("Anti-Crop", systemImage: "rectangle.split.2x1")
                    .tag(SidebarSelection.antiCrop)
                MenuRow("Glue", systemImage: "rectangle.split.2x1.fill")
                    .tag(SidebarSelection.glue)
                MenuRow("Multi Crop", systemImage: "crop")
                    .tag(SidebarSelection.multiCrop)
            }
            #else
            // On the Mac: Glue and Multi Crop on any files (Folders has them on its photos too).
            MenuSection("Tools") {
                MenuRow("Glue", systemImage: "rectangle.split.2x1.fill")
                    .tag(SidebarSelection.glue)
                MenuRow("Multi Crop", systemImage: "crop")
                    .tag(SidebarSelection.multiCrop)
            }
            #endif
            MenuSection("Library") {
                MenuRow("All Media", systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.allMedia)
            }
            MenuSection("Projects") {
                if projects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        FormNote("Nothing here yet. A project is a set of photos you import to rank together, apart from your library.")
                        Button("New Project") { showingNewProject = true }
                            .buttonStyle(.text)
                    }
                    .padding(.vertical, 2)
                }
                ForEach(projects) { project in
                    projectRow(project)
                }
            }
        }
        .tableSurfaceList()
        // The mark and the name head the menu, as a screen's header heads it.
        .safeAreaInset(edge: .top, spacing: 0) { BrandHeader() }
        #if os(macOS)
        // Wide enough for the name on one line: narrower, the Mac stacked
        // "BestShot" a letter per line and cut the rows short (18 Nov run).
        .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 320)
        #endif
        .navigationTitle("BestShot")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { sidebarToolbar }
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        #if os(iOS)
        // The mark and the name, centred in the bar's own row.
        ToolbarItem(placement: .principal) { BrandBarTitle() }
        #endif
        // Both in plain sight. A secondary item folds into the bar's own
        // overflow button, which put one More menu inside another.
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
            // The way into the command menu without a keyboard.
            Button {
                CommandRoute.presentMenu()
            } label: {
                Label("Commands", systemImage: "command")
            }
            #endif
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button {
                showingNewProject = true
            } label: {
                Label("New Project", systemImage: "plus")
            }
        }
    }

    private func withSheets<V: View>(_ base: V) -> some View {
        base
            .sheet(isPresented: $showingNewProject) {
                NewProjectSheet(name: $projectName, description: $projectDescription) { name, description in
                    createProject(name: name, description: description)
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(names: $labelDrafts) }
            .sheet(isPresented: $showingWhatsNew) { WhatsNewView() }
            .task {
                // Once after an update; never under XCTest.
                if WhatsNew.unseen && NSClassFromString("XCTestCase") == nil { showingWhatsNew = true }
            }
            .sheet(item: $renaming) { project in
                TextPromptSheet(title: "Rename Project", placeholder: "Name", action: "Rename", text: $newName) {
                    ProjectLibrary.rename(project, to: newName, context: context)
                    newName = ""
                }
            }
    }

    private func withAlerts<V: View>(_ base: V) -> some View {
        base
            .alert("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), presenting: deleting) { project in
                Button("Delete Project", role: .destructive) { delete(project) }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { project in
                Text(ProjectLibrary.removalMessage(for: project))
            }
            .alert("Couldn't delete the project", isPresented: Binding(
                get: { projectProblem != nil }, set: { if !$0 { projectProblem = nil } }
            ), presenting: projectProblem) { _ in
                Button("OK") { projectProblem = nil }
            } message: { Text($0) }
            .escapeCloses(when: deleting != nil) { deleting = nil }
            .escapeCloses(when: projectProblem != nil) { projectProblem = nil }
    }

    private func withCommands<V: View>(_ base: V) -> some View {
        base
            // Choosing a place in the menu opens it, on a phone too.
            .onChange(of: selection, initial: true) { _, new in
                if new != nil { compactColumn = .detail }
                commands.place = Self.place(new)
            }
            .onChange(of: commands.request?.id) { _, _ in
                if let command = commands.request?.command { carryOut(command) }
            }
            .alert("BestShot", isPresented: Binding(
                get: { commands.message != nil }, set: { if !$0 { commands.message = nil } }
            )) {
                Button("OK") { commands.message = nil }
            } message: { Text(commands.message ?? "") }
            .escapeCloses(when: commands.message != nil) { commands.message = nil }
            // Esc's last step is the main menu. A Triage session waits behind Resume.
            .escapeRoot(escapes) {
                selection = nil
                compactColumn = .sidebar
                columns = .all
            }
            .onAppear {
                commands.leaveSheet = { [escapes] in if escapes.hasSheet { escapes.press() } }
                #if os(macOS) && DEBUG
                // `BESTSHOT_FOLDER=<path>` opens Folders on that folder, for test runs.
                if FolderHomeView.launchFolder != nil { selection = .folders }
                #endif
            }
    }

    /// Every screen but a project's, which has Commands in its Options menu.
    private var commandsInBar: Bool {
        switch selection {
        case .project, nil: return false
        default: return true
        }
    }

    private static func place(_ selection: SidebarSelection?) -> AppCommands.Place {
        switch selection {
        case .triage: return .triage
        case .organise: return .organise
        case .rank: return .rank
        case .folders: return .folders
        case .allMedia: return .allMedia
        case .joinVideos: return .joinVideos
        case .antiCrop: return .antiCrop
        case .glue: return .glue
        case .multiCrop: return .multiCrop
        case .project(let id): return .project(id)
        case nil: return .home
        }
    }

    /// A command from the ⌘K menu for the main menu: going somewhere, or a project.
    private func carryOut(_ command: BestShotCommand) {
        switch command {
        case .go(let section):
            switch section {
            case .triage: selection = .triage
            case .rank: selection = .rank
            case .organise: selection = .organise
            case .allMedia: selection = .allMedia
            case .projects:
                selection = nil
                compactColumn = .sidebar
            case .settings: showingSettings = true
            }
        case .project(let id): selection = .project(id)
        case .joinVideos: selection = .joinVideos
        case .antiCrop: selection = .antiCrop
        case .glue: selection = .glue
        case .multiCrop: selection = .multiCrop
        case .newProject(let name): createProject(name: name, description: "")
        case .renameProject(let id, let name):
            if let project = projects.first(where: { $0.uuid == id }) { _ = ProjectLibrary.rename(project, to: name, context: context) }
        case .deleteProject(let id):
            // The same question as the menu's Delete: nothing goes without it.
            deleting = projects.first { $0.uuid == id }
        case .projectRemoved(let id):
            // Deleted from the monitor, which asked first: let go of it here.
            if selection == .project(id) {
                selection = nil
                compactColumn = .sidebar
            }
        default:
            break
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .triage:
            TriageHomeView()
        case .organise:
            OrganiseHomeView()
        case .rank:
            PhotosRankView()
        case .folders:
            #if os(macOS)
            FolderHomeView()
            #else
            EmptyView()
            #endif
        case .joinVideos:
            #if os(iOS)
            VideoJoinView()
            #else
            EmptyView()
            #endif
        case .antiCrop:
            #if os(iOS)
            AntiCropView()
            #else
            EmptyView()
            #endif
        case .glue:
            GlueView()
        case .multiCrop:
            MultiCropView()
        case .allMedia:
            AllMediaView()
        case .project(let id):
            if let project = projects.first(where: { $0.uuid == id }) {
                GalleryView(project: project,
                            onRename: { startRenaming(project) },
                            onDelete: { deleting = project })
                    .id(project.uuid)
            } else {
                EmptyState("Select a Project").tableSurface()
            }
        case nil:
            HomeDetailView()
        }
    }

    private func createProject(name: String, description: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let project = Project(
            name: trimmed,
            projectDescription: description,
            sortIndex: (projects.map(\.sortIndex).max() ?? 0) + 1
        )
        context.insert(project)
        try? context.save()
        selection = .project(project.uuid)
    }

    /// A project in the menu: tap to open; swipe or long-press to rename or delete.
    private func projectRow(_ project: Project) -> some View {
        ProjectRow(project: project)
            .contextMenu { projectMenu(project) }
            .swipeActions(edge: .trailing) {
                Button { deleting = project } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Theme.table.accent)
                Button { startRenaming(project) } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(Theme.table.muted)
            }
            .tag(SidebarSelection.project(project.uuid))
    }

    @ViewBuilder
    private func projectMenu(_ project: Project) -> some View {
        Button { selection = .project(project.uuid) } label: {
            Label("Open", systemImage: "folder")
        }
        Button { startRenaming(project) } label: {
            Label("Rename…", systemImage: "pencil")
        }
        Button(role: .destructive) { deleting = project } label: {
            Label("Delete Project…", systemImage: "trash")
        }
    }

    private func startRenaming(_ project: Project) {
        newName = project.name
        renaming = project
    }

    /// The project only: its photos move to Files, never deleted.
    private func delete(_ project: Project) {
        deleting = nil
        let id = project.uuid
        do {
            try ProjectLibrary.remove(project, context: context)
            if selection == .project(id) {
                selection = nil
                compactColumn = .sidebar
            }
        } catch {
            projectProblem = "Its photos couldn't be moved to Files, so it's been kept. \(error.localizedDescription)"
        }
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(Theme.table.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.row).lineLimit(1)
                Text("\(project.itemCount) item\(project.itemCount == 1 ? "" : "s")")
                    .font(.small)
                    .foregroundStyle(Theme.table.muted)
            }
        }
        .menuRowBackground()
    }
}

/// A heading in the main menu: Rank's small mono label.
private struct MenuSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            SheetLabel(title)
        }
    }
}

/// A place in the main menu: a quiet icon and the name in mono, on the table.
private struct MenuRow: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title).font(.row)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Theme.table.muted)
        }
        .menuRowBackground()
    }
}

private struct MenuRowBackground: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        // On a phone the menu is a list of rows on paper. Beside the iPad's screen
        // it's a sidebar, and the system draws which row is open.
        if sizeClass == .compact { content.listRowBackground(Theme.table.paper) } else { content }
        #else
        content
        #endif
    }
}

private extension View {
    func menuRowBackground() -> some View { modifier(MenuRowBackground()) }
}

/// Sheet for creating a project (name + optional description), mirroring the
/// web app's "Create project / Spin up" flow.
struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String
    @Binding var description: String
    let onCreate: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TableSection("Project") {
                    EscapingField(placeholder: "Name", text: $name)
                    #if os(iOS)
                    EscapingEditor(placeholder: "Description (optional)", text: $description)
                        .frame(minHeight: 70)
                    #else
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    #endif
                }
            }
            .tableForm()
            .navigationTitle("New Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clear()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name, description)
                        clear()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 220)
        .escapeScreen { dismiss() }
    }

    private func clear() {
        name = ""
        description = ""
    }
}

/// Lets screens deep inside a mode (e.g. the Triage summary) jump to Rank.
struct ShowRankAction {
    var action: () -> Void = {}
    func callAsFunction() { action() }
    init(_ action: @escaping () -> Void = {}) { self.action = action }
}

/// How many times the open place's sidebar row has been tapped again. Its pane
/// scrolls to the top on each (`scrollsToTopOnReselect`, kit/swift/TabReselect.swift).
private struct ReselectSignalKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var reselectSignal: Int {
        get { self[ReselectSignalKey.self] }
        set { self[ReselectSignalKey.self] = newValue }
    }
}

/// The head of a pane's ScrollView, for a re-tap to scroll back to.
enum ScrollTop {
    static let id = "bestshot.scroll.top"
    static var anchor: some View { Color.clear.frame(height: 0).id(id).accessibilityHidden(true) }
}

private struct ShowRankKey: EnvironmentKey {
    static let defaultValue = ShowRankAction()
}

extension EnvironmentValues {
    var showRank: ShowRankAction {
        get { self[ShowRankKey.self] }
        set { self[ShowRankKey.self] = newValue }
    }
}

/// Beside the menu on an iPad or a Mac, before anything is chosen.
private struct HomeDetailView: View {
    var body: some View {
        VStack(spacing: 0) {
            BrandMark().frame(width: 88, height: 88)
            EmptyState("BestShot", message: message).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tableSurface()
    }

    private var message: String {
        #if os(iOS)
        "Triage to keep or delete, Rank to put the keepers in order, Organise to file them into albums. Tools join videos and cut bands out of photos."
        #else
        "Triage to keep or delete, Rank to put the keepers in order, Organise to file them into albums."
        #endif
    }
}
