import SwiftUI
import Photos

/// The active triage screen. Presents a focus card (swipe Keep/Delete, icons for
/// the rest) that you can spread two fingers on to look closer, or pinch together
/// to see the whole session gallery, then tap a tile to go back in. Finishing
/// commits the batch deletion.
struct TriageView: View {
    @Bindable var session: TriageSession
    let onFinish: () -> Void
    /// Back to the start screen without finishing.
    let onLeave: () -> Void

    @State private var showGallery = false
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
                Theme.Motion.run(Theme.Motion.settle) { showGallery = false }
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
                Theme.Motion.run(Theme.Motion.settle) { showGallery = false }
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if let asset = session.current {
            TriageCardView(
                asset: asset,
                isFavourited: session.isFavourited(asset),
                onKeep: { Theme.Motion.run(Theme.Motion.snap) { session.keep() } },
                onDelete: { Theme.Motion.run(Theme.Motion.snap) { session.delete() } },
                onGrid: { Theme.Motion.run(Theme.Motion.settle) { showGallery = true } }
            )
            .id(asset.localIdentifier)
            .padding(12)
            .transition(.opacity)
        } else {
            EmptyState("All done", palette: Theme.viewfinder)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Button { onLeave() } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Leave Triage")

            VStack(spacing: 4) {
                ProgressLine(value: session.progress, palette: Theme.viewfinder)
                HStack(spacing: 12) {
                    tally(.keep, session.keptCount, Theme.viewfinder.ink)
                    tally(.bin, session.deleteCount, Theme.viewfinder.accent)
                    tally(.favourite, session.favouriteCount, Theme.viewfinder.muted)
                    Spacer()
                    Text("\(min(session.index + 1, session.assets.count)) / \(session.assets.count)")
                        .font(.small)
                        .foregroundStyle(Theme.viewfinder.muted)
                }
            }

            Button {
                Theme.Motion.run(Theme.Motion.settle) { showGallery.toggle() }
            } label: {
                Image(systemName: showGallery ? "rectangle.portrait" : "square.grid.2x2")
            }
            .accessibilityLabel(showGallery ? "Back to the photo" : "See the whole set")

            Button { showSummary = true } label: { Image(systemName: TriageControl.done.symbol) }
                .accessibilityLabel(TriageControl.done.title)
                .help(TriageControl.done.title)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .foregroundStyle(Theme.viewfinder.ink)
        .background(Color.black)
        .overlay(alignment: .bottom) { HairlineRule(palette: Theme.viewfinder) }
    }

    private func tally(_ control: TriageControl, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: control.symbol).font(.system(size: 10, weight: .semibold))
            Text("\(count)").font(.eyebrow)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(control.title): \(count)")
    }

    // MARK: - Controls

    private var controls: some View {
        let favourite = session.current.map(session.isFavourited) == true
        return HStack(spacing: 0) {
            ForEach(TriageControl.bar, id: \.self) { control in
                Button { run(control) } label: {
                    icon(control, isOn: control == .favourite && favourite)
                }
                .buttonStyle(.plain)
                .disabled(control == .undo && !session.canUndo)
                .accessibilityLabel(control.title(isOn: favourite))
                .help(control.title(isOn: favourite))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .overlay(alignment: .top) { HairlineRule(palette: Theme.viewfinder) }
    }

    /// Keep is the one filled: it's what you'll press most.
    private func icon(_ control: TriageControl, isOn: Bool) -> some View {
        let inked = control == .keep
        return Image(systemName: control.symbol(isOn: isOn))
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(inked ? Theme.viewfinder.accentInk
                             : control == .bin || isOn ? Theme.viewfinder.accent : Theme.viewfinder.ink)
            .opacity(control == .undo && !session.canUndo ? 0.35 : 1)
            .frame(width: 52, height: 52)
            .background(inked ? Theme.viewfinder.ink : .clear, in: Circle())
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    private func run(_ control: TriageControl) {
        switch control {
        case .bin: Theme.Motion.run(Theme.Motion.snap) { session.delete() }
        case .keep: Theme.Motion.run(Theme.Motion.snap) { session.keep() }
        case .undo: session.undo()
        case .skip: session.skip()
        case .favourite: session.toggleFavourite()
        case .done: showSummary = true
        }
    }
}
