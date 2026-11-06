import SwiftUI
import SwiftData

@main
struct BestShotApp: App {
    /// Shared SwiftData container holding projects + media metadata.
    /// Media bytes and thumbnails live on disk (see `MediaStore`); the store
    /// only holds lightweight metadata + relative file paths.
    let container: ModelContainer

    init() {
        BrandFonts.register()
        do {
            container = try ModelContainer(for: Project.self, MediaItem.self, AssetReview.self, RankedOrder.self)
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
                // Light table by default; judging screens switch to the viewfinder.
                .preferredColorScheme(.light)
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
