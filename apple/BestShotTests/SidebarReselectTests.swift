import SwiftUI
import XCTest
@testable import BestShot

/// The place already open, its sidebar row tapped again, scrolls its pane to the top
/// (App Kit GUIDE, 19 Nov). The pane reads its own count, so another place never moves.
final class SidebarReselectTests: XCTestCase {
    func testTheSamePlaceAgainIsAReselect() {
        var taps = TabReselect<RootView.SidebarSelection>()
        XCTAssertFalse(taps.tapped(.rank, current: .allMedia))
        XCTAssertTrue(taps.tapped(.allMedia, current: .allMedia))
        XCTAssertEqual(taps.signal(.allMedia), 1)
        XCTAssertEqual(taps.signal(.rank), 0)
    }

    func testTheSidebarsBindingHearsTheSameRow() {
        var selection: RootView.SidebarSelection? = .rank
        var heard: [RootView.SidebarSelection?] = []
        let binding = Binding(get: { selection }, set: { selection = $0 }).reselecting { heard.append($0) }

        binding.wrappedValue = .allMedia
        XCTAssertEqual(heard, [], "moving to another place is not a re-tap")
        binding.wrappedValue = .allMedia
        XCTAssertEqual(heard, [.allMedia])
        XCTAssertEqual(selection, .allMedia)
    }

    func testAProjectIsItsOwnPlace() {
        let a = UUID(), b = UUID()
        var taps = TabReselect<RootView.SidebarSelection>()
        _ = taps.tapped(.project(a), current: .project(a))
        XCTAssertEqual(taps.signal(.project(a)), 1)
        XCTAssertEqual(taps.signal(.project(b)), 0)
    }
}
