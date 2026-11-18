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
    @State private var commands = AppCommands.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            if !showGallery {
                if let asset = session.current { labels(asset) }
                controls
            }
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
        // The ⌘K menu's Grid and Finish, as the buttons up top.
        .onChange(of: showGallery, initial: true) { _, shown in commands.triageGrid = shown }
        .onDisappear { commands.triageGrid = false }
        .onChange(of: commands.request?.id) { _, _ in
            switch commands.request?.command {
            case .grid?: Theme.Motion.run(Theme.Motion.settle) { showGallery.toggle() }
            case .finishTriage?: showSummary = true
            default: break
            }
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
                if !session.tags.isEmpty {
                    // What a keep adds, so it's never a surprise.
                    Label(session.tags.joined(separator: " · "), systemImage: "tag")
                        .font(.small)
                        .foregroundStyle(Theme.viewfinder.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Keeping tags: \(session.tags.joined(separator: ", "))")
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

            #if os(iOS)
            // The bar is hidden here, so its ⋯ menu is too: Commands sits with the other buttons.
            Button { CommandRoute.presentMenu() } label: { Image(systemName: "command") }
                .accessibilityLabel("Commands")
            #endif
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

    // MARK: - Stars and colour labels

    /// Stars and colours, as in Folders and on the monitor, in the marks they
    /// share. A colour stays on the photo, so pressing it again clears it; green
    /// keeps, yellow skips, red marks it for deleting. Keys 1-5, 0 and 6-9 too.
    private func labels(_ asset: PHAsset) -> some View {
        let rating = session.mark(for: asset).rating
        let shown = session.shownColour(for: asset)
        let names = LabelStore.shared
        return HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { n in
                Button { session.rate(rating == n ? 0 : n) } label: {
                    Image(systemName: n <= rating ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(n <= rating ? Theme.viewfinder.ink : Theme.viewfinder.muted)
                        .frame(width: 30, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(LabelKey(key: String(n), on: keysHere))
                .accessibilityLabel(n == 1 ? "1 star" : "\(n) stars")
                .accessibilityAddTraits(n == rating ? .isSelected : [])
            }
            // 0 clears the stars, as in Folders.
            Button { session.rate(0) } label: { EmptyView() }
                .modifier(LabelKey(key: "0", on: keysHere))
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            ForEach(LabelColour.allCases) { colour in
                let on = shown == colour
                Button { Theme.Motion.run(Theme.Motion.snap) { session.toggleColour(colour) } } label: {
                    Circle()
                        .fill(Theme.label(colour))
                        .frame(width: on ? 22 : 16, height: on ? 22 : 16)
                        .overlay(Circle().strokeBorder(Theme.viewfinder.ink, lineWidth: on ? 2 : 0))
                        .frame(width: 34, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(LabelKey(key: colour.key, on: keysHere))
                .accessibilityLabel(names.name(colour))
                .accessibilityHint(on ? "Takes the colour off" : colour.triageHint)
                .accessibilityAddTraits(on ? .isSelected : [])
                .help(names.name(colour) + (colour.key.map { " (\($0))" } ?? ""))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    /// With a monitor up, the keyboard is the monitor's: its own keys set these there.
    private var keysHere: Bool {
        #if os(iOS)
        MonitorDisplay.shared.desk?.isConnected != true
        #else
        true
        #endif
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

/// A label's digit, where it has one (purple has none).
private struct LabelKey: ViewModifier {
    let key: String?
    let on: Bool

    func body(content: Content) -> some View {
        if on, let key, let character = key.first {
            content.keyboardShortcut(KeyEquivalent(character), modifiers: [])
        } else {
            content
        }
    }
}

private extension LabelColour {
    var triageHint: String {
        switch decision {
        case .kept: return "Keeps the photo"
        case .skipped: return "Maybe: it comes round again"
        case .deleted: return "Marks the photo to delete"
        case .undecided: return "A label only"
        }
    }
}
