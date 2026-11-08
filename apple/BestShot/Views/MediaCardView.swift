import SwiftUI

/// A single gallery tile: thumbnail + rank badge / "New" pill + optional
/// selection checkmark. Square, unrounded, as the prints on Rank's sheet.
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
                .background(Theme.table.tile)
                .clipped()
                .overlay(alignment: .center) {
                    if item.mediaType == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.viewfinder.ink)
                            .frame(width: 48, height: 48)
                            .background(Color.black.opacity(0.55), in: Circle())
                    }
                }

            // Rank / New badge
            badge
                .padding(6)

            if !item.tags.isEmpty {
                Image(systemName: "tag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.table.ink)
                    .padding(5)
                    .background(Theme.table.paper)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(6)
            }

            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.table.accent : .white)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
            }
        }
        .overlay {
            Rectangle()
                .strokeBorder(isSelected ? Theme.table.accent : .clear, lineWidth: 3)
        }
    }

    /// The rank as Rank writes it, on a slip of paper; a new one gets the red tab.
    @ViewBuilder
    private var badge: some View {
        if let rank = item.rank {
            RankNumber(rank: rank + 1)
                .padding(.horizontal, 6)
                .background(Theme.table.paper)
                .accessibilityLabel("Rank \(rank + 1)")
        } else {
            Text("New")
                .font(.mono(10, medium: true))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .foregroundStyle(Theme.table.accentInk)
                .background(Theme.table.accent, in: Capsule())
        }
    }
}
