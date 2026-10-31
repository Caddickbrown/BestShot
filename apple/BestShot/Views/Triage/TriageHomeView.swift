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
    @State private var source: TriageSourceOption = .allPhotos
    @State private var albums: [PHAssetCollection] = []
    @State private var session: TriageSession?
    @State private var isLoading = false
    @State private var emptyMessage: String?

    var body: some View {
        Group {
            if let session {
                TriageView(session: session) {
                    self.session = nil
                }
            } else {
                startScreen
            }
        }
        .lightTableList()
        .navigationTitle("Triage")
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
            Section("Order") {
                Picker("Order", selection: $order) {
                    ForEach(SessionOrder.allCases) { o in
                        Label(o.title, systemImage: o.systemImage).tag(o)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Source") {
                Picker("Source", selection: $source) {
                    Text("All Photos").tag(TriageSourceOption.allPhotos)
                    Text("Screenshots").tag(TriageSourceOption.screenshots)
                    ForEach(albums, id: \.localIdentifier) { album in
                        Text(album.localizedTitle ?? "Album").tag(TriageSourceOption.album(album.localIdentifier))
                    }
                }
            }

            Section {
                Button {
                    start()
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label("Start Triage", systemImage: "play.fill")
                    }
                }
                .disabled(isLoading)
            }

            if let emptyMessage {
                Section { Text(emptyMessage).foregroundStyle(.secondary) }
            }

            Section {
                Text("Swipe right to keep, left to delete. Deletions are batched and confirmed once at the end. Pinch out to see the whole set.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .task { albums = PhotoLibraryService.shared.userAlbums() }
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
        // Exclude only assets already kept or deleted (organised-only records
        // should still be triageable).
        let reviewedIDs = Set(reviews
            .filter { $0.decision == .kept || $0.decision == .deleted }
            .map(\.assetLocalID))
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
                    session = TriageSession(assets: assets, context: context)
                }
            }
        }
    }

    static func resolveCollection(_ source: TriageSourceOption) -> PHAssetCollection? {
        switch source {
        case .allPhotos:
            return nil
        case .screenshots:
            return PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil
            ).firstObject
        case .album(let id):
            return PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [id], options: nil
            ).firstObject
        }
    }
}

/// Selectable triage source. Albums are referenced by local identifier so the
/// value stays `Hashable` for the picker.
enum TriageSourceOption: Hashable {
    case allPhotos
    case screenshots
    case album(String)
}
