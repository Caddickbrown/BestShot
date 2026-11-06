import SwiftUI
import Photos

/// The active triage screen. Presents a focus card (swipe Keep/Delete, buttons
/// for Favourite/Skip/Undo) that you can **pinch out** to see the whole session
/// gallery for context, then tap a tile to zoom back in. Finishing commits the
/// batch deletion.
struct TriageView: View {
    @Bindable var session: TriageSession
    let onFinish: () -> Void
    /// Back to the start screen without finishing.
    let onLeave: () -> Void

    @State private var showGallery = false
    @State private var pinch: CGFloat = 1
    @State private var showSummary = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            if !showGallery { controls }
        }
        .viewfinder()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showSummary) {
            TriageSummaryView(session: session, onCommit: onFinish, onKeepGoing: { showSummary = false })
        }
        .onChange(of: session.isComplete) { _, complete in
            if complete { showSummary = true }
        }
        .escapeCloses {
            if showGallery {
                withAnimation(.spring(response: 0.35)) { showGallery = false }
            } else {
                onLeave()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if showGallery {
            TriageGalleryView(session: session) { index in
                session.focus(on: index)
                withAnimation(.spring(response: 0.35)) { showGallery = false }
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if let asset = session.current {
            TriageCardView(
                asset: asset,
                isFavourited: session.isFavourited(asset),
                onKeep: { withAnimation(.spring(response: 0.3)) { session.keep() } },
                onDelete: { withAnimation(.spring(response: 0.3)) { session.delete() } }
            )
            .id(asset.localIdentifier)
            .padding(12)
            .scaleEffect(pinch)
            .gesture(
                MagnificationGesture()
                    .onChanged { pinch = min(1, $0) }
                    .onEnded { value in
                        if value < 0.75 {
                            withAnimation(.spring(response: 0.35)) { showGallery = true }
                        }
                        withAnimation(.spring(response: 0.3)) { pinch = 1 }
                    }
            )
            .transition(.opacity)
        } else {
            ContentUnavailableView("All done", systemImage: "checkmark.circle")
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Button { onLeave() } label: { Image(systemName: "xmark") }

            VStack(spacing: 4) {
                GeometryReader { geo in
                    Rectangle().fill(Theme.viewfinder.rule)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.viewfinder.ink).frame(width: geo.size.width * session.progress)
                        }
                }
                .frame(height: 2)
                HStack(spacing: 12) {
                    tally("✓ \(session.keptCount)", Theme.viewfinder.ink)
                    tally("✕ \(session.deleteCount)", Theme.viewfinder.accent)
                    tally("♥ \(session.favouriteCount)", Theme.viewfinder.muted)
                    Spacer()
                    Text("\(min(session.index + 1, session.assets.count)) / \(session.assets.count)")
                        .font(.mono(11))
                        .foregroundStyle(Theme.viewfinder.muted)
                }
            }

            Button {
                withAnimation(.spring(response: 0.35)) { showGallery.toggle() }
            } label: {
                Image(systemName: showGallery ? "rectangle.portrait" : "square.grid.2x2")
            }

            Button("Done") { showSummary = true }
                .buttonStyle(.viewfinderText)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .foregroundStyle(Theme.viewfinder.ink)
        .background(Color.black)
        .overlay(alignment: .bottom) { HairlineRule(palette: Theme.viewfinder) }
    }

    private func tally(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.mono(12))
            .foregroundStyle(color)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button("← Bin") {
                withAnimation(.spring(response: 0.3)) { session.delete() }
            }
            .buttonStyle(.viewfinderText)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .overlay(Capsule().stroke(Theme.viewfinder.rule, lineWidth: 1))
            Spacer(minLength: 0)
            Button("Undo") { session.undo() }
                .buttonStyle(.viewfinderText)
                .disabled(!session.canUndo)
            Button("Skip") { session.skip() }
                .buttonStyle(.viewfinderText)
            Button(session.current.map(session.isFavourited) == true ? "♥ Fav" : "♡ Fav") { session.toggleFavourite() }
                .buttonStyle(.viewfinderText)
            Spacer(minLength: 0)
            Button("Keep →") {
                withAnimation(.spring(response: 0.3)) { session.keep() }
            }
            .buttonStyle(.viewfinderPill)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .overlay(alignment: .top) { HairlineRule(palette: Theme.viewfinder) }
    }
}
