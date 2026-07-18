import SwiftUI
import Photos

/// The active triage screen. Presents a focus card (swipe Keep/Delete, buttons
/// for Favourite/Skip/Undo) that you can **pinch out** to see the whole session
/// gallery for context, then tap a tile to zoom back in. Finishing commits the
/// batch deletion.
struct TriageView: View {
    @Bindable var session: TriageSession
    let onFinish: () -> Void

    @State private var showGallery = false
    @State private var pinch: CGFloat = 1
    @State private var showSummary = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            if !showGallery { controls }
        }
        #if os(iOS)
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showSummary) {
            TriageSummaryView(session: session, onCommit: onFinish, onKeepGoing: { showSummary = false })
        }
        .onChange(of: session.isComplete) { _, complete in
            if complete { showSummary = true }
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
            Button { onFinish() } label: { Image(systemName: "xmark") }

            VStack(spacing: 4) {
                ProgressView(value: session.progress)
                HStack(spacing: 12) {
                    tally("checkmark", session.keptCount, .green)
                    tally("trash", session.deleteCount, .red)
                    tally("heart.fill", session.favouriteCount, .pink)
                    Spacer()
                    Text("\(min(session.index + 1, session.assets.count))/\(session.assets.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                withAnimation(.spring(response: 0.35)) { showGallery.toggle() }
            } label: {
                Image(systemName: showGallery ? "rectangle.portrait" : "square.grid.2x2")
            }

            Button("Done") { showSummary = true }
                .fontWeight(.semibold)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        #if os(iOS)
        .foregroundStyle(.white)
        #endif
        .background(.ultraThinMaterial)
    }

    private func tally(_ symbol: String, _ count: Int, _ color: Color) -> some View {
        Label("\(count)", systemImage: symbol)
            .font(.caption.bold())
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 22) {
            controlButton("arrow.uturn.backward", "Undo", .gray) { session.undo() }
                .disabled(!session.canUndo)
            controlButton("trash", "Delete", .red) {
                withAnimation(.spring(response: 0.3)) { session.delete() }
            }
            controlButton("forward.end", "Skip", .orange) { session.skip() }
            controlButton("heart", "Favourite", .pink) { session.toggleFavourite() }
            controlButton("checkmark", "Keep", .green) {
                withAnimation(.spring(response: 0.3)) { session.keep() }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func controlButton(_ symbol: String, _ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(color.opacity(0.18)))
                    .foregroundStyle(color)
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
