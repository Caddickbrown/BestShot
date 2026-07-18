import SwiftUI

/// Shows the proposed ranking after a comparison session and lets the user
/// apply it, mirroring the web app's "Apply Ranking" results modal.
struct ComparisonResultsView: View {
    @Environment(\.dismiss) private var dismiss
    let session: ComparisonSession
    let onApply: () -> Void

    private var items: [MediaItem] { session.finalItems() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(items.enumerated()), id: \.element.uuid) { index, item in
                        HStack(spacing: 12) {
                            Text("#\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .frame(width: 44, alignment: .leading)
                                .foregroundStyle(Theme.accent)
                            AsyncFileImage(url: item.thumbnailURL ?? item.fileURL,
                                           downsampleTo: 160, contentMode: .fill)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(item.filename).lineLimit(1)
                        }
                    }
                } header: {
                    Text("\(session.comparisonsAsked) comparisons · \(session.comparisonsSkipped) inferred")
                }
            }
            .navigationTitle("Proposed Ranking")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply Ranking") {
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 480)
    }
}
