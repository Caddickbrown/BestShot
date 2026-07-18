import SwiftUI
import Photos

/// A single swipeable photo card. Swipe right = Keep, left = Delete. Shows a
/// coloured KEEP / DELETE stamp as you drag past the threshold.
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
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topLeading) { stamp("KEEP", .green, visible: offset.width > 40) }
                .overlay(alignment: .topTrailing) { stamp("DELETE", .red, visible: offset.width < -40) }
                .overlay(alignment: .bottomTrailing) {
                    if isFavourited {
                        Image(systemName: "heart.fill")
                            .font(.title2)
                            .foregroundStyle(.pink)
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

    private func stamp(_ text: String, _ color: Color, visible: Bool) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(text == "KEEP" ? -18 : 18))
            .padding(28)
            .opacity(visible ? min(1, abs(offset.width) / threshold) : 0)
    }
}
