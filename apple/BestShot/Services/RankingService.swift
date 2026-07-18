import Foundation
import SwiftData

/// Writes ranking results back onto `MediaItem.rank`. Ranks are 0-based and
/// contiguous over the items being ordered, matching the web app's
/// `.ranking.json` (an ordered list of names).
@MainActor
enum RankingService {

    /// Persist an explicit ordering (best-first) as ranks 0…n-1.
    static func applyOrder(_ orderedItems: [MediaItem], context: ModelContext) {
        for (index, item) in orderedItems.enumerated() {
            item.rank = index
        }
        try? context.save()
    }

    /// Apply a comparison result given by item name, best-first. Items in the
    /// project that weren't part of the session keep their place appended after.
    static func applyRanking(orderedNames: [String], project: Project, context: ModelContext) {
        let byName = Dictionary(project.items.map { ($0.filename, $0) }, uniquingKeysWith: { a, _ in a })
        var rank = 0
        var placed = Set<String>()
        for name in orderedNames {
            if let item = byName[name] {
                item.rank = rank
                rank += 1
                placed.insert(name)
            }
        }
        // Any items not in the session (shouldn't happen for scope .all) trail,
        // preserving their prior relative order.
        let remaining = project.items
            .filter { !placed.contains($0.filename) }
            .sorted(by: SortOption.rank.comparator)
        for item in remaining {
            item.rank = rank
            rank += 1
        }
        try? context.save()
    }

    /// Remove all rankings in a project (back to "New").
    static func clearRankings(project: Project, context: ModelContext) {
        for item in project.items { item.rank = nil }
        try? context.save()
    }

    /// Reorder after a drag-and-drop move within the current sorted list.
    static func reorder(items: [MediaItem], from source: IndexSet, to destination: Int, context: ModelContext) {
        var ordered = items
        ordered.move(fromOffsets: source, toOffset: destination)
        applyOrder(ordered, context: context)
    }
}
