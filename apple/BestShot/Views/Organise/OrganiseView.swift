import SwiftUI
import Photos

/// The active Organise screen: shows the current photo with a set of album
/// chips beneath it. Tap a chip to file the photo into that album; "New Album"
/// creates one on the fly. Next advances (and marks organised); Skip defers.
struct OrganiseView: View {
    @Bindable var session: OrganiseSession
    let onFinish: () -> Void

    @State private var showNewAlbum = false
    @State private var newAlbumName = ""
    @State private var albumQuery = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            if let asset = session.current {
                // Pinch or double-tap to zoom, drag to look around; a single tap
                // puts the keyboard away.
                OrganisePhoto(asset: asset) { searchFocused = false }
                    .id(asset.localIdentifier)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Theme.Space.bar)

                HairlineRule()
                albumChips(for: asset)
                controls
            } else {
                EmptyState("All organised")
            }
        }
        .tableSurface()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle("Organise")
        .onChange(of: session.isComplete) { _, complete in
            if complete { onFinish() }
        }
        .sheet(isPresented: $showNewAlbum) {
            TextPromptSheet(title: "New Album", placeholder: "Album name", action: "Create", text: $newAlbumName) {
                if let asset = session.current {
                    let name = newAlbumName
                    newAlbumName = ""
                    Task { await session.createAlbumAndAdd(name: name, asset: asset) }
                }
            }
        }
        // Albums and Next are saved as they happen, so leaving loses nothing.
        .escapeCloses(onFinish)
    }

    private var header: some View {
        VStack(spacing: 6) {
            ProgressLine(value: session.progress)
            HStack {
                Text("\(min(session.index + 1, session.assets.count)) / \(session.assets.count)")
                    .font(.small)
                    .foregroundStyle(Theme.table.muted)
                Spacer()
                // One album per photo: a tap files it and moves on.
                Toggle("One album, then next", isOn: $session.singleAlbum)
                    .font(.small)
                    .foregroundStyle(Theme.table.muted)
                    .tint(Theme.table.accent)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, 8)
    }

    /// Albums matching what's typed (all of them when nothing is).
    private var shownAlbums: [PHAssetCollection] {
        let q = albumQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return session.albums }
        return session.albums.filter { session.label($0).localizedCaseInsensitiveContains(q) }
    }

    /// What's typed names no album yet, so ↵ or + makes one.
    private var canCreate: Bool {
        let q = albumQuery.trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && !session.albums.contains {
            ($0.localizedTitle ?? "").localizedCaseInsensitiveCompare(q) == .orderedSame
        }
    }

    private func submitQuery(_ asset: PHAsset) {
        let q = albumQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let matches = shownAlbums
        if matches.count == 1 {
            Task { await session.pick(asset, album: matches[0]) }
        } else if canCreate {
            Task { await session.createAlbumAndAdd(name: q, asset: asset) }
        } else { return }
        albumQuery = ""
    }

    /// One search box that finds an album or makes a new one, the five in use
    /// in a row of their own, then every other album, small enough to scan.
    private func albumChips(for asset: PHAsset) -> some View {
        let recentIDs = Set(AlbumRecency.recentIDs(AlbumRecency.settled))
        let searching = !albumQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let albums = shownAlbums
        let recent = searching ? [] : albums.filter { recentIDs.contains($0.localIdentifier) }
        let rest = searching ? albums : albums.filter { !recentIDs.contains($0.localIdentifier) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.table.muted)
                TextField("Find or add an album", text: $albumQuery)
                    .focused($searchFocused)
                    .font(.row)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { submitQuery(asset) }
                if canCreate {
                    Button { submitQuery(asset) } label: {
                        Label("Add", systemImage: "plus").font(.note)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.table.accent)
                    .accessibilityLabel("Add album \(albumQuery)")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .overlay(Capsule().stroke(Theme.table.rule, lineWidth: 1))

            if !recent.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recent, id: \.localIdentifier) { chip($0, asset) }
                    }
                }
            }
            ScrollView {
                FlowLayout(spacing: 6) {
                    ForEach(rest, id: \.localIdentifier) { chip($0, asset) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if albums.isEmpty && searching {
                    Text(canCreate ? "↵ adds \u{201C}\(albumQuery.trimmingCharacters(in: .whitespaces))\u{201D}" : "No album matches")
                        .font(.note).foregroundStyle(Theme.table.muted)
                }
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, Theme.Space.bar)
        .frame(maxHeight: 300)
    }

    private func chip(_ album: PHAssetCollection, _ asset: PHAsset) -> some View {
        let added = session.isAdded(album: album, to: asset)
        return Button {
            Task { await session.pick(asset, album: album) }
        } label: {
            HStack(spacing: 4) {
                if added { Image(systemName: "checkmark").font(.small) }
                Text(album.localizedTitle ?? "Album").lineLimit(1).layoutPriority(1)
                // Photos hides an album in its folder; the folder tells twins apart.
                if let folder = session.folder(of: album) {
                    Text(folder).font(.small).opacity(0.55)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 110, alignment: .leading)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(session.label(album))
        }
        // In it already: inked in, like the one pill on a screen.
        .buttonStyle(AlbumChipStyle(added: added))
        .accessibilityHint(session.singleAlbum ? "Files the photo here and moves to the next"
                           : added ? "Takes the photo out of this album" : "Adds the photo to this album")
    }

    private var controls: some View {
        BottomBar {
            HStack(spacing: Theme.Space.actions) {
                Button {
                    session.skip()
                } label: {
                    Label("Skip", systemImage: "forward.end").frame(maxWidth: .infinity)
                }
                .buttonStyle(.outline)

                Button {
                    session.next()
                } label: {
                    Label("Next", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill)

                Button { onFinish() } label: {
                    Text("Done")
                }
                .buttonStyle(.text)
            }
        }
    }
}

/// An album to file into: a hairline capsule, filled with ink once the photo's in it.
private struct AlbumChipStyle: ButtonStyle {
    let added: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.note)
            .foregroundStyle(added ? Theme.table.paper : Theme.table.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(added ? Theme.table.ink : .clear, in: Capsule())
            .overlay(Capsule().stroke(added ? .clear : Theme.table.rule, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.55 : 1)
            .contentShape(Capsule())
    }
}

/// Organise's photo, zoomable the way Triage's is (PhotoZoom), without the
/// swipes: pinch or double-tap to zoom, one finger moves it while zoomed.
private struct OrganisePhoto: View {
    let asset: PHAsset
    let onTap: () -> Void
    @State private var zoom = PhotoZoom()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let box = geo.size
            PhotoAssetImage(asset: asset, targetSize: CGSize(width: box.width * 2 * CGFloat(zoom.detail),
                                                             height: box.height * 2 * CGFloat(zoom.detail)),
                            contentMode: .fit)
                .frame(width: box.width, height: box.height)
                .scaleEffect(zoom.scale * zoom.shrink)
                .offset(zoom.pan)
                .frame(width: box.width, height: box.height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    animated { zoom.doubleTap(at: fromMiddle(location, box), in: box) }
                }
                .onTapGesture { onTap() }
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { value in if zoom.isZoomed { zoom.drag(by: value.translation, in: box) } }
                    .onEnded { _ in zoom.endDrag() },
                    including: zoom.isZoomed ? .all : .subviews)
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { value in
                        zoom.pinch(by: value.magnification, around: fromMiddle(value.startLocation, box), in: box)
                    }
                    .onEnded { _ in animated { _ = zoom.endPinch(in: box) } })
                .accessibilityAction(named: zoom.isZoomed ? "Zoom out" : "Zoom in") {
                    zoom.doubleTap(at: .zero, in: box)
                }
        }
    }

    private func fromMiddle(_ point: CGPoint, _ box: CGSize) -> CGPoint {
        CGPoint(x: point.x - box.width / 2, y: point.y - box.height / 2)
    }

    private func animated(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(Theme.Motion.snap, change) }
    }
}
