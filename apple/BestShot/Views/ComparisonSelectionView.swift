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
            VStack(spacing: 16) {
                Text("What would you like to rank?")
                    .font(.headline)

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

                Spacer()
            }
            .padding()
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
    }

    private func optionLabel(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 40)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
