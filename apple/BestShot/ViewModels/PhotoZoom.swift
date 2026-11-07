import CoreGraphics

/// Zoom and pan on a photo in Triage. At normal size one finger still means swipe
/// and pinching in still opens the grid; zoomed, one finger moves the photo.
/// Points are measured from the middle of the photo's box.
struct PhotoZoom: Equatable {
    static let most: CGFloat = 6
    static let tapped: CGFloat = 2.5
    /// Pinched in this far, the grid opens.
    private static let gridAt: CGFloat = 0.75

    private(set) var scale: CGFloat = 1
    private(set) var pan: CGSize = .zero
    /// How far pinching in at normal size has shrunk the photo, on the way to the grid.
    private(set) var shrink: CGFloat = 1

    private var pinchStart: (scale: CGFloat, pan: CGSize)?
    private var dragStart: CGSize?

    static func == (a: PhotoZoom, b: PhotoZoom) -> Bool {
        a.scale == b.scale && a.pan == b.pan && a.shrink == b.shrink
    }

    var isZoomed: Bool { scale > 1.01 }
    var isPinching: Bool { pinchStart != nil }
    var swipeDecides: Bool { !isZoomed && !isPinching }

    /// How much sharper than normal the image needs to be, in whole steps so a
    /// pinch doesn't ask PhotoKit for every size on the way.
    var detail: Int { Int(min(scale, 3).rounded(.up)) }

    mutating func pinch(by magnification: CGFloat, around point: CGPoint, in box: CGSize) {
        let start = pinchStart ?? (scale, pan)
        pinchStart = start
        let wanted = start.scale * magnification
        scale = min(max(wanted, 1), Self.most)
        shrink = start.scale <= 1 ? min(max(wanted, 0.5), 1) : 1
        let grown = scale / start.scale
        pan = limited(CGSize(width: point.x - (point.x - start.pan.width) * grown,
                             height: point.y - (point.y - start.pan.height) * grown), in: box)
    }

    /// True if this pinch was the one that asks for the grid.
    @discardableResult
    mutating func endPinch(in box: CGSize) -> Bool {
        let wantsGrid = (pinchStart?.scale ?? 1) <= 1 && shrink < Self.gridAt
        pinchStart = nil
        shrink = 1
        if !isZoomed { reset() } else { pan = limited(pan, in: box) }
        return wantsGrid
    }

    mutating func drag(by translation: CGSize, in box: CGSize) {
        let start = dragStart ?? pan
        dragStart = start
        pan = limited(CGSize(width: start.width + translation.width, height: start.height + translation.height), in: box)
    }

    mutating func endDrag() { dragStart = nil }

    mutating func doubleTap(at point: CGPoint, in box: CGSize) {
        if isZoomed {
            reset()
        } else {
            scale = Self.tapped
            pan = limited(CGSize(width: point.x * (1 - scale), height: point.y * (1 - scale)), in: box)
        }
    }

    private mutating func reset() {
        scale = 1
        pan = .zero
    }

    /// The photo's edge can reach the box's edge and no further.
    private func limited(_ pan: CGSize, in box: CGSize) -> CGSize {
        let x = box.width * (scale - 1) / 2, y = box.height * (scale - 1) / 2
        return CGSize(width: min(max(pan.width, -x), x), height: min(max(pan.height, -y), y))
    }
}
