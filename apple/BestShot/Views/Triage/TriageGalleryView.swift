import SwiftUI
import Photos

/// The "context" view of a triage session: a grid of every photo in the
/// session, colour-coded by decision, with the current photo highlighted.
/// Reached by pinching out from the focus card. Tap a tile to jump back into
/// focus there; long-press for quick decisions.
struct TriageGalleryView: View {
    @Bindable var session: TriageSession
    /// Called when the user taps a tile to return to focus at that index.
    let onSelect: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 4)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(session.assets.enumerated()), id: \.element.localIdentifier) { idx, asset in
                        tile(asset, index: idx)
                            .id(idx)
                    }
                }
                .padding(4)
            }
            .onAppear { proxy.scrollTo(session.index, anchor: .center) }
        }
    }

    private func tile(_ asset: PHAsset, index: Int) -> some View {
        let decision = session.decision(for: asset)
        return PhotoAssetImage(asset: asset,
                               targetSize: CGSize(width: 200, height: 200),
                               contentMode: .fill)
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .overlay { tint(for: decision) }
            .overlay(alignment: .topTrailing) { decisionBadge(decision) }
            .overlay(alignment: .bottomLeading) {
                if session.isFavourited(asset) {
                    Image(systemName: "heart.fill")
                        .font(.caption2).foregroundStyle(.pink).padding(3)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(index == session.index ? Theme.accent : .clear, lineWidth: 3)
            }
            .onTapGesture { onSelect(index) }
            .contextMenu {
                Button { session.setDecision(.kept, for: asset) } label: { Label("Keep", systemImage: "checkmark") }
                Button(role: .destructive) { session.setDecision(.deleted, for: asset) } label: { Label("Delete", systemImage: "trash") }
                Button { session.setDecision(.undecided, for: asset) } label: { Label("Clear decision", systemImage: "arrow.uturn.backward") }
            }
    }

    @ViewBuilder
    private func tint(for decision: ReviewDecision) -> some View {
        switch decision {
        case .deleted: Color.red.opacity(0.35)
        case .kept: Color.green.opacity(0.20)
        case .skipped: Color.black.opacity(0.35)
        case .undecided: Color.clear
        }
    }

    @ViewBuilder
    private func decisionBadge(_ decision: ReviewDecision) -> some View {
        switch decision {
        case .deleted:
            Image(systemName: "trash.fill").font(.caption2).foregroundStyle(.white)
                .padding(3).background(Circle().fill(.red)).padding(3)
        case .kept:
            Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white)
                .padding(3).background(Circle().fill(.green)).padding(3)
        default:
            EmptyView()
        }
    }
}
