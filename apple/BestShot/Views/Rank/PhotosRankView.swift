import SwiftUI
import SwiftData
import Photos

/// Rank for the Photos library: the photos you kept in Triage, ranked with
/// Compare or by dragging, and optionally saved as an album in rank order.
struct PhotosRankView: View {
    @Environment(\.modelContext) private var context
    /// The board the monitor's Rank shows too.
    @State private var holder = RankHolder.shared
    @State private var loaded = false
    @State private var albumMessage: String?

    private var board: RankBoard? { loaded ? holder.board : nil }

    static let albumTitle = "BestShot · Ranked"

    var body: some View {
        Group {
            if let board {
                RankBoardView(board: board, extraAction: (title: "Save as album", run: saveAlbum))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tableSurface()
            }
        }
        // The board has its own heading. Left to the default the bar holds a large
        // title's empty space above it, pushing the whole sheet down.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        #if os(iOS)
        // A Compare started here comes up on the monitor too, the same pair.
        .onChange(of: holder.board?.compare?.id) { _, run in
            if run != nil { MonitorDisplay.shared.desk?.phoneOpened(.rank) }
        }
        #endif
        .alert("Album", isPresented: Binding(get: { albumMessage != nil }, set: { if !$0 { albumMessage = nil } })) {
            Button("OK") { albumMessage = nil }
        } message: {
            Text(albumMessage ?? "")
        }
        .escapeCloses(when: albumMessage != nil) { albumMessage = nil }
    }

    private func load() async {
        _ = await PhotoLibraryService.shared.requestAuthorization()
        _ = holder.board(context: context)
        loaded = true
    }

    /// The photos kept in Triage, newest first.
    @MainActor
    static func keptAssets(_ context: ModelContext) -> [PHAsset] {
        let kept = ReviewDecision.kept.rawValue
        let reviews = (try? context.fetch(FetchDescriptor<AssetReview>(predicate: #Predicate { $0.decisionRaw == kept }))) ?? []
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(withLocalIdentifiers: reviews.map(\.assetLocalID), options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    @MainActor
    static func savedOrder(_ context: ModelContext) -> RankedOrder {
        let key = RankedOrder.photosLibraryKey
        if let existing = try? context.fetch(FetchDescriptor<RankedOrder>(predicate: #Predicate { $0.key == key })).first {
            return existing
        }
        let created = RankedOrder(key: key)
        context.insert(created)
        return created
    }

    private func saveAlbum() {
        guard let board else { return }
        let assets = board.ranked.compactMap { holder.media.assets[$0] }
        Task { albumMessage = await Self.saveAlbum(assets) }
    }

    /// What to tell the user afterwards.
    static func saveAlbum(_ assets: [PHAsset]) async -> String {
        let ok = await PhotoLibraryService.shared.replaceAlbumContents(titled: albumTitle, with: assets)
        return ok
            ? "Saved \(assets.count) photos to “\(albumTitle)” in rank order."
            : "Couldn't update the album. Check BestShot has full access to Photos."
    }
}

/// Draws Photos-library assets for the rank board.
@MainActor
final class PhotosRankMedia: RankMedia {
    var assets: [String: PHAsset] = [:]

    func thumbnail(_ id: String) -> AnyView {
        guard let asset = assets[id] else { return AnyView(Theme.table.tile) }
        return AnyView(PhotoAssetImage(asset: asset, targetSize: CGSize(width: 400, height: 400), contentMode: .fill))
    }

    func fullImage(_ id: String) -> AnyView {
        guard let asset = assets[id] else { return AnyView(Color.black) }
        return AnyView(PhotoAssetImage(asset: asset, targetSize: CGSize(width: 2000, height: 2000), contentMode: .fit))
    }

    func caption(_ id: String) -> String {
        guard let date = assets[id]?.creationDate else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
