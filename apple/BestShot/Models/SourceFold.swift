import Foundation

/// Whether the start screen's list of sources is open. With a source chosen it
/// folds into one row (the source, its count and a chevron); tapping that opens
/// the list again, and choosing one, even the same one, folds it once more. It
/// opens by itself only when nothing has been chosen yet, which on a start screen
/// is the All Photos it begins with.
struct SourceFold: Equatable {
    private(set) var open: Bool

    init(source: TriageSourceOption) {
        open = source == .allPhotos
    }

    /// A source tapped: the list folds up to it.
    mutating func choose() { open = false }

    /// The folded row tapped: the whole list, to change it.
    mutating func reopen() { open = true }
}
