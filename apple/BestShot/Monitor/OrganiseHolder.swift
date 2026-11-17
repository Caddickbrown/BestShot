import Foundation
import Observation

/// The Organise session, held above any one screen as Triage's is, so the phone
/// and the monitor are on the same one: the same photo, the same albums ticked,
/// the same Undo. Acting on either moves both (Dan, 17 Nov: "the same on the
/// screen and the monitor").
@Observable
@MainActor
final class OrganiseHolder {
    static let shared = OrganiseHolder()

    private(set) var session: OrganiseSession?
    /// Left before the end. Each step is saved as it happens, so nothing waits on
    /// it, but the place and Undo are kept until it's resumed or started again.
    private(set) var paused = false

    /// Up on the screens now, not waiting on a start screen.
    var isOpen: Bool { session != nil && !paused }

    /// A new session in place of any before it.
    func start(_ session: OrganiseSession) {
        self.session = session
        paused = false
    }

    /// Back to the start without finishing. A finished session just ends.
    func leave() {
        if session?.isComplete ?? true { end() } else { paused = true }
    }

    func resume() {
        if session != nil { paused = false }
    }

    func end() {
        session = nil
        paused = false
    }
}
