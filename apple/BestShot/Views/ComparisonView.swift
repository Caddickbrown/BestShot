import SwiftUI

/// The side-by-side A/B comparison screen. Tap (or press 1 / 2) to pick a
/// winner, Skip (space) for a tie. Keyboard shortcuts work on Mac and iPad.
struct ComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: ComparisonSession
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            if let pair = session.currentPair {
                GeometryReader { geo in
                    let isWide = geo.size.width > geo.size.height
                    let layout = isWide
                        ? AnyLayout(HStackLayout(spacing: Theme.Space.gutter))
                        : AnyLayout(VStackLayout(spacing: Theme.Space.gutter))
                    layout {
                        side(pair.left, side: .left)
                        side(pair.right, side: .right)
                    }
                    .padding(Theme.Space.gutter)
                }
            } else {
                ProgressView()
                    .tint(Theme.viewfinder.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            footer
        }
        .viewfinder()
        .onChange(of: session.isFinished) { _, finished in
            if finished { onFinish() }
        }
        .onAppear {
            // A session can already be complete (e.g. all relationships inferred).
            if session.isFinished { onFinish() }
        }
        // Keyboard shortcuts (hardware keyboard / Mac).
        .background {
            Group {
                Button("") { pick(.left) }.keyboardShortcut("1", modifiers: [])
                Button("") { pick(.right) }.keyboardShortcut("2", modifiers: [])
                Button("") { pick(.left) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { pick(.right) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { session.skip() }.keyboardShortcut(.space, modifiers: [])
                Button("") { leave() }.keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
        }
        .escapeScreen(leave)
    }

    /// Esc: picks already made go to the results rather than being lost.
    private func leave() {
        if session.comparisonsAsked > 0 { onFinish() } else { dismiss() }
    }

    /// As Rank's Compare bar: the question in Archivo, the count in mono.
    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Exit", systemImage: "xmark")
            }
            .buttonStyle(.viewfinderText)
            Spacer()
            VStack(spacing: 2) {
                Text("Which is better?").font(.barTitle)
                Text("\(session.comparisonsAsked) compared · \(session.comparisonsSkipped) inferred")
                    .font(.small)
                    .foregroundStyle(Theme.viewfinder.muted)
            }
            Spacer()
            // Balance layout
            Label("Exit", systemImage: "xmark").font(.note).opacity(0)
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, Theme.Space.bar)
        .overlay(alignment: .bottom) {
            ProgressLine(value: session.progress, palette: Theme.viewfinder)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                session.skip()
            } label: {
                Label("Skip / Tie", systemImage: "equal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.viewfinderOutline)
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, Theme.Space.bar)
        .overlay(alignment: .top) { HairlineRule(palette: Theme.viewfinder) }
    }

    private func side(_ item: MediaItem, side: ComparisonSession.Side) -> some View {
        Button {
            pick(side)
        } label: {
            ZStack(alignment: .bottom) {
                AsyncFileImage(url: item.fileURL, downsampleTo: 1600, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(item.filename)
                    .font(.eyebrow)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.viewfinder.paper)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ side: ComparisonSession.Side) {
        guard session.currentPair != nil else { return }
        session.choose(winner: side)
    }
}
