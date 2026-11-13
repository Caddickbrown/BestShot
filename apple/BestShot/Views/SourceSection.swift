import SwiftUI
import Photos

/// What to go through, on the Triage and Organise start screens: rows for the
/// common sets, so Screenshots and the like are in plain sight, then any album,
/// found by typing its name. Empty albums never show, and ↵ starts.
struct SourceSection: View {
    @Binding var source: TriageSourceOption
    let albums: [PHAssetCollection]
    /// Album id → its folder, so two albums with one name read apart.
    var folders: [String: String] = [:]
    /// Album id → how many photos it holds. Until it's known, no album shows.
    var counts: [String: Int]?
    /// ↵ in the album field: start with what's chosen.
    var onStart: () -> Void = {}

    @State private var query = ""

    private func title(_ album: PHAssetCollection) -> String? { album.localizedTitle }
    private func folder(_ album: PHAssetCollection) -> String? { folders[album.localIdentifier] }
    private func count(_ album: PHAssetCollection) -> Int? { counts?[album.localIdentifier] }

    private var typing: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var matches: [PHAssetCollection] {
        AlbumList.sources(albums, query: query, title: title, folder: folder, count: count)
    }

    private var chosenAlbum: PHAssetCollection? {
        guard case .album(let id) = source else { return nil }
        return albums.first { $0.localIdentifier == id }
    }

    var body: some View {
        TableSection("Go through") {
            Picker("Source", selection: $source) {
                ForEach(TriageSourceOption.quick, id: \.self) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        if !albums.isEmpty {
            TableSection(title: "Or an album") {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.table.muted)
                    EscapingField(placeholder: "Type an album's name", text: $query, onSubmit: submit)
                }
                if typing {
                    let shown = matches
                    ForEach(shown.prefix(40), id: \.localIdentifier) { row($0) }
                    if shown.isEmpty {
                        FormNote(counts == nil ? "Counting photos in your albums…" : "No album with photos matches.")
                    } else if shown.count > 40 {
                        FormNote("\(shown.count - 40) more: keep typing.")
                    }
                } else if let chosenAlbum {
                    row(chosenAlbum)
                }
            } footer: {
                FormNote(typing ? "↵ starts with the album named, or the only one that matches."
                         : "Empty albums aren't listed.")
            }
        }
    }

    private func row(_ album: PHAssetCollection) -> some View {
        let chosen = chosenAlbum?.localIdentifier == album.localIdentifier
        return Button {
            source = chosen ? .allPhotos : .album(album.localIdentifier)
            query = ""
        } label: {
            HStack {
                Label(AlbumList.label(title: album.localizedTitle, folder: folder(album)),
                      systemImage: TriageSourceOption.album("").symbol)
                    .lineLimit(1)
                Spacer()
                if let n = count(album) {
                    Text("\(n)").font(.small).foregroundStyle(Theme.table.muted)
                }
                if chosen {
                    Image(systemName: "checkmark").foregroundStyle(Theme.table.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// ↵: the album typed, if it's clear which, then start. With nothing typed,
    /// start with what's chosen.
    private func submit() {
        if typing {
            guard let album = AlbumList.sourceToStart(albums, query: query, title: title, folder: folder, count: count)
            else { return }
            source = .album(album.localIdentifier)
            query = ""
        }
        onStart()
    }
}
