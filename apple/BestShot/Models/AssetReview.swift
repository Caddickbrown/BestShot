import Foundation
import SwiftData

/// Persisted record of a triage/organise decision for a Photos-library asset,
/// keyed by its `PHAsset.localIdentifier`. Lets us skip already-reviewed photos
/// across sessions without copying anything out of the Photos library.
///
/// Only `kept` and `deleted` decisions are stored (skips are intentionally
/// transient so they resurface later). `organised` tracks that the asset was
/// filed into at least one album.
@Model
final class AssetReview {
    @Attribute(.unique) var assetLocalID: String
    var decisionRaw: String
    var reviewedAt: Date
    var organised: Bool

    init(assetLocalID: String, decision: ReviewDecision, organised: Bool = false) {
        self.assetLocalID = assetLocalID
        self.decisionRaw = decision.rawValue
        self.reviewedAt = .now
        self.organised = organised
    }

    var decision: ReviewDecision {
        get { ReviewDecision(rawValue: decisionRaw) ?? .undecided }
        set { decisionRaw = newValue.rawValue }
    }
}
