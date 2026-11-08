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

    private var status: String {
        let n = displayed.count
        return n == allItems.count ? "\(n) item\(n == 1 ? "" : "s")" : "\(n) of \(allItems.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "Library", title: "All Media", status: allItems.isEmpty ? nil : status)
            Group {
                if allItems.isEmpty {
                    // Nothing to search, so no search box promising otherwise.
                    EmptyState("Nothing here yet",
                               message: "All Media shows the photos and videos imported into projects. Your Photos library is in Triage and Organise.")
                } else if displayed.isEmpty {
                    EmptyState("No results for “\(searchText)”", message: "Check the spelling or try a new search.")
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: gridSize.minCellWidth), spacing: Theme.Space.gutter)],
                            spacing: Theme.Space.gutter
                        ) {
                            ForEach(displayed) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    MediaCardView(item: item)
                                        .onTapGesture { viewerItem = item }
                                    if let project = item.project {
                                        Text(project.name)
                                            .font(.tiny)
                                            .foregroundStyle(Theme.table.muted)
                                            .lineLimit(1)
                                            .padding(.horizontal, 2)
                                    }
                                }
                            }
                        }
                        .padding(Theme.Space.gutter)
                    }
                }
            }
            .mediaSearch(text: $searchText, prompt: "Search names, tags or projects", shown: !allItems.isEmpty)
        }
        .tableSurfaceList()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
