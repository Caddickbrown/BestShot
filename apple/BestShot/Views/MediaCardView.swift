import SwiftUI

/// A single gallery tile: thumbnail + rank badge / "New" pill + optional
/// selection checkmark.
struct MediaCardView: View {
    let item: MediaItem
    var isSelected: Bool = false
    var selectionMode: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            AsyncFileImage(url: item.thumbnailURL ?? item.fileURL,
                           downsampleTo: 512,
                           contentMode: .fill)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .center) {
                    if item.mediaType == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                }

            // Rank / New badge
            badge
                .padding(6)

            if !item.tags.isEmpty {
                Image(systemName: "tag.fill")
                    .font(.caption2)
                    .padding(4)
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(6)
            }

            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .white)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let rank = item.rank {
            Text("#\(rank + 1)")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
        } else {
            Text("New")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 3)
                .foregroundStyle(.black)
                .background(Theme.accent, in: Capsule())
        }
    }
}
