import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// The main project screen: a filterable, sortable, searchable grid of media
/// with import, drag-to-rank, comparison mode, bulk selection, and export.
struct GalleryView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context

    // Display controls
    @State private var filter: MediaFilter = .all
    @State private var sort: SortOption = .rank
    @State private var gridSize: GridSize = .medium
    @State private var searchText = ""

    // Import
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var isImporting = false
    @State private var importMessage: String?

    // Selection / bulk
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingBulkTag = false
    @State private var bulkTagText = ""

    // Viewer
    @State private var viewerItem: MediaItem?

    // Tools: the chosen videos, in the grid's order, going into Join Videos.
    @State private var joining: JoinRequest?

    // Comparison
    @State private var showingCompareSelection = false
    @State private var session: ComparisonSession?
    @State private var resultsSession: ComparisonSession?

    // Drag reorder
    @State private var draggingItem: MediaItem?

    // Export / share
    @State private var shareURL: ShareableURL?
    @State private var showingClearConfirm = false

    private var displayedItems: [MediaItem] {
        project.sortedItems(by: sort, filter: filter).filter { MediaSearch.matches(searchText, item: $0) }
    }

    private var canReorder: Bool {
        sort == .rank && searchText.isEmpty && !selectionMode
    }

    private var status: String {
        let n = project.itemCount, ranked = n - project.unrankedCount
        return "\(ranked) ranked · \(project.unrankedCount) new"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: project.projectDescription.isEmpty ? "Project" : project.projectDescription,
                         title: project.name, status: project.items.isEmpty ? nil : status)
            content
                .mediaSearch(text: $searchText, prompt: "Search names, tags or comments")
        }
            .tableSurfaceList()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if selectionMode {
                    BulkActionBar(
                        count: selectedIDs.count,
                        onJoin: joinableVideos.count >= 2 ? { joinSelected() } : nil,
                        onTag: { showingBulkTag = true },
                        onDownload: bulkDownload,
                        onDelete: bulkDelete,
                        onCancel: exitSelection
                    )
                }
            }
            .overlay { if isImporting { importOverlay } }
            .onChange(of: photoItems) { _, newItems in importFromPhotos(newItems) }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItems, matching: .any(of: [.images, .videos]))
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.image, .movie, .video],
                allowsMultipleSelection: true
            ) { result in importFromFiles(result) }
            .fullScreenCoverCompat(item: $viewerItem) { item in
                FullscreenViewerView(items: displayedItems, initial: item)
            }
            .sheet(item: $joining) { request in
                ToolSheet { VideoJoinView(initial: request.urls) }
            }
            .sheet(isPresented: $showingCompareSelection) {
                ComparisonSelectionView(
                    allCount: project.itemCount,
                    unrankedCount: project.unrankedCount
                ) { scope in
                    startComparison(scope: scope)
                }
            }
            .fullScreenCoverCompat(item: $session) { session in
                ComparisonView(session: session) {
                    // On finish, transition to results.
                    resultsSession = session
                    self.session = nil
                }
            }
            .sheet(item: $resultsSession) { session in
                ComparisonResultsView(session: session) {
                    RankingService.applyRanking(
                        orderedNames: session.finalOrderNames(),
                        project: project,
                        context: context
                    )
                    resultsSession = nil
                }
            }
            .sheet(isPresented: $showingBulkTag) {
                TextPromptSheet(title: "Add Tag", placeholder: "Tag", action: "Add",
                                text: $bulkTagText, onCommit: applyBulkTag)
            }
            .alert("Clear all rankings?", isPresented: $showingClearConfirm) {
                Button("Clear", role: .destructive) {
                    RankingService.clearRankings(project: project, context: context)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every item returns to \"New\". This can't be undone.")
            }
            .alert("Import", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            ), presenting: importMessage) { _ in
                Button("OK") { importMessage = nil }
            } message: { message in
                Text(message)
            }
            .sheet(item: $shareURL) { wrapper in
                ShareSheet(url: wrapper.url)
            }
            .modifier(GalleryEscapes(
                selecting: selectionMode, onSelecting: exitSelection,
                picker: $showingPhotoPicker, importer: $showingFileImporter,
                clearConfirm: $showingClearConfirm, importMessage: $importMessage, share: $shareURL
            ))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if project.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: gridSize.minCellWidth), spacing: Theme.Space.gutter)],
                    spacing: Theme.Space.gutter
                ) {
                    ForEach(displayedItems) { item in
                        cell(for: item)
                    }
                }
                .padding(Theme.Space.gutter)
            }
        }
    }

    @ViewBuilder
    private func cell(for item: MediaItem) -> some View {
        let card = MediaCardView(
            item: item,
            isSelected: selectedIDs.contains(item.uuid),
            selectionMode: selectionMode
        )
        .onTapGesture { handleTap(item) }

        if canReorder {
            card
                .opacity(draggingItem?.uuid == item.uuid ? 0.4 : 1)
                .draggable(item.filename) {
                    MediaCardView(item: item)
                        .frame(width: gridSize.minCellWidth, height: gridSize.minCellWidth)
                        .onAppear { draggingItem = item }
                }
                .dropDestination(for: String.self) { _, _ in
                    draggingItem = nil
                    return true
                } isTargeted: { targeted in
                    if targeted, let dragging = draggingItem, dragging.uuid != item.uuid {
                        moveItem(dragging, before: item)
                    }
                }
        } else {
            card
        }
    }

    private var emptyState: some View {
        EmptyState(title: "No Media Yet", message: "Import photos and videos to start ranking.") {
            Button {
                showingPhotoPicker = true
            } label: {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.pill)
            Button {
                showingFileImporter = true
            } label: {
                Label("Import from Files", systemImage: "folder")
            }
            .buttonStyle(.text)
        }
    }

    private var importOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: Theme.Space.stack) {
                ProgressView().tint(Theme.table.accent)
                Text("Importing…").font(.note)
            }
            .padding(24)
            .background(Theme.table.paper)
            .overlay(Rectangle().stroke(Theme.table.rule, lineWidth: 1))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showingPhotoPicker = true
            } label: {
                Label("Import", systemImage: "plus")
            }

            Button {
                showingCompareSelection = true
            } label: {
                Label("Compare", systemImage: "arrow.left.arrow.right")
            }
            .disabled(project.itemCount < 2)

            Menu {
                Picker("Filter", selection: $filter) {
                    ForEach(MediaFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Sort", selection: $sort) {
                    ForEach(SortOption.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Grid", selection: $gridSize) {
                    ForEach(GridSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                Divider()
                Button { showingFileImporter = true } label: {
                    Label("Import from Files", systemImage: "folder")
                }
                Button {
                    selectionMode.toggle()
                    if !selectionMode { selectedIDs.removeAll() }
                } label: {
                    Label(selectionMode ? "Done Selecting" : "Select", systemImage: "checkmark.circle")
                }
                Divider()
                exportMenu
                Button(role: .destructive) { showingClearConfirm = true } label: {
                    Label("Clear Rankings", systemImage: "arrow.uturn.backward")
                }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var exportMenu: some View {
        Menu {
            Button { export(.json) } label: { Label("Export JSON", systemImage: "curlybraces") }
            Button { export(.csv) } label: { Label("Export CSV", systemImage: "tablecells") }
            Button { downloadAll() } label: { Label("Download All (ZIP)", systemImage: "archivebox") }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    // MARK: - Interaction

    private func handleTap(_ item: MediaItem) {
        if selectionMode {
            if selectedIDs.contains(item.uuid) { selectedIDs.remove(item.uuid) }
            else { selectedIDs.insert(item.uuid) }
        } else {
            viewerItem = item
        }
    }

    private func moveItem(_ dragging: MediaItem, before target: MediaItem) {
        var ordered = displayedItems
        guard let from = ordered.firstIndex(where: { $0.uuid == dragging.uuid }),
              let to = ordered.firstIndex(where: { $0.uuid == target.uuid }),
              from != to
        else { return }
        let item = ordered.remove(at: from)
        let insertAt = ordered.firstIndex(where: { $0.uuid == target.uuid }) ?? to
        ordered.insert(item, at: insertAt)
        RankingService.applyOrder(ordered, context: context)
    }

    private func exitSelection() {
        selectionMode = false
        selectedIDs.removeAll()
    }

    // MARK: - Comparison

    private func startComparison(scope: ComparisonScope) {
        showingCompareSelection = false
        // The engine handles scope internally (seeding + pair filtering), so we
        // always hand it the full item set.
        session = ComparisonSession(items: project.items, scope: scope)
    }

    // MARK: - Import

    private func importFromPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isImporting = true
        Task {
            var candidates: [ImportCandidate] = []
            for (idx, pItem) in items.enumerated() {
                guard let data = try? await pItem.loadTransferable(type: Data.self) else { continue }
                let type = pItem.supportedContentTypes.first
                let isVideo = (type?.conforms(to: .movie) ?? false) || (type?.conforms(to: .video) ?? false)
                let ext = type?.preferredFilenameExtension ?? (isVideo ? "mov" : "jpg")
                let name = "IMG_\(Date.timestampSlug)_\(idx).\(ext)"
                candidates.append(ImportCandidate(filename: name, data: data,
                                                  mediaType: isVideo ? .video : .image))
            }
            let result = await ImportService.importItems(candidates, into: project, context: context)
            await MainActor.run {
                photoItems = []
                isImporting = false
                announce(result)
            }
        }
    }

    private func importFromFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        isImporting = true
        Task {
            var candidates: [ImportCandidate] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
                candidates.append(ImportCandidate(
                    filename: url.lastPathComponent,
                    data: data,
                    mediaType: ImportService.mediaType(forExtension: ext)
                ))
            }
            let result = await ImportService.importItems(candidates, into: project, context: context)
            await MainActor.run {
                isImporting = false
                announce(result)
            }
        }
    }

    private func announce(_ result: ImportResult) {
        var parts: [String] = []
        if result.added > 0 { parts.append("Added \(result.added) item\(result.added == 1 ? "" : "s").") }
        if !result.duplicates.isEmpty {
            parts.append("Skipped \(result.duplicates.count) duplicate\(result.duplicates.count == 1 ? "" : "s").")
        }
        if !parts.isEmpty { importMessage = parts.joined(separator: " ") }
    }

    // MARK: - Bulk

    private var selectedItems: [MediaItem] {
        project.items.filter { selectedIDs.contains($0.uuid) }
    }

    /// The chosen videos in the order they're shown. Tools are iPhone and iPad only.
    private var joinableVideos: [MediaItem] {
        #if os(iOS)
        displayedItems.filter { selectedIDs.contains($0.uuid) && $0.mediaType == .video }
        #else
        []
        #endif
    }

    private func joinSelected() {
        joining = JoinRequest(urls: joinableVideos.map(\.fileURL))
        exitSelection()
    }

    private func applyBulkTag() {
        let tag = bulkTagText.trimmingCharacters(in: .whitespaces)
        bulkTagText = ""
        guard !tag.isEmpty else { return }
        for item in selectedItems where !item.tags.contains(tag) {
            item.tags.append(tag)
        }
        try? context.save()
    }

    private func bulkDelete() {
        for item in selectedItems {
            MediaStore.shared.deleteMedia(relativePath: item.relativePath,
                                          thumbnailRelativePath: item.thumbnailRelativePath)
            context.delete(item)
        }
        try? context.save()
        exitSelection()
    }

    private func bulkDownload() {
        zip(items: selectedItems, name: "\(project.name)-selected")
    }

    private func downloadAll() {
        zip(items: project.items, name: project.name)
    }

    /// Build the archive entries on the main actor (reading SwiftData safely),
    /// then create the ZIP off-actor.
    private func zip(items: [MediaItem], name: String) {
        let entries = items.map {
            ExportService.ZipEntry(sourceURL: $0.fileURL, filename: $0.filename)
        }
        Task.detached {
            if let url = try? ExportService.zipMedia(entries: entries, archiveName: name) {
                await MainActor.run { shareURL = ShareableURL(url: url) }
            }
        }
    }

    private enum ExportFormat { case json, csv }

    private func export(_ format: ExportFormat) {
        do {
            let (data, name): (Data, String)
            switch format {
            case .json: (data, name) = (try ExportService.jsonData(for: project), "\(project.name).json")
            case .csv: (data, name) = (ExportService.csvData(for: project), "\(project.name).csv")
            }
            let url = try ExportService.writeTemp(data, filename: name)
            shareURL = ShareableURL(url: url)
        } catch {
            importMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

/// What Esc closes over the gallery that isn't a sheet of ours, newest first.
private struct GalleryEscapes: ViewModifier {
    let selecting: Bool
    let onSelecting: () -> Void
    @Binding var picker: Bool
    @Binding var importer: Bool
    @Binding var clearConfirm: Bool
    @Binding var importMessage: String?
    @Binding var share: ShareableURL?

    func body(content: Content) -> some View {
        content
            .escapeCloses(when: selecting, onSelecting)
            .escapeCloses(when: picker) { picker = false }
            .escapeCloses(when: importer) { importer = false }
            .escapeCloses(when: clearConfirm) { clearConfirm = false }
            .escapeCloses(when: importMessage != nil) { importMessage = nil }
            .escapeCloses(when: share != nil) { share = nil }
    }
}

/// Wrapper so a URL can drive `.sheet(item:)`.
struct ShareableURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// Videos chosen in a project, on their way into Join Videos.
private struct JoinRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
}
