import Foundation
import LocalAuthentication
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Photos' Hidden album opens only after Face ID (or Touch ID, or the passcode),
/// as it does in Photos, and locks again whenever BestShot goes to the background.
@MainActor
final class HiddenGate {
    static let shared = HiddenGate()
    private(set) var isUnlocked = false

    private init() {
        #if os(iOS)
        let away = UIApplication.didEnterBackgroundNotification
        #else
        let away = NSApplication.didResignActiveNotification
        #endif
        NotificationCenter.default.addObserver(forName: away, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { HiddenGate.shared.isUnlocked = false }
        }
    }

    /// Asks once; true when unlocked (already, or now).
    func unlock() async -> Bool {
        if isUnlocked { return true }
        let context = LAContext()
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else { return false }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: "Open your Hidden photos")) ?? false
        isUnlocked = ok
        return ok
    }

    /// For starting a session: anything but Hidden goes straight through.
    func allows(_ source: TriageSourceOption) async -> Bool {
        source.isHidden ? await unlock() : true
    }
}
