import Foundation
import SwiftData
import Photos
import Observation

/// Drives a triage session over a list of Photos assets: tracks the current
/// position, records Keep/Delete/Skip/Favourite decisions, supports Undo, and
/// commits the batch deletion at the end.
///
/// Decisions are persisted to `AssetReview` as they're made (except Skip, which
/// is transient) so quitting mid-session keeps progress. Favouriting is applied
/// to the library immediately (it's cheap and reversible).
@Observable
@MainActor
final class TriageSession {

    let assets: [PHAsset]
    /// Current focus index. When == assets.count the session is complete.
    var index: Int = 0

    /// In-memory decision per local ID (mirrors persisted AssetReview).
    private(set) var decisions: [String: ReviewDecision] = [:]
    /// Local IDs favourited during this session (for the running tally + badges).
    private(set) var favourited: Set<String> = []

    /// Undo stack of (index, previousDecision, wasFavourited).
    private var history: [(index: Int, previous: ReviewDecision, wasFav: Bool)] = []

    private let context: ModelContext
    private let library = PhotoLibraryService.shared

    init(assets: [PHAsset], context: ModelContext) {
        self.assets = assets
        self.context = context
    }

    // MARK: - Derived

    var isComplete: Bool { index >= assets.count }
    var current: PHAsset? { assets.indices.contains(index) ? assets[index] : nil }
    var progress: Double { assets.isEmpty ? 1 : Double(index) / Double(assets.count) }
    var canUndo: Bool { !history.isEmpty }

    var keptCount: Int { decisions.values.filter { $0 == .kept }.count }
    var deleteCount: Int { decisions.values.filter { $0 == .deleted }.count }
    var favouriteCount: Int { favourited.count }

    func decision(for asset: PHAsset) -> ReviewDecision {
        decisions[asset.localIdentifier] ?? .undecided
    }

    func isFavourited(_ asset: PHAsset) -> Bool {
        favourited.contains(asset.localIdentifier) || asset.isFavorite
    }

    /// Assets currently marked for deletion, in order.
    var pendingDeletions: [PHAsset] {
        assets.filter { decisions[$0.localIdentifier] == .deleted }
    }

    // MARK: - Decisions

    func keep() { record(.kept) }
    func delete() { record(.deleted) }

    /// Skip advances without persisting, so the photo resurfaces next time.
    func skip() {
        guard let asset = current else { return }
        history.append((index, decisions[asset.localIdentifier] ?? .undecided, favourited.contains(asset.localIdentifier)))
        decisions[asset.localIdentifier] = .skipped
        index += 1
    }

    func toggleFavourite() {
        guard let asset = current else { return }
        let id = asset.localIdentifier
        let newValue = !favourited.contains(id)
        if newValue { favourited.insert(id) } else { favourited.remove(id) }
        Task { _ = await library.setFavorite(newValue, for: asset) }
    }

    private func record(_ decision: ReviewDecision) {
        guard let asset = current else { return }
        let id = asset.localIdentifier
        history.append((index, decisions[id] ?? .undecided, favourited.contains(id)))
        decisions[id] = decision
        persist(id: id, decision: decision)
        index += 1
    }

    /// Jump the focus to a specific index (used when tapping a gallery tile).
    func focus(on targetIndex: Int) {
        guard assets.indices.contains(targetIndex) else { return }
        index = targetIndex
    }

    /// Set a decision for an arbitrary asset (used from the gallery grid) without
    /// moving the focus.
    func setDecision(_ decision: ReviewDecision, for asset: PHAsset) {
        let id = asset.localIdentifier
        decisions[id] = decision
        if decision == .skipped || decision == .undecided {
            removePersisted(id: id)
        } else {
            persist(id: id, decision: decision)
        }
    }

    // MARK: - Undo

    func undo() {
        guard let last = history.popLast() else { return }
        index = last.index
        if let asset = assets[safe: last.index] {
            let id = asset.localIdentifier
            if last.previous == .undecided {
                decisions.removeValue(forKey: id)
                removePersisted(id: id)
            } else {
                decisions[id] = last.previous
                if last.previous == .skipped { removePersisted(id: id) }
                else { persist(id: id, decision: last.previous) }
            }
            // Revert favourite side-effect.
            if favourited.contains(id) != last.wasFav {
                if last.wasFav { favourited.insert(id) } else { favourited.remove(id) }
                Task { _ = await library.setFavorite(last.wasFav, for: asset) }
            }
        }
    }

    // MARK: - Commit

    /// Commit the session: batch-delete everything marked for deletion. Returns
    /// the number actually deleted (0 if the user cancelled the system prompt).
    func commitDeletions() async -> Int {
        let toDelete = pendingDeletions
        guard !toDelete.isEmpty else { return 0 }
        let confirmed = await library.deleteAssets(toDelete)
        if confirmed {
            return toDelete.count
        } else {
            // User cancelled: revert those to undecided so they can be re-triaged.
            for asset in toDelete {
                decisions[asset.localIdentifier] = .undecided
                removePersisted(id: asset.localIdentifier)
            }
            return 0
        }
    }

    // MARK: - Persistence

    private func persist(id: String, decision: ReviewDecision) {
        if let existing = fetchReview(id: id) {
            existing.decision = decision
            existing.reviewedAt = .now
        } else {
            context.insert(AssetReview(assetLocalID: id, decision: decision))
        }
        try? context.save()
    }

    private func removePersisted(id: String) {
        if let existing = fetchReview(id: id) {
            context.delete(existing)
            try? context.save()
        }
    }

    private func fetchReview(id: String) -> AssetReview? {
        var descriptor = FetchDescriptor<AssetReview>(predicate: #Predicate { $0.assetLocalID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
