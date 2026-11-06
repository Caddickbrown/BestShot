import Foundation
import Observation

/// The Triage session, held above any one screen, so the phone and the monitor
/// are on the same session and it's still there whichever of them goes.
@Observable
@MainActor
final class TriageHolder {
    static let shared = TriageHolder()

    var session: TriageSession?
    /// Left with photos still marked for deletion. Those marks live only in the
    /// session, so it waits on the start screen until it's resumed and finished.
    var paused = false

    /// Back to the start without finishing.
    func leave() {
        if (session?.deleteCount ?? 0) > 0 {
            paused = true
        } else {
            session = nil
            paused = false
        }
    }

    func end() {
        session = nil
        paused = false
    }
}
