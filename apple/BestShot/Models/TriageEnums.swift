import Foundation

/// The decision recorded for a photo during a triage session.
enum ReviewDecision: String, Codable {
    /// Not yet decided (default / after Undo).
    case undecided
    /// Keep — no change to the library, just marked reviewed.
    case kept
    /// Marked for deletion; committed as a batch when the session finishes.
    case deleted
    /// Skipped for now — intentionally NOT persisted, so it resurfaces later.
    case skipped
}

/// Ordering for the photos fed into a triage / organise session.
enum SessionOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .random: return "Random"
        }
    }

    var systemImage: String {
        switch self {
        case .newest: return "arrow.down.to.line"
        case .oldest: return "arrow.up.to.line"
        case .random: return "shuffle"
        }
    }
}
