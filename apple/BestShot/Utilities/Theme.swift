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

    // MARK: Spacing, radii, motion
    //
    // Rank's sheet set these: a 20pt inset to the header, 4pt gaps between
    // prints, plain text buttons 18pt apart and one red pill. Every screen takes
    // them from here.

    enum Space {
        /// The side inset of a screen's header and bars.
        static let screen: CGFloat = 20
        /// Above a header's eyebrow, and under its last line.
        static let headerTop: CGFloat = 4
        /// Between a header's small line and its title, which has a tall face.
        static let eyebrowGap: CGFloat = 8
        static let headerBottom: CGFloat = 8
        /// Between the lines of a header, and the rows of a short stack.
        static let stack: CGFloat = 10
        /// Between plain text buttons in a row.
        static let actions: CGFloat = 18
        /// Between tabs, and around a stat.
        static let tabs: CGFloat = 22
        /// Above a section label on the sheet.
        static let section: CGFloat = 24
        /// Between prints on a contact sheet, and around it.
        static let gutter: CGFloat = 4
        /// Around an empty state or a centred panel.
        static let panel: CGFloat = 40
        /// Inside a bar: above and below its contents.
        static let bar: CGFloat = 12
    }

    /// The only radii. Prints and tiles have none; pills are capsules.
    /// The same names as `--radius-sm`, `--radius-md`, `--radius-lg` on the web.
    enum Radius {
        static let sm: CGFloat = 2
        static let md: CGFloat = 6
        static let lg: CGFloat = 12
    }

    /// Springs, and none at all with Reduce Motion on.
    enum Motion {
        /// A decision landing: a photo kept or binned.
        static let snap = Animation.spring(response: 0.3)
        /// A view changing over: the card to the grid and back.
        static let settle = Animation.spring(response: 0.35)

        @MainActor
        static func run(_ animation: Animation, _ change: () -> Void) {
            if reduceMotion { change() } else { withAnimation(animation, change) }
        }

        @MainActor
        static var reduceMotion: Bool {
            #if canImport(UIKit)
            UIAccessibility.isReduceMotionEnabled
            #else
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            #endif
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

    /// Archivo's heavy condensed cut, which every heading uses.
    static func heading(_ size: CGFloat) -> Font { display(size, weight: 800, width: 70) }

    // The type scale, from Rank. Headings are Archivo; everything else is Plex Mono.

    /// A screen's name: "Rank", "Triage".
    static let screenTitle = heading(38)
    /// A centred heading: an empty state, a finished run.
    static let panelTitle = heading(30)
    /// A smaller heading: an empty state, a sheet's own title.
    static let sectionTitle = heading(24)
    /// The title in a bar over photos: "Which is better?"
    static let barTitle = heading(22)
    /// The line over a screen's name, and the counts beside it.
    static let eyebrow = mono(12)
    /// Rows, choices and fields.
    static let row = mono(14)
    /// Running text, and plain text buttons.
    static let note = mono(13)
    /// The label on the one red pill.
    static let pill = mono(14, medium: true)
    /// Progress and small print.
    static let small = mono(11)
    /// A print's caption.
    static let tiny = mono(9)
}

#if canImport(UIKit)
extension UIFont {
    /// Plex Mono for UIKit, scaled with the text size setting.
    static func mono(_ size: CGFloat, medium: Bool = false, style: UIFont.TextStyle = .body) -> UIFont {
        let base = UIFont(name: medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: medium ? .medium : .regular)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    /// Archivo's heading cut for UIKit.
    static func heading(_ size: CGFloat, style: UIFont.TextStyle = .largeTitle) -> UIFont {
        let wght: UInt32 = 0x7767_6874, wdth: UInt32 = 0x7764_7468
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: "Archivo",
            kCTFontVariationAttribute: [wght: 800, wdth: 70],
        ]
        let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil) as UIFont
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }
}

/// The system's bars in the table's type and colours, so a sheet's title and its
/// Done read like the rest. Called once at launch.
@MainActor
enum BrandBars {
    static func apply() {
        let ink = UIColor(Theme.table.ink)
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor(Theme.table.background)
        bar.shadowColor = UIColor(Theme.table.rule)
        bar.titleTextAttributes = [.font: UIFont.mono(15, medium: true, style: .headline), .foregroundColor: ink]
        bar.largeTitleTextAttributes = [.font: UIFont.heading(34), .foregroundColor: ink]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: UIFont.mono(15)]
        bar.buttonAppearance = button
        bar.doneButtonAppearance = button
        bar.backButtonAppearance = button
        let edge = bar.copy()
        edge.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = edge
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont.mono(13)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont.mono(13, medium: true)], for: .selected)
    }
}
#endif

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

    /// A system Form or List set like the sheet: on the table, rows in Plex Mono.
    /// Sections are `TableSection`s.
    func tableForm() -> some View {
        self
            .font(.row)
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
