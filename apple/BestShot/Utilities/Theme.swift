import SwiftUI

/// Light / dark / follow-system preference, persisted via `@AppStorage`.
enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "themePreference"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// App-wide colors. The web app's "darkroom" identity uses a deep near-black
/// with a warm amber accent; we reuse that accent here.
enum Theme {
    static let accent = Color(red: 0.98, green: 0.68, blue: 0.28)
}
