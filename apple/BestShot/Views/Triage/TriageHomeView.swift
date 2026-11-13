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
    @State private var folders: [String: String] = [:]
    @State private var counts: [String: Int]?
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
    /// Tags for every photo kept in the next run, as typed.
    @State private var tagText = ""
    private var marks: PhotoMarkStore { .shared }

    var body: some View {
        Group {
            if let session, !paused {
                TriageView(session: session) {
                    self.session = nil
                } onLeave: {
                    holder.leave()
                }
            } else {
                // Its own heading, as Rank has: no title in the bar over it.
                VStack(spacing: 0) {
                    ScreenHeader(eyebrow: "Photos library", title: "Triage", status: status)
                    startScreen
                }
            }
        }
        .tableSurfaceList()
        .onChange(of: markedDeleted, initial: true) { findWaitingDeletes() }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Start screen

    private var status: String? {
        guard let session else { return nil }
        return session.deleteCount > 0 ? "Paused · \(session.deleteCount) to delete" : "Paused"
    }

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
                TableSection("Waiting") {
                    Text("\(waitingDeletes.count) photo\(waitingDeletes.count == 1 ? "" : "s") waiting to be deleted, from a session that ended early.")
                    Button("Delete Them", role: .destructive) { Task { await finishWaitingDeletes() } }
                        .buttonStyle(TextButtonStyle(destructive: true))
                    Button("Keep Them") { releaseWaitingDeletes() }
                        .buttonStyle(.text)
                }
            }
            SourceSection(source: $source, albums: albums, folders: folders, counts: counts, onStart: start)

            TableSection("Order") {
                Picker("Order", selection: $order) {
                    ForEach(SessionOrder.allCases) { o in
                        Label(o.title, systemImage: o.systemImage).tag(o)
                    }
                }
            }

            tagSection

            if let emptyMessage {
                TableSection { Text(emptyMessage).foregroundStyle(Theme.table.muted) }
            }

            TableSection {
                FormNote("Swipe right to keep, left to delete. Deletions are batched and confirmed once at the end. Spread two fingers to zoom in; pinch them together to see the whole set.")
            }
        }
        .tableForm()
        .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
        .task {
            let found = PhotoLibraryService.shared.userAlbumsWithFolders()
            albums = found.albums
            folders = found.folders
            let all = found.albums
            counts = await Task.detached { PhotoLibraryService.shared.photoCounts(all) }.value
        }
    }

    /// Always on screen, however long the list above it gets.
    private var startBar: some View {
        BottomBar {
            if let session {
                Button {
                    paused = false
                } label: {
                    Label("Resume Triage", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill)
                FormNote("\(session.deleteCount) marked to delete. Resume, then finish, to delete them.")
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
        EmptyState(title: "Access Your Photos",
                   message: "BestShot needs access to your photo library to triage, favourite, and organise photos.") {
            Button("Allow Access") {
                Task {
                    authStatus = await PhotoLibraryService.shared.requestAuthorization()
                }
            }
            .buttonStyle(.pill)
        }
    }

    private var deniedPrompt: some View {
        EmptyState("Photos Access Denied", message: "Enable photo library access in Settings to use triage.")
    }

    // MARK: - Tags for the run

    /// Tags to give everything kept in the run, typed or picked from those in use.
    private var tagSection: some View {
        let typed = TriageTags.parse(tagText)
        let known = marks.knownTags.filter { tag in !typed.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        return TableSection(title: "Tag what you keep") {
            HStack(spacing: 8) {
                Image(systemName: "tag").foregroundStyle(Theme.table.muted)
                EscapingField(placeholder: "Tags, with commas between", text: $tagText, onSubmit: start)
            }
            if !known.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(known.prefix(12), id: \.self) { tag in
                        Button(tag) { addTag(tag) }
                            .buttonStyle(.outline)
                    }
                }
                .padding(.vertical, 4)
            }
        } footer: {
            FormNote(typed.isEmpty
                     ? "Optional. Every photo you keep in this run gets these tags, the ones the monitor shows and filters by."
                     : "Every photo you keep gets \(typed.joined(separator: ", ")). Undo takes them off again.")
        }
    }

    private func addTag(_ tag: String) {
        let trimmed = tagText.trimmingCharacters(in: .whitespaces)
        tagText = trimmed.isEmpty || trimmed.hasSuffix(",") ? trimmed + (trimmed.isEmpty ? "" : " ") + tag : trimmed + ", " + tag
    }

    // MARK: - Start a session

    private func start() {
        guard !isLoading else { return }
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
                    session = TriageSession(assets: assets, context: context,
                                            tags: TriageTags.parse(tagText), marks: marks)
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
