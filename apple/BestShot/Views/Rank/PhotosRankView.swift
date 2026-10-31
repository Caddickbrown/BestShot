import SwiftUI
import SwiftData
import Photos

/// Rank for the Photos library: the photos you kept in Triage, ranked with
/// Compare or by dragging, and optionally saved as an album in rank order.
struct PhotosRankView: View {
    @Environment(\.modelContext) private var context
    @State private var board: RankBoard?
    @State private var media = PhotosRankMedia()
    @State private var albumMessage: String?

    static let albumTitle = "BestShot · Ranked"

    var body: some View {
        Group {
            if let board {
                RankBoardView(board: board, extraAction: (title: "Save as album", run: saveAlbum))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .lightTable()
            }
        }
        .task { await load() }
        .alert("Album", isPresented: Binding(get: { albumMessage != nil }, set: { if !$0 { albumMessage = nil } })) {
            Button("OK") { albumMessage = nil }
        } message: {
            Text(albumMessage ?? "")
        }
    }

    private func load() async {
        _ = await PhotoLibraryService.shared.requestAuthorization()
        let kept = ReviewDecision.kept.rawValue
        let reviews = (try? context.fetch(FetchDescriptor<AssetReview>(predicate: #Predicate { $0.decisionRaw == kept }))) ?? []
        let ids = reviews.map(\.assetLocalID)

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        media.assets = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })

        let order = savedOrder()
        board = RankBoard(
            title: "Photos library",
            media: media,
            pools: [RankPool(id: "kept", title: "Kept", ids: assets.map(\.localIdentifier))],
            ranking: order.ids
        ) { ranking in
            order.ids = ranking
            order.updatedAt = .now
            try? context.save()
        }
    }

    private func savedOrder() -> RankedOrder {
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
        let assets = board.ranked.compactMap { media.assets[$0] }
        Task {
            let ok = await PhotoLibraryService.shared.replaceAlbumContents(titled: Self.albumTitle, with: assets)
            albumMessage = ok
                ? "Saved \(assets.count) photos to “\(Self.albumTitle)” in rank order."
                : "Couldn't update the album. Check BestShot has full access to Photos."
        }
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
