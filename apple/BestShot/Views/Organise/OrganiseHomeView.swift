import SwiftUI
import SwiftData
import Photos
import UniformTypeIdentifiers

/// Entry point for Organise mode: permission gate + source/order config, then
/// steps through unorganised photos filing them into albums.
struct OrganiseHomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var reviews: [AssetReview]

    @State private var authStatus = PhotoLibraryService.shared.status
    @State private var order: SessionOrder = .newest
    @State private var source: TriageSourceOption = .allPhotos
    @State private var albums: [PHAssetCollection] = []
    @State private var folders: [String: String] = [:]
    @State private var counts: [String: Int]?
    @State private var session: OrganiseSession?
    @State private var isLoading = false
    @State private var emptyMessage: String?
    @State private var choosingFolder = false

    var body: some View {
        Group {
            if let session {
                OrganiseView(session: session) { self.session = nil }
            } else {
                VStack(spacing: 0) {
                    ScreenHeader(eyebrow: "Photos library", title: "Organise")
                    startScreen
                }
            }
        }
        .tableSurfaceList()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var startScreen: some View {
        switch authStatus {
        case .authorized, .limited:
            configForm
        case .notDetermined:
            EmptyState(title: "Access Your Photos",
                       message: "BestShot needs photo library access to file photos into albums.") {
                Button("Allow Access") {
                    Task { authStatus = await PhotoLibraryService.shared.requestAuthorization() }
                }
                .buttonStyle(.pill)
            }
        default:
            EmptyState("Photos Access Denied", message: "Enable photo library access in Settings.")
        }
    }

    private var configForm: some View {
        Form {
            SourceSection(source: $source, albums: albums, folders: folders, counts: counts, onStart: start)
            TableSection("Order") {
                Picker("Order", selection: $order) {
                    ForEach(SessionOrder.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
            }
            TableSection(title: "Or a folder in Files") {
                Button {
                    choosingFolder = true
                } label: {
                    Label("Choose a Folder…", systemImage: "folder")
                }
                .disabled(isLoading)
            } footer: {
                FormNote("iCloud Drive, a camera import or anywhere else in Files. A photo is added to your library when you first file it into an album; the file stays where it is.")
            }
            if let emptyMessage {
                TableSection { Text(emptyMessage).foregroundStyle(Theme.table.muted) }
            }
        }
        .tableForm()
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let folder): startFromFolder(folder)
            case .failure(let error): emptyMessage = error.localizedDescription
            }
        }
        .escapeCloses(when: choosingFolder) { choosingFolder = false }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar { Button {
                start()
            } label: {
                Group {
                    if isLoading { ProgressView().tint(Theme.table.accentInk) }
                    else { Label("Start Organising", systemImage: "play.fill") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
            .disabled(isLoading) }
        }
        .task {
            let found = PhotoLibraryService.shared.userAlbumsWithFolders()
            albums = found.albums
            folders = found.folders
            let all = found.albums
            counts = await Task.detached { PhotoLibraryService.shared.photoCounts(all) }.value
        }
    }

    /// The photos a new session would go through. The monitor starts one this way.
    @MainActor
    static func fetchSession(order: SessionOrder, source: TriageSourceOption, context: ModelContext) -> [PHAsset] {
        let reviews = (try? context.fetch(FetchDescriptor<AssetReview>())) ?? []
        return PhotoLibraryService.shared.fetchAssets(
            in: TriageHomeView.resolveCollection(source), order: order,
            excluding: Set(reviews.filter(\.organised).map(\.assetLocalID))
        )
    }

    /// Organise the photo files in a folder from Files (and the folders in it),
    /// leaving out any Next has already been pressed on.
    private func startFromFolder(_ folder: URL) {
        emptyMessage = nil
        isLoading = true
        Task {
            let result = await OrganiseSession.fromFolder(folder, order: order, context: context)
            isLoading = false
            switch result {
            case .success(let started): session = started
            case .failure(let problem): emptyMessage = problem.message
            }
        }
    }

    private func start() {
        guard !isLoading else { return }
        isLoading = true
        emptyMessage = nil
        // Skip already-organised assets.
        let organisedIDs = Set(reviews.filter(\.organised).map(\.assetLocalID))
        let chosenOrder = order
        let chosenSource = source
        Task {
            let collection = TriageHomeView.resolveCollection(chosenSource)
            let assets = PhotoLibraryService.shared.fetchAssets(
                in: collection, order: chosenOrder, excluding: organisedIDs
            )
            let current = PhotoLibraryService.shared.userAlbumsWithFolders()
            await MainActor.run {
                isLoading = false
                if assets.isEmpty {
                    emptyMessage = "No unorganised photos found for this source."
                } else {
                    session = OrganiseSession(assets: assets, albums: current.albums, folders: current.folders, context: context)
                }
            }
        }
    }
}
