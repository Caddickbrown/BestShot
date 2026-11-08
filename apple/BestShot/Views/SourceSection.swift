import SwiftUI
import Photos

/// What to go through, on the Triage and Organise start screens: rows for the
/// common sets, so Screenshots and the like are in plain sight, then any album.
struct SourceSection: View {
    @Binding var source: TriageSourceOption
    let albums: [PHAssetCollection]
    /// Album id → its folder, so two albums with one name read apart.
    var folders: [String: String] = [:]

    var body: some View {
        TableSection("Go through") {
            Picker("Source", selection: $source) {
                ForEach(TriageSourceOption.quick, id: \.self) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if !albums.isEmpty {
                Picker(selection: album) {
                    Text("None").tag(String?.none)
                    ForEach(albums, id: \.localIdentifier) { album in
                        Text(AlbumList.label(title: album.localizedTitle, folder: folders[album.localIdentifier]))
                            .tag(Optional(album.localIdentifier))
                    }
                } label: {
                    Label("Album", systemImage: TriageSourceOption.album("").symbol)
                }
            }
        }
    }

    private var album: Binding<String?> {
        Binding {
            if case .album(let id) = source { return id }
            return nil
        } set: { id in
            source = id.map(TriageSourceOption.album) ?? .allPhotos
        }
    }
}
