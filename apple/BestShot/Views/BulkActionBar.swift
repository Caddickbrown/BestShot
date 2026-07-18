import SwiftUI

/// Bottom bar shown in selection mode, mirroring the web app's bulk-action bar:
/// add tag, download ZIP, delete.
struct BulkActionBar: View {
    let count: Int
    let onTag: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text("\(count) selected")
                .font(.subheadline.weight(.medium))

            Spacer()

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
            .disabled(count == 0)

            Button("Cancel", action: onCancel)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding()
    }
}
