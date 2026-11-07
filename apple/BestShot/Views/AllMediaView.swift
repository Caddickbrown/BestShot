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
        allItems
            .filter { filter.matches($0) && MediaSearch.matches(searchText, item: $0) }
            .sorted { $0.importedAt > $1.importedAt }
    }

    var body: some View {
        Group {
            if allItems.isEmpty {
                // Nothing to search, so no search box promising otherwise.
                ContentUnavailableView("Nothing here yet", systemImage: "square.grid.2x2",
                                       description: Text("All Media shows the photos and videos imported into projects. Your Photos library is in Triage and Organise."))
            } else if displayed.isEmpty {
                ContentUnavailableView.search(text: searchText)
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
        .tableSurfaceList()
        .navigationTitle("All Media")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .mediaSearch(text: $searchText, prompt: "Search names, tags or projects", shown: !allItems.isEmpty)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(MediaFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Grid", selection: $gridSize) {
                        ForEach(GridSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
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
