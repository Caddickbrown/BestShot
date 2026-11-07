#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Recent folders, remembered as security-scoped bookmarks so the sandboxed
/// app can reopen them.
struct RecentFolder: Codable, Identifiable, Equatable {
    var id: String { path }
    let path: String
    let name: String
    let bookmark: Data
    var reviewed: Int
    var total: Int
}

@MainActor
enum RecentFolders {
    private static let key = "recentFolders"

    static func load() -> [RecentFolder] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RecentFolder].self, from: data)) ?? []
    }

    static func save(_ list: [RecentFolder]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(list.prefix(8))), forKey: key)
    }

    static func remember(_ url: URL, reviewed: Int, total: Int) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var list = load().filter { $0.path != url.path }
        list.insert(RecentFolder(path: url.path, name: url.lastPathComponent, bookmark: bookmark, reviewed: reviewed, total: total), at: 0)
        save(list)
    }

    static func forget(_ folder: RecentFolder) {
        save(load().filter { $0.path != folder.path })
    }

    static func resolve(_ folder: RecentFolder) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: folder.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}

/// Mac-only: cull a folder of files, exactly like BestShot for Linux.
struct FolderHomeView: View {
    @State private var session: FolderCullSession?
    @State private var recents = RecentFolders.load()
    @State private var importing = false
    @State private var opening = false
    @State private var error: String?
    @State private var dropTargeted = false
    @AppStorage("folderRecursive") private var recursive = true
    @AppStorage("folderIncludeVideos") private var includeVideos = true

    var body: some View {
        Group {
            if let session {
                FolderCullView(session: session) { close() }
                    .id(session.root)
            } else {
                home
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { open(url) }
        }
        .onDisappear { session?.flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session?.flush()
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Folders")
                    .font(.display(44, weight: 800, width: 70))
                Text("Rate, label and cull a folder of photos. Ratings, labels and keywords are standard XMP sidecars; decisions and ranking are saved in the folder, so it picks up where BestShot for Linux left off.")
                    .font(.mono(13))
                    .foregroundStyle(Theme.table.muted)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            .padding(.bottom, 24)

            if !recents.isEmpty {
                SheetLabel("Recent")
                    .padding(.bottom, 6)
                ForEach(recents) { folder in
                    HStack {
                        Button {
                            if let url = RecentFolders.resolve(folder) { open(url) } else { error = "Can't reach \(folder.path) any more." }
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(folder.name)
                                    .font(.display(24, weight: 700, width: 75))
                                Text(folder.total > 0 ? "\(folder.reviewed) of \(folder.total) reviewed" : folder.path)
                                    .font(.mono(12))
                                    .foregroundStyle(Theme.table.muted)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button("Forget") {
                            RecentFolders.forget(folder)
                            recents = RecentFolders.load()
                        }
                        .buttonStyle(.text)
                    }
                    HairlineRule()
                }
            }

            HStack(spacing: 18) {
                Button(opening ? "Opening…" : "Open folder…") { importing = true }
                    .buttonStyle(.pill)
                    .disabled(opening)
                Text("or drop a folder here")
                    .font(.mono(12))
                    .foregroundStyle(Theme.table.muted)
            }
            .padding(.top, 24)

            HStack(spacing: 24) {
                Toggle("Include subfolders", isOn: $recursive)
                Toggle("Include videos", isOn: $includeVideos)
            }
            .font(.mono(12))
            .toggleStyle(.checkbox)
            .padding(.top, 16)

            if let error {
                Text(error)
                    .font(.mono(12))
                    .foregroundStyle(Theme.table.accent)
                    .padding(.top, 16)
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tableSurface()
        .overlay {
            if dropTargeted {
                Rectangle().strokeBorder(Theme.table.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(16)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            open(url.hasDirectoryPath ? url : url.deletingLastPathComponent())
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private func open(_ url: URL) {
        error = nil
        opening = true
        _ = url.startAccessingSecurityScopedResource()
        Task {
            do {
                let opened = try await FolderCullSession.open(url, recursive: recursive, includeVideos: includeVideos)
                if opened.items.isEmpty {
                    error = "No photos found in \(url.lastPathComponent)."
                    url.stopAccessingSecurityScopedResource()
                } else {
                    let c = opened.counts
                    RecentFolders.remember(url, reviewed: Int(c.keep + c.reject + c.other), total: opened.items.count)
                    session = opened
                }
            } catch let e as CoreError {
                error = e.message
            } catch {
                self.error = error.localizedDescription
            }
            opening = false
        }
    }

    private func close() {
        if let session {
            let c = session.counts
            RecentFolders.remember(session.root, reviewed: Int(c.keep + c.reject + c.other), total: session.items.count)
            session.flush()
            session.root.stopAccessingSecurityScopedResource()
        }
        session = nil
        recents = RecentFolders.load()
    }
}
#endif
