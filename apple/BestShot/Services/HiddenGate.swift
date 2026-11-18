import Foundation
import LocalAuthentication
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Photos' Hidden album opens only after Face ID (or Touch ID, or the passcode),
/// as it does in Photos, and locks again whenever BestShot goes to the background.
@MainActor
@Observable
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

extension View {
    /// Covers a session holding Hidden photos while Hidden is locked. The lock was only checked
    /// when a session started, so one resumed after BestShot had been in the background showed
    /// the Hidden photos again with no Face ID.
    func hiddenLock(_ holdsHidden: Bool) -> some View {
        modifier(HiddenLockCover(holdsHidden: holdsHidden))
    }
}

private struct HiddenLockCover: ViewModifier {
    let holdsHidden: Bool
    @State private var gate = HiddenGate.shared

    func body(content: Content) -> some View {
        if holdsHidden && !gate.isUnlocked {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Theme.table.muted)
                Text("Hidden is locked").font(.sectionTitle)
                Button("Unlock") { Task { _ = await gate.unlock() } }
                    .buttonStyle(.pill)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tableSurface()
            .task { _ = await gate.unlock() }
        } else {
            content
        }
    }
}
