import SwiftUI
import SwiftData
import Photos

/// Entry point for Organise mode: permission gate + source/order config, then
/// steps through unorganised photos filing them into albums.
struct OrganiseHomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var reviews: [AssetReview]

    @State private var authStatus = PhotoLibraryService.shared.status
    @State private var order: SessionOrder = .newest
    @State private var source: TriageSourceOption = .allPhotos
    @State private var albums: [PHAssetCollection] = []
    @State private var session: OrganiseSession?
    @State private var isLoading = false
    @State private var emptyMessage: String?

    var body: some View {
        Group {
            if let session {
                OrganiseView(session: session) { self.session = nil }
            } else {
                startScreen
            }
        }
        .tableSurfaceList()
        .navigationTitle("Organise")
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
            ContentUnavailableView {
                Label("Access Your Photos", systemImage: "photo.stack")
            } description: {
                Text("BestShot needs photo library access to file photos into albums.")
            } actions: {
                Button("Allow Access") {
                    Task { authStatus = await PhotoLibraryService.shared.requestAuthorization() }
                }
                .buttonStyle(.borderedProminent)
            }
        default:
            ContentUnavailableView("Photos Access Denied", systemImage: "lock",
                                   description: Text("Enable photo library access in Settings."))
        }
    }

    private var configForm: some View {
        Form {
            SourceSection(source: $source, albums: albums)
            Section {
                Picker("Order", selection: $order) {
                    ForEach(SessionOrder.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
            }
            if let emptyMessage {
                Section { Text(emptyMessage).foregroundStyle(.secondary) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                start()
            } label: {
                Group {
                    if isLoading { ProgressView().tint(Theme.table.accentInk) }
                    else { Label("Start Organising", systemImage: "play.fill") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
            .disabled(isLoading)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Theme.table.background)
            .overlay(alignment: .top) { HairlineRule() }
        }
        .task { albums = PhotoLibraryService.shared.userAlbums() }
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

    private func start() {
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
            let currentAlbums = PhotoLibraryService.shared.userAlbums()
            await MainActor.run {
                isLoading = false
                if assets.isEmpty {
                    emptyMessage = "No unorganised photos found for this source."
                } else {
                    session = OrganiseSession(assets: assets, albums: currentAlbums, context: context)
                }
            }
        }
    }
}
