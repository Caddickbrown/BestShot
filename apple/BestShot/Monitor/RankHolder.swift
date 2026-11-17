import SwiftData
import Observation

/// The Photos library's rank board, one for the phone and the monitor, as
/// Triage's session is: a drag, a Compare answer or an Undo on either is on
/// both, and a Compare started on one is the same pair on the other.
@Observable
@MainActor
final class RankHolder {
    static let shared = RankHolder()

    let media = PhotosRankMedia()
    private(set) var board: RankBoard?

    /// The board with the photos kept in Triage as they are now.
    func board(context: ModelContext) -> RankBoard {
        let kept = PhotosRankView.keptAssets(context)
        media.assets = Dictionary(kept.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        return board(kept: kept.map(\.localIdentifier)) {
            let order = PhotosRankView.savedOrder(context)
            return (order.ids, { ranking in
                order.ids = ranking
                order.updatedAt = .now
                try? context.save()
            })
        }
    }

    /// Made once, from the saved order; after that only the photos taking part
    /// are brought up to date, so a Compare running on either screen carries on.
    func board(kept ids: [String], saved: () -> (ranking: [String], persist: ([String]) -> Void)) -> RankBoard {
        let pool = RankPool(id: "kept", title: "Kept", ids: ids)
        if let board {
            if board.pools != [pool] { board.pools = [pool] }
            return board
        }
        let order = saved()
        let made = RankBoard(title: "Photos library", media: media, pools: [pool], ranking: order.ranking, persist: order.persist)
        board = made
        return made
    }
}
