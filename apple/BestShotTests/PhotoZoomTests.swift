import XCTest
@testable import BestShot

final class PhotoZoomTests: XCTestCase {
    private let box = CGSize(width: 300, height: 400)

    func testSpreadingFingersZoomsIn() {
        var zoom = PhotoZoom()
        zoom.pinch(by: 2, around: .zero, in: box)
        zoom.endPinch(in: box)
        XCTAssertEqual(zoom.scale, 2, accuracy: 0.001)
        XCTAssertTrue(zoom.isZoomed)
    }

    func testAZoomStopsAtTheMost() {
        var zoom = PhotoZoom()
        zoom.pinch(by: 50, around: .zero, in: box)
        XCTAssertEqual(zoom.scale, PhotoZoom.most, accuracy: 0.001)
    }

    func testPinchingOnFromAZoomKeepsWhatWasThere() {
        var zoom = PhotoZoom()
        zoom.pinch(by: 2, around: .zero, in: box)
        zoom.endPinch(in: box)
        zoom.pinch(by: 1.5, around: .zero, in: box)
        XCTAssertEqual(zoom.scale, 3, accuracy: 0.001)
    }

    func testThePointUnderTheFingersStaysThere() {
        var zoom = PhotoZoom()
        let point = CGPoint(x: 60, y: -80)
        zoom.pinch(by: 2, around: point, in: box)
        // The middle of the photo moves away from the fingers as much as they're from it.
        XCTAssertEqual(zoom.pan.width, -60, accuracy: 0.001)
        XCTAssertEqual(zoom.pan.height, 80, accuracy: 0.001)
    }

    func testPinchingBackToTheStartLetsGoAndCentres() {
        var zoom = PhotoZoom()
        zoom.pinch(by: 2, around: CGPoint(x: 60, y: 0), in: box)
        zoom.endPinch(in: box)
        zoom.pinch(by: 0.4, around: .zero, in: box)
        zoom.endPinch(in: box)
        XCTAssertFalse(zoom.isZoomed)
        XCTAssertEqual(zoom.pan, .zero)
    }

    func testPanningStopsAtThePhotosEdge() {
        var zoom = PhotoZoom()
        zoom.pinch(by: 2, around: .zero, in: box)
        zoom.endPinch(in: box)
        zoom.drag(by: CGSize(width: 1000, height: -1000), in: box)
        XCTAssertEqual(zoom.pan.width, 150, accuracy: 0.001)
        XCTAssertEqual(zoom.pan.height, -200, accuracy: 0.001)
    }

    func testADragCarriesOnFromWhereTheLastEnded() {
        var zoom = PhotoZoom()
        zoom.pinch(by: 4, around: .zero, in: box)
        zoom.endPinch(in: box)
        zoom.drag(by: CGSize(width: 30, height: 0), in: box)
        zoom.endDrag()
        zoom.drag(by: CGSize(width: 30, height: 0), in: box)
        XCTAssertEqual(zoom.pan.width, 60, accuracy: 0.001)
    }

    /// One finger means swipe until the photo's zoomed, then it moves the photo.
    func testSwipingOnlyDecidesAtNormalSize() {
        var zoom = PhotoZoom()
        XCTAssertTrue(zoom.swipeDecides)
        zoom.pinch(by: 2, around: .zero, in: box)
        XCTAssertFalse(zoom.swipeDecides)
    }

    func testASwipeCantStartMidPinch() {
        var zoom = PhotoZoom()
        zoom.pinch(by: 1.0, around: .zero, in: box)
        XCTAssertFalse(zoom.swipeDecides)
        zoom.endPinch(in: box)
        XCTAssertTrue(zoom.swipeDecides)
    }

    func testPinchingInAtNormalSizeOpensTheGridInstead() {
        var zoom = PhotoZoom()
        zoom.pinch(by: 0.6, around: .zero, in: box)
        XCTAssertEqual(zoom.scale, 1, accuracy: 0.001)
        XCTAssertEqual(zoom.shrink, 0.6, accuracy: 0.001)
        XCTAssertTrue(zoom.endPinch(in: box))
        XCTAssertEqual(zoom.shrink, 1, accuracy: 0.001)
    }

    func testPinchingInFromAZoomNeverOpensTheGrid() {
        var zoom = PhotoZoom()
        zoom.pinch(by: 2, around: .zero, in: box)
        zoom.endPinch(in: box)
        zoom.pinch(by: 0.3, around: .zero, in: box)
        XCTAssertFalse(zoom.endPinch(in: box))
    }

    func testDoubleTapZoomsAndComesBack() {
        var zoom = PhotoZoom()
        zoom.doubleTap(at: CGPoint(x: 50, y: 0), in: box)
        XCTAssertEqual(zoom.scale, PhotoZoom.tapped, accuracy: 0.001)
        XCTAssertLessThan(zoom.pan.width, 0)
        zoom.doubleTap(at: .zero, in: box)
        XCTAssertFalse(zoom.isZoomed)
        XCTAssertEqual(zoom.pan, .zero)
    }

    func testTheSharpImageIsAskedForOnceZoomed() {
        var zoom = PhotoZoom()
        XCTAssertEqual(zoom.detail, 1)
        zoom.pinch(by: 3, around: .zero, in: box)
        zoom.endPinch(in: box)
        XCTAssertEqual(zoom.detail, 3)
    }
}
