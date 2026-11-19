import SwiftUI

/// Shown once after an update (guide: every release has notes, on the device
/// too). The text matches the newest CHANGELOG.md entry.
enum WhatsNew {
    static let id = "2026-11-19-glue-multicrop"
    static let title = "Multi Crop and Glue"
    static let lines = [
        "Multi Crop pulls several photos out of one image, such as a scanned page of prints. Use last crop (L) repeats the boxes on the next scan.",
        "Glue joins 2 to 10 photos: side by side, stacked, in a grid, or placed freely on a colour or blurred background, with a soft fade at the seams.",
        "Turn any photo or box before saving with R. New files keep the date, location and keywords, never stars or labels, and the originals are never changed.",
    ]
    private static let key = "whatsNew.seen"

    static var unseen: Bool {
        UserDefaults.standard.string(forKey: key) != id
    }
    static func markSeen() { UserDefaults.standard.set(id, forKey: key) }
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.section) {
            VStack(alignment: .leading, spacing: Theme.Space.eyebrowGap) {
                Text("What's new").font(.eyebrow).foregroundStyle(Theme.table.muted)
                Text(WhatsNew.title).font(.panelTitle).foregroundStyle(Theme.table.ink)
            }
            VStack(alignment: .leading, spacing: Theme.Space.stack) {
                ForEach(WhatsNew.lines, id: \.self) { line in
                    Text(line).font(.note).foregroundStyle(Theme.table.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Got it") { dismiss() }.buttonStyle(.pill)
            }
        }
        .padding(Theme.Space.panel)
        .frame(maxWidth: 520)
        .background(Theme.table.background)
        .onDisappear { WhatsNew.markSeen() }
        .escapeScreen { dismiss() }
    }
}
