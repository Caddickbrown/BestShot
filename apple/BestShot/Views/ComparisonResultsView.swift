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
                            RankNumber(rank: index + 1)
                                .frame(width: 44, alignment: .leading)
                            AsyncFileImage(url: item.thumbnailURL ?? item.fileURL,
                                           downsampleTo: 160, contentMode: .fill)
                                .frame(width: 48, height: 48)
                                .background(Theme.table.tile)
                                .clipped()
                            Text(item.filename).lineLimit(1)
                        }
                        .listRowBackground(Theme.table.paper)
                    }
                } header: {
                    SheetLabel("\(session.comparisonsAsked) comparisons · \(session.comparisonsSkipped) inferred")
                }
            }
            .tableForm()
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
        // As in Rank's Compare, Esc saves. Discard is the way to throw it away.
        .escapeScreen {
            onApply()
            dismiss()
        }
    }
}
