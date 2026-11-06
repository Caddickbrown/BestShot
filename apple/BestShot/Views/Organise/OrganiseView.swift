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
                    .padding(12)

                albumChips(for: asset)
                controls
            } else {
                ContentUnavailableView("All organised", systemImage: "checkmark.circle")
                    .frame(maxHeight: .infinity)
            }
        }
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
            ProgressView(value: session.progress)
            Text("\(min(session.index + 1, session.assets.count)) / \(session.assets.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func albumChips(for asset: PHAsset) -> some View {
        ScrollView {
            FlowLayout(spacing: 8) {
                Button {
                    showNewAlbum = true
                } label: {
                    Label("New Album", systemImage: "plus")
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.accent.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)

                ForEach(session.albums, id: \.localIdentifier) { album in
                    let added = session.isAdded(album: album, to: asset)
                    Button {
                        Task { await session.add(asset, to: album) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: added ? "checkmark.circle.fill" : "rectangle.stack")
                            Text(album.localizedTitle ?? "Album").lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(added ? Color.green.opacity(0.25) : Color.secondary.opacity(0.15),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(added)
                }
            }
            .padding()
        }
        .frame(maxHeight: 160)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                session.skip()
            } label: {
                Label("Skip", systemImage: "forward.end").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                session.next()
            } label: {
                Label("Next", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button { onFinish() } label: {
                Text("Done")
            }
        }
        .controlSize(.large)
        .padding()
    }
}
