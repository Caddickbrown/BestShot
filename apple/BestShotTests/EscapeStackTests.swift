import XCTest
import SwiftUI
@testable import BestShot

@MainActor
final class EscapeStackTests: XCTestCase {
    private var log: [String] = []

    private func stack() -> EscapeStack {
        let stack = EscapeStack()
        stack.base = { self.log.append("home") }
        return stack
    }

    func testWithNothingOnTopEscGoesHome() {
        stack().press()
        XCTAssertEqual(log, ["home"])
    }

    func testEnvironmentDefaultsToNoStackAndKeepsWindowStacksSeparate() {
        var firstWindow = EnvironmentValues()
        var secondWindow = EnvironmentValues()
        XCTAssertNil(firstWindow.escapeStack)
        XCTAssertNil(secondWindow.escapeStack)

        let first = stack()
        let second = stack()
        firstWindow.escapeStack = first
        secondWindow.escapeStack = second
        XCTAssertTrue(firstWindow.escapeStack === first)
        XCTAssertTrue(secondWindow.escapeStack === second)
        XCTAssertFalse(firstWindow.escapeStack === secondWindow.escapeStack)
    }

    func testTheNewestLayerClosesFirstAndOnlyIt() {
        let stack = stack()
        stack.push(UUID()) { self.log.append("gallery") }
        stack.push(UUID()) { self.log.append("viewer") }
        stack.press()
        XCTAssertEqual(log, ["viewer"])
    }

    func testEveryLayerClosingOnItsPressEndsAtHome() {
        let stack = stack()
        for name in ["selection", "viewer", "sheet"] {
            let id = UUID()
            stack.push(id) {
                self.log.append(name)
                stack.remove(id)
            }
        }
        for _ in 0..<4 { stack.press() }
        XCTAssertEqual(log, ["sheet", "viewer", "selection", "home"])
    }

    func testPushingAgainKeepsItsPlaceAndTakesTheNewAction() {
        let stack = stack()
        let lower = UUID()
        stack.push(lower) { self.log.append("old") }
        stack.push(UUID()) { self.log.append("top") }
        stack.push(lower) { self.log.append("new") }
        stack.press()
        XCTAssertEqual(log, ["top"])
    }

    func testRemovingALayerUncoversTheOneBelow() {
        let stack = stack()
        let top = UUID()
        stack.push(UUID()) { self.log.append("below") }
        stack.push(top) { self.log.append("top") }
        stack.remove(top)
        stack.press()
        XCTAssertEqual(log, ["below"])
    }
}
