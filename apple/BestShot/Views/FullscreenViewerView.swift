import SwiftUI
import AVKit

/// Fullscreen media viewer: paging with arrows/keys, pinch-zoom for images,
/// inline video playback, an info panel (EXIF, size), and editable tags +
/// comment. Slideshow auto-advances images. Mirrors the web app's viewer.
struct FullscreenViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let items: [MediaItem]
    @State private var index: Int
    @State private var showInfo = false
    @State private var slideshow = false
    @State private var zoom: CGFloat = 1
    @State private var newTag = ""
    /// The photo open in Anti-Crop, over the viewer.
    @State private var antiCrop: AntiCropRequest?

    private let slideshowInterval: TimeInterval = 3

    init(items: [MediaItem], initial: MediaItem) {
        self.items = items
        _index = State(initialValue: items.firstIndex(where: { $0.uuid == initial.uuid }) ?? 0)
    }

    private var current: MediaItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let item = current {
                mediaView(item)
                    .id(item.uuid)
            }

            controlsOverlay

            if showInfo, let item = current {
                infoPanel(item)
                    .transition(.move(edge: .trailing))
            }
        }
        .viewfinder()
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
        .background {
            Group {
                Button("") { previous() }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { next() }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { escape() }.keyboardShortcut(.escape, modifiers: [])
                Button("") { slideshow.toggle() }.keyboardShortcut("p", modifiers: [])
            }
            .opacity(0)
        }
        .escapeScreen(escape)
        .sheet(item: $antiCrop) { request in
            ToolSheet { AntiCropView(initial: request.url) }
        }
        .task(id: slideshow) {
            guard slideshow else { return }
            while slideshow && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(slideshowInterval * 1_000_000_000))
                if slideshow { next() }
            }
        }
    }

    // MARK: - Media

    @ViewBuilder
    private func mediaView(_ item: MediaItem) -> some View {
        if item.mediaType == .video {
            VideoPlayer(player: AVPlayer(url: item.fileURL))
                .ignoresSafeArea()
        } else {
            AsyncFileImage(url: item.fileURL, contentMode: .fit)
                .scaleEffect(zoom)
                .gesture(
                    MagnificationGesture()
                        .onChanged { zoom = max(1, min($0, 5)) }
                        .onEnded { _ in if zoom < 1.05 { zoom = 1 } }
                )
                .onTapGesture(count: 2) {
                    withAnimation { zoom = zoom > 1 ? 1 : 2.5 }
                }
                .ignoresSafeArea()
        }
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack {
            HStack {
                Button { close() } label: {
                    Image(systemName: "xmark").padding(10)
                }
                Spacer()
                if let item = current {
                    Text(item.filename).font(.eyebrow).lineLimit(1)
                }
                Spacer()
                Button { slideshow.toggle() } label: {
                    Image(systemName: slideshow ? "pause.fill" : "play.fill").padding(10)
                }
                #if os(iOS)
                if let item = current, item.mediaType == .image {
                    Button {
                        slideshow = false
                        antiCrop = AntiCropRequest(url: item.fileURL)
                    } label: {
                        Image(systemName: "rectangle.split.2x1").padding(10)
                    }
                    .accessibilityLabel("Anti-Crop")
                }
                #endif
                Button { withAnimation { showInfo.toggle() } } label: {
                    Image(systemName: "info.circle").padding(10)
                }
            }
            .padding(.horizontal, 6)
            .background(Color.black.opacity(0.6))
            .overlay(alignment: .bottom) { HairlineRule(palette: Theme.viewfinder) }

            Spacer()

            HStack {
                Button { previous() } label: {
                    Image(systemName: "chevron.left").font(.title).padding()
                }
                .disabled(index == 0)
                Spacer()
                Text("\(index + 1) / \(items.count)")
                    .font(.eyebrow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                Spacer()
                Button { next() } label: {
                    Image(systemName: "chevron.right").font(.title).padding()
                }
                .disabled(index >= items.count - 1)
            }
            .padding(.horizontal)
        }
        .foregroundStyle(Theme.viewfinder.ink)
        .buttonStyle(.plain)
    }

    // MARK: - Info panel

    private func infoPanel(_ item: MediaItem) -> some View {
        HStack(spacing: 0) {
            Spacer()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Details").font(.barTitle)

                    row("File", item.filename)
                    row("Type", item.mediaType.rawValue.capitalized)
                    row("Size", item.formattedFileSize)
                    row("Imported", item.importedAt.formatted(date: .abbreviated, time: .shortened))
                    if let rank = item.rank { row("Rank", "#\(rank + 1)") }

                    if let exif = item.exif, !exif.isEmpty {
                        HairlineRule(palette: Theme.viewfinder)
                        SheetLabel("Camera", palette: Theme.viewfinder)
                        ForEach(exif.displayRows, id: \.0) { label, value in
                            row(label, value)
                        }
                    }

                    HairlineRule(palette: Theme.viewfinder)
                    tagsEditor(item)

                    HairlineRule(palette: Theme.viewfinder)
                    commentEditor(item)
                }
                .padding(Theme.Space.screen)
            }
            .frame(width: 300)
            .background(Theme.viewfinder.paper)
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.viewfinder.rule).frame(width: 1)
            }
        }
    }

    private func tagsEditor(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetLabel("Tags", palette: Theme.viewfinder)
            FlowLayout(spacing: 6) {
                ForEach(item.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag).font(.eyebrow)
                        Button {
                            item.tags.removeAll { $0 == tag }
                            try? context.save()
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .overlay(Capsule().stroke(Theme.viewfinder.rule, lineWidth: 1))
                }
            }
            HStack {
                EscapingField(placeholder: "Add tag", text: $newTag, bordered: true, onSubmit: addTag)
                Button("Add", action: addTag)
                    .buttonStyle(.viewfinderText)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func commentEditor(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetLabel("Notes", palette: Theme.viewfinder)
            EscapingEditor(text: Binding(
                get: { item.comment },
                set: { item.comment = $0; try? context.save() }
            ))
            .frame(minHeight: 100)
            .padding(.horizontal, 6)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.viewfinder.rule))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.small).foregroundStyle(Theme.viewfinder.muted)
            Text(value).font(.note)
        }
    }

    // MARK: - Actions

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        newTag = ""
        guard !tag.isEmpty, let item = current, !item.tags.contains(tag) else { return }
        item.tags.append(tag)
        try? context.save()
    }

    /// The panel first, then the viewer.
    private func escape() {
        if showInfo {
            withAnimation { showInfo = false }
        } else {
            close()
        }
    }

    /// A tag still being typed is added rather than lost.
    private func close() {
        addTag()
        dismiss()
    }

    private func next() {
        zoom = 1
        if index < items.count - 1 { index += 1 }
        else if slideshow { index = 0 } // loop during slideshow
    }

    private func previous() {
        zoom = 1
        if index > 0 { index -= 1 }
    }
}

/// A project photo on its way into Anti-Crop.
private struct AntiCropRequest: Identifiable {
    let id = UUID()
    let url: URL
}
