import XCTest
@testable import BestShot

/// An iPad's keyboard often has no Esc, and iOS never makes ⌘. into one, so ⌘. has
/// to be declared everywhere Esc is.
final class EscapeChordTests: XCTestCase {
    func testAFieldAndTheCatcherHearBoth() {
        XCTAssertEqual(EscapeChord.declared(composing: false), [.escape, .commandPeriod])
    }

    func testMidCompositionBothBelongToTheInputMethod() {
        XCTAssertTrue(EscapeChord.declared(composing: true).isEmpty)
    }

    func testTheChords() {
        XCTAssertEqual(EscapeChord.escape.input, "\u{1B}")
        XCTAssertFalse(EscapeChord.escape.command)
        XCTAssertEqual(EscapeChord.commandPeriod.input, ".")
        XCTAssertTrue(EscapeChord.commandPeriod.command)
    }
}
