import SwiftUI

/// Bottom bar shown in selection mode, mirroring the web app's bulk-action bar:
/// add tag, download ZIP, delete. With two or more videos chosen, Join opens
/// them in Join Videos.
struct BulkActionBar: View {
    let count: Int
    /// Nil hides Join: fewer than two videos chosen, or on the Mac.
    var onJoin: (() -> Void)? = nil
    let onTag: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.actions) {
            Text("\(count) selected")
                .font(.mono(13, medium: true))

            Spacer()

            if let onJoin {
                Button(action: onJoin) {
                    Label("Join Videos", systemImage: "film.stack")
                }
            }

            Button(action: onTag) {
                Label("Tag", systemImage: "tag")
            }
            .disabled(count == 0)

            Button(action: onDownload) {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .disabled(count == 0)

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(TextButtonStyle(destructive: true))
            .disabled(count == 0)

            Button("Cancel", action: onCancel)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.text)
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, Theme.Space.bar)
        .background(Theme.table.background)
        .overlay(alignment: .top) { HairlineRule() }
    }
}
