import SwiftUI
import SwiftData
import Photos

/// Entry point for triage: handles the Photos permission gate, lets the user
/// choose a source + order, starts a session, and returns here when finished.
struct TriageHomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var reviews: [AssetReview]

    @State private var authStatus = PhotoLibraryService.shared.status
    @State private var order: SessionOrder = .newest
    /// Photos marked for deletion in a session that ended before its commit. A delete
    /// that went through leaves no asset, so anything still here was never deleted.
    @State private var waitingDeletes: [PHAsset] = []
    @State private var source: TriageSourceOption = .allPhotos
    @State private var albums: [PHAssetCollection] = []
    /// Above this screen, so the monitor shares it and leaving doesn't lose it.
    @State private var holder = TriageHolder.shared
    private var session: TriageSession? {
        get { holder.session }
        nonmutating set { holder.session = newValue }
    }
    private var paused: Bool {
        get { holder.paused }
        nonmutating set { holder.paused = newValue }
    }
    @State private var isLoading = false
    @State private var emptyMessage: String?

    var body: some View {
        Group {
            if let session, !paused {
                TriageView(session: session) {
                    self.session = nil
                } onLeave: {
                    holder.leave()
                }
            } else {
                startScreen
            }
        }
        .tableSurfaceList()
        .navigationTitle("Triage")
        .onChange(of: markedDeleted, initial: true) { findWaitingDeletes() }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Start screen

    @ViewBuilder
    private var startScreen: some View {
        switch authStatus {
        case .authorized, .limited:
            configForm
        case .notDetermined:
            permissionPrompt
        default:
            deniedPrompt
        }
    }

    private var configForm: some View {
        Form {
            if !waitingDeletes.isEmpty && session == nil {
                Section {
                    Text("\(waitingDeletes.count) photo\(waitingDeletes.count == 1 ? "" : "s") waiting to be deleted, from a session that ended early.")
                    Button("Delete Them", role: .destructive) { Task { await finishWaitingDeletes() } }
                    Button("Keep Them") { releaseWaitingDeletes() }
                }
            }
            SourceSection(source: $source, albums: albums)

            Section {
                Picker("Order", selection: $order) {
                    ForEach(SessionOrder.allCases) { o in
                        Label(o.title, systemImage: o.systemImage).tag(o)
                    }
                }
            }

            if let emptyMessage {
                Section { Text(emptyMessage).foregroundStyle(.secondary) }
            }

            Section {
                Text("Swipe right to keep, left to delete. Deletions are batched and confirmed once at the end. Spread two fingers to zoom in; pinch them together to see the whole set.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
        .task { albums = PhotoLibraryService.shared.userAlbums() }
    }

    /// Always on screen, however long the list above it gets.
    private var startBar: some View {
        VStack(spacing: 6) {
            if let session {
                Button {
                    paused = false
                } label: {
                    Label("Resume Triage", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill)
                Text("\(session.deleteCount) marked to delete. Resume, then finish, to delete them.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Button {
                    start()
                } label: {
                    Group {
                        if isLoading { ProgressView().tint(Theme.table.accentInk) }
                        else { Label("Start Triage", systemImage: "play.fill") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill)
                .disabled(isLoading)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Theme.table.background)
        .overlay(alignment: .top) { HairlineRule() }
    }

    /// The ids marked for deletion, for noticing when that set changes.
    private var markedDeleted: [String] {
        reviews.filter { $0.decision == .deleted }.map(\.assetLocalID).sorted()
    }

    private func findWaitingDeletes() {
        let ids = markedDeleted
        guard !ids.isEmpty else { waitingDeletes = []; return }
        let found = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        waitingDeletes = found.objects(at: IndexSet(0..<found.count))
    }

    private func finishWaitingDeletes() async {
        // Cancelling the system prompt leaves them waiting, to be decided another time.
        if await PhotoLibraryService.shared.deleteAssets(waitingDeletes) { waitingDeletes = [] }
    }

    /// Takes the decision back, so the photos come up in the next session.
    private func releaseWaitingDeletes() {
        let ids = Set(waitingDeletes.map(\.localIdentifier))
        for review in reviews where ids.contains(review.assetLocalID) { context.delete(review) }
        try? context.save()
        waitingDeletes = []
    }

    private var permissionPrompt: some View {
        ContentUnavailableView {
            Label("Access Your Photos", systemImage: "photo.stack")
        } description: {
            Text("BestShot needs access to your photo library to triage, favourite, and organise photos.")
        } actions: {
            Button("Allow Access") {
                Task {
                    authStatus = await PhotoLibraryService.shared.requestAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var deniedPrompt: some View {
        ContentUnavailableView {
            Label("Photos Access Denied", systemImage: "lock")
        } description: {
            Text("Enable photo library access in Settings to use triage.")
        }
    }

    // MARK: - Start a session

    private func start() {
        isLoading = true
        emptyMessage = nil
        let reviewedIDs = Self.reviewedIDs(reviews)
        let chosenOrder = order
        let chosenSource = source
        Task {
            let collection = Self.resolveCollection(chosenSource)
            let assets = PhotoLibraryService.shared.fetchAssets(
                in: collection, order: chosenOrder, excluding: reviewedIDs
            )
            await MainActor.run {
                isLoading = false
                if assets.isEmpty {
                    emptyMessage = "No unreviewed photos found for this source. Try another source or order."
                } else {
                    paused = false
                    session = TriageSession(assets: assets, context: context)
                }
            }
        }
    }

    /// Exclude only assets already kept or deleted (organised-only records should
    /// still be triageable).
    static func reviewedIDs(_ reviews: [AssetReview]) -> Set<String> {
        Set(reviews.filter { $0.decision == .kept || $0.decision == .deleted }.map(\.assetLocalID))
    }

    /// The photos a new session would go through. The monitor starts one this way.
    @MainActor
    static func fetchSession(order: SessionOrder, source: TriageSourceOption, context: ModelContext) -> [PHAsset] {
        let reviews = (try? context.fetch(FetchDescriptor<AssetReview>())) ?? []
        return PhotoLibraryService.shared.fetchAssets(
            in: resolveCollection(source), order: order, excluding: reviewedIDs(reviews)
        )
    }

    static func resolveCollection(_ source: TriageSourceOption) -> PHAssetCollection? {
        switch source {
        case .allPhotos:
            return nil
        case .smart(let smart):
            return PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: smart.subtype, options: nil
            ).firstObject
        case .album(let id):
            return PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [id], options: nil
            ).firstObject
        }
    }
}
