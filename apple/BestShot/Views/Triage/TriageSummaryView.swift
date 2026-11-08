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
            VStack(spacing: Theme.Space.section) {
                GreasePencilMark(shape: .circle, lineWidth: 3)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                Text("Session summary").font(.sectionTitle)

                HStack(spacing: Theme.Space.tabs + 6) {
                    stat("\(session.keptCount)", "Kept", Theme.table.ink)
                    stat("\(session.deleteCount)", "To delete", Theme.table.accent)
                    stat("\(session.favouriteCount)", "Favourited", Theme.table.muted)
                }

                if session.deleteCount > 0 {
                    Text("Deleting moves \(session.deleteCount) photo\(session.deleteCount == 1 ? "" : "s") to Recently Deleted (recoverable for 30 days).")
                        .font(.note)
                        .foregroundStyle(Theme.table.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        commit()
                    } label: {
                        Label("Delete \(session.deleteCount) Photo\(session.deleteCount == 1 ? "" : "s")",
                              systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill)
                    .disabled(isDeleting)
                } else {
                    Text("Nothing marked for deletion.")
                        .font(.note)
                        .foregroundStyle(Theme.table.muted)
                    Button("Finish") { onCommit(); dismiss() }
                        .buttonStyle(.pill)
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
                        .buttonStyle(.text)
                }

                if isDeleting { ProgressView().tint(Theme.table.accent) }
            }
            .padding(Theme.Space.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tableSurface()
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
        .escapeScreen {
            guard !isDeleting else { return }
            onKeepGoing()
            dismiss()
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.panelTitle).monospacedDigit().foregroundStyle(color)
            Text(label).font(.small).foregroundStyle(Theme.table.muted)
        }
        .accessibilityElement(children: .combine)
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
