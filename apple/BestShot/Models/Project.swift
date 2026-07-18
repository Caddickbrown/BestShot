import Foundation
import SwiftData

/// A collection of media items ranked together, mirroring a "project" folder
/// in the web app.
@Model
final class Project {
    /// Stable identifier used for on-disk media folder names and UI selection.
    /// (Named `uuid` rather than `id` so it doesn't clash with SwiftData's own
    /// `persistentModelID`-based `Identifiable` conformance.)
    @Attribute(.unique) var uuid: UUID
    var name: String
    var projectDescription: String
    var createdAt: Date
    /// Manual ordering of projects in the sidebar.
    var sortIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \MediaItem.project)
    var items: [MediaItem] = []

    init(name: String, projectDescription: String = "", sortIndex: Int = 0) {
        self.uuid = UUID()
        self.name = name
        self.projectDescription = projectDescription
        self.createdAt = .now
        self.sortIndex = sortIndex
    }

    // MARK: Derived

    var itemCount: Int { items.count }

    var rankedCount: Int { items.lazy.filter { $0.rank != nil }.count }

    var unrankedCount: Int { items.lazy.filter { $0.rank == nil }.count }

    /// Items sorted by the given option (does not mutate storage).
    func sortedItems(by option: SortOption, filter: MediaFilter = .all) -> [MediaItem] {
        items
            .filter { filter.matches($0) }
            .sorted(by: option.comparator)
    }
}
