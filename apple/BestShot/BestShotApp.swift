import SwiftUI
import SwiftData

@main
struct BestShotApp: App {
    /// Shared SwiftData container holding projects + media metadata.
    /// Media bytes and thumbnails live on disk (see `MediaStore`); the store
    /// only holds lightweight metadata + relative file paths.
    let container: ModelContainer
    @AppStorage(Appearance.key) private var appearance = Appearance.fallback

    /// The tests run inside this app, and must never open a real library.
    private static var underTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        BrandFonts.register()
        do {
            if Self.underTest {
                container = try ModelContainer(for: Project.self, MediaItem.self, AssetReview.self, RankedOrder.self,
                                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } else {
                container = try ModelContainer(for: Project.self, MediaItem.self, AssetReview.self, RankedOrder.self)
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        #if os(iOS)
        MonitorDisplay.shared.start(container: container)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // The table follows this; judging screens are always the viewfinder.
                .preferredColorScheme(appearance.scheme)
                .tint(Theme.accent)
        }
        .modelContainer(container)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .help) {
                // Placeholder; the in-app "?" shortcut opens the shortcut sheet.
            }
        }
        #endif
    }
}
