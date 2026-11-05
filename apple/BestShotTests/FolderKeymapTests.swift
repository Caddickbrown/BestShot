#if os(macOS)
import SwiftUI
import XCTest
@testable import BestShot

/// The Folders keys, without a window.
final class FolderKeymapTests: XCTestCase {

    private func command(_ text: String, on surface: FolderSurface = .loupe, modifiers: EventModifiers = []) -> FolderCommand? {
        FolderKeymap.command(key: KeyEquivalent(Character(text)), characters: text, modifiers: modifiers, on: surface)
    }

    func testStarsAndLabelsInTheLoupeAndGrid() {
        for surface in [FolderSurface.loupe, .grid] {
            XCTAssertEqual(command("0", on: surface), .rate(0))
            XCTAssertEqual(command("5", on: surface), .rate(5))
            XCTAssertEqual(command("6", on: surface), .label(.red))
            XCTAssertEqual(command("7", on: surface), .label(.yellow))
            XCTAssertEqual(command("8", on: surface), .label(.green))
            XCTAssertEqual(command("9", on: surface), .label(.blue))
        }
    }

    func testDigitsAreLeftAloneInRankAndWithCommand() {
        XCTAssertNil(command("1", on: .rank))
        XCTAssertNil(command("8", on: .rank))
        XCTAssertNil(command("8", modifiers: .command))
    }

    func testExistingKeysStillWork() {
        XCTAssertEqual(command("p"), .keep)
        XCTAssertEqual(command("x"), .reject)
        XCTAssertEqual(command("z", modifiers: .command), .undo)
        XCTAssertEqual(FolderKeymap.command(key: .rightArrow, characters: "", modifiers: [], on: .loupe), .keep)
        XCTAssertEqual(FolderKeymap.command(key: .rightArrow, characters: "", modifiers: [], on: .grid), .next)
        XCTAssertEqual(FolderKeymap.command(key: .delete, characters: "", modifiers: .command, on: .loupe), .trashRed)
    }
}
#endif
