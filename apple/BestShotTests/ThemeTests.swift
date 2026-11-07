import XCTest
import SwiftUI
@testable import BestShot

final class ThemeTests: XCTestCase {
    private func hex(_ colour: Color, _ scheme: ColorScheme) -> UInt32 {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let c = colour.resolve(in: environment)
        func byte(_ v: Float) -> UInt32 { UInt32((max(0, min(1, v)) * 255).rounded()) }
        return byte(c.red) << 16 | byte(c.green) << 8 | byte(c.blue)
    }

    private func luminance(_ rgb: UInt32) -> Double {
        func linear(_ channel: UInt32) -> Double {
            let c = Double(channel & 0xff) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb >> 16) + 0.7152 * linear(rgb >> 8) + 0.0722 * linear(rgb)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    func testTheTableTurnsDarkWhenTheSchemeDoes() {
        XCTAssertEqual(hex(Theme.table.background, .light), 0xEFEBE1)
        XCTAssertLessThan(luminance(hex(Theme.table.background, .dark)), 0.05)
    }

    func testTextReadsOnBothTables() {
        for scheme in [ColorScheme.light, .dark] {
            let t = Theme.table
            for surface in [t.background, t.paper] {
                XCTAssertGreaterThanOrEqual(contrast(hex(t.ink, scheme), hex(surface, scheme)), 7, "\(scheme)")
                XCTAssertGreaterThanOrEqual(contrast(hex(t.muted, scheme), hex(surface, scheme)), 4.5, "\(scheme)")
                XCTAssertGreaterThanOrEqual(contrast(hex(t.accent, scheme), hex(surface, scheme)), 3, "\(scheme)")
            }
            XCTAssertGreaterThanOrEqual(contrast(hex(t.accentInk, scheme), hex(t.accent, scheme)), 4.5, "\(scheme)")
        }
    }

    func testAppearanceFollowsTheSystemUntilToldOtherwise() {
        XCTAssertEqual(Appearance.fallback, .system)
        XCTAssertNil(Appearance.system.scheme)
        XCTAssertEqual(Appearance.light.scheme, .light)
        XCTAssertEqual(Appearance.dark.scheme, .dark)
    }

    func testALabelsOwnLookStandsUntilItIsChanged() {
        XCTAssertEqual(hex(Theme.label(.green, tints: [:]), .light), 0x2FA354)
        XCTAssertEqual(hex(Theme.label(.green, tints: [.green: "#112233"]), .light), 0x112233)
        XCTAssertEqual(hex(Theme.label(.green, tints: [.green: "nonsense"]), .light), 0x2FA354)
    }

    func testAPickedColourBecomesHex() {
        XCTAssertEqual(Theme.hex(Color(hex: 0x12AB9F)), "#12AB9F")
    }
}
