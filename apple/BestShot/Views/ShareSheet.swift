import SwiftUI

#if os(iOS)
import UIKit

/// Wraps `UIActivityViewController` for sharing exported files on iOS/iPadOS.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#else
import AppKit

/// On macOS, present the standard sharing picker anchored to a small view.
struct ShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Export ready")
                .font(.sectionTitle)
            Text(url.lastPathComponent)
                .font(.note)
                .foregroundStyle(Theme.table.muted)
            HStack {
                ShareLink(item: url) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.pill)
            }
            .buttonStyle(.text)
        }
        .padding(28)
        .tableSurface()
        .frame(minWidth: 360)
    }
}
#endif
