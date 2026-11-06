import SwiftUI

/// App information. The look is fixed (light table + viewfinder), shared with
/// the Linux and web apps, so there's no theme setting.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var labels = LabelStore.shared
    /// Typed but not saved. Held by the root so Esc can close this and keep them.
    @Binding var names: [LabelColour: String]
    @State private var namesMessage: String?
    @State private var showingBridgeImport = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Colour labels") {
                    ForEach(LabelColour.allCases) { colour in
                        EscapingField(placeholder: colour.title, text: nameBinding(colour))
                    }
                    Button("Save label names", action: saveNames)
                    if let namesMessage {
                        Text(namesMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("The text written to xmp:Label for each colour. Files saved under an old name keep their colour.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                #if os(macOS)
                Section("Folders") {
                    Toggle("Also write into JPEGs", isOn: $labels.writeJPEG)
                    Text("Off by default: BestShot writes .xmp sidecars and leaves originals alone. Adobe apps ignore sidecars for JPEGs, so turn this on if they need to see your ratings. Writes are atomic and leave the image data byte-identical.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Import from Bridge…") { showingBridgeImport = true }
                }
                #endif
                Section("About") {
                    LabeledContent("App", value: "BestShot")
                    LabeledContent("Version", value: appVersion)
                    Text("Cull and rank your photos on-device. Ratings, labels and keywords are standard XMP. Folder decisions are saved in .bestshot-cull.json, shared with BestShot for Linux.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .lightTableList()
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 560)
        #if os(macOS)
        .sheet(isPresented: $showingBridgeImport) { BridgeImportView() }
        #endif
        .onChange(of: labels.revision) { names = [:] }
        .escapeScreen { dismiss() }
    }

    private func nameBinding(_ colour: LabelColour) -> Binding<String> {
        Binding(get: { names[colour] ?? labels.name(colour) }, set: { names[colour] = $0 })
    }

    private func saveNames() {
        var settings = labels.settings
        do {
            for (colour, name) in names {
                settings = try renameLabel(settings: settings, colour: colour, name: name)
            }
            try labels.save(settings)
            namesMessage = "Saved."
        } catch {
            namesMessage = (error as? CoreError)?.message ?? error.localizedDescription
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
