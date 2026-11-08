import SwiftUI
import Photos

/// A single swipeable photo card. Swipe right = Keep, left = Delete, and the
/// matching icon comes up as you drag. Spread two fingers or double-tap to look
/// closer, when one finger moves the photo instead. Pinching together at normal
/// size opens the grid.
struct TriageCardView: View {
    let asset: PHAsset
    var isFavourited: Bool
    let onKeep: () -> Void
    let onDelete: () -> Void
    let onGrid: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize = .zero
    @State private var zoom = PhotoZoom()
    /// A pinch started during this drag, so letting go of it decides nothing.
    @State private var dragHadPinch = false
    private let threshold: CGFloat = 110

    var body: some View {
        GeometryReader { geo in
            let box = geo.size
            PhotoAssetImage(asset: asset, targetSize: CGSize(width: box.width * 2 * CGFloat(zoom.detail),
                                                             height: box.height * 2 * CGFloat(zoom.detail)),
                            contentMode: .fit)
                .frame(width: box.width, height: box.height)
                .scaleEffect(zoom.scale * zoom.shrink)
                .offset(zoom.pan)
                .frame(width: box.width, height: box.height)
                .clipped()
                .background(Color.black)
                .contentShape(Rectangle())
                .overlay { stamp(.keep, Theme.viewfinder.ink, ink: Theme.viewfinder.accentInk, visible: offset.width > 20) }
                .overlay { stamp(.bin, Theme.viewfinder.accent, ink: Theme.viewfinder.accentInk, visible: offset.width < -20) }
                .overlay(alignment: .bottomTrailing) {
                    if isFavourited {
                        Image(systemName: "heart.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.viewfinder.accent)
                            .padding(12)
                    }
                }
                .offset(offset)
                .rotationEffect(.degrees(Double(offset.width / 22)))
                .onTapGesture(count: 2) { location in
                    animated { zoom.doubleTap(at: fromMiddle(location, box), in: box) }
                }
                .gesture(swipe(box))
                .simultaneousGesture(pinch(box))
                .accessibilityAction(named: zoom.isZoomed ? "Zoom out" : "Zoom in") {
                    zoom.doubleTap(at: .zero, in: box)
                }
        }
    }

    private func swipe(_ box: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if zoom.isPinching {
                    dragHadPinch = true
                } else if zoom.isZoomed {
                    zoom.drag(by: value.translation, in: box)
                } else if !dragHadPinch {
                    offset = value.translation
                }
            }
            .onEnded { value in
                defer {
                    zoom.endDrag()
                    dragHadPinch = false
                }
                if zoom.swipeDecides, !dragHadPinch, value.translation.width > threshold {
                    onKeep()
                } else if zoom.swipeDecides, !dragHadPinch, value.translation.width < -threshold {
                    onDelete()
                } else {
                    animated { offset = .zero }
                }
            }
    }

    private func pinch(_ box: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if offset != .zero {
                    offset = .zero
                    dragHadPinch = true
                }
                zoom.pinch(by: value.magnification, around: fromMiddle(value.startLocation, box), in: box)
            }
            .onEnded { _ in
                var wantsGrid = false
                animated { wantsGrid = zoom.endPinch(in: box) }
                if wantsGrid { onGrid() }
            }
    }

    private func fromMiddle(_ point: CGPoint, _ box: CGSize) -> CGPoint {
        CGPoint(x: point.x - box.width / 2, y: point.y - box.height / 2)
    }

    private func animated(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(Theme.Motion.snap, change) }
    }

    /// The icon of what letting go will do, fading in with the drag.
    private func stamp(_ control: TriageControl, _ fill: Color, ink: Color, visible: Bool) -> some View {
        let progress = visible ? min(1, abs(offset.width) / threshold) : 0
        return Image(systemName: control.symbol)
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(ink)
            .frame(width: 96, height: 96)
            .background(fill, in: Circle())
            .scaleEffect(0.75 + 0.25 * progress)
            .opacity(progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
