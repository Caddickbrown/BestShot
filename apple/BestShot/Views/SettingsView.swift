import SwiftUI

/// App information. The look is fixed (light table + viewfinder), shared with
/// the Linux and web apps, so there's no theme setting.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    LabeledContent("App", value: "BestShot")
                    LabeledContent("Version", value: appVersion)
                    Text("Cull and rank your photos on-device. Folder decisions are saved in .bestshot-cull.json, shared with BestShot for Linux.")
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
        .frame(minWidth: 360, minHeight: 360)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
