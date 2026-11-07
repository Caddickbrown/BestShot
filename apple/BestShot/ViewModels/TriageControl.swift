import Foundation

/// Triage's buttons: an icon each, with the words kept for VoiceOver and the
/// pointer's tooltip.
enum TriageControl: CaseIterable {
    case bin, undo, skip, favourite, keep, done

    /// The row under the photo: decide at each end, the rest between.
    static let bar: [TriageControl] = [.bin, .undo, .skip, .favourite, .keep]

    var symbol: String { symbol(isOn: false) }
    var title: String { title(isOn: false) }

    func symbol(isOn: Bool) -> String {
        switch self {
        case .bin: return "trash"
        case .undo: return "arrow.uturn.backward"
        case .skip: return "forward"
        case .favourite: return isOn ? "heart.fill" : "heart"
        case .keep: return "checkmark"
        case .done: return "flag.checkered"
        }
    }

    func title(isOn: Bool) -> String {
        switch self {
        case .bin: return "Bin"
        case .undo: return "Undo"
        case .skip: return "Skip"
        case .favourite: return isOn ? "Remove favourite" : "Favourite"
        case .keep: return "Keep"
        case .done: return "Done"
        }
    }
}
