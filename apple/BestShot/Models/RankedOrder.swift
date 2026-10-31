import Foundation
import SwiftData

/// A saved ranking (best first) for photos that don't live in a folder, i.e.
/// the Photos library, where ids are `PHAsset.localIdentifier`s. Folder
/// rankings live in the folder's `.bestshot-cull.json` instead.
@Model
final class RankedOrder {
    @Attribute(.unique) var key: String
    var ids: [String]
    var updatedAt: Date

    init(key: String, ids: [String] = []) {
        self.key = key
        self.ids = ids
        self.updatedAt = .now
    }

    static let photosLibraryKey = "photos-library"
}
