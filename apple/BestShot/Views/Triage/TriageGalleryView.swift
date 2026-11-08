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

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: Theme.Space.gutter)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Space.gutter) {
                    ForEach(Array(session.assets.enumerated()), id: \.element.localIdentifier) { idx, asset in
                        tile(asset, index: idx)
                            .id(idx)
                    }
                }
                .padding(Theme.Space.gutter)
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
            .overlay { decisionMark(decision) }
            .overlay(alignment: .bottomLeading) {
                if session.isFavourited(asset) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10)).foregroundStyle(Theme.viewfinder.accent).padding(4)
                }
            }
            .overlay {
                Rectangle()
                    .strokeBorder(index == session.index ? Theme.viewfinder.ink : .clear, lineWidth: 3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(decision == .undecided ? "Not decided" : decision == .kept ? "Kept" : decision == .deleted ? "To delete" : "Skipped")
            .accessibilityAddTraits(.isButton)
            .onTapGesture { onSelect(index) }
            .contextMenu {
                Button { session.setDecision(.kept, for: asset) } label: { Label("Keep", systemImage: "checkmark") }
                Button(role: .destructive) { session.setDecision(.deleted, for: asset) } label: { Label("Delete", systemImage: "trash") }
                Button { session.setDecision(.undecided, for: asset) } label: { Label("Clear decision", systemImage: "arrow.uturn.backward") }
            }
    }

    /// What's going dims, as on the light table; what's skipped dims less.
    @ViewBuilder
    private func tint(for decision: ReviewDecision) -> some View {
        switch decision {
        case .deleted: Color.black.opacity(0.5)
        case .skipped: Color.black.opacity(0.3)
        case .kept, .undecided: Color.clear
        }
    }

    /// The grease-pencil marks every BestShot uses: a ring to keep, a cross to bin.
    @ViewBuilder
    private func decisionMark(_ decision: ReviewDecision) -> some View {
        switch decision {
        case .deleted:
            GreasePencilMark(shape: .cross, color: Theme.viewfinder.accent, lineWidth: 3).padding(10)
        case .kept:
            GreasePencilMark(shape: .circle, color: Theme.viewfinder.accent, lineWidth: 3).padding(8)
        default:
            EmptyView()
        }
    }
}
