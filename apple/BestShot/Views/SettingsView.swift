import SwiftUI

/// Appearance, label names and colours, and app information.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var labels = LabelStore.shared
    /// Typed but not saved. Held by the root so Esc can close this and keep them.
    @Binding var names: [LabelColour: String]
    @State private var namesMessage: String?
    @State private var showingBridgeImport = false
    @State private var showingShortcuts = false
    @AppStorage(Appearance.key) private var appearance = Appearance.fallback

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section("Colour labels") {
                    ForEach(LabelColour.allCases) { colour in
                        HStack(spacing: 12) {
                            ColorPicker("Colour for \(colour.title)", selection: tintBinding(colour), supportsOpacity: false)
                                .labelsHidden()
                            EscapingField(placeholder: colour.title, text: nameBinding(colour))
                        }
                    }
                    Button("Save label names", action: saveNames)
                    if !labels.settings.tints.isEmpty {
                        Button("Put the colours back", action: resetTints)
                    }
                    if let namesMessage {
                        Text(namesMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Tap a swatch to change how a label looks here. Names are the text written to xmp:Label, and files saved under an old name keep their colour. Green still means keep and red still means reject, whatever they look like.")
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
                Section("Help") {
                    Button("Keyboard Shortcuts") { showingShortcuts = true }
                }
                Section("About") {
                    LabeledContent("App", value: "BestShot")
                    LabeledContent("Version", value: appVersion)
                    Text("Cull and rank your photos on-device. Ratings, labels and keywords are standard XMP. Folder decisions are saved in .bestshot-cull.json, shared with BestShot for Linux.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tableSurfaceList()
            .sheet(isPresented: $showingShortcuts) { ShortcutsHelpView() }
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

    private func tintBinding(_ colour: LabelColour) -> Binding<Color> {
        Binding(get: { Theme.label(colour) }, set: { setTint(colour, Theme.hex($0)) })
    }

    private func setTint(_ colour: LabelColour, _ hex: String) {
        do {
            try labels.saveLook(tintLabel(settings: labels.settings, colour: colour, hex: hex))
        } catch {
            namesMessage = "Couldn't save that colour. The label keeps the one it had."
        }
    }

    private func resetTints() {
        var settings = labels.settings
        settings.tints = [:]
        do {
            try labels.saveLook(settings)
        } catch {
            namesMessage = "Couldn't put the colours back. They're as they were."
        }
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
