#if os(macOS)
import SwiftUI

// Folders' way into Glue and Multi Crop: the icons in the top bar, the bar
// that shows what's chosen, and the sheet the editor opens in. New files go
// beside the photos; the folder is scanned again to show them.

/// An icon in Folders' top bar: 44 pt, a label, and the key as a tooltip.
struct FolderToolButton: View {
    let label: String
    let symbol: String
    let key: String
    let palette: Theme.Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.ink)
        .help("\(label) (\(key))")
        .accessibilityLabel(label)
    }
}

/// Along the bottom of the grid while photos are chosen.
struct FolderSelectionBar: View {
    @Bindable var session: FolderCullSession

    var body: some View {
        HStack(spacing: Theme.Space.actions) {
            Text("\(session.selection.count) selected").font(.mono(13, medium: true))
            Spacer()
            FolderToolButton(label: "Glue", symbol: "rectangle.split.2x1.fill", key: "⌥⌘G", palette: Theme.table) { session.openGlue() }
                .disabled(session.selection.count < 2)
            Button("Clear") { session.clearSelection() }.buttonStyle(.text)
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, 4)
        .background(Theme.table.background)
        .overlay(alignment: .top) { HairlineRule() }
    }
}

/// The editor over the folder, writing beside the photos.
struct FolderToolSheet: View {
    let session: FolderCullSession
    let request: FolderCullSession.ToolRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch request.kind {
            case .multiCrop:
                MultiCropView(initial: request.urls.first, beside: request.folder, keywords: request.keywords.first ?? [],
                              onMade: made, onClose: { dismiss() })
            case .glue:
                GlueView(initial: request.urls, beside: request.folder, keywords: request.keywords,
                         onMade: made, onClose: { dismiss() })
            }
        }
        .frame(minWidth: 960, idealWidth: 1200, minHeight: 680, idealHeight: 860)
    }

    private func made(_ urls: [URL], _ text: String) {
        session.madeFiles(urls, text, showFirst: request.kind == .glue)
        // Glue closes and the new photo shows; Multi Crop's source stays current.
        dismiss()
    }
}
#endif
