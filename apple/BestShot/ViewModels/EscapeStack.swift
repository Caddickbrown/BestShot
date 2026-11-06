import Foundation

/// Who hears Esc: the newest thing on screen first, down to `base`, which goes
/// home. Whatever is on top registers while it's up and closes on the press, so
/// a few presses from anywhere reach Triage.
@MainActor
final class EscapeStack {
    private var layers: [(id: UUID, close: () -> Void)] = []
    /// With nothing on top: go to the home screen.
    var base: () -> Void = {}

    /// A layer already here keeps its place: a change on screen doesn't lift it
    /// over what opened since.
    func push(_ id: UUID, close: @escaping () -> Void) {
        if let index = layers.firstIndex(where: { $0.id == id }) {
            layers[index].close = close
        } else {
            layers.append((id, close))
        }
    }

    func remove(_ id: UUID) {
        layers.removeAll { $0.id == id }
    }

    func press() {
        if let top = layers.last { top.close() } else { base() }
    }
}
