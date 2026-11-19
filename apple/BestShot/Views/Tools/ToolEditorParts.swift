import SwiftUI
#if os(macOS)
import AppKit
#endif

// Parts Glue and Multi Crop share: icon buttons, the zoomable canvas, and the
// bar that saves or shares what was made.

/// An action with a clear icon: a 44 pt target, an accessible label, and the
/// label (and key) as a tooltip (guide: icons over text).
struct ToolIcon: View {
    let label: String
    let symbol: String
    var key: String? = nil
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .frame(width: 44, height: 44)
                .foregroundStyle(active ? Theme.table.accent : Theme.table.ink)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(key.map { "\(label) (\($0))" } ?? label)
        .accessibilityLabel(label)
    }
}

/// A canvas that zooms freely: pinch, ⌘+ / ⌘−, ⌘0 or the icon to fit. `zoom`
/// is relative to fit (1 = the whole thing in view). Drawing gestures belong
/// to the content; on touch, `panning` hands one-finger drags to scrolling.
struct ZoomCanvas<Content: View>: View {
    /// The content's size in its own units (pixels).
    let size: CGSize
    @Binding var zoom: CGFloat
    var panning = false
    @ViewBuilder var content: (_ scale: CGFloat) -> Content

    @State private var pinchStart: CGFloat?
    static var range: ClosedRange<CGFloat> { 0.2...12 }

    var body: some View {
        GeometryReader { box in
            let fit = max(0.0001, min(box.size.width / max(size.width, 1), box.size.height / max(size.height, 1)))
            let scale = fit * zoom
            let w = size.width * scale, h = size.height * scale
            ScrollView([.horizontal, .vertical], showsIndicators: zoom > 1) {
                content(scale)
                    .frame(width: w, height: h)
                    .frame(width: max(w, box.size.width), height: max(h, box.size.height))
                    .allowsHitTesting(!panning)
            }
            .scrollDisabled(zoom <= 1 && !panning)
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? zoom
                        pinchStart = start
                        zoom = min(max(start * value.magnification, Self.range.lowerBound), Self.range.upperBound)
                    }
                    .onEnded { _ in pinchStart = nil }
            )
        }
        .background(Theme.table.tile)
        .clipped()
    }

    static func step(_ zoom: CGFloat, _ command: CanvasZoomCommand) -> CGFloat {
        switch command {
        case .zoomIn: return min(range.upperBound, zoom * 1.25)
        case .zoomOut: return max(range.lowerBound, zoom / 1.25)
        case .fit: return 1
        }
    }
}

/// Once files are made: Share and Save to Photos (iPhone, iPad), or Save to a
/// folder (Mac Tools). In Folders the files are already beside the source,
/// so this says so and offers Undo.
struct ToolMadeBar: View {
    let urls: [URL]
    let notice: String?
    let beside: Bool
    let takeBack: () -> Void

    @State private var saving = false
    @State private var saved = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Space.actions) {
                if let notice { Text(notice).font(.note).foregroundStyle(Theme.table.muted).lineLimit(1) }
                Spacer()
                if beside {
                    Button("Undo", action: takeBack).buttonStyle(.text)
                } else {
                    ShareLink(items: urls) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }
                        .buttonStyle(.plain)
                        .help("Share")
                        .accessibilityLabel("Share")
                    #if os(macOS)
                    Button("Save to Folder…") { saveToFolder() }.buttonStyle(.pill)
                    #else
                    Button(saved ? "Saved to Photos" : saving ? "Saving…" : "Save to Photos") { save() }
                        .buttonStyle(.pill)
                        .disabled(saving || saved)
                    #endif
                }
            }
            if let message { FormNote(message) }
        }
        .onChange(of: urls) {
            saved = false
            message = nil
        }
    }

    private func save() {
        saving = true
        message = nil
        Task {
            var ok = true
            for url in urls { ok = await PhotoLibraryService.shared.saveFile(url, isVideo: false) && ok }
            saving = false
            saved = ok
            if !ok { message = "Couldn't save. Allow BestShot to add to Photos in Settings." }
        }
    }

    #if os(macOS)
    private func saveToFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        var done = 0
        for url in urls {
            let stem = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let taken = Set(ToolImaging.names(in: folder).map { ($0 as NSString).deletingPathExtension.lowercased() })
            var name = stem
            var n = 2
            while taken.contains(name.lowercased()) { name = "\(stem)-\(n)"; n += 1 }
            if (try? ToolImaging.publish(url, as: "\(name).\(ext)", in: folder)) != nil { done += 1 }
        }
        message = done == urls.count ? "Saved to \(folder.lastPathComponent)." : "Saved \(done) of \(urls.count)."
    }
    #endif
}

/// The ⋯ options menu: the output format (JPEG unless chosen otherwise).
struct ToolOptionsMenu: View {
    @Binding var format: ToolOutputFormat

    var body: some View {
        Menu {
            Picker("Save as", selection: $format) {
                ForEach(ToolOutputFormat.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Options")
        .accessibilityLabel("Options")
    }
}
