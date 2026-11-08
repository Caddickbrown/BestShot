import Foundation

/// Who hears Esc: the newest thing on screen first, down to `base`, which goes
/// home. Whatever is on top registers while it's up and closes on the press, so
/// a few presses from anywhere reach the main menu.
///
/// With a monitor up: a sheet on the phone goes first, then the monitor steps back
/// to its own home, then the phone's layers and `base` follow, so one key reaches
/// home on both.
@MainActor
final class EscapeStack {
    private var layers: [(id: UUID, isSheet: Bool, close: () -> Void)] = []
    /// With nothing on top: go to the home screen.
    var base: () -> Void = {}
    /// The monitor's step back. False when it has nothing left to step back from.
    var monitorStep: () -> Bool = { false }
    /// A sheet came up on the phone, or the last one went.
    var onSheets: (Bool) -> Void = { _ in }

    var hasSheet: Bool { layers.contains(where: \.isSheet) }

    /// A layer already here keeps its place: a change on screen doesn't lift it
    /// over what opened since.
    func push(_ id: UUID, isSheet: Bool = false, close: @escaping () -> Void) {
        if let index = layers.firstIndex(where: { $0.id == id }) {
            layers[index].close = close
        } else {
            layers.append((id, isSheet, close))
            if isSheet { onSheets(true) }
        }
    }

    func remove(_ id: UUID) {
        let hadSheet = hasSheet
        layers.removeAll { $0.id == id }
        if hadSheet, !hasSheet { onSheets(false) }
    }

    func press() {
        if !hasSheet, monitorStep() { return }
        if let top = layers.last { top.close() } else { base() }
    }
}

/// The keys that mean Esc. iOS's text system knows the Esc key alone and never
/// turns ⌘. into it, so ⌘. works only where it's declared, and an iPad's keyboard
/// often has no Esc. From MiniOffice.
struct EscapeChord: Equatable {
    let input: String
    let command: Bool

    static let escape = EscapeChord(input: "\u{1B}", command: false)
    static let commandPeriod = EscapeChord(input: ".", command: true)

    /// Mid-composition both belong to the input method.
    static func declared(composing: Bool) -> [EscapeChord] {
        composing ? [] : [escape, commandPeriod]
    }
}
