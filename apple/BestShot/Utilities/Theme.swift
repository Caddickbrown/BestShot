import SwiftUI
import CoreText

/// The BestShot look, shared with the Linux and web apps
/// (`desktop/src/styles.css` `:root`): a warm light table for sorting, marked
/// in grease-pencil red, and a pure-black viewfinder for judging photos.
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
        background: Color(hex: 0xEFEBE1),
        paper: Color(hex: 0xFBFAF6),
        tile: Color(hex: 0xDDD8CC),
        ink: Color(hex: 0x141414),
        muted: Color(hex: 0x5C5850),
        dim: Color(hex: 0x8A857A),
        rule: Color(hex: 0x141414).opacity(0.16),
        accent: Color(hex: 0xC8261D),
        accentInk: Color(hex: 0xFBFAF6)
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
}

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
    /// The warm light table: paper background, dark ink, red accent.
    func lightTable() -> some View {
        self
            .foregroundStyle(Theme.table.ink)
            .tint(Theme.table.accent)
            .background(Theme.table.background.ignoresSafeArea())
            .environment(\.colorScheme, .light)
    }

    /// The light table behind a system Form or List.
    func lightTableList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .lightTable()
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
