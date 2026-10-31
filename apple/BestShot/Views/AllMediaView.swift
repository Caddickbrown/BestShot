import SwiftUI
import SwiftData

/// Combined view of every media item across all projects, mirroring the web
/// app's "All Projects" view. Read-only browsing + fullscreen viewer.
struct AllMediaView: View {
    @Query private var allItems: [MediaItem]

    @State private var filter: MediaFilter = .all
    @State private var gridSize: GridSize = .medium
    @State private var searchText = ""
    @State private var viewerItem: MediaItem?

    private var displayed: [MediaItem] {
        var items = allItems.filter { filter.matches($0) }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.filename.lowercased().contains(q) ||
                $0.tags.contains { $0.lowercased().contains(q) }
            }
        }
        return items.sorted { $0.importedAt > $1.importedAt }
    }

    var body: some View {
        Group {
            if allItems.isEmpty {
                ContentUnavailableView("No Media", systemImage: "square.grid.2x2",
                                       description: Text("Create a project and import media to see it here."))
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: gridSize.minCellWidth), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(displayed) { item in
                            VStack(spacing: 4) {
                                MediaCardView(item: item)
                                    .onTapGesture { viewerItem = item }
                                if let project = item.project {
                                    Text(project.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .lightTableList()
        .navigationTitle("All Media")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search filename or tags")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(MediaFilter.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Grid", selection: $gridSize) {
                        ForEach(GridSize.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .fullScreenCoverCompat(item: $viewerItem) { item in
            FullscreenViewerView(items: displayed, initial: item)
        }
    }
}
