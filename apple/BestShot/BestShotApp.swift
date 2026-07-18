import SwiftUI
import SwiftData

@main
struct BestShotApp: App {
    /// Shared SwiftData container holding projects + media metadata.
    /// Media bytes and thumbnails live on disk (see `MediaStore`); the store
    /// only holds lightweight metadata + relative file paths.
    let container: ModelContainer

    @AppStorage(ThemePreference.storageKey) private var themeRaw = ThemePreference.system.rawValue

    init() {
        do {
            container = try ModelContainer(for: Project.self, MediaItem.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    private var theme: ThemePreference {
        ThemePreference(rawValue: themeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(theme.colorScheme)
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
