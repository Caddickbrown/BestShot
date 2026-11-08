#if os(macOS)
import SwiftUI

/// Import from Bridge: lists the label text in a folder and lets each value be
/// mapped to a colour. Bridge's names are per-user, so nothing is assumed: its
/// defaults are only pre-selected here. Scanning reads files and changes none.
struct BridgeImportView: View {
    @Environment(\.dismiss) private var dismiss
    private let labels = LabelStore.shared

    @State private var importing = false
    @State private var recursive = true
    @State private var scanning = false
    @State private var scan: LabelScan?
    @State private var choices: [String: LabelColour?] = [:]
    @State private var writeNames = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from Bridge").font(.panelTitle)
            Text("Choose a folder Bridge has labelled. BestShot only reads it.")
                .font(.mono(12))
                .foregroundStyle(Theme.table.muted)
            HStack(spacing: 18) {
                Button(scanning ? "Scanning…" : "Choose folder…") { importing = true }
                    .buttonStyle(.pill)
                    .disabled(scanning)
                Toggle("Include subfolders", isOn: $recursive)
                    .toggleStyle(.checkbox)
                    .font(.mono(12))
            }
            if let error {
                Text(error).font(.mono(12)).foregroundStyle(Theme.table.accent)
            }
            if let scan { results(scan) }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.text)
                if scan?.values.isEmpty == false {
                    Button("Save mapping", action: save).buttonStyle(.pill)
                }
            }
        }
        .padding(28)
        .frame(width: 600, height: 560)
        .tableSurface()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { run(url) }
        }
    }

    @ViewBuilder
    private func results(_ scan: LabelScan) -> some View {
        Text("\(scan.files) files, \(scan.values.count) label value\(scan.values.count == 1 ? "" : "s").")
            .font(.mono(12))
        if !scan.problems.isEmpty {
            Text("\(scan.problems.count) couldn't be read and weren't counted.")
                .font(.mono(12))
                .foregroundStyle(Theme.table.accent)
        }
        ScrollView {
            VStack(spacing: 0) {
                ForEach(scan.values, id: \.text) { value in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(value.text).font(.mono(13, medium: true))
                            Text("\(value.count) · \(value.field) · e.g. \(value.example)")
                                .font(.mono(10))
                                .foregroundStyle(Theme.table.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Picker("", selection: choice(value.text)) {
                            Text("Not a colour").tag(LabelColour?.none)
                            ForEach(LabelColour.allCases) { colour in
                                Text(colour.title).tag(LabelColour?.some(colour))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    .padding(.vertical, 6)
                    HairlineRule()
                }
            }
        }
        if !scan.values.isEmpty {
            Text("Green counts as Keep. Red counts as Reject, so anything mapped to red goes in Trash all red.")
                .font(.mono(11))
                .foregroundStyle(Theme.table.accent)
            Toggle("Write these names back, so Bridge shows the same colours", isOn: $writeNames)
                .toggleStyle(.checkbox)
                .font(.mono(12))
        }
    }

    private func choice(_ text: String) -> Binding<LabelColour?> {
        Binding(get: { choices[text] ?? nil }, set: { choices[text] = .some($0) })
    }

    private func run(_ url: URL) {
        scanning = true
        error = nil
        let path = url.path
        let recursive = recursive
        let settings = labels.settings
        Task {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try scanLabels(root: path, recursive: recursive)
                }.value
                // What's already mapped, else what Bridge's defaults suggest.
                choices = Dictionary(uniqueKeysWithValues: found.values.map { value in
                    (value.text, labelColourOf(settings: settings, text: value.text) ?? labelSuggestion(text: value.text))
                })
                scan = found
            } catch {
                self.error = (error as? CoreError)?.message ?? error.localizedDescription
            }
            scanning = false
        }
    }

    private func save() {
        guard let scan else { return }
        var settings = labels.settings
        if writeNames {
            // The commonest xmp:Label for each colour becomes its written name.
            for colour in LabelColour.allCases {
                let top = scan.values.first { $0.field == "xmp:Label" && (choices[$0.text] ?? nil) == colour }
                if let top, let renamed = try? renameLabel(settings: settings, colour: colour, name: top.text) {
                    settings = renamed
                }
            }
        }
        for value in scan.values {
            settings = mapLabel(settings: settings, text: value.text, colour: choices[value.text] ?? nil)
        }
        do {
            try labels.save(settings)
            dismiss()
        } catch {
            self.error = (error as? CoreError)?.message ?? error.localizedDescription
        }
    }
}
#endif
