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
    @State private var escapes = EscapeStack()
    /// On a phone, which column is showing. The menu, the sidebar, is home.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    /// On an iPad, the menu stays in sight beside what's open.
    @State private var columns = NavigationSplitViewVisibility.all
    // Kept here so Esc can close their sheets without losing what's typed.
    @State private var projectName = ""
    @State private var projectDescription = ""
    @State private var labelDrafts: [LabelColour: String] = [:]

    enum SidebarSelection: Hashable {
        case triage
        case organise
        case rank
        case folders
        case allMedia
        case project(UUID)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            List(selection: $selection) {
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
                        ProjectRow(project: project)
                            .tag(SidebarSelection.project(project.uuid))
                            .contextMenu {
                                Button(role: .destructive) {
                                    delete(project)
                                } label: {
                                    Label("Delete Project", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .tableSurfaceList()
            .navigationTitle("BestShot")
            .toolbar {
                // Both in plain sight. A secondary item folds into the bar's own
                // overflow button, which put one More menu inside another.
                ToolbarItemGroup(placement: .primaryAction) {
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
        } detail: {
            detailView
                .environment(\.showRank, ShowRankAction { selection = .rank })
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet(name: $projectName, description: $projectDescription) { name, description in
                createProject(name: name, description: description)
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(names: $labelDrafts) }
        // Esc's last step is the main menu. A Triage session waits behind Resume.
        .escapeRoot(escapes) {
            selection = nil
            compactColumn = .sidebar
            columns = .all
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
        case .allMedia:
            AllMediaView()
        case .project(let id):
            if let project = projects.first(where: { $0.uuid == id }) {
                GalleryView(project: project)
                    .id(project.uuid)
            } else {
                ContentUnavailableView("Select a Project", systemImage: "photo.on.rectangle")
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

    private func delete(_ project: Project) {
        MediaStore.shared.deleteProjectFolder(projectID: project.uuid)
        context.delete(project)
        try? context.save()
        if selection == .project(project.uuid) { selection = .allMedia }
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
        EmptyState("BestShot", message: "Triage to keep or delete, Rank to put the keepers in order, Organise to file them into albums.")
            .tableSurface()
    }
}
