import SwiftUI
import Photos

/// A single swipeable photo card. Swipe right = Keep, left = Delete. A
/// grease-pencil ring (keep) or cross (delete) draws in as you drag.
struct TriageCardView: View {
    let asset: PHAsset
    var isFavourited: Bool
    let onKeep: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGSize = .zero
    private let threshold: CGFloat = 110

    var body: some View {
        GeometryReader { geo in
            PhotoAssetImage(asset: asset, targetSize: CGSize(width: geo.size.width * 2,
                                                             height: geo.size.height * 2),
                            contentMode: .fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Color.black)
                .overlay { mark(.stageCircle, visible: offset.width > 20) }
                .overlay { mark(.stageCross, visible: offset.width < -20) }
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
                .gesture(
                    DragGesture()
                        .onChanged { offset = $0.translation }
                        .onEnded { value in
                            if value.translation.width > threshold {
                                onKeep()
                            } else if value.translation.width < -threshold {
                                onDelete()
                            } else {
                                withAnimation(.spring(response: 0.3)) { offset = .zero }
                            }
                        }
                )
        }
    }

    /// Draws in proportionally to how far the card has been dragged.
    private func mark(_ shape: GreasePencilShape, visible: Bool) -> some View {
        let progress = visible ? min(1, abs(offset.width) / threshold) : 0
        return shape
            .trim(from: 0, to: progress)
            .stroke(Theme.viewfinder.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            .padding(24)
            .allowsHitTesting(false)
    }
}
