#if os(iOS)
import SwiftUI
import SwiftData
import UIKit

// Plug the phone into a monitor and BestShot gets a window of its own there
// instead of a mirror: the external-display scene declared in Support/Info-iOS.plist
// points at `MonitorSceneDelegate` below. The monitor shows the big picture,
// driven by the keyboard; the phone stays free.
//
// From MarkRead's MonitorDisplay.swift and MiniOffice's Display.swift: a
// non-interactive scene shown but never made key, the phone kept awake while it
// drives a monitor, and `reconcile` for what iOS doesn't report while the app is
// away. A locked display never draws a photo.

/// A singleton because the monitor's window is built by a UIKit scene delegate,
/// which can't reach the app scene's environment.
@MainActor final class MonitorDisplay {
    static let shared = MonitorDisplay()

    /// Made at launch, when there's a container to reach the data with.
    private(set) var desk: MonitorDesk?
    private var protectedDataGone = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ body: @escaping @MainActor (MonitorDisplay) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in body(MonitorDisplay.shared) }
            })
        }
        // iOS doesn't always tell a scene its monitor went while the app was
        // away, so every return checks what's really there.
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.willEnterForegroundNotification,
                     UIApplication.willResignActiveNotification,
                     UIScreen.didConnectNotification, UIScreen.didDisconnectNotification,
                     UIScene.didDisconnectNotification, UIScene.didActivateNotification,
                     UIScene.willEnterForegroundNotification, UIScene.didEnterBackgroundNotification] {
            observe(name) { $0.reconcile() }
        }
        observe(UIApplication.protectedDataWillBecomeUnavailableNotification) {
            $0.protectedDataGone = true
            $0.updateLock()
        }
        observe(UIApplication.protectedDataDidBecomeAvailableNotification) {
            $0.protectedDataGone = false
            $0.updateLock()
        }
    }

    /// From the app's init: `UIApplication.shared` isn't there yet, so this mustn't
    /// touch it. The first scene to connect brings on `reconcile`.
    func start(container: ModelContainer) {
        guard desk == nil else { return }
        desk = MonitorDesk(library: MonitorPhotosLibrary(context: container.mainContext), marks: PhotoMarkStore())
        desk?.onPause = { [weak self] in self?.updateIdleTimer() }
    }

    /// The monitor's scene, if it's attached to a screen that's still there.
    private var monitorScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.role == .windowExternalDisplayNonInteractive
                && $0.activationState != .unattached && UIScreen.screens.contains($0.screen) }
    }

    /// Makes the desk's `isConnected` what's really there, whatever was or wasn't
    /// reported while the app was away.
    func reconcile() {
        guard let desk else { return }
        let present = monitorScene != nil
        if desk.isConnected && !present {
            displayDidDisconnect()
        } else if !desk.isConnected && present {
            displayDidConnect()
        }
        updateLock()
        updateIdleTimer()
    }

    func displayDidConnect() {
        desk?.isConnected = true
        desk?.library.reloadSources()
        updateLock()
        updateIdleTimer()
    }

    /// Everything lives in the desk and the session, not in the monitor's window,
    /// so it's all there when it comes back.
    func displayDidDisconnect() {
        desk?.isConnected = false
        desk?.monitorLeft()
        updateIdleTimer()
    }

    /// Fails closed: with no sign of the phone's scene, the monitor stays blank.
    private func updateLock() {
        let inFront = UIApplication.shared.connectedScenes.contains {
            $0.session.role == .windowApplication
                && ($0.activationState == .foregroundActive || $0.activationState == .foregroundInactive)
        }
        desk?.setLocked(protectedDataGone || !UIApplication.shared.isProtectedDataAvailable || !inFront)
    }

    /// The phone stays awake while it's driving a monitor.
    func updateIdleTimer() {
        guard let desk else { return }
        UIApplication.shared.isIdleTimerDisabled = desk.isConnected && !desk.isPaused
            && UIApplication.shared.applicationState == .active
    }
}

/// Delegate for the `UIWindowSceneSessionRoleExternalDisplayNonInteractive` scene
/// in the plist. Declaring that scene is what stops iOS mirroring the app; this
/// builds the window that takes the mirror's place.
final class MonitorSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard session.role == .windowExternalDisplayNonInteractive,
              let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: MonitorWindowRoot())
        // Shown but never made key: the phone keeps keyboard focus.
        window.isHidden = false
        self.window = window
        MonitorDisplay.shared.displayDidConnect()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard scene.session.role == .windowExternalDisplayNonInteractive else { return }
        window = nil
        MonitorDisplay.shared.displayDidDisconnect()
    }

    /// The scene can come back from the background without a new connection.
    func sceneWillEnterForeground(_ scene: UIScene) {
        MonitorDisplay.shared.reconcile()
    }
}

/// The desk is made in the app's init, ahead of any scene.
private struct MonitorWindowRoot: View {
    var body: some View {
        if let desk = MonitorDisplay.shared.desk {
            MonitorRoot(desk: desk)
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}
#endif
