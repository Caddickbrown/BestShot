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

    var body: some View {
        VStack(spacing: 0) {
            header

            if let asset = session.current {
                PhotoAssetImage(asset: asset, contentMode: .fit)
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
            Text("\(min(session.index + 1, session.assets.count)) / \(session.assets.count)")
                .font(.small)
                .foregroundStyle(Theme.table.muted)
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, 8)
    }

    private func albumChips(for asset: PHAsset) -> some View {
        ScrollView {
            FlowLayout(spacing: 8) {
                Button {
                    showNewAlbum = true
                } label: {
                    Label("New Album", systemImage: "plus")
                        .foregroundStyle(Theme.table.accent)
                }
                .buttonStyle(.outline)

                ForEach(session.albums, id: \.localIdentifier) { album in
                    let added = session.isAdded(album: album, to: asset)
                    Button {
                        Task { await session.add(asset, to: album) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: added ? "checkmark" : "rectangle.stack")
                            Text(album.localizedTitle ?? "Album").lineLimit(1)
                            // Photos hides an album in its folder; the folder tells twins apart.
                            if let folder = session.folder(of: album) {
                                Text("· \(folder)").opacity(0.6).lineLimit(1)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(session.label(album))
                    }
                    // In it already: inked in, like the one pill on a screen.
                    .buttonStyle(AlbumChipStyle(added: added))
                    .disabled(added)
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.bar)
        }
        .frame(maxHeight: 160)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(added ? Theme.table.ink : .clear, in: Capsule())
            .overlay(Capsule().stroke(added ? .clear : Theme.table.rule, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.55 : 1)
            .contentShape(Capsule())
    }
}
