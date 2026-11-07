import SwiftUI
import SwiftData

/// Top-level navigation. A sidebar lists projects plus an "All Media" entry;
/// the detail pane shows the selected project's gallery. Adapts to a stack on
/// iPhone and a split view on iPad / Mac automatically.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Project.sortIndex), SortDescriptor(\Project.createdAt)])
    private var projects: [Project]

    @State private var selection: SidebarSelection? = .triage
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var escapes = EscapeStack()
    /// On a phone, which column is showing. Triage, the detail, is home.
    @State private var compactColumn = NavigationSplitViewColumn.detail
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
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List(selection: $selection) {
                Section("Review") {
                    Label("Triage", systemImage: "rectangle.stack.badge.person.crop")
                        .tag(SidebarSelection.triage)
                    Label("Organise", systemImage: "folder.badge.plus")
                        .tag(SidebarSelection.organise)
                    Label("Rank", systemImage: "list.number")
                        .tag(SidebarSelection.rank)
                }
                #if os(macOS)
                Section("Folders") {
                    Label("Cull a folder", systemImage: "folder")
                        .tag(SidebarSelection.folders)
                }
                #endif
                Section("Library") {
                    Label("All Media", systemImage: "square.grid.2x2")
                        .tag(SidebarSelection.allMedia)
                }
                Section("Projects") {
                    if projects.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nothing here yet. A project is a set of photos you import to rank together, apart from your library.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("New Project") { showingNewProject = true }
                                .font(.footnote)
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
        .escapeRoot(escapes) {
            selection = .triage
            compactColumn = .detail
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
            ContentUnavailableView("Select a Project", systemImage: "photo.on.rectangle")
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
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).lineLimit(1)
                Text("\(project.itemCount) item\(project.itemCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
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
                Section("Project") {
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
