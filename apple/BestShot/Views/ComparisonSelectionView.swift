import SwiftUI

/// Lets the user choose whether to compare all items or only place the new
/// (unranked) ones, mirroring the web app's comparison-scope modal.
struct ComparisonSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let allCount: Int
    let unrankedCount: Int
    let onSelect: (ComparisonScope) -> Void

    private var canCompareUnranked: Bool {
        unrankedCount >= 1 && allCount >= 2 && unrankedCount < allCount
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("What would you like to rank?")
                    .font(.sectionTitle)
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.top, Theme.Space.headerTop)
                    .padding(.bottom, Theme.Space.stack)
                HairlineRule()

                Button {
                    onSelect(.all)
                    dismiss()
                } label: {
                    optionLabel(
                        title: "All Items",
                        subtitle: "\(allCount) item\(allCount == 1 ? "" : "s")",
                        systemImage: "square.stack.3d.up"
                    )
                }
                .buttonStyle(.plain)
                HairlineRule()

                Button {
                    onSelect(.unranked)
                    dismiss()
                } label: {
                    optionLabel(
                        title: "New Items Only",
                        subtitle: "\(unrankedCount) new item\(unrankedCount == 1 ? "" : "s")",
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canCompareUnranked)
                .opacity(canCompareUnranked ? 1 : 0.4)
                HairlineRule()

                Spacer()
            }
            .tableSurface()
            .navigationTitle("Comparison Mode")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .escapeScreen { dismiss() }
    }

    /// A row on the table, between hairlines.
    private func optionLabel(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Theme.table.muted)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.mono(15, medium: true))
                Text(subtitle).font(.eyebrow).foregroundStyle(Theme.table.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.table.dim)
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
