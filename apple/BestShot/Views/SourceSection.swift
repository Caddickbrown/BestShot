import SwiftUI
import Photos

/// What to go through, on the Triage and Organise start screens: rows for the
/// common sets, so Screenshots and the like are in plain sight, then any album,
/// found by typing its name. Empty albums never show, and ↵ starts. On iOS, once a
/// source is chosen the list folds into one row showing it, with its count and a
/// chevron; tapping that opens the list again (see `SourceFold`).
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
    @State private var fold: SourceFold
    /// How many photos each of the common sets holds, once counted.
    @State private var quickCounts: [TriageSourceOption: Int] = [:]

    init(source: Binding<TriageSourceOption>, albums: [PHAssetCollection],
         folders: [String: String] = [:], counts: [String: Int]? = nil,
         onStart: @escaping () -> Void = {}) {
        _source = source
        self.albums = albums
        self.folders = folders
        self.counts = counts
        self.onStart = onStart
        _fold = State(initialValue: SourceFold(source: source.wrappedValue))
    }

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
        #if os(iOS)
        TableSection("Go through") {
            if fold.open {
                ForEach(TriageSourceOption.quick, id: \.self) { quickRow($0) }
            } else {
                foldedRow
            }
        }
        .task {
            quickCounts = await Task.detached { SourceSection.countQuick() }.value
        }
        if fold.open { albumSection }
        #else
        TableSection("Go through") {
            Picker("Source", selection: $source) {
                ForEach(TriageSourceOption.quick, id: \.self) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        albumSection
        #endif
    }

    @ViewBuilder
    private var albumSection: some View {
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

    // MARK: Folding

    /// What is chosen, by name: an album by its own (and its folder's).
    private var chosenTitle: String {
        if let chosenAlbum {
            return AlbumList.label(title: chosenAlbum.localizedTitle, folder: folder(chosenAlbum))
        }
        return source.title
    }

    private var chosenCount: Int? {
        if let chosenAlbum { return count(chosenAlbum) }
        return quickCounts[source]
    }

    /// The list folded up: the source chosen, its count, and a chevron to open it.
    private var foldedRow: some View {
        Button {
            Theme.Motion.run(Theme.Motion.settle) { fold.reopen() }
        } label: {
            HStack(spacing: 10) {
                Label(chosenTitle, systemImage: source.symbol)
                    .lineLimit(1)
                Spacer()
                if let n = chosenCount {
                    Text("\(n)").font(.small).foregroundStyle(Theme.table.muted)
                }
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.table.dim)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows every source, to choose another")
    }

    /// One of the common sets, as a row: tapping it chooses it and folds the list.
    private func quickRow(_ option: TriageSourceOption) -> some View {
        let chosen = source == option
        return Button {
            choose(option)
        } label: {
            HStack(spacing: 10) {
                Label(option.title, systemImage: option.symbol)
                    .lineLimit(1)
                Spacer()
                if let n = quickCounts[option] {
                    Text("\(n)").font(.small).foregroundStyle(Theme.table.muted)
                }
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.table.accent)
                    .opacity(chosen ? 1 : 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func choose(_ option: TriageSourceOption) {
        source = option
        query = ""
        Theme.Motion.run(Theme.Motion.settle) { fold.choose() }
    }

    /// Photos in each of the common sets, counted as the album counts are.
    nonisolated static func countQuick() -> [TriageSourceOption: Int] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        var out: [TriageSourceOption: Int] = [:]
        for option in TriageSourceOption.quick {
            switch option {
            case .allPhotos:
                out[option] = PHAsset.fetchAssets(with: options).count
            case .smart(let smart):
                if let set = PHAssetCollection.fetchAssetCollections(
                    with: .smartAlbum, subtype: smart.subtype, options: nil).firstObject {
                    out[option] = PHAsset.fetchAssets(in: set, options: options).count
                }
            case .album:
                break
            }
        }
        return out
    }

    private func row(_ album: PHAssetCollection) -> some View {
        let chosen = chosenAlbum?.localIdentifier == album.localIdentifier
        return Button {
            #if os(iOS)
            // Chosen already or not, a tap settles on it and folds the list.
            choose(.album(album.localIdentifier))
            #else
            source = chosen ? .allPhotos : .album(album.localIdentifier)
            query = ""
            #endif
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
            .frame(minHeight: 44)
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
            fold.choose()
        }
        onStart()
    }
}
