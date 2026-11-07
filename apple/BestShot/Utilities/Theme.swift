import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The BestShot look, shared with the Linux and web apps
/// (`desktop/src/styles.css` `:root`): a warm table for sorting, marked in
/// grease-pencil red, and a pure-black viewfinder for judging photos. The table
/// is light or dark with the system, or as Settings says; the viewfinder is
/// always black.
enum Theme {

    struct Palette {
        let background: Color
        let paper: Color
        let tile: Color
        let ink: Color
        let muted: Color
        let dim: Color
        let rule: Color
        let accent: Color
        let accentInk: Color
    }

    /// Sorting surfaces: lists, grids, the rank sheet.
    static let table = Palette(
        background: Color(light: 0xEFEBE1, dark: 0x171512),
        paper: Color(light: 0xFBFAF6, dark: 0x22201C),
        tile: Color(light: 0xDDD8CC, dark: 0x2E2B26),
        ink: Color(light: 0x141414, dark: 0xE8E6E1),
        muted: Color(light: 0x5C5850, dark: 0xB4AFA5),
        dim: Color(light: 0x8A857A, dark: 0x8A857A),
        rule: Color(light: 0x141414, dark: 0xE8E6E1).opacity(0.16),
        accent: Color(light: 0xC8261D, dark: 0xFF5A4E),
        accentInk: Color(light: 0xFBFAF6, dark: 0x000000)
    )

    /// Judging surfaces: the loupe, Triage, Compare.
    static let viewfinder = Palette(
        background: .black,
        paper: Color(hex: 0x111111),
        tile: Color(hex: 0x1A1A1A),
        ink: Color(hex: 0xE8E6E1),
        muted: Color(hex: 0xE8E6E1).opacity(0.66),
        dim: Color(hex: 0xE8E6E1).opacity(0.42),
        rule: Color(hex: 0xE8E6E1).opacity(0.14),
        accent: Color(hex: 0xFF5A4E),
        accentInk: .black
    )

    /// Grease-pencil red, the single accent.
    static let accent = table.accent

    /// Colour labels, the one place colours other than the accent appear.
    /// Each starts as in `desktop/src/styles.css` and can be changed in Settings.
    static func label(_ colour: LabelColour, tints: [LabelColour: String]) -> Color {
        tints[colour].flatMap(Color.init(hexString:)) ?? Color(hex: ownLook(colour))
    }

    @MainActor
    static func label(_ colour: LabelColour) -> Color {
        label(colour, tints: LabelStore.shared.settings.tints)
    }

    private static func ownLook(_ colour: LabelColour) -> UInt32 {
        switch colour {
        case .red: return 0xE0352B
        case .yellow: return 0xEDBB12
        case .green: return 0x2FA354
        case .blue: return 0x2F73E0
        case .purple: return 0x8E52D6
        }
    }

    /// `#RRGGBB`, for saving a colour someone picked.
    static func hex(_ colour: Color) -> String {
        let c = colour.resolve(in: EnvironmentValues())
        func byte(_ v: Float) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.red), byte(c.green), byte(c.blue))
    }
}

/// Light, dark, or whatever the system is doing.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let fallback = Appearance.system
    static let key = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Nil if it isn't six hex digits, for colours that arrive as data.
    init?(hexString: String) {
        let digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// Resolves light or dark at draw time. From the kit's `Color+LightDark.swift`.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(rgb: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif

// MARK: - Typography

/// Archivo (condensed display) and IBM Plex Mono, bundled under
/// `Resources/Fonts` and registered at launch.
enum BrandFonts {
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Archivo, a variable font: `weight` 100–900, `width` 62–125 (100 = normal).
    static func display(_ size: CGFloat, weight: CGFloat = 700, width: CGFloat = 75) -> Font {
        let wght: UInt32 = 0x7767_6874 // 'wght'
        let wdth: UInt32 = 0x7764_7468 // 'wdth'
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: "Archivo",
            kCTFontVariationAttribute: [wght: weight, wdth: width],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    /// IBM Plex Mono for labels, counts, filenames and keys.
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
    }
}

// MARK: - Surfaces

extension View {
    /// The warm table: paper background, ink, red accent.
    func tableSurface() -> some View {
        self
            .foregroundStyle(Theme.table.ink)
            .tint(Theme.table.accent)
            .background(Theme.table.background.ignoresSafeArea())
    }

    /// The table behind a system Form or List.
    func tableSurfaceList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .tableSurface()
    }

    /// The black viewfinder: nothing competes with the photo.
    func viewfinder() -> some View {
        self
            .foregroundStyle(Theme.viewfinder.ink)
            .tint(Theme.viewfinder.accent)
            .background(Color.black.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
    }
}
