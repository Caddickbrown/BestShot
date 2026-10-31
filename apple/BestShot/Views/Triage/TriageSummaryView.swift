import SwiftUI

/// End-of-session summary. Shows the tally and, if any photos are marked for
/// deletion, a single button that triggers the one system delete confirmation.
struct TriageSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showRank) private var showRank
    @Bindable var session: TriageSession
    /// Called when the session should end (after committing / nothing to do).
    let onCommit: () -> Void
    /// Called to return to triaging without finishing.
    let onKeepGoing: () -> Void

    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.accent)

                Text("Session summary").font(.title2.bold())

                HStack(spacing: 28) {
                    stat("\(session.keptCount)", "Kept", .green)
                    stat("\(session.deleteCount)", "To delete", .red)
                    stat("\(session.favouriteCount)", "Favourited", .pink)
                }

                if session.deleteCount > 0 {
                    Text("Deleting moves \(session.deleteCount) photo\(session.deleteCount == 1 ? "" : "s") to Recently Deleted (recoverable for 30 days).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        commit()
                    } label: {
                        Label("Delete \(session.deleteCount) Photo\(session.deleteCount == 1 ? "" : "s")",
                              systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isDeleting)
                } else {
                    Text("Nothing marked for deletion.")
                        .foregroundStyle(.secondary)
                    Button("Finish") { onCommit(); dismiss() }
                        .buttonStyle(.borderedProminent)
                }

                if session.keptCount > 1 {
                    // Keepers are saved as you go; pending deletions stay pending.
                    Button("Rank your keepers") {
                        onKeepGoing()
                        dismiss()
                        showRank()
                    }
                    .buttonStyle(.text)
                }

                if !session.isComplete {
                    Button("Keep triaging") { onKeepGoing(); dismiss() }
                }

                if isDeleting { ProgressView() }
            }
            .padding()
            .navigationTitle("Finish")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { onKeepGoing(); dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 420)
        .interactiveDismissDisabled(isDeleting)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack {
            Text(value).font(.title.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func commit() {
        isDeleting = true
        Task {
            _ = await session.commitDeletions()
            isDeleting = false
            onCommit()
            dismiss()
        }
    }
}
