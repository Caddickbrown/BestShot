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
    /// From Hidden: covered while Hidden is locked (`hiddenLock`).
    let holdsHidden: Bool
    /// Current focus index. When == assets.count the session is complete.
    var index: Int = 0

    /// In-memory decision per local ID (mirrors persisted AssetReview).
    private(set) var decisions: [String: ReviewDecision] = [:]
    /// Local IDs favourited during this session (for the running tally + badges).
    private(set) var favourited: Set<String> = []

    /// One step back: where it was, the decision and favourite before, the tags
    /// it added, and the stars, colour and tags before when the step changed them.
    private struct Step {
        var index: Int
        var previous: ReviewDecision
        var wasFav: Bool
        var tagged: [String] = []
        var mark: PhotoMark? = nil
    }
    private var history: [Step] = []

    /// Tags given to every photo kept in this run, chosen at the start. They go
    /// in the same marks the monitor shows and filters by.
    let tags: [String]
    private let marks: PhotoMarkStore?

    private let context: ModelContext
    private let library = PhotoLibraryService.shared

    init(assets: [PHAsset], context: ModelContext, tags: [String] = [], marks: PhotoMarkStore? = nil) {
        self.assets = assets
        self.holdsHidden = assets.contains(where: \.isHidden)
        self.context = context
        self.tags = tags
        self.marks = marks
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
        history.append(Step(index: index, previous: decisions[asset.localIdentifier] ?? .undecided,
                            wasFav: favourited.contains(asset.localIdentifier)))
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
        let tagged = decision == .kept ? addTags(to: id) : []
        history.append(Step(index: index, previous: decisions[id] ?? .undecided, wasFav: favourited.contains(id), tagged: tagged))
        decisions[id] = decision
        persist(id: id, decision: decision)
        index += 1
    }

    /// Gives the photo the run's tags it doesn't have yet, and says which.
    private func addTags(to id: String) -> [String] {
        guard let marks, !tags.isEmpty else { return [] }
        var mark = marks.mark(id)
        let new = tags.filter { !mark.has(tag: $0) }
        guard !new.isEmpty else { return [] }
        mark.tags += new
        marks.set(mark, for: id)
        return new
    }

    private func removeTags(_ tagged: [String], from id: String) {
        guard let marks, !tagged.isEmpty else { return }
        var mark = marks.mark(id)
        mark.tags.removeAll { tag in tagged.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        marks.set(mark, for: id)
    }

    // MARK: - Stars and colour labels

    /// The current photo's stars, colour and tags: the monitor's, so either can set them.
    func mark(for asset: PHAsset) -> PhotoMark { (marks ?? .shared).mark(asset.localIdentifier) }

    /// The colour showing: a keep is green and a delete red, whatever's saved.
    func shownColour(for asset: PHAsset) -> LabelColour? {
        mark(for: asset).shownColour(decision(for: asset))
    }

    func rate(_ stars: Int) { changeMark { $0.rate(stars); return nil } }

    /// Stays on the photo, so a second press clears it, as in Folders and on the monitor.
    func toggleColour(_ colour: LabelColour) {
        guard let asset = current else { return }
        let shown = shownColour(for: asset)
        changeMark { $0.toggle(colour, shown: shown) }
    }

    func clearColour() { changeMark { $0.clearColour() } }

    func toggleTag(_ tag: String) { changeMark { $0.toggle(tag: tag); return nil } }

    /// One step for Undo, whatever it changed. A colour's decision is saved as a
    /// swipe's would be, without moving on.
    private func changeMark(_ body: (inout PhotoMark) -> ReviewDecision?) {
        guard let asset = current else { return }
        let store = marks ?? .shared
        let id = asset.localIdentifier
        var mark = store.mark(id)
        let before = mark
        let decision = decisions[id] ?? .undecided
        let new = body(&mark)
        guard mark != before || (new != nil && new != decision) else { return }
        history.append(Step(index: index, previous: decision, wasFav: favourited.contains(id), mark: before))
        store.set(mark, for: id)
        if let new, new != decision {
            if new == .undecided { decisions.removeValue(forKey: id) } else { decisions[id] = new }
            if new == .skipped || new == .undecided { removePersisted(id: id) } else { persist(id: id, decision: new) }
        }
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
        if decision == .kept { _ = addTags(to: id) }
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
            removeTags(last.tagged, from: id)
            if let mark = last.mark { (marks ?? .shared).set(mark, for: id) }
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
    /// Cancelled or failed, the marks stay, in memory and saved: the session goes on,
    /// and the photos can be deleted from the summary again or from "waiting to be
    /// deleted" later. (They were reverted to undecided, and the session ended anyway.)
    func commitDeletions() async -> Int {
        let toDelete = pendingDeletions
        guard !toDelete.isEmpty else { return 0 }
        return await library.deleteAssets(toDelete) ? toDelete.count : 0
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

    /// Takes the decision back. A row that also says the photo was organised stays, undecided:
    /// deleting it made an organised photo come up in Organise again after an Undo here.
    private func removePersisted(id: String) {
        if let existing = fetchReview(id: id) {
            if existing.undecide() { context.delete(existing) }
            try? context.save()
        }
    }

    private func fetchReview(id: String) -> AssetReview? {
        var descriptor = FetchDescriptor<AssetReview>(predicate: #Predicate { $0.assetLocalID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

/// What's typed for a run's tags: split at commas, trimmed, each once
/// whatever its case, in the order typed.
enum TriageTags {
    static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").compactMap { part in
            let tag = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { return nil }
            return tag
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
