import SwiftUI

/// Keyboard-shortcut reference, mirroring the web app's "?" help overlay.
/// Most relevant on Mac and iPad with a hardware keyboard.
struct ShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        ("← / →", "Navigate media in the viewer"),
        ("Esc", "Close what's on top, step back, then Triage"),
        ("Esc", "Leave a field, keeping its text"),
        ("P", "Toggle slideshow"),
        ("1 or ←", "Pick left (comparison mode)"),
        ("2 or →", "Pick right (comparison mode)"),
        ("Space", "Skip / Tie (comparison mode)"),
        ("Double-tap", "Zoom an image in the viewer"),
        ("1-5 / 0", "Folders: set stars / clear them"),
        ("6 7 8 9", "Folders: red, yellow, green, blue; again to clear"),
        ("K", "Folders: keywords"),
        ("⌘⌫", "Folders: Trash all red"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Keyboard Shortcuts") {
                    ForEach(shortcuts, id: \.1) { key, action in
                        HStack {
                            Text(key)
                                .font(.callout.monospaced())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            Spacer()
                            Text(action)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .navigationTitle("Help")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .escapeScreen { dismiss() }
    }
}
